# Signing Troubleshooting — decision tree and forensics

Work the tree top-down. Before anything else, capture ground truth:

```bash
security find-identity -v -p codesigning            # certs + private keys actually usable
ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/   # installed profiles
codesign -dvvv MyApp.app 2>&1 | head -20            # what the binary is signed with
codesign -d --entitlements - MyApp.app              # what the binary CLAIMS
security cms -D -i profile.mobileprovision > profile.plist      # what the profile ALLOWS
```

`find-identity` shows only cert+key pairs. A cert visible in Keychain Access but absent here
means the **private key is missing** — that is the diagnosis, stop looking elsewhere.

## Decision tree

### "No signing certificate 'iOS Distribution' found" / "No certificate matching..."

1. `security find-identity -v -p codesigning` — is a `Apple Distribution: <Team>` identity
   listed?
   - **Not listed, cert exists in portal** → you don't have the private key on this machine.
     Options: export `.p12` from the machine that created it; or revoke and let cloud-managed
     signing take over (automatic signing + ASC API key, nothing to install); or
     `fastlane match nuke distribution && fastlane match appstore`.
   - **Listed but Xcode ignores it** → team mismatch: check `DEVELOPMENT_TEAM` in build
     settings matches the cert's team ID; check you're not overriding `CODE_SIGN_IDENTITY` to a
     stale name in an xcconfig.
2. On CI: the cert imported fine but into a keychain not in the search list, or partition list
   not set. See "CI keychain pathologies" below.
3. Account has hit the cert limit (2 distribution certs of a type per team): revoke the one
   nobody can find the key for. Revoking a **distribution** cert does NOT break shipped apps or
   TestFlight builds; it breaks nothing except pending builds signed with it.

### "Provisioning profile ... doesn't include the <X> entitlement"

The binary claims an entitlement the profile wasn't generated with.

```bash
codesign -d --entitlements - MyApp.app                          # claims
security cms -D -i embedded.mobileprovision | plutil -p - | grep -A2 Entitlements  # allowed
```

Diff them. Then:
1. Capability recently added (push, App Groups, iCloud, associated domains)? Portal profiles
   are point-in-time snapshots — regenerate: automatic signing does it on next build with
   `-allowProvisioningUpdates`; manual → portal → profile → Edit → Save (regenerates) →
   re-download.
2. Entitlement in `.entitlements` file but capability never enabled on the App ID → enable the
   capability in the portal (or Xcode Signing & Capabilities, which does both).
3. Entitlement is restricted/managed (e.g. `com.apple.developer.networking.custom-protocol`,
   CarPlay) → requires Apple approval per-app; the profile can't include it until granted.
4. It's an extension target failing, not the app: every target signs separately with its own
   profile. Check the failing target's bundle ID has its own App ID + profile.
5. Wrong: deleting the entitlements file to make the error go away — the feature silently
   breaks at runtime. Right: make profile and claims agree.

### "Device not registered" / "doesn't include this device"

Development / ad-hoc only (distribution profiles have no device list).

1. Get the UDID: Xcode → Window → Devices, or `xcrun devicectl list devices`.
2. Register: portal → Devices → +, or let automatic signing do it when the device is plugged in.
3. Regenerate + reinstall the profile — registering the device does NOT update existing
   profiles.
4. Device limit (100/type/year) reached → prune at membership-year reset, or use TestFlight
   internal testers instead of ad-hoc (no device list at all).
5. If this error appears for an App Store build, you're exporting with the wrong method —
   check `method` in ExportOptions.plist is `app-store-connect`, not `ad-hoc` or `development`.

### "Unable to build chain to self-signed root" / WWDR intermediate problems

Cert chain broken locally. The old WWDR G1 intermediate expired 2023; anything referencing it
is stale.

```bash
security find-certificate -c "Apple Worldwide Developer Relations" -p -a login.keychain \
  | openssl x509 -noout -enddate
```

1. Delete expired WWDR intermediates from the login AND System keychains.
2. Current intermediates (G4 etc.) auto-install with Xcode; or fetch from
   https://www.apple.com/certificateauthority/ and `security add-certificates`.
3. Also check the leaf: your dev cert trust settings must be "Use System Defaults" — a manual
   "Always Trust" paradoxically breaks codesign ("unable to build chain").

### "errSecInternalComponent" or codesign hangs (CI classic)

Keychain can't authorize codesign to use the key without UI.

```bash
security unlock-keychain -p "$PW" "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KEYCHAIN"   # the fix
security set-keychain-settings -lut 21600 "$KEYCHAIN"    # stop it re-locking mid-build
```

If it still hangs: keychain not in search list —
`security list-keychains -d user -s "$KEYCHAIN" login.keychain-db`.

### "Revoked certificate" popup / builds suddenly failing team-wide

Someone (or Xcode's "Revoke and request") revoked the shared cert. Development certs are
per-person, harmless. A revoked distribution cert with team members holding stale copies causes
exactly this. Recovery: one authority regenerates (match, or one designated machine), everyone
else consumes read-only (`match(readonly: true)`), nobody clicks "Revoke" in Xcode dialogs again.

### Profile expired (annual)

Profiles die yearly even when certs are fine. `security cms -D -i profile.mobileprovision |
plutil -p - | grep Expiration`. Automatic signing + `-allowProvisioningUpdates` renews silently;
manual setups should calendar it or let CI regenerate via match/portal API.

## Entitlements forensics — the three-way diff

When behavior (not the build) is wrong — push tokens never arrive, keychain group access denied,
universal links dead — diff all three layers:

```bash
codesign -d --entitlements - MyApp.app                       # 1. what shipped
security cms -D -i MyApp.app/embedded.mobileprovision | plutil -p -   # 2. what profile allows
cat MyApp/MyApp.entitlements                                 # 3. what you intended
```

- In 3 but not 1 → target's `CODE_SIGN_ENTITLEMENTS` points at the wrong file/none.
- In 1 but not 2 → the "doesn't include entitlement" case above (may install in dev, then fail
  distribution).
- `aps-environment: development` in a distribution build → exported with the wrong method;
  the app-store-connect export rewrites it to `production`.
- Verify a signature end-to-end: `codesign --verify --deep --strict -vv MyApp.app`; for
  notarized macOS apps also `spctl -a -vv MyApp.app`.

## CI keychain pathologies (quick table)

| Symptom | Cause | Fix |
|---|---|---|
| Hang at signing step | Missing `set-key-partition-list` | Run it after import |
| Cert imported, `find-identity` empty | Imported cert w/o key, or wrong keychain | Import full `.p12`; add keychain to search list |
| Works first job, fails later | Keychain auto-locked | `set-keychain-settings -lut 21600` |
| "duplicate item" on import | Leftover keychain from previous run (self-hosted) | Delete keychain in `always()` cleanup |
| Random UI prompt on self-hosted Mac | Cert in login keychain w/ ACL prompts | Dedicated CI keychain, never login |
