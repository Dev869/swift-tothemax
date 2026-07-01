# App icons, launch screens, and branding restraint

Verified against the HIG "App icons" page (changelog: June 8 2026 "Refined guidance for
Liquid Glass") and WWDC25/26 sessions. The icon is the single most-seen artifact of the
app — it deserves designer-level attention even in a solo project.

## The layered icon model (current)

Icons on every platform are now **layered**, rendered live by the system with Liquid
Glass effects (specular highlights, refraction, translucency) that adapt per platform,
per size, and per OS version. A flat single image still works but forfeits all of it —
ship layers.

- **iOS / iPadOS / macOS / watchOS:** background layer + one or more foreground layers,
  assembled in **Icon Composer** (ships with Xcode). One `.icon` design fans out to all
  four platforms and all appearance variants.
- **tvOS:** 2–5 layers in an Xcode image stack; parallax on focus.
- **visionOS:** background + 1–2 upper layers in an image stack; rendered as a 3D circular
  object with system shadows between layers.

### Icon Composer workflow

1. Design layers in any tool; export each layer separately — **vector (SVG/PDF)
   preferred** so edges stay crisp at every size; PNG for raster/mesh-gradient art.
2. Import foreground layers; define the background in Composer (it supports solid colors
   and gradients natively — you rarely need a background image; if you import one it must
   be full-bleed and opaque).
3. Adjust placement, group layers to apply Liquid Glass attributes (specular, refraction,
   translucency) at group level; annotate the default / dark / mono appearances.
4. Preview across sizes, platforms, and OS versions; export for Xcode.
5. **Beta (WWDC26 tooling):** Icon Composer adds per-layer refraction annotation and
   "content effects", plus an interactive preview of how the icon renders on *earlier*
   OS releases — icons render sharper with more defined edges on OS 27.

### Layer craft rules

- Clearly defined, hard edges on foreground shapes — soft/feathered edges break the
  system's highlights and shadows.
- Vary layer opacity to create depth; import layers opaque and dial transparency inside
  Composer so you can preview interaction with system effects.
- Do NOT bake in effects the system now owns: no drop shadows between layers, no bevels,
  no baked specular highlights, no glows, no pre-blurred edges. Static baked effects
  fight the dynamic system ones.
- Convert all text to outlines; no live text in exported layers.

## Shape and masking

Provide **unmasked, full-bleed layers**; the system applies the mask. Pre-rounding your
own corners ruins specular edges and produces jagged masking.

| Platform | You provide | System masks to |
|---|---|---|
| iOS, iPadOS, macOS | 1024×1024 px square layers | Rounded rectangle (concentric with hardware/UI radii) |
| tvOS | 800×480 px rectangular layers | Rounded rectangle, landscape |
| watchOS | 1088×1088 px square layers | Circle |
| visionOS | 1024×1024 px square layers | Circle (3D, embossed upper layers) |

Keep primary content centered — corner and circular masking crops edges, and tvOS focus
motion crops further (keep a generous safe zone; foreground layers crop more than
background). macOS no longer gets bespoke freeform icon shapes: same squircle, same
layered rendering as iOS. Color spaces: sRGB or Display P3 (Gray Gamma 2.2 for grayscale).

## Appearance variants

Users choose Home Screen icon appearance on iOS, iPadOS, and macOS. Six rendered
variants exist: **default, dark, clear light, clear dark, tinted light, tinted dark**.
The system auto-generates any you don't design — but auto-generated dark/tinted icons
from a busy light icon usually look muddy. Annotate at minimum **default, dark, and
mono** in Icon Composer (mono drives the clear/tinted family).

- Keep the same core shapes across all variants — never swap elements per appearance
  (users lose the icon when they switch modes).
- Dark variant: start from the light design, keep complementary colors, avoid
  excessively bright fills; a colored background usually gives better contrast than
  black-on-dark.
- Clear/tinted variants are more subdued by design; test legibility against real
  wallpapers.
- **Alternate app icons** (team skins, seasonal, pro-user thanks) are supported on
  iOS/iPadOS/tvOS (+ compatible visionOS); each alternate needs its own dark/clear/tinted
  variants, must remain recognizably *your* app, and passes App Review like the primary.

## Icon design judgment

- One concept, minimal shapes. If it needs explaining, it's too complex; fine detail
  disappears at 29pt and turns to noise under system highlights.
- Simple background (solid/gradient) that pushes the foreground forward; you don't have
  to fill the canvas with content.
- Filled, overlapping shapes with slight translucency layer beautifully under Liquid
  Glass — this is the current house style for a reason.
- Illustration over photography, always. Photos die at small sizes and split poorly into
  layers. Don't replicate UI screenshots or standard components in the icon.
- Text only if it IS the brand (a mnemonic letter is fine); never words like "New",
  "Play", or the app's name (it's already displayed beneath).
- No Apple hardware replicas (copyrighted), no thin hairlines, no sharp needle corners.
- One 1024px master is the only required raster; the system scales all smaller variants.
  Audit legibility at Spotlight/Settings size anyway.
- Keep the icon visually consistent across every platform you ship — same concept, same
  palette, adjusted to each canvas shape.

## Launch screens

The launch screen's only job is to make launch feel instant. It is scaffolding, not a
stage.

- Make it a wireframe of the app's first screen: background color, bar placeholders,
  empty content shells. When the real UI paints, the transition should be undetectable.
- **No logos, no wordmarks, no taglines, no spinners, no animation, no version numbers.**
  A "splash screen" is the single loudest web-port smell on the platform — branding at
  launch is a toll, not a welcome.
- No text at all if avoidable (it can't localize and will flash-swap).
- Use semantic colors so the launch screen matches light/dark mode; test both.
- SwiftUI/UIKit apps configure this via the launch screen storyboard or
  `UILaunchScreen` Info.plist keys (background color, image, bar visibility) —
  keep it dumb.
- If the app genuinely needs seconds of setup, launch into the shell instantly and load
  content with placeholders/`redacted` inside the real UI — never extend the launch
  screen artificially.

## Branding restraint inside the app

Branding in a native app is felt, not seen: a distinctive accent color, considered
typography, the icon, and the quality of motion.

- One brand accent applied through the app tint; semantic colors for everything else.
  Don't paint nav bars in brand color by default — Liquid Glass bars want content, not
  paint, underneath.
- Custom display type is acceptable for large titles/marketing moments; body text stays
  SF/Dynamic Type.
- Don't put the logo in the navigation bar of every screen; the user knows what app
  they're in. The About/settings screen and paywall are the sanctioned logo venues.
- Mascots and illustration belong in empty states and onboarding, not layered over
  functional screens.
- If every screen screams the brand, the app reads as a marketing site; if no screen
  does, it reads as a template. Aim for: unmistakable in a screenshot lineup, invisible
  during use.
