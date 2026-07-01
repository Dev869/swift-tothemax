# Store Presence — metadata, screenshots, releases, reviews, monitoring

Everything here is automatable via the App Store Connect API; treat the ASC web UI as the
fallback, not the workflow. For review-rejection strategy, hand off to `app-review-max`.

## Metadata fields and limits

| Field | Limit | Notes |
|---|---|---|
| App name | 30 chars | Indexed for search. Locked while a version is In Review. |
| Subtitle | 30 chars | Indexed. Second-highest ASO weight. |
| Keywords | 100 chars | Comma-separated, no spaces after commas; don't repeat name/subtitle words. |
| Description | 4000 chars | NOT search-indexed on the App Store; write for humans. |
| Promotional text | 170 chars | Updatable **without a new version** — use for launch notes, incident notices. |
| What's New | 4000 chars | Per-version; required on updates. |
| Support URL | required | Must actually work; a dead link is a rejection. |
| Privacy policy URL | required | Content questions → `apple-legal-max`. |

Editable **without review**: promotional text, keywords? No — keywords need a version. Only
promotional text, app privacy answers, pricing, and availability change freely. Everything
version-bound waits for the next submission — plan copy changes with the release train.

API: `PATCH /v1/appStoreVersionLocalizations/{id}` per locale; fastlane `deliver` syncs a
`fastlane/metadata/` directory and is the sane way to manage >2 locales.

## Screenshot specifications (verified July 2026)

One screenshot set per required device class; Apple downscales for smaller devices. Rules:
PNG or JPEG, RGB, no alpha channel, exact pixel dimensions, 1–10 screenshots per class.

| Class | Required? | Accepted portrait sizes (px) |
|---|---|---|
| iPhone 6.9" | Yes (any iPhone app) | 1320×2868, 1290×2796, or 1260×2736 |
| iPad 13" | Yes if iPad is supported | 2064×2752 (also 2048×2732 accepted) |
| Apple Watch | If watch app | 410×502 (Ultra 416×496 optional) |
| Apple TV | If TV app | 3840×2160 or 1920×1080 landscape |
| Vision Pro | If visionOS app | 3840×2160 landscape |

Landscape variants = the same pairs transposed. Lead with the 6.9" set (1320×2868); the old 6.5"
set alone no longer covers current flagships. App previews (video, 15–30s) follow the same
device classes.

Automate capture with a UI-test target + `xcodebuild test -resultBundlePath` extraction or
fastlane `snapshot` (simulator matrix per device class) → `deliver` uploads. Off-by-one pixel
dimensions are rejected at upload, not at review — validate sizes in CI:
`sips -g pixelWidth -g pixelHeight *.png`.

## App privacy labels (nutrition labels)

- Declared in ASC → App Privacy; answers persist across versions, so they silently rot as the
  app gains SDKs. **Re-audit every time a third-party SDK is added or updated** — analytics and
  ads SDKs change collection behavior between minor versions.
- Cross-check against the **privacy manifests** (`PrivacyInfo.xcprivacy`) bundled in your app
  and SDKs: Xcode's archive step can generate a privacy report from the archive
  (Organizer → archive → Generate Privacy Report). Labels that contradict manifest data are a
  rejection and, worse, a trust problem.
- Required-reason APIs (UserDefaults, file timestamps, etc.) must be covered by a manifest
  reason or uploads fail validation (ITMS-91053).
- What the policy/legal wording must say → `apple-legal-max`.

## Phased release mechanics and review windows

- Phased release applies to **automatic updates only**: day 1 = 1%, then 2%, 5%, 10%, 20%,
  50%, 100% over 7 days. Manual updaters and new downloads always get the newest version — a
  broken build still reaches anyone who taps Update.
- Controls: **Pause** (up to 30 days total), **Release to All Users** (finish early). No
  rollback, no halt-and-revert. Version release options at submission: manual release,
  automatic on approval, or scheduled date — pick **manual** for coordinated launches so
  approval ≠ release.
- Review windows (planning numbers, not promises): most submissions clear in 24–48h;
  resubmissions after rejection usually faster; expedited review is a request form and is
  granted for genuine critical bugs/security issues a handful of times a year — don't burn it.
  Strategy for making a submission review-proof → `app-review-max`.
- Practical cadence: submit with manual release + phased ON → release Monday–Wednesday morning
  (never Friday) → watch crash metrics through day 3 (≤10% exposure) → let it ride or pause.

## Responding to App Store user reviews via API

Customer reviews and developer responses are first-class ASC API resources — automate triage:

```
GET  /v1/apps/{appId}/customerReviews?sort=-createdDate&filter[rating]=1,2
POST /v1/customerReviewResponses      # body: review relationship + responseBody
GET  /v1/customerReviews/{id}/response
```

Auth = the same ASC API JWT as everything else (key with App Manager or Customer Support role).
One response per review; editing replaces it; the user is notified and can update their review.

Playbook: pull 1–2★ reviews daily; answer crash/bug reports with the fixed-version number once
shipped ("Fixed in 2.4.1 — update and reply if it persists"); never argue ratings. Responses
are public and show up in search results for your app's problems — write them as documentation.
fastlane has no first-class action here; a 30-line script with the JWT is the standard move.

## Crash triage: Organizer and MetricKit

Two pipelines, different latencies — use both:

**Xcode Organizer / ASC Analytics** (opt-in users who share analytics; hours–1 day lag):
- Organizer → Crashes: signatures ranked by device count, per version. Open a signature →
  "Open in Project" jumps to the symbolicated frame if the archive is on this machine.
- ASC → Analytics → Metrics: crash *rate* (crashes per session) — trend this, not absolute
  counts, which follow adoption.
- Symbolication requires dSYMs. Bitcode is dead, so dSYMs come straight from your archive
  (`MyApp.xcarchive/dSYMs/`); archive from CI and keep the `.xcarchive` (or at least dSYMs) as
  a build artifact for every shipped build. Symbolicate a raw report by hand:
  `xcrun symbolicatecrash crash.ips MyApp.app.dSYM` (or `CrashSymbolicator.py` for .ips).

**MetricKit** (in-process, all users, delivered to YOUR endpoint — near-real-time):
- Adopt `MXMetricManagerSubscriber`; `MXCrashDiagnostic`, `MXHangDiagnostic`,
  `MXAppLaunchMetric` arrive in daily payloads (diagnostics often same-day). Ship payloads to
  your backend — this is the early-warning system that catches a spike while phased release is
  still at 5%.
- Watch alongside crashes: hang rate and launch time regressions, which never show in Organizer
  crash counts but tank reviews.

Wire ASC **webhooks** (build state, TestFlight feedback events) into the same channel so
"build processed", "beta feedback received", and your MetricKit alarms land where the team
already looks. Full incident sequence: SKILL.md → "Incident triage".
