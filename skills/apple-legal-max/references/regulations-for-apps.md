# Regulations for Apple-Platform Apps

Engineering-grade summaries keyed to articles/sections. Not legal advice; route final calls through counsel. Fast-moving sections carry as-of dates.

## GDPR (EU/EEA/UK-GDPR) — applies if you offer the app to, or monitor, people in the EU/EEA/UK, regardless of where you are

**Lawful basis (Art 6)** — every processing purpose needs exactly one:
- Contract (Art 6(1)(b)): core app functionality the user signed up for. NOT ads, NOT analytics.
- Consent (Art 6(1)(a)): tracking, personalized ads, most third-party analytics, marketing. Must be freely given, specific, informed, unambiguous, and as easy to withdraw as to give (Art 7).
- Legitimate interests (Art 6(1)(f)): fraud prevention, security, some first-party analytics — requires a documented balancing test (LIA).
- Note: reading/writing identifiers on the device (IDFA, cookies-equivalent, local storage for non-essential purposes) additionally triggers the **ePrivacy Directive Art 5(3)** consent requirement — this is why "legitimate interest" cannot launder ad tracking.

**Consent UX checklist:**
- [ ] No pre-ticked boxes or consent bundled into ToS acceptance (Art 7(2))
- [ ] "Reject" as prominent and easy as "Accept" (EDPB guidance; national DPA enforcement)
- [ ] Granular per purpose (analytics ≠ ads ≠ personalization)
- [ ] Withdrawal path inside the app settings, not an email address
- [ ] ATT prompt ≠ GDPR consent and vice versa; you may need both (ATT for Apple policy, a consent layer for GDPR/ePrivacy). CMPs (TCF-registered) handle the ad-stack signal.

**Data subject rights (Arts 15–22):** access, rectification, erasure ("right to be forgotten"), restriction, portability, objection. Respond within one month. Apple's 5.1.1(v) account deletion satisfies the *front door* of Art 17, not the back office (backups, processors, logs).

**Other load-bearing items:** processor DPAs (Art 28) with every SDK/analytics/cloud vendor; records of processing (Art 30, small-org exemptions narrow); breach notification 72h to DPA (Art 33), to users if high risk (Art 34); DPIA for high-risk processing incl. large-scale tracking or children (Art 35); EU representative if you're outside the EU with no establishment (Art 27); international transfers via adequacy / EU-US Data Privacy Framework / SCCs (Ch V). Children: Art 8 sets consent age 16 (member states may lower to 13); UK Age Appropriate Design Code applies design duties to services "likely to be accessed" by under-18s.

## United States — state comprehensive privacy laws **[as of July 2026]**

No federal comprehensive law. ~19–20 state laws in force; new in 2026: **Indiana, Kentucky, Rhode Island (Jan 1, 2026)**. Already effective: CA (CCPA/CPRA), VA, CO, CT, UT, TX, OR, MT, FL (FDBR), DE, IA, NE, NH, NJ, TN, MN (Jul 2025), MD (Oct 2025).

Common denominator obligations (thresholds vary — typically 100k residents' data, or 25k + majority revenue from data sales; CA adds $25M-revenue prong so small high-revenue apps can be covered):
- [ ] Privacy notice: categories collected, purposes, third-party sharing, rights, opt-out methods
- [ ] Rights: access, delete, correct, portability, opt out of **sale**, **targeted advertising**, and **profiling**
- [ ] "Sale" is broad — sharing device IDs with ad SDKs for consideration counts in CA and most states
- [ ] Sensitive data (precise geolocation, health, biometrics, kids' data): opt-in consent in most states (CO, CT, VA, TX…); CA uses "limit use" model
- [ ] **Universal opt-out / Global Privacy Control**: must honor in ~12 states incl. CA, CO, CT, TX, MN as of 2026 — for apps this maps to honoring platform/OS signals and in-app opt-outs
- [ ] Cure periods sunset across 2026 in CT, DE, KY, MN, MT — enforcement is getting faster

2026 effective/enforcement dates to watch:

| Date (2026) | Event |
|---|---|
| Jan 1 | Indiana, Kentucky, Rhode Island laws effective; Texas app-store age law effective |
| Jul 1 | Connecticut amendments (expanded scope/minors), Arkansas, Utah amendments effective |
| Aug 1 | New California data-broker registration requirements |
| Through 2026 | Cure periods sunset (CT, DE, KY, MN, MT) |

Standouts:
- **Maryland (MODPA):** strictest — hard data-minimization (collect only what's *reasonably necessary* for the requested service), flat **ban on selling sensitive data**, ban on targeted ads to known under-18s. If you comply with Maryland you likely comply everywhere.
- **Washington My Health My Data:** consumer-health data outside HIPAA, **private right of action** — fitness/wellness/cycle apps take note.
- **Illinois BIPA:** biometrics, private right of action, per-scan damages history — FaceID-adjacent features that never leave the Secure Enclave are fine; your own face/voice templates are not.
- **App-store age verification laws** **[fast-moving — verify]:** Texas App Store Accountability Act (SB 2420, effective Jan 1, 2026) and Utah's equivalent (in force 2026) push age verification/parental consent to Apple; developers consume Apple's **Declared Age Range API** and must request age signals where required. Louisiana and others pending.

## COPPA + Apple's kids rules (US, under-13)

FTC's **amended COPPA Rule**: effective June 23, 2025; full compliance was required by **April 22, 2026** — fully in force now.
- Applies if the app is **directed to children** or you have **actual knowledge** of under-13 users.
- [ ] Verifiable parental consent (VPC) before collecting personal info — now including **separate, standalone consent for third-party disclosures** (e.g. targeted advertising)
- [ ] "Personal information" now includes **biometric identifiers** and government IDs
- [ ] Written information security program: named coordinator, annual risk assessment, safeguards, testing (new)
- [ ] Data retention: only as long as necessary, published retention policy; indefinite retention banned
- [ ] Direct notice + online notice (privacy policy child section)
- Apple layer: **Kids Category (Guideline 1.3)** — no third-party analytics/ads except narrowly with contractual commitments and no IDFA; parental gate before commerce/external links; **5.1.4** requires COPPA/GDPR-K compliance for any app targeting kids even outside the Kids Category. Age rating tiers are now 4+/9+/13+/16+/18+ (2025 revamp).

## India DPDP Act 2023 + DPDP Rules 2025 — brief **[as of July 2026]**

Rules notified Nov 2025; phased: consent-manager provisions from **Nov 13, 2026**; full compliance (notices, rights, breach protocol) by **May 13, 2027**; soft enforcement through 2026. Consent-centric (no legitimate-interest equivalent for most uses); notice in plain language (+ 22 scheduled languages ideal); verifiable parental consent for under-18s and **no tracking/targeted ads directed at children**; penalties up to ₹250 crore. If you're distributing in India: start with consent records, notice, and grievance contact.

## EU DMA — iOS distribution & payments **[fast-moving — as of July 2026, verify fees]**

What exists today for EU storefronts:
- **Alternative app marketplaces** (iOS 17.4+) and **Web Distribution** from your own domain (iOS 17.5+): both require Apple **notarization** (baseline automated + human review: accuracy, functionality, no malware, privacy floor), marketplace/web-distribution authorization, and — for marketplaces — content moderation, anti-fraud, and payment-dispute processes.
- **External purchase links / alternative payments** (StoreKit External Purchase Link Entitlement): custom links to your site allowed; system disclosure sheet shown; you own refunds, support, fraud. Transactions reported via External Purchase Server API.
- **Fees:** Core Technology Commission (**CTC, 5%** on externally-linked digital sales) live since June 26, 2025. Apple announced a single-business-model transition (CTF → CTC for everyone) targeted Jan 1, 2026, but **as of mid-2026 the CTF→CTC unification has not fully landed** and remains under discussion with the European Commission — verify current fee schedule (initial acquisition fee, tiered Store Services fee, CTF €0.50/first-annual-install > 1M) on developer.apple.com/support/dma-and-apps-in-the-eu/ before advising on money.
- Legal consequences for you: alternative distribution ≠ escape from GDPR/consumer law; you take on **merchant-of-record duties** (VAT, EU consumer withdrawal rights (Directive 2011/83/EU 14-day rules for digital content), refund handling) that Apple otherwise absorbs.

## EU DSA — trader status (applies to EVERYONE selling in the EU, not just DMA users)

- DSA Art 30/31: marketplaces must verify traders. Apple requires developers with paid apps/IAP to declare and verify **trader status** (address, phone, email displayed on the EU product page). Non-verified apps have been removed from EU storefronts since **Feb 17, 2025**. Non-trader (hobbyist, fully free) declaration is possible but narrow.

## Export compliance & encryption

- Every build upload answers the encryption question. Set **`ITSAppUsesNonExemptEncryption`** in Info.plist to stop the per-build prompt: `false` if you use no crypto or ONLY exempt crypto (HTTPS/ATS, OS-provided crypto for standard purposes); `true` otherwise (then provide compliance docs and `ITSEncryptionExportComplianceCode` once approved).
- US EAR: most apps using standard crypto qualify as **mass-market / 5D992** with self-classification; a **annual self-classification report** to BIS/NSA may apply if you rely on that route rather than Apple's coverage — counsel check for non-standard/proprietary crypto.
- **France:** separate national regime (decree 2007-663). Non-exempt encryption distributed on the **French storefront** requires a **declaration to ANSSI** before distribution; App Store Connect asks for confirmation you've filed it. Standard-exempt apps (`ITSAppUsesNonExemptEncryption=false`) skip it.

## ATT ↔ legal consent interplay (common confusion)

| Signal | Governs | Satisfies |
|---|---|---|
| ATT prompt (allowed) | Apple policy 5.1.2 — permission to *track* per Apple's definition | NOT GDPR consent, NOT CCPA opt-out handling by itself |
| GDPR/ePrivacy consent banner (CMP) | EU law — lawful basis + device-storage access | NOT the ATT requirement (Apple still requires its prompt) |
| CCPA "Do Not Sell/Share" + GPC | US state law opt-outs | NOT ATT; and ATT denial ≠ automatic CCPA opt-out record |

Rules: never gate app functionality on ATT acceptance (5.1.2 + 3.2.2); if ATT is denied you may not track by any means (fingerprinting ban, 2.3.1); sequence CMP consent and ATT so the ad SDK initializes only after BOTH signals permit; store consent records with timestamp + policy version (GDPR Art 7(1) proof).

## Breach response floor (app developer scale)

- [ ] GDPR: notify lead DPA within **72h** of awareness (Art 33) unless no risk; affected users "without undue delay" if high risk (Art 34)
- [ ] US states: attorney-general/consumer notice under all 50 states' breach statutes (timelines 30–90 days; residency-based)
- [ ] COPPA-scope apps: FTC scrutiny — security-program documentation is now mandatory evidence
- [ ] India DPDP: notify Data Protection Board + affected users (Rules 2025 set format/timeline) **[phasing]**
- [ ] Keep processor incident-notification clauses in every SDK/cloud DPA so the 72h clock is survivable

## Quick jurisdiction trigger table

| You distribute in… | Floor requirements |
|---|---|
| Anywhere | Apple guidelines 5.1.x, privacy manifest, labels, export answer |
| EU/EEA | GDPR + ePrivacy consent, trader status (DSA), Art 27 rep if no EU entity |
| UK | UK GDPR + Age Appropriate Design Code |
| US | State patchwork (design to Maryland/CA), COPPA if kids, WA MHMD if health-ish |
| India | DPDP notice + consent + grievance officer **[phasing through 2027]** |
| France (with real crypto) | ANSSI declaration |
| Brazil / Canada / Australia | LGPD / PIPEDA / Privacy Act — GDPR-shaped; a GDPR-grade program mostly covers them (counsel confirm) |
