# Document Skeletons & App Store Connect Placement

Skeleton outlines, not finished legalese. Fill factually from the app's real data flows, then have counsel review. Every `⚖️` marks a business/legal decision the developer (or counsel) must make — never invent these.

## 1. Privacy Policy skeleton

Satisfies Guideline 5.1.1(i) structure + GDPR Arts 12–14 + CCPA/state notice requirements when filled honestly.

```
1. Who we are
   - Legal entity name, address, contact email  [GDPR Art 13(1)(a)]
   - EU/UK representative + DPO if applicable   [Art 27, Art 37] ⚖️
2. What we collect (mirror your nutrition labels EXACTLY — reviewers diff these)
   - Per category: data items, source (you / device / third parties)
   - Automatically collected: device identifiers, crash/usage data, IP
   - From SDKs: name each SDK vendor and what it receives
3. Why (purpose + lawful basis table)                      [Art 13(1)(c)]
   | Purpose | Data | Lawful basis (EU) |
   e.g. Provide service / Contract; Analytics / Consent or LI ⚖️;
   Ads / Consent; Security / Legitimate interests
4. Tracking & advertising
   - Whether you "track" per Apple's definition; ATT behavior
   - Whether you "sell"/"share" per CCPA (ad SDKs usually = yes) ⚖️
   - Opt-out: ATT, in-app settings, GPC honoring statement (US states)
5. Sharing
   - Processors (hosting, analytics, crash) — commit that they provide
     equal or greater protection                    [Guideline 5.1.1(i)]
   - No sale of sensitive data if MD applies         [MODPA]
6. Retention & deletion
   - Per-category retention periods or criteria      [Art 13(2)(a)]
   - Account deletion: exactly how, in-app           [Guideline 5.1.1(v)]
7. Your rights (EU rights list; US state rights list incl. appeal; how to
   exercise; response timelines; authorized agents for CA)
8. International transfers (DPF / SCCs / hosting locations) ⚖️
9. Children (either "not directed at children under 13/16" + what happens
   on discovery, or full COPPA direct-notice section for kids' apps)
10. Security (measures in plain terms; breach notification commitment)
11. Changes to this policy (notice method, effective date at top)
12. Contact / complaints (email; right to lodge complaint with DPA [Art 77])
```

## 2. Terms of Service skeleton (service contract — needed for accounts/UGC/services)

```
1. Acceptance & eligibility (minimum age — align with age rating and
   COPPA/GDPR Art 8 stance) ⚖️
2. The service (what it is; free/paid tiers; no-guarantee of availability)
3. Accounts (accuracy, one per person, security duties, our termination
   rights, YOUR in-app deletion right — cross-ref 5.1.1(v))
4. Acceptable use (prohibited conduct list; UGC apps: harassment, illegal
   content, spam, scraping, reverse engineering)
5. User content & license (you keep ownership; grant us a limited license
   to host/display; our takedown rights; DMCA agent + process (US, 17
   U.S.C. §512) for UGC apps)
6. Purchases & subscriptions (incorporate §4 block below; Apple bills via
   Apple Account; refunds through Apple for IAP)
7. Intellectual property (our marks/code; feedback license)
8. Third-party services & links (not ours, not our responsibility)
9. Disclaimers & limitation of liability ("AS IS"; cap) ⚖️ jurisdiction-
   sensitive — consumer law in EU/AU limits enforceability
10. Indemnity (UGC/commercial apps) ⚖️
11. Termination (by either side; effect on data — cross-ref privacy policy)
12. Governing law & disputes (venue; arbitration/class waiver ⚖️ — varies
    by jurisdiction, often unenforceable vs EU consumers)
13. Changes to terms (notice + continued-use acceptance; material changes
    require fresh assent for subscriptions in several US states)
14. Contact
```

## 3. EULA: standard vs custom (Guideline/Schedules — "Minimum Terms")

**Default:** Apple's standard EULA (Licensed Application End User Agreement, apple.com/legal/internet-services/itunes/dev/stdeula/) applies automatically. Most apps should keep it and write nothing.

**Choose a custom EULA only if** you need extra license restrictions (enterprise seats, anti-benchmarking, beta confidentiality) — and then it MUST embed Apple's **Instructions for Minimum Terms of Developer's EULA**, i.e. these deltas on top of your terms:

- [ ] Acknowledgement: agreement is between developer and user only; **Apple is not a party** and doesn't own/maintain the app
- [ ] License scope: non-transferable, use on Apple-branded products the user owns/controls, per App Store Usage Rules (Family Sharing acknowledgment)
- [ ] Maintenance & support: **developer solely responsible**; Apple has no obligation
- [ ] Warranty: developer responsible; on failure user may notify Apple for a refund of purchase price — Apple's only warranty obligation
- [ ] Product claims (user/third-party): developer, not Apple, addresses them (product liability, regulatory noncompliance, consumer protection)
- [ ] IP claims: developer responsible for infringement claims defense
- [ ] Legal compliance: user reps they're not in an embargoed country / prohibited-party list
- [ ] Developer name, address, and contact for user questions/complaints
- [ ] Third-party terms: user must comply with applicable third-party agreements
- [ ] **Apple and subsidiaries are third-party beneficiaries** with the right to enforce against the user

## 4. Subscription terms block (auto-renewable — Guideline 3.1.2(a) + state ARLs)

Must appear **in the purchase flow UI** (before buy) and be reflected in the App Store description / ToS. Required disclosures:

```
• Title of the subscription
• Length of subscription period (weekly/monthly/annual)
• Price, and price per unit if applicable (e.g. $9.99/month)
• Payment charged to your Apple Account at confirmation of purchase
• Subscription automatically renews unless canceled at least 24 hours
  before the end of the current period; renewal charged within 24 hours
  prior to the end of the current period
• Manage/cancel: Settings > [your name] > Subscriptions (or App Store
  account settings) after purchase
• Free trial terms: length, what happens at expiry, that unused trial time
  is forfeited on purchase (if applicable)
• Links: Privacy Policy + Terms of Use (EULA) — functional in the app AND
  in App Store metadata [3.1.2]
```

State auto-renewal laws (CA ARL, and 2025–26 amendments; FTC click-to-cancel status is litigation-dependent **[verify]**) add: clear-and-conspicuous pre-purchase disclosure, acknowledgment email with cancellation instructions, and cancellation as easy as sign-up — Apple's subscription system satisfies the mechanics for IAP, but YOUR web-sold subscriptions (external purchase links, DMA channels) must implement all of it yourself.

## 5. Where every URL/document goes in App Store Connect

| Document | Location in App Store Connect | Notes |
|---|---|---|
| Privacy Policy URL | App > **App Privacy** section (per-platform field) | Required for ALL apps before submission; shown on product page. Also link it inside the app (Settings/About) — 5.1.1(i) |
| Privacy nutrition labels | App > **App Privacy** questionnaire | Editable anytime, no binary needed; keep in sync with manifest report |
| Custom EULA | App > General > **App Information > License Agreement** (Edit) | Paste text or apply per-country; absent = Apple standard EULA |
| Terms of Use (EULA) link for subscription apps | **App description** field or in-app functional link | Required by 3.1.2 if using standard EULA; custom EULA in App Information also satisfies it |
| Support URL | App Information | Required; real support contact behind it |
| Trader status & contact (EU) | Business/App Information > **Trader information** (DSA) | Verified address/phone/email; displayed on EU product page |
| Age rating | App > **Age Rating** questionnaire | 2025 system (4+/9+/13+/16+/18+); answer updated questions; can set higher minimum age |
| Export compliance | Per-build question, or `ITSAppUsesNonExemptEncryption` in Info.plist | France ANSSI confirmation prompted when non-exempt |
| Account deletion | No URL field — reviewed in-app | Ensure discoverable path; note it in Review Notes if buried |
| Subscription auto-renew disclosures | In purchase UI + description; subscription group metadata | Reviewed under 3.1.2 |

## Drafting rules for this skill

1. Never generate a policy that claims less collection than the nutrition labels — reviewers and plaintiffs diff them.
2. Enumerate SDKs from the lockfile before drafting §2 of the privacy policy.
3. Date every document ("Effective: …") and keep a change log for GDPR Art 5(2) accountability.
4. Plain language beats boilerplate: GDPR Art 12(1) requires "concise, transparent, intelligible."
5. Output every ⚖️ item as an explicit question list back to the user at the end of a drafting task.
