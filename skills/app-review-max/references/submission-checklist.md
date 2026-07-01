# Submission Checklist — Archive to Approval, In Order

Work top to bottom. Items marked (BLOCKER) will stop upload or guarantee rejection. Privacy manifest/label/legal-document correctness is owned by apple-legal-max — the checklist flags where to invoke it. Release mechanics after approval (phased release, versioning strategy) belong to apple-release-ops.

## Phase -1 — Account & Agreements (do once, verify every cycle)

0a. (BLOCKER for paid apps/IAP) Paid Applications Agreement accepted in App Store Connect, with banking and tax forms complete — App Review approves nothing monetized without it, and IAP products silently fail to load in sandbox/review when it lapses.
0b. Apple Developer Program membership not within 30 days of expiry (mid-review lapses pull the app).
0c. App record created with the correct bundle ID, primary language, and SKU; team roles set so the person submitting has Admin/App Manager rights.
0d. If the app needs managed capabilities (CarPlay, HealthKit clinical records, CallKit in China, MDM, etc.), the entitlement request is already granted — these take days-to-weeks and block submission.

## Phase 0 — Code Freeze Sanity (before archiving)

1. (BLOCKER) Built with Xcode 26+ / platform SDK 26+ — App Store Connect rejects older-SDK uploads (enforced since late April 2026). Check developer.apple.com/news/upcoming-requirements for the current floor.
2. Version (`CFBundleShortVersionString`) and build (`CFBundleVersion`) bumped; build number higher than any previously uploaded for this version.
3. Release configuration builds clean; no debug menus, shake-to-debug, staging URLs, or verbose logging reachable in release.
4. All feature flags set to their review-time state. (BLOCKER) Never plan to flip hidden features on post-approval — that's 2.3.1 and can terminate the developer account.
5. No private API usage: review upload warnings from previous builds; audit new third-party SDKs.
6. Every `NS*UsageDescription` present for every permission the app (or its SDKs) can request, each naming the feature it powers. (BLOCKER — missing strings crash at request time and fail upload validation in some cases.)
7. Privacy manifest, required-reason API declarations, nutrition labels, ATT state → run apple-legal-max alignment pass.
8. Third-party AI calls (OpenAI/Anthropic/Gemini/etc.): disclosure + consent UI in place (5.1.2(i)).
9. Deep links / universal links resolve; associated domains file live.

## Phase 1 — Device QC (the reviewer simulation)

10. Install the **archived** build (via TestFlight internal, not Xcode run) on: smallest supported iPhone, largest iPhone, and an iPad (even for iPhone-only apps — compatibility mode is tested).
11. Cold launch under 10 seconds on the oldest supported device; no crash, no blank first screen.
12. Walk EVERY screen: no lorem ipsum, no "coming soon", no dead ends, no empty states that look broken (seed demo data).
13. (BLOCKER) IPv6-only test: macOS Internet Sharing → Create NAT64 Network; run signup, login, purchase, and core flows. IPv4-literal hosts and IPv4-only backends fail App Review's network.
14. Offline / airplane mode: app degrades gracefully with real error messaging, no infinite spinners.
15. Interruptions: incoming call during purchase, backgrounding mid-flow, permission denial for every permission — app survives all.
16. Tap every in-app link: privacy policy, terms, support, help articles. All load. (2.1 rejects broken links.)
17. Dynamic Type at largest accessibility size and smallest device: nothing truncated into meaninglessness; dark mode renders correctly.
18. If the backend geo-restricts: confirm US/California IPs are allowed, or document the restriction in review notes with a demo path.

## Phase 2 — Commerce QC (skip if free with no IAP)

19. All IAP/subscription products created in App Store Connect, metadata complete, screenshots attached to each product, state "Ready to Submit".
20. (BLOCKER) New IAP products are selected for submission WITH the binary (App Store Connect → app version page → In-App Purchases section). Unsubmitted products = broken paywall at review = 2.1.
21. Sandbox test on device: purchase, cancel, restore, interrupted purchase (App Store Connect sandbox setting), Ask to Buy deferral.
22. Paywall shows StoreKit-localized price, billing period, auto-renew disclosure, trial terms; Restore Purchases visible and working.
23. External purchase links (if any): confirm the storefront rules for every region the app ships in — see monetization-compliance.md. Server-side toggle in place for regions where links are prohibited.

## Phase 3 — App Store Connect Metadata

24. App name ≤30 chars, subtitle ≤30, no prices/platform names/trademarks you don't own.
25. Keywords ≤100 chars, comma-separated, no spaces after commas, no competitor names, no words duplicated from name/subtitle.
26. Description describes THIS version only; no future promises, no prices (they vary by storefront).
27. (BLOCKER) Screenshots: 6.9" iPhone set (1–10 images) of real UI from this build; 13" iPad set if the app runs on iPad. Localized screenshots for localized listings. No mockups, no features that don't exist.
28. App previews (optional): ≤30s, actual on-device capture, up to 3 per localization; first frame chosen deliberately.
29. Support URL and marketing URL load; privacy policy URL loads and matches the in-app policy (apple-legal-max owns policy content).
30. (BLOCKER) Age rating questionnaire answered under the current global system (4+, 9+, 13+, 16+, 18+; mandatory re-answers since Jan 31, 2026) — cover ads, UGC, loot boxes, wellness topics honestly.
31. App category matches primary function; secondary category sane.
32. Content rights declaration: if the app shows third-party content, have documentation ready.
33. Export compliance: standard HTTPS/ATS-only apps qualify for the exemption; answer the encryption questions, set `ITSAppUsesNonExemptEncryption` appropriately to skip per-build prompts.

## Phase 4 — App Review Information (the highest-ROI five minutes)

34. (BLOCKER if login exists) Demo account: dedicated review credentials, seeded with realistic data, 2FA off or fixed code, verified working the day of submission. SMS-only login → fixed-code test number.
35. Review notes written from the SKILL.md template: what the app does, tap-paths to key features, permission justifications, anything unusual (hardware, geo, background modes, UGC moderation).
36. Attachments where words fail: screen recording links for hardware-dependent or hard-to-reach features.
37. Contact info current — reviewers do occasionally call.

## Phase 5 — TestFlight (recommended before App Review)

38. Upload build; wait for processing (minutes to ~1h); resolve any ITMS email warnings — they preview App Review's automated findings.
39. Internal testing (up to 100 team members): no review needed, available immediately. Run Phase 1 QC here.
40. External testing quirks — know these:
    - The FIRST build of each version number sent to external testers requires **Beta App Review** (~24–48h). Subsequent builds of the same version usually skip re-review.
    - Beta App Review applies a subset of the guidelines (completeness, safety) — passing it does NOT guarantee App Review approval, and a beta rejection generally doesn't scar your App Store record, but repeated abuse does.
    - Provide beta review notes + demo account for Beta App Review too; it's a lighter but real human review.
    - TestFlight builds expire after 90 days; IAP in TestFlight uses the sandbox and charges nothing — warn testers.
    - Don't use TestFlight as a distribution channel for a "finished" app or to demo features you won't ship — that's a guideline 2.2 beta-misuse rejection.
41. Collect at least one full external-tester pass through signup → core flow → purchase before submitting for App Review.

## Phase 6 — Submit

42. Select the build on the version page; confirm all sections show green checkmarks.
43. Set release option: Manual release (recommended for launches — approval ≠ instant availability), Automatic, or Scheduled. Phased-release strategy → apple-release-ops.
44. Submit for review. Expect movement within 24h (90% of submissions); "In Review" longer than 48h with no word is normal-ish; longer than a week → polite status inquiry via Contact Us.

## Phase 7 — During and After Review

45. Watch email + App Store Connect. "Metadata Rejected" → fix listing, reply, no new build. "Rejected" (binary) → rejection playbook.
46. If the reviewer asks a question in Resolution Center, answer within hours if you can — the review often resumes immediately.
47. Approved: verify the store listing renders correctly, then release (manual) and monitor crash reports for the first 48h. An emergency fix qualifies for expedited review only if user-facing and severe.
48. Save what worked: archive the exact review notes, demo account, and screenshots that passed — reuse and increment next cycle.

## Day-of-Submission Ten-Minute Smoke Test

Run this immediately before pressing Submit, even if Phases 0–5 passed days ago:

- Demo account logs in RIGHT NOW on a device that has never seen it (sessions expire, backends get redeployed).
- Privacy policy URL, support URL, and marketing URL all load from a phone on cellular.
- Sandbox purchase completes on the build you selected for review.
- Push the app through signup → core action → paywall once, cold start, on cellular.
- Backend deploy freeze confirmed for the review window — a migration that 500s the API mid-review is a self-inflicted 2.1.
- Skim the App Review Guidelines "recent changes" note (Apple updates several times a year; Nov 2025 added third-party AI consent and copycat rules — assume something changed since your last submission).

## Fast Re-Submission Rules of Thumb

- Metadata-only fix: same build, resubmit same day.
- Binary fix: bump build number only (not version), describe the delta in Resolution Center, resubmit — repeat reviews of resubmissions are often faster.
- Rejection you dispute: one evidence-rich reply first; appeal to the App Review Board only after the reply fails.
- Never resubmit unchanged hoping for a different reviewer — repeated identical submissions escalate toward 4.3 spam flags.
