# Accessibility: audit workflow and SwiftUI semantics

Accessibility is a correctness requirement, not a feature tier. Roughly 1 in 4 users
enables at least one accessibility setting; Dynamic Type alone is used by a third of iOS
users. Design reviews that skip this file are incomplete.

## VoiceOver semantics in SwiftUI

The goal: a blind user hears the same *meaning* a sighted user sees, in the same priority
order, with no noise.

### Labels, values, hints

- Every interactive element needs an `accessibilityLabel` that names the thing, not the
  glyph: "Add Reminder", not "plus.circle". Labels are nouns/short phrases, never include
  the control type ("button" is announced automatically), never include state.
- State goes in `accessibilityValue`: a custom rating control has label "Rating",
  value "3 of 5 stars".
- `accessibilityHint` describes the result of activating, phrased as "Adds…", "Opens…".
  Hints are optional and users can disable them — never put essential info in a hint.
- SF Symbols and text-bearing system controls usually label themselves. Verify rather than
  duplicate: a redundant label makes VoiceOver read everything twice.

### Grouping and order

- Collapse composite rows: `.accessibilityElement(children: .combine)` turns a cell of
  title + subtitle + timestamp + icon into ONE swipe stop with a sensible combined label.
  A list where each cell costs 4 swipes is the most common VoiceOver failure.
- Use `.accessibilityElement(children: .ignore)` + explicit label when the combined
  auto-label reads garbage (e.g., data visualizations).
- Reading order follows layout order; if visual layout diverges from logical order, fix
  with `.accessibilitySortPriority(_:)` (higher reads first).
- Hide decoration: `.accessibilityHidden(true)` on ornamental images, separators,
  background blurs. If it carries no information, it costs a swipe for nothing.

### Actions and custom controls

- Swipe actions, drag handles, and long-press menus need
  `.accessibilityAction(named:)` equivalents — VoiceOver users cannot perform a
  trailing-swipe on a row.
- Adjustable controls (sliders, steppers, custom): `.accessibilityAdjustableAction` so
  swipe up/down changes the value.
- Custom tap targets must carry `.isButton` trait; toggles `.isToggle`; headers
  `.isHeader` (headers power the rotor's fast navigation — every section title in a long
  screen should be a header).
- Charts: adopt Swift Charts and audio graphs (`AXChartDescriptor`) rather than labeling
  a bitmap "chart of revenue".

### Announcements

- Post `AccessibilityNotification.Announcement` for async outcomes ("Upload complete") —
  a visual toast is silent to VoiceOver.
- Screen changes that re-lay the page should move focus intentionally
  (`@AccessibilityFocusState`), e.g., to the error banner after failed validation.

## Dynamic Type discipline

- **Text styles everywhere.** `.font(.body)`, `.font(.headline)` — never
  `.font(.system(size: 17))`. Custom fonts: `Font.custom(_:size:relativeTo:)`.
- **Scale the layout, not just the text.** Dimensions that must track text
  (icon sizes, padding around labels, custom control heights) use
  `@ScaledMetric(relativeTo: .body) var iconSize = 24`.
- **No fixed-height containers around text.** Fixed frames + AX sizes = clipped text.
  Let stacks grow; use `ViewThatFits` or switch an `HStack` to `VStack` at accessibility
  sizes (`@Environment(\.dynamicTypeSize)`, check `.isAccessibilityCategory`).
- **Test at both ends:** xSmall and AX5 (largest). AX5 body text is 53pt — if the design
  only survives to XXL, it fails. Xcode Previews:
  `.environment(\.dynamicTypeSize, .accessibility5)`.
- `minimumScaleFactor` is a last resort for short labels (never below ~0.75, never on
  body copy); `lineLimit(1)` on user content is a bug at large sizes.
- Multi-column layouts collapse to one column at accessibility sizes; trailing text in
  list rows wraps below the title.
- Truncation review: at AX sizes, buttons keep full labels; drop icons before dropping words.

## Contrast ratios

WCAG-derived numbers Apple's tooling checks:

| Content | Minimum ratio |
|---|---|
| Body/regular text < 18pt (or < 14pt bold) | 4.5:1 |
| Large text ≥ 18pt regular / ≥ 14pt bold (≈ 17pt semibold+) | 3:1 |
| Icons, control shapes, focus indicators | 3:1 |
| Enhanced (AAA) target for reading-heavy apps | 7:1 |

- Semantic colors and vibrant material styles pass automatically in both modes; hardcoded
  grays are where failures live. Never use `systemGray3`+ for text on materials.
- Test with **Increase Contrast** ON: semantic colors shift; custom colors don't — provide
  high-contrast variants in the asset catalog if you ship custom colors.
- Text over images/glass always needs a scrim, gradient, or the regular (not clear)
  Liquid Glass variant. The clear glass variant over bright media requires a ~35 %-opacity
  dark dimming layer.
- Don't rely on color alone for state: pair red/green with symbols
  (checkmark/exclamation) and labels.

## Reduce Motion (and friends)

- Read `@Environment(\.accessibilityReduceMotion)`. When true: replace movement-based
  transitions with cross-fades; kill parallax, auto-playing video, bouncing, and
  scale-from-zero effects; keep functional animation (progress indicators) but make it
  subtle.
- Pattern: `withAnimation(reduceMotion ? nil : .spring) { … }` or opacity-only
  `transition`.
- Also honor: `accessibilityReduceTransparency` (glass falls back to opaque — verify your
  custom overlays still look intentional), `accessibilityDifferentiateWithoutColor`,
  `accessibilityInvertColors` (mark media with `.accessibilityIgnoresInvertColors()`), and
  Prefer Cross-Fade Transitions.
- Autoplaying/looping animation must pause via Reduce Motion or an in-app control;
  flashing above 3 Hz is prohibited outright.

## Audit workflow

Run this loop per screen, before UX sign-off:

1. **Accessibility Inspector (Xcode → Open Developer Tool).** Target the simulator, run
   an **Audit** on each screen. It flags: missing labels, low contrast, small hit regions
   (< 44pt), clipped text at large type, missing traits. Fix everything or document why not.
2. **Inspection pointer.** Hover elements to verify label/value/traits/hint read exactly
   what you designed — this is the fastest label-quality check.
3. **Live VoiceOver pass on device.** Triple-click side button (set the Accessibility
   Shortcut). Swipe through the screen start to finish: Can you reach everything? Is
   order sane? Does each stop say something useful? Do custom gestures have actions?
   Simulator VoiceOver is not representative; use hardware.
4. **Dynamic Type sweep.** Settings → Accessibility → Display & Text Size → Larger Text →
   AX5. Walk every screen. Then xSmall.
5. **Setting matrix:** Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text,
   Smart Invert — one pass each on the app's top 3 screens.
6. **Automate:** XCUITest `app.performAccessibilityAudit()` in UI tests catches
   regressions (labels, contrast, hit region, Dynamic Type clipping) in CI. Scope with
   audit types when third-party views produce noise.

## Assistive Access

Assistive Access (iOS/iPadOS) runs apps in a simplified, high-clarity mode for users with
cognitive disabilities — large controls, one thing per screen, a persistent back button.

- Adopt the native scene support (SwiftUI `AssistiveAccess` scene; UIKit
  `UISupportsFullScreenInAssistiveAccess`) so the app fills the screen and opts into the
  simplified chrome instead of appearing letterboxed.
- Design the Assistive Access experience as a *reduced feature set*, not a shrunken UI:
  pick the 1–2 core tasks, remove ambiguity, use large tap targets (the system grid
  provides them) and literal icon + text labels.
- Avoid timed interactions and multi-step modality; every screen needs an obvious single
  purpose. Test by enabling Assistive Access in Settings → Accessibility.

## Review gate

A screen passes when: every element has a correct label/value/trait; a full VoiceOver
traversal is coherent; layout survives xSmall→AX5; all text/icons meet 4.5:1 / 3:1;
Reduce Motion produces a calm variant; the Inspector audit is clean; and the core flow is
completable with VoiceOver, Switch Control timing off, and Assistive Access on.
