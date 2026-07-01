# Privacy Manifests (PrivacyInfo.xcprivacy)

Enforced since **May 1, 2024** for new apps and updates; still current mid-2026. Missing/invalid entries produce upload-time ITMS errors (ITMS-91053 missing required-reason declaration, ITMS-91054 invalid reason code, ITMS-91056 invalid tracking domain).

## File anatomy

A property list named exactly `PrivacyInfo.xcprivacy`, at the root of the app bundle (or SDK bundle). Xcode: File > New > File > App Privacy. Four top-level keys:

```xml
<dict>
  <key>NSPrivacyTracking</key>              <!-- Bool -->
  <false/>
  <key>NSPrivacyTrackingDomains</key>       <!-- Array of String -->
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>    <!-- Array of Dict -->
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>      <!-- Array of Dict -->
  <array/>
</dict>
```

### 1. NSPrivacyTracking (Bool)
`true` if the app/SDK uses data for **tracking** as defined by Apple's ATT policy: linking user or device data with third-party data for targeted advertising or ad measurement, or sharing it with data brokers. If true, you must also request ATT authorization at runtime before tracking (Guideline 5.1.2).

### 2. NSPrivacyTrackingDomains (Array of String)
Internet domains the app/SDK connects to that engage in tracking. **Enforced at the network layer**: if the user has not granted ATT permission, requests to these domains fail. Practical notes:
- Find candidates: Xcode Instruments > Points of Interest / Network profile flags likely tracking domains at runtime.
- SDKs that both track and serve functional traffic often publish separate tracking hostnames (e.g. an `-att` or consented endpoint split); use the SDK vendor's documented domain list.
- Declaring a domain here does NOT excuse an ATT prompt; it complements it.
- Hiding tracking behind an undeclared domain or proxy is a 5.1.2 violation (fingerprinting-adjacent; removal risk).

### 3. NSPrivacyCollectedDataTypes (Array of Dict)
One dict per collected data type. Each dict:

| Key | Value |
|---|---|
| `NSPrivacyCollectedDataType` | String constant, e.g. `NSPrivacyCollectedDataTypeEmailAddress`, `...PreciseLocation`, `...CoarseLocation`, `...DeviceID`, `...UserID`, `...ProductInteraction`, `...CrashData`, `...PerformanceData`, `...Photos`, `...AudioData`, `...PurchaseHistory`, `...BrowsingHistory`, `...SearchHistory`, `...Health`, `...Fitness`, `...PaymentInfo`, `...PhysicalAddress`, `...PhoneNumber`, `...Name`, `...Contacts`, `...EmailsOrTextMessages`, `...GameplayContent`, `...CustomerSupport`, `...OtherUserContent`, `...SensitiveInfo`, `...EnvironmentScanning`, `...Hands`, `...Head`, `...OtherDataTypes` |
| `NSPrivacyCollectedDataTypeLinked` | Bool — linked to the user's identity |
| `NSPrivacyCollectedDataTypeTracking` | Bool — used for tracking |
| `NSPrivacyCollectedDataTypePurposes` | Array of String: `NSPrivacyCollectedDataTypePurposeAppFunctionality`, `...Analytics`, `...DeveloperAdvertising`, `...ThirdPartyAdvertising`, `...ProductPersonalization`, `...Other` |

"Collected" = transmitted off-device and retained beyond what's needed to service the request in real time.

### 4. NSPrivacyAccessedAPITypes (Array of Dict) — Required Reason APIs
One dict per accessed API category:

| Key | Value |
|---|---|
| `NSPrivacyAccessedAPIType` | Category constant (below) |
| `NSPrivacyAccessedAPITypeReasons` | Array of reason-code strings (below) |

## Required reason API categories & reason codes

Five categories as of mid-2026 (Apple treats the list as open — re-check "Describing use of required reason API" on developer.apple.com when auditing). You may only declare reasons that match your actual use; use of the API for any undeclared purpose is a violation.

### NSPrivacyAccessedAPICategoryFileTimestamp
APIs: `creationDate`, `modificationDate`, `fileModificationDate`, `contentModificationDateKey`, `creationDateKey`, `getattrlist`, `stat`, `fstat`, etc.
- **DDA9.1** — display file timestamps to the person using the device
- **C617.1** — access timestamps/size/metadata of files inside the app container, app group container, or the app's CloudKit container
- **3B52.1** — access timestamps/size/metadata of files the user explicitly granted access to (document picker, etc.)
- **0A2A.1** — 3rd-party SDK providing a wrapper over this API for the app to use (SDK-only; wrapper must be declared in the SDK docs)

### NSPrivacyAccessedAPICategorySystemBootTime
APIs: `systemUptime`, `mach_absolute_time()`, etc.
- **35F9.1** — measure elapsed time between events within the app; may not be sent off-device (only elapsed deltas may)
- **8FFB.1** — calculate absolute event timestamps for UIKit/AVFAudio API events (e.g. `UITouch.timestamp`)
- **3D61.1** — include boot time in an optional bug report the person chooses to submit (must be visible to the user)

### NSPrivacyAccessedAPICategoryDiskSpace
APIs: `volumeAvailableCapacityKey`, `volumeTotalCapacityKey`, `systemFreeSize`, `statfs`, etc.
- **85F4.1** — display disk space to the user
- **E174.1** — check whether sufficient space exists before writing files, or delete when space is low; disk space may not be sent off-device
- **7D9E.1** — include disk space in an optional, user-submitted bug report (visible to user)
- **B728.1** — health-research apps with user consent, avoiding data loss

### NSPrivacyAccessedAPICategoryActiveKeyboards
API: `activeInputModes`
- **3EC4.1** — the app IS a custom keyboard and accesses this to function
- **54BD.1** — access active keyboard info to present the correct customized UI; data stays on device and may not be sent off-device

### NSPrivacyAccessedAPICategoryUserDefaults
API: `UserDefaults` (and `NSUbiquitousKeyValueStore` adjacency)
- **CA92.1** — read/write data accessible only to the app itself
- **1C8F.1** — read/write data accessible to apps/extensions in the same App Group (same developer)
- **C56D.1** — 3rd-party SDK wrapper over UserDefaults for the hosting app's use (SDK-only)
- **AC6B.1** — read `com.apple.configuration.managed` / write `com.apple.feedback.managed` for MDM managed app configuration

Practically: nearly every app declares **UserDefaults / CA92.1**; apps checking free space before downloads declare **DiskSpace / E174.1**; file-cache code usually needs **FileTimestamp / C617.1**; analytics/anti-fraud uptime math needs **SystemBootTime / 35F9.1**.

## Third-party SDK requirements

Apple publishes a list of ~86 "commonly used third-party SDKs" (developer.apple.com/support/third-party-SDK-requirements/) — includes Firebase modules, FBSDK*, GoogleSignIn/GoogleUtilities, Alamofire, AFNetworking, Flutter, hermes/React Native pods, UnityFramework, Capacitor, Cordova, Lottie, SDWebImage, Kingfisher, RealmSwift, RxSwift, OneSignal, SnapKit, Charts, and more. For any listed SDK:

- [ ] The SDK **must contain its own privacy manifest** — you cannot declare on its behalf in the app manifest (the app manifest covers only your code); update the SDK if its bundled manifest is missing/outdated.
- [ ] If added as a **binary dependency**, the SDK must be **signed** (Apple Developer Program signature or self-signed certificate); Xcode verifies the signer is unchanged on version updates and surfaces it in the inspector.
- [ ] App submissions including a listed SDK without its manifest/signature are rejected.
- [ ] Non-listed SDKs that collect data or touch required-reason APIs still *should* ship manifests; if they don't, their API use must be covered by reasons you can truthfully declare, and their data collection must be reflected in **your** nutrition labels regardless.

## Aggregation into the privacy label

- Xcode: **Product > Archive > (right-click archive) Generate Privacy Report** — produces a PDF aggregating `NSPrivacyCollectedDataTypes` across the app and every SDK manifest in the bundle.
- Use that report as the checklist when filling in **App Store Connect > App Privacy**. The report is organized by label section, so transcription is mechanical.
- The manifest does NOT auto-populate the label — you still answer the App Privacy questionnaire; the report keeps you honest.
- Re-run the report on every SDK version bump; SDKs add data types silently.
- Labels can be edited in App Store Connect at any time without a new binary — fix inaccuracies immediately, don't wait for the next release.

## Audit checklist (run per release)

- [ ] `PrivacyInfo.xcprivacy` present at app-bundle root and in each of your own frameworks that touch required-reason APIs
- [ ] Grep for required-reason API symbols (`stat(`, `systemUptime`, `UserDefaults`, `volumeAvailableCapacity`, `activeInputModes`) in your code; each hit maps to a declared category+reason
- [ ] Every listed SDK at a version that bundles its own manifest; binary SDKs signed
- [ ] `NSPrivacyTracking` matches reality; if true → ATT prompt implemented and tracking domains listed
- [ ] Generate Privacy Report ↔ App Store Connect label diff = empty
- [ ] Purpose strings exist for every `NS…UsageDescription` the binary references
