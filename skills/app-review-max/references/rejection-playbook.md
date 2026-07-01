# Rejection Playbook — Per-Guideline Deep Dive

For each guideline: the exact requirement, what actually triggers the rejection, the fix, and how to word the resubmission. Always re-read the live guideline text at developer.apple.com/app-store/review/guidelines before responding — numbering below verified against the mid-2026 guidelines.

## 2.1 — App Completeness (the #1 rejection, ~40% of all)

**Requirement.** Submissions must be final: no placeholder text, no dead links, no crashes, all IAP complete and visible, demo credentials for anything behind a login.

**Common triggers**
- Crash on launch or on a specific device class the developer never tested (reviewer devices include iPads even for iPhone-only apps, running in compatibility mode).
- Backend rejected the reviewer: expired demo account, 2FA/SMS gate, geo-fenced API blocking US IPs, IPv6-incompatible server.
- "We were unable to sign in" — credentials missing, wrong, or the login flow requires email verification the reviewer can't complete.
- Empty screens because the demo account has no data.
- IAP products not submitted with the build, so the paywall errors out.
- "Bug on iPad": iPhone-only apps still run on iPad; broken layouts or crashes there are 2.1 rejections.

**Fix**
- Test the *archived release build* (not a debug run) on physical devices, including an iPad in compatibility mode.
- Create a dedicated, never-expiring review account with seeded data; verify it the day you submit.
- Test on an IPv6-only NAT64 network (macOS Internet Sharing → Create NAT64 Network).
- Whitelist or remove geo-restrictions for review traffic; assume a US/California origin.
- Submit IAP products together with the binary; verify sandbox purchase + restore.

**Resubmission wording.** If the reviewer simply couldn't reach a feature, do NOT upload a new build. Reply in Resolution Center:
> "The reported issue occurs before sign-in. Working credentials: <user>/<pass> (2FA disabled). Steps to reach <feature>: 1) … 2) …. Screen recording of the full flow on iOS <version>: <link>. No binary changes were needed; please continue the review with this information."

If you fixed a crash: state device/OS where it reproduced, root cause in one sentence, and "fixed in build <N>."

## 2.3.x — Accurate Metadata

**Requirement.** Name, subtitle, description, keywords, screenshots, and previews must describe the app as submitted — nothing hidden, nothing misleading, nothing irrelevant. Since Nov 2025, Apple also rejects listings that impersonate or trade on other apps/brands more aggressively (paired with 4.1 copycat enforcement).

**Common triggers**
- 2.3.1: hidden or undocumented features; feature flags that reveal functionality after approval (this can escalate to developer program termination — never do it).
- 2.3.3/2.3.10: screenshots showing marketing renders, other platforms, devices frames with wrong UI, or features not in this build; mentions of Android/Google Play anywhere.
- 2.3.7: prices in name/subtitle/screenshots ("Free!"), trademarked terms, competitor names in keywords, name >30 chars.
- 2.3.8: icon/screenshot content above 4+ appropriateness even when the app is rated higher.
- Description promising features shipping "soon."

**Fix.** Regenerate screenshots from the exact submitted build; strip prices, platform names, and future-tense promises; audit keywords for third-party trademarks; keep age-inappropriate imagery out of the listing.

**Resubmission wording.** Metadata rejections usually don't need a new binary. Reply: "Updated screenshots to show the current UI of build <N> and removed the reference to <X> from the description. All metadata now reflects shipping functionality." Then resubmit the same build.

## 3.1.1 / 3.1.1(a) / 3.1.3 — Payments

**Requirement.** Digital features, content, subscriptions, and currency must use IAP unless a 3.1.3 exception applies (reader apps, multiplatform services, enterprise, person-to-person services, physical goods, free companions, licensed crypto exchanges per 3.1.5). External purchase links are storefront-dependent — see monetization-compliance.md for the full 2026 region matrix.

**Common triggers**
- "Buy on our website" buttons/links for digital goods on non-US storefronts without the External Purchase Link entitlement.
- Unlock codes, license keys, or crypto payments for digital features.
- Paywall missing price, billing period, or auto-renewal disclosure; free trial not stating post-trial price.
- No visible Restore Purchases.
- Tipping/donation flows for digital content routed outside IAP.

**Fix.** Route digital purchases through StoreKit; show full subscription terms on the paywall (price, period, renewal, trial terms); add a Restore button; gate any external link behind the correct storefront rules/entitlement.

**Resubmission wording.** Be concrete about the payment architecture: "All digital content is purchasable exclusively via In-App Purchase (product IDs: …). The link on <screen> leads to <physical goods / account management>, which falls under 3.1.3(e)/3.1.5(iv); no digital content is sold there." If relying on the US-storefront link allowance, say so explicitly and confirm the app's distribution is limited accordingly.

## 4.3 — Spam, and 4.2 — Minimum Functionality

**Requirement.** 4.3(a): one bundle ID per app concept — no re-skinned duplicates. 4.3(b): saturated categories (dating, wallpaper, flashlight, fortune-telling, drinking games) need a genuinely distinct, high-quality experience. 4.2: the app must do more than wrap a website; it needs native, lasting utility. Nov 2025 update explicitly targets clone/copycat apps of popular titles.

**Common triggers**
- Template apps: same codebase, different content packs, multiple bundle IDs.
- WKWebView shell around an existing site with no native capability.
- AI-generated single-feature apps indistinguishable from hundreds of others.
- Resubmitting a rejected app unchanged under a new bundle ID (fast-track to a 4.3 flag on the whole account).

**Fix (structural — a reply won't save you)**
- Consolidate variants into one app with IAP/configuration.
- Add native-only value: offline mode, widgets, push, HealthKit/ARKit/camera integration, system share sheet, Live Activities.
- Differentiate visibly: unique UI, unique data, unique workflow.

**Resubmission wording.** Enumerate concrete differentiators: "Since the previous review, the app adds: offline caching of all content, a lock-screen widget, HealthKit sync, and <unique feature>. It is not a repackaged website: <native capabilities list>." If accused of duplicating another developer's app, prove independent authorship and distinct functionality; if you own the "other" app, consolidate instead of arguing.

## 5.1.x — Privacy (surface only; deep compliance → apple-legal-max)

**Requirement.** 5.1.1(i): accessible privacy policy in-app and in the listing. 5.1.1(ii)-(iii): consent + data minimization. 5.1.1(v): required login only when core functionality demands it; account creation ⇒ in-app account deletion. 5.1.2(i): disclose and get explicit consent before sharing personal data with third parties — **including third-party AI services** (added Nov 13, 2025). ATT prompt required for cross-app tracking, forbidden when you don't track.

**Common triggers**
- Privacy policy URL 404s or points to a homepage.
- Vague purpose strings: "This app needs camera access."
- Account signup exists but deletion is "email us."
- App sends chat/user content to an LLM API without disclosure/consent.
- ATT prompt shown with no tracking (or tracking with no prompt); functionality gated on accepting tracking.
- Privacy nutrition labels contradicting observed network traffic.

**Fix.** Specific purpose strings naming the feature; in-app account deletion that actually deletes; consent sheet before third-party AI calls; align labels/manifest/policy (hand the alignment work to apple-legal-max).

**Resubmission wording.** Point to exact locations: "Account deletion: Settings → Account → Delete Account (video: <link>). Purpose strings updated in build <N> to state the feature each permission powers. Data sent to <AI provider> is disclosed on first use with an explicit consent screen (screenshot attached)."

## 4.0 / 4.1 / 4.8 — Design, Copycats, Login Services

- **4.0 Design**: broken layouts, truncated text, ignored safe areas, non-functional UI on any supported size class. Fix by running on smallest/largest devices and iPad compatibility mode. Resubmission: list the screens fixed with before/after screenshots.
- **4.1 Copying**: don't clone another developer's app/name/icon. If flagged wrongly, document your app's independent history (first release dates, trademark, design evolution).
- **4.8 Login Services**: any third-party login (Google, Facebook, X) requires also offering Sign in with Apple or another service that limits data to name/email, allows email hiding, and doesn't track. Fix: add Sign in with Apple; it's the cheapest compliance path.

## 2.5.x — Software Requirements (quick hits)

- 2.5.1: private API use → automated flag, near-certain rejection. Audit third-party SDKs; run `nm -u` / check upload warnings.
- 2.5.2: no downloading executable code that changes functionality post-review (JS via WKWebView/JavaScriptCore within Apple's rules is the exception; hot-pushing new features is not).
- 2.5.4: declared background modes must be genuinely used (audio, location, VoIP).

## Escalation Ladder

1. Resolution Center reply (evidence-first, one clear ask).
2. New build if the fix requires code; always bump build number and describe the delta.
3. App Review Board appeal — only after a failed reply, only once per rejection, with the complete factual record.
4. Phone consultation: request a call via Contact Us; reviewers sometimes offer 30-minute appointments for guideline discussion.
5. If the rejection cites a rule in legal flux (external links, age verification), state the regulation/court order you're relying on precisely and ask for escalation to the review team's policy group.
