# UX patterns by screen type

Concrete do/don't guidance for the screens every app ends up needing. The recurring
principle: get the user to value fast, and let the system's vocabulary carry the UI.

## Onboarding

The best onboarding is a first screen so obvious it needs none. Onboarding exists to reach
the first "aha" moment fast — not to tour features.

**Do**
- Let users in before asking anything. Show real value (sample data, a template, a demo
  document) before sign-up. Defer account creation until it's required to save/sync.
- Keep any intro to ≤ 3 screens with a visible Skip on every one. One idea per screen.
- Teach in context, just-in-time: a one-time tip the first time the user reaches the
  relevant screen beats a front-loaded carousel they'll forget.
- Request permissions at the moment of need, each preceded by a one-sentence pre-prompt
  explaining the benefit ("Allow notifications so you know when your order ships").
  One permission per moment.
- Offer Sign in with Apple wherever there's third-party login (also an App Store rule).

**Don't**
- Don't wall the app behind signup, an email field, or a paywall before demonstrating value.
- Don't fire the notification permission dialog at first launch — the denial is nearly
  permanent.
- Don't replicate the App Store screenshots as an in-app slideshow.
- Don't gate re-entry: onboarding shows once; returning users go straight in.

## Settings

Settings is where confidence in an app quietly dies. Ruthless curation beats organization.

**Do**
- First, try to eliminate the setting: pick a good default or infer from behavior. Every
  setting is a design decision you outsourced to the user.
- Use grouped list style with system controls (toggles, pickers, steppers). Order by
  frequency of use; group by user goal, not by internal architecture.
- Put account/profile at top; About/legal/version at bottom. Destructive actions
  (Sign Out, Delete Account) last, in red, separated.
- Effects apply immediately — no Save button in settings.
- On macOS, settings live in a Settings window (⌘,); on iOS in a screen reachable from a
  tab or profile; never both a gear AND a hamburger.
- Deep-link into Settings.app for system permissions the user previously denied.

**Don't**
- Don't nest more than 2 levels deep. Don't create a "General" junk drawer.
- Don't restyle toggles/pickers; the system look tells users "this is a setting".
- Don't hide primary features in settings (if users toggle it weekly, it belongs in the UI).

## Paywalls (UX only — see app-review-max for compliance)

A paywall is a screen the user should *understand in 5 seconds* and never feel trapped in.

**Do**
- Lead with benefits (3–4 short lines, outcome-phrased), not a feature matrix.
- Show price + renewal period verbatim and adjacent to the purchase button:
  "$29.99/year, renews annually". If there's a trial: "1 week free, then $29.99/year" —
  the *then* price is the headline, not the fine print.
- Preselect the plan you recommend; max 3 options; label the difference ("Save 40 %").
- Big obvious close button (top corner, standard ✕), visible from first paint.
- Restore Purchases visible without scrolling. Use StoreKit views/sheets where possible —
  users trust the system purchase sheet.
- Trigger paywalls at moments of intent (user taps a locked feature), not on a timer.

**Don't**
- Don't hide or delay the close button, shrink it, or fake-disable it — dark pattern and
  a review flag.
- Don't use "FREE" as the visual headline for an auto-renewing trial.
- Don't show the paywall before the app has demonstrated any value, or re-show it every
  foreground.
- Don't invent countdown urgency for a subscription that isn't actually limited.

## Empty states

An empty state is the app's first screen for most new users — design it as the start of a
flow, not the absence of one.

**Do**
- Use `ContentUnavailableView` (or match its anatomy): SF Symbol, one-line title,
  one-sentence description, ONE primary action button. "No Recipes Yet / Save recipes
  from the web or add your own. / [Add Recipe]".
- Distinguish the four empties and design each: first-run (sell the action), user-cleared
  ("Inbox Zero" — celebrate, no button needed), no-search-results
  (`ContentUnavailableView.search` + suggest broadening), filtered-out (offer to clear
  filters).
- Keep surrounding chrome (tabs, nav) so the user still knows where they are.

**Don't**
- Don't show a blank scroll view, a lone spinner, or "No data".
- Don't use an error tone for a normal empty ("Nothing found!" reads as failure).
- Don't hide the empty state behind a modal prompt to sign up.

## Error and offline states

Errors are UX, not plumbing. Rule: preserve user input at all costs.

**Do**
- Match severity to surface: inline text under the field (validation) → status
  row/banner (sync, offline) → alert (data loss, blocking failure only).
- Structure every message: what happened → why (if known) → what to do next. Include a
  Retry action wherever retrying can work.
- Offline: keep cached content readable, mark it as possibly stale, queue user actions
  for later sync ("Will send when you're back online"). Airplane mode is a state, not an
  error.
- Validate inline as fields complete, not with an alert on submit; scroll to and focus
  the first invalid field.
- Skeletons/`redacted(reason: .placeholder)` for loads < ~2s; progress + cancel for
  longer; never a full-screen spinner over previously visible content.

**Don't**
- Don't show raw codes/exceptions ("Error 500", "NSURLErrorDomain -1009") as the message
  body; tuck codes into a details disclosure for support.
- Don't blame ("Invalid input"), apologize theatrically ("Oops!!"), or dead-end (a
  message with no action and no dismiss).
- Don't wipe a half-composed form because a request failed.
- Don't alert for transient blips that resolve on their own; retry silently once first.

## Search

**Do**
- Use the system search field (`.searchable`); on iOS 26+ give search a dedicated tab
  with `Tab(role: .search)` when it's a primary behavior (system floats it at the
  trailing edge of the tab bar). [Beta: iOS 27 re-integrates the search tab visually
  inside the tab bar.]
- Show recent searches and suggestions the moment the field focuses; update results
  live as the user types (debounced) when the corpus is local.
- Use tokens/scope bars for filtering; keep filters visible above results.
- Handle zero results with `ContentUnavailableView.search(text:)` plus "did you mean" /
  broaden-scope suggestions.

**Don't**
- Don't build a custom search bar that ignores the keyboard's Search key, dictation, or
  the cancel affordance.
- Don't clear the query when the user backs out of a result.
- Don't make search modal if browsing is also a first-class activity — search
  complements navigation, it doesn't replace it.

## Lists vs grids

Choose by what the user scans by:

| Users identify items by… | Use |
|---|---|
| Text (title/metadata) | List — faster vertical scan, swipe actions, more rows/screen |
| Image (photos, covers, products) | Grid — 2–3 columns compact, more when regular width |
| Both, user preference varies | Offer a list/grid toggle, persist the choice |

**Do**
- List rows: ≥ 44pt tall, leading thumbnail, title (Headline) + subtitle (Subheadline,
  `.secondary`), trailing metadata; disclosure indicator only if a push follows.
- Add swipe actions for the top 1–2 actions, context menu for the rest, pull-to-refresh
  on any server-backed list.
- Grids: uniform cell aspect ratio, adaptive columns (`GridItem(.adaptive)`) so iPad and
  landscape gain columns; label cells under the image, not overlaid, unless the image
  guarantees contrast.
- Sectioned lists with headers become VoiceOver rotor landmarks — use real headers.

**Don't**
- Don't put more than one line of metadata in a grid cell — that's a list wanting to
  happen.
- Don't infinite-scroll without any position anchors (section index, headers,
  scroll-to-top on status-bar tap must work).
- Don't lazy-load images without fixed cell sizes (layout shift while scrolling reads
  as jank).
