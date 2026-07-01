# Monetization Compliance — IAP, External Purchases, Subscriptions, Kids

State verified July 2026. The external-purchase landscape is litigation-driven and changes fast — re-verify guideline 3.1.1(a)/3.1.3 and Apple's developer news before shipping any external payment path.

## The Baseline Rule (Guideline 3.1.1)

Digital goods and services consumed in the app — feature unlocks, subscriptions, premium content, game currency, ad removal, digital tips — must use Apple In-App Purchase. Forbidden substitutes: license keys, QR codes, cryptocurrency payments, "activate on our website" flows (outside the regional allowances below).

**Never requires IAP (3.1.3(e) and friends):** physical goods, real-world services (rides, delivery, bookings), person-to-person real-time services (3.1.3(d) — tutoring, medical consults, fitness training; one-to-few and one-to-many MUST use IAP), enterprise apps for employees/students (3.1.3(c)), reader apps for previously purchased content (3.1.3(a)), multiplatform services honoring purchases made elsewhere (3.1.3(b)) — as long as the app doesn't steer non-US users to buy outside.

## External Purchase Links by Region (mid-2026 matrix)

### United States storefront — links allowed, state IN FLUX
- Since the May 2025 guideline update (forced by the *Epic v. Apple* contempt ruling), apps on the **US storefront** may include buttons, external links, and calls to action to outside purchase flows for digital goods — **no entitlement required**, no mandated warning screens, and (as of the injunction) no Apple commission on those linked purchases.
- **Flux warning:** the Ninth Circuit (Dec 11, 2025) affirmed the contempt finding but vacated the blanket commission ban — Apple may charge a commission on linked-out purchases limited to costs "genuinely and reasonably necessary" for the external handoff. The Supreme Court granted Apple's cert petition in June 2026. Expect the zero-commission status and possibly the link rules themselves to change. Architect paywalls so the external path can be toggled per storefront remotely (server-driven config), and re-check the current guideline text at every release.
- Users completing purchases on your site get none of Apple's refund/family-sharing/Ask-to-Buy machinery — handle support, taxes, and refunds yourself.

### European Union — DMA regime
- **External links & alternative payments:** allowed under Apple's June 2025 updated business terms; earlier restrictions on link count/format were dropped after the EC's €500M anti-steering fine (April 2025).
- **Fees (as of Jan 1, 2026):** the per-install Core Technology Fee is gone, replaced by a **5% Core Technology Commission (CTC)** on digital goods revenue across all EU distribution paths (App Store, Web Distribution, alternative marketplaces). On top: **Store Services Fee** — Tier 1 (mandatory basics) 5%, Tier 2 (full store services: auto-updates, search suggestions, etc.) 13% (10% for Small Business Program) — plus a **2% Initial Acquisition Fee** for new users' first 6 months when using external purchase links.
- **Alternative distribution:** alternative marketplaces and Web Distribution exist for iOS/iPadOS in the EU; all binaries still require Apple **notarization** (baseline review for fraud/security, not full guideline review — but guidelines marked "NR" still apply).
- Flag to users: EU terms have been revised roughly twice a year under EC pressure; treat every fee number as provisional.

### Other storefronts with link entitlements
- **StoreKit External Purchase Link Entitlement** available in specific regions (historically: South Korea, Japan adjustments under JFTC/smartphone competition act, Netherlands dating apps, Brazil developments). Each has its own entitlement, disclosure sheet, and reduced-commission scheme. Without the entitlement, external purchase links on these storefronts = 3.1.1 rejection.
- Everywhere else: external links, buttons, or CTAs for digital purchases remain prohibited.

### Reader apps (3.1.3(a))
- May link to account creation/management on the web via the External Link Account entitlement (not needed on the US storefront). Cannot offer IAP for the same content alongside the external flow in ways the guideline prohibits — read the current text.

### Quick region matrix (digital-goods external purchase paths, July 2026)

| Storefront | Links/buttons out? | Entitlement needed | Apple cut on linked sales | Stability |
|---|---|---|---|---|
| United States | Yes | No | $0 today; cost-based commission possible after remand/SCOTUS | LOW — active litigation |
| European Union | Yes (links, alt payments, alt marketplaces, web distribution) | Yes (EU alternative terms) | 2% acquisition + 5–13% Store Services + 5% CTC | MEDIUM — EC reviews ongoing |
| South Korea / Japan / other entitlement regions | Yes, within each scheme's rules | Yes, region-specific | Reduced commission per scheme | MEDIUM |
| Everywhere else | No | N/A — prohibited | 15/30% standard IAP only | HIGH |

## Subscription Requirements (3.1.2)

Reviewers reject paywalls on sight for missing disclosures. Before the purchase button, show:
- **Price and billing period** ("$4.99/month"), including per-unit price for bundles.
- **Auto-renewal disclosure**: subscription renews unless cancelled; how to cancel (Settings → Apple Account → Subscriptions).
- **Free-trial terms**: trial length, what happens at expiry, post-trial price, and the fact that it converts automatically. "Try Free" buttons with the price in 6pt gray text get rejected — Apple expects the binary choice to be legible.
- **Restore Purchases**: visible, functional control (StoreKit 2: `AppStore.sync()` + entitlement recheck). Missing restore is one of the most common 3.1.x rejections.
- **Functionality**: subscriptions must unlock something ongoing; don't paywall previously-free core features for existing users without care; content promised must exist at review time.
- Links to Terms of Use (EULA) and Privacy Policy on or reachable from the paywall (Apple's standard EULA is acceptable if you use it; custom EULAs go in the App Description field or in-app — drafting belongs to apple-legal-max).

**Pricing display traps:** never show prices fetched from your server in a different currency than StoreKit's localized price; always render `Product.displayPrice`. Hardcoded "$" strings break in 174 storefronts and invite 2.3.2 metadata mismatch rejections.

### Subscription mechanics reviewers and users hit

- **Subscription groups**: every auto-renewable subscription lives in a group; users hold one active subscription per group. Set upgrade/downgrade ranks deliberately — wrong ranks make "upgrades" behave as crossgrades and confuse proration.
- **Intro offers**: one introductory offer (free trial, pay-as-you-go, pay-up-front) per subscription per user, enforced by Apple. Don't promise "another free month" in marketing when the user already burned eligibility — that's a 2.3.2 misleading-metadata risk. Check `Product.SubscriptionInfo` eligibility before advertising the trial.
- **Promotional offers & win-back offers**: for existing/lapsed subscribers; require server-side signing (promotional) or App Store Connect configuration (win-back). Fine with review as long as displayed terms are accurate.
- **Offer codes**: redeemable via App Store or in-app redemption sheet; show the same disclosure set when the code applies a discounted period.
- **Price increases**: significant increases require explicit user consent via Apple's sheet (users who don't consent lapse); small increases may auto-apply with notice. Don't try to bypass with a "new" product silently replacing the old one while killing grandfathered pricing — users complain, Apple notices patterns.
- **Grace period / billing retry**: enable Billing Grace Period in App Store Connect and honor `isInBillingRetry` — cutting access instantly on a failed renewal is legal but churns; reviewers don't require it, revenue does.
- **Family Sharing for IAP**: opt-in per product; once enabled for a product, disabling it later removes access for family members — decide before launch.

## Kids Category & Minors (1.3, 5.1.4 — plus 2026 age-assurance flux)

- **Kids Category apps** may not include behavioral advertising or third-party analytics/ad SDKs that transmit identifiable data; contextual ads only, human-reviewed for age appropriateness.
- **Parental gates** required before commerce, external links, or leaving the app.
- **No links out** to purchases or websites without a parental gate; IAP must sit behind the gate too.
- **Data**: comply with COPPA/GDPR-K; don't send children's personal data to third parties (5.1.4); no ATT-style tracking of minors.
- **Age ratings (2025-2026 change):** Apple's global system now uses 4+, 9+, 13+, 16+, 18+; the updated questionnaire (covering ads, UGC, loot boxes, medical/wellness topics) became mandatory Jan 31, 2026. Stale answers block submission.
- **US state age-verification laws** (Texas App Store Accountability Act effective Jan 1, 2026; Utah, Louisiana following): Apple surfaces age signals via the **Declared Age Range API**; apps "likely to be accessed by minors" may need to request and honor the age range and obtain parental consent for certain features in those states. Region-specific, actively litigated — verify current scope before building.

## Other Purchase-Adjacent Rules

- **Loot boxes / paid randomized items**: disclose odds before purchase (3.1.1).
- **IAP credits/currency**: must not expire.
- **Crypto (3.1.5, revised Nov 2025)**: exchanges only where licensed, in regions where the app holds permissions; no mining on device; no crypto for unlocking features.
- **Tips for digital content** = IAP. Tips passed 100% to human creators for real-world value have nuances — read the current 3.2.1 list.
- **"Free" claims**: don't call the app free in metadata if core functionality requires payment (2.3.2/2.3.7).
- **Ads**: apps showing ads must declare them in the age questionnaire; ads must be appropriate to the app's rating; no full-screen unclosable interstitials (4.0 design + 2.1 completeness rejections).

## Standard Commission & Programs (for context when weighing external paths)

- **Standard IAP commission**: 30%; auto-renewable subscriptions drop to 15% after one year of continuous service per subscriber.
- **Small Business Program**: 15% on everything while proceeds stay under $1M/year (trailing). Enroll in App Store Connect — it is not automatic. Losing eligibility mid-year changes the math on whether US/EU external links are worth their support burden.
- **App Store Server Notifications v2 + server-side `Transaction` verification** are not review requirements, but reviewers do exercise refund/restore edge cases; client-only receipt logic that breaks on Ask to Buy or refunds shows up as 2.1 "IAP not functional."

## Ad-Monetized Apps

- Ads require honest age-rating questionnaire answers (frequency, content) — mismatches are metadata rejections.
- Personalized ads across other companies' apps/sites ⇒ ATT prompt required; ATT denial must degrade to contextual ads, not blocked functionality (5.1.2).
- No ads in Kids Category except contextual, human-reviewed inventory; most ad SDKs are disqualifying there.
- Interstitials must be dismissible and not impersonate system UI (4.0/2.3.1); rewarded-video "watch to unlock" is fine.

## Compliance Decision Tree (run for every monetized flow)

1. Is the thing purchased consumed **in the app** and digital? → IAP required, subject to 2-4.
2. Is it physical / real-world / person-to-person real-time? → external payment fine (Apple Pay encouraged, not required).
3. Do you want to ALSO sell digital goods on the web and link to it? → US storefront: allowed today, verify current commission state. EU: allowed under DMA terms + fee stack. Entitlement regions: acquire entitlement first. Rest of world: don't link.
4. Subscriptions? → paywall disclosure set + restore + StoreKit-rendered price.
5. Any users under 18 plausible? → age questionnaire accuracy, parental gates if Kids Category, Declared Age Range for US state laws.
6. Anything ambiguous? → put the explanation in App Review notes preemptively; surprise is what converts gray areas into rejections.
