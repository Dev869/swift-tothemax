# CI Recipes — iOS/macOS pipelines that don't flake

Verified July 2026: GitHub-hosted `macos-26` runners are GA (Apple Silicon, Xcode 26.6
preinstalled); `macos-latest` resolves to macos-26 as of June 2026. Pin the image AND the Xcode
version — image updates swap default Xcodes without warning.

## Secrets you need (GitHub → Settings → Secrets)

| Secret | Contents |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID (Team key, role: App Manager) |
| `ASC_ISSUER_ID` | Issuer UUID from the Integrations page |
| `ASC_KEY_P8` | Full contents of the `AuthKey_XXX.p8` file |
| `DIST_CERT_P12_BASE64` | `base64 -i dist.p12` — only for manual signing |
| `DIST_CERT_PASSWORD` | p12 password — only for manual signing |

With cloud-managed certificates + automatic signing you need only the first three.

## GitHub Actions: build + test + TestFlight

```yaml
name: release
on:
  push:
    tags: ['v*']

jobs:
  testflight:
    runs-on: macos-26          # Apple Silicon; pin, don't ride macos-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      - name: Pin Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.6.app

      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Write ASC API key
        run: |
          mkdir -p private_keys
          echo "${{ secrets.ASC_KEY_P8 }}" > private_keys/AuthKey_${{ secrets.ASC_KEY_ID }}.p8

      - name: Test
        run: |
          set -o pipefail
          xcodebuild test \
            -project MyApp.xcodeproj -scheme MyApp \
            -destination 'platform=iOS Simulator,name=iPhone 17' \
            -resultBundlePath build/Tests.xcresult | xcbeautify

      - name: Archive + upload to TestFlight
        run: |
          set -o pipefail
          xcodebuild archive \
            -project MyApp.xcodeproj -scheme MyApp \
            -destination 'generic/platform=iOS' \
            -archivePath build/MyApp.xcarchive \
            CURRENT_PROJECT_VERSION=${{ github.run_number }} \
            -allowProvisioningUpdates \
            -authenticationKeyID "${{ secrets.ASC_KEY_ID }}" \
            -authenticationKeyIssuerID "${{ secrets.ASC_ISSUER_ID }}" \
            -authenticationKeyPath "$PWD/private_keys/AuthKey_${{ secrets.ASC_KEY_ID }}.p8" \
            | xcbeautify
          xcodebuild -exportArchive \
            -archivePath build/MyApp.xcarchive \
            -exportOptionsPlist ExportOptions.plist \
            -exportPath build/export \
            -allowProvisioningUpdates \
            -authenticationKeyID "${{ secrets.ASC_KEY_ID }}" \
            -authenticationKeyIssuerID "${{ secrets.ASC_ISSUER_ID }}" \
            -authenticationKeyPath "$PWD/private_keys/AuthKey_${{ secrets.ASC_KEY_ID }}.p8"

      - name: Upload dSYMs to crash reporter   # if using one; archive keeps them in dSYMs/
        run: ./scripts/upload-dsyms.sh build/MyApp.xcarchive/dSYMs
```

`ExportOptions.plist` uses `method: app-store-connect`, `destination: upload` (see SKILL.md).
The export step then IS the upload — no altool, no Transporter step.

## Keychain setup — only for manual signing (imported .p12)

GitHub-hosted runners give you a fresh user without an unlocked keychain. Create a throwaway:

```bash
KEYCHAIN=$RUNNER_TEMP/ci.keychain-db
KEYCHAIN_PW=$(uuidgen)
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"        # no auto-lock for 6h
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
echo "${DIST_CERT_P12_BASE64}" | base64 --decode > "$RUNNER_TEMP/dist.p12"
security import "$RUNNER_TEMP/dist.p12" -k "$KEYCHAIN" \
  -P "$DIST_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
# CRITICAL: without this, codesign hangs forever waiting for a UI password prompt
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PW" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
```

Install matching profiles to `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` and use
`signingStyle: manual` + `provisioningProfiles` dict in ExportOptions. Delete the keychain in an
`always()` cleanup step. Skip all of this if cloud signing works for you — it usually does.

## macOS runner realities

- Apple Silicon only on macos-26; anything shelling out to x86-only tools needs Rosetta
  (`softwareupdate --install-rosetta --agree-to-license`).
- First `xcodebuild` per job pays simulator/first-launch tax. `xcodebuild -downloadPlatform iOS`
  if the pinned Xcode lacks the simulator runtime you test on.
- macOS runners bill at 10x Linux minutes. Keep test jobs on PRs, archive jobs on tags.
- DerivedData caching across jobs is usually a net loss (huge, poor hit rate); cache only
  SourcePackages/SPM as above.
- Hardware keychain/UI prompts are the #1 hang: if a job stalls at "signing", it's the
  partition-list step missing (above) or a password prompt you can't see.

## Xcode Cloud — when it's the better pick

Choose Xcode Cloud when: team is fully in the Apple ecosystem, you want zero secret management
(signing and upload are fully managed — no certs, no API keys in CI), TestFlight distribution is
the main goal, and 25 free compute hours/month covers you. Workflows live in ASC/Xcode; custom
logic goes in `ci_scripts/ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `ci_post_xcodebuild.sh`
(the only escape hatches — no arbitrary pipeline graph).

Choose GitHub Actions when: you need non-Apple steps (Docker, backend deploys, monorepo
orchestration), matrix builds, self-hosted hardware, artifacts pushed anywhere but TestFlight,
or fine-grained caching. Many teams run both: Xcode Cloud for TestFlight, Actions for PR checks.

## fastlane equivalents

fastlane remains maintained and is worth it when you outgrow raw xcodebuild (screenshots,
metadata sync, multi-app cert sharing):

```ruby
# fastlane/Fastfile
lane :beta do
  app_store_connect_api_key(key_id: ENV["ASC_KEY_ID"],
                            issuer_id: ENV["ASC_ISSUER_ID"],
                            key_content: ENV["ASC_KEY_P8"])
  match(type: "appstore", readonly: is_ci)   # pulls certs+profiles from encrypted git/S3
  gym(scheme: "MyApp", export_method: "app-store-connect")   # = archive + exportArchive
  pilot(skip_waiting_for_build_processing: true)             # = upload + TestFlight mgmt
end
```

- `match` = the manual-signing keychain dance above, automated and shared across machines.
  `match nuke distribution` resets a corrupted cert state cleanly.
- `gym` = archive + export. `pilot` = upload + tester/group management. `deliver` = metadata,
  screenshots, submission.
- Wrong: fastlane with Apple ID + `FASTLANE_SESSION` cookies (expires, 2FA breaks CI).
  Right: `app_store_connect_api_key` everywhere.

## Debugging a red pipeline

1. Re-run with `xcodebuild ... -verbose` and without `xcbeautify` — the beautifier eats the
   interesting stderr.
2. Signing failures: jump to `references/signing-troubleshooting.md`.
3. Upload rejections (ITMS-xxxxx) are validation, not signing — read the message; usual
   suspects: duplicate build number, missing usage-description Info.plist keys, icon format.
4. "Works locally, fails in CI" is almost always: different Xcode (check `xcodebuild -version`
   in the log), missing keychain partition list, or a profile present locally but not installed
   on the runner.
