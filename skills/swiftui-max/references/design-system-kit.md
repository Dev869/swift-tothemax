# Design System Kit

Build a token-driven, accessibility-complete SwiftUI design system as a local SPM package — and make every generated screen consume it instead of magic values.

Version tags: untagged = iOS 17 baseline; (18) = iOS 18; (26) = iOS 26 / Liquid Glass era; **(27β)** = WWDC26 betas — mark as beta in output code.

**TOC:** 1. Tokens · 2. Theming · 3. Component layer · 4. Packaging & snapshot contract · 5. Agent governance · 6. Worked mini-example

## 1. Token architecture

Four token families: color, spacing, typography, shape/motion. Everything downstream references these; nothing else defines raw values.

### Semantic colors

Name by role, not hue. Back with asset-catalog colors (free dark-mode + increased-contrast variants via "High Contrast" appearance in the asset editor), then expose through one extension.

```swift
// WRONG — hue-named, literal, no dark mode, no contrast variant
static let blue500 = Color(red: 0.22, green: 0.47, blue: 0.99)

// RIGHT — role-named, asset-backed (Assets: Any/Dark + High Contrast slots filled)
public extension Color {
    static let dsBackground   = Color("Background",    bundle: .module)
    static let dsSurface      = Color("Surface",       bundle: .module)
    static let dsTextPrimary  = Color("TextPrimary",   bundle: .module)
    static let dsTextMuted    = Color("TextMuted",     bundle: .module)
    static let dsAccent       = Color("Accent",        bundle: .module)
    static let dsDestructive  = Color("Destructive",   bundle: .module)
    static let dsSeparator    = Color("Separator",     bundle: .module)
}
```

- Prefer system semantics where they already exist (`.primary`, `.secondary`, `Color(.separator)`) — they get Liquid Glass vibrancy adaptation for free (26).
- If colors must come from code (server-driven themes), branch on `colorSchemeContrast` in the environment for increased-contrast variants.

### Spacing scale

```swift
public enum DSSpacing {
    /// 4-pt base grid. No other padding values exist.
    public static let xxs: CGFloat = 4
    public static let xs:  CGFloat = 8
    public static let sm:  CGFloat = 12
    public static let md:  CGFloat = 16
    public static let lg:  CGFloat = 24
    public static let xl:  CGFloat = 32
    public static let xxl: CGFloat = 48
}
// Usage: .padding(DSSpacing.md)  — never .padding(17)
```

### Typography — Dynamic Type must keep working

Custom fonts MUST be registered relative to a `TextStyle` so they scale with Dynamic Type. `Font.custom(_:size:)` alone is frozen — that's the classic mistake.

```swift
// WRONG — fixed size, ignores Dynamic Type entirely
Text(title).font(.custom("Inter-SemiBold", size: 22))

// RIGHT — scales like .title2, respects the user's size setting
public enum DSFont {
    public static let display  = Font.custom("Inter-Bold",     size: 34, relativeTo: .largeTitle)
    public static let title    = Font.custom("Inter-SemiBold", size: 22, relativeTo: .title2)
    public static let body     = Font.custom("Inter-Regular",  size: 17, relativeTo: .body)
    public static let caption  = Font.custom("Inter-Regular",  size: 12, relativeTo: .caption)
}
```

- Pure SwiftUI: `relativeTo:` is all you need. Bridging to UIKit? use `UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)`.
- If the brand has no custom font, alias tokens to system styles (`public static let body = Font.body`) — same call sites, zero cost.
- Never set a fixed frame height on text containers; let Dynamic Type grow them.

### Shape, elevation, motion

```swift
public enum DSRadius   { public static let card: CGFloat = 16; public static let control: CGFloat = 12 }
public enum DSElevation {
    public static func card(_ scheme: ColorScheme) -> some ShapeStyle { .shadow(.drop(radius: scheme == .dark ? 0 : 8, y: 2)) }
}
public enum DSMotion {
    public static let quick   = Animation.snappy(duration: 0.2)
    public static let standard = Animation.smooth(duration: 0.35)
    public static let emphasized = Animation.bouncy
}
```

Prefer `.rect(cornerRadius: DSRadius.card)` / `ConcentricRectangle()` (26) over hand-built shapes; concentric shapes nest correctly inside glass containers.

## 2. Theming via Environment

Inject a theme struct with `@Entry` (18) — no boilerplate `EnvironmentKey` conformances.

```swift
public struct DSTheme: Sendable, Equatable {
    public var accent: Color = .dsAccent
    public var surface: Color = .dsSurface
    public var cardRadius: CGFloat = DSRadius.card
    public static let standard = DSTheme()
    public static let contrast = DSTheme(accent: .dsTextPrimary)
}

public extension EnvironmentValues {
    @Entry var dsTheme: DSTheme = .standard
}

// Runtime switching: store selection in app state, inject at the root.
WindowGroup {
    RootView()
        .environment(\.dsTheme, settings.useContrastTheme ? .contrast : .standard)
        .tint(settings.useContrastTheme ? DSTheme.contrast.accent : DSTheme.standard.accent)
}
// Components read it: @Environment(\.dsTheme) private var theme
```

### Don't fight Liquid Glass (26)

The system chrome layer (bars, tab bars, sheets, standard buttons) is glass. Brand there via `.tint`, not by rebuilding chrome.

```swift
// WRONG — opaque brand-colored fake toolbar floating over content
HStack { /* buttons */ }.background(Color.dsAccent).clipShape(Capsule())

// RIGHT — glass chrome, brand as tint
GlassEffectContainer {
    HStack { /* buttons */ }
        .padding(DSSpacing.sm)
        .glassEffect(.regular.tint(.dsAccent.opacity(0.3)).interactive(), in: .capsule)
}
```

- Glass is for the *functional* layer only (controls, navigation, transient UI) — never for content cards, list rows, or text surfaces. Custom chrome is still fine for content-layer components: cards, banners, charts, empty states. Keep owning those with tokens.
- Standard buttons: `.buttonStyle(.glass)` / `.glassProminent` (26). visionOS-style backing: `glassBackgroundEffect`.
- Wrap availability once: `extension View { @ViewBuilder func dsGlass() -> some View { if #available(iOS 26, *) { glassEffect() } else { background(.ultraThinMaterial, in: .capsule) } } }`

## 3. Component layer — Style protocols are THE extension mechanism

Never fork a `MyButton` view when a `ButtonStyle` will do: styles keep system behavior (keyboard, pointer, accessibility traits, glass adoption) and restyle only the visual.

```swift
// WRONG — custom tappable view: loses Button semantics, focus, traits
struct DSButton: View { var body: some View { Text(title).onTapGesture(perform: action) } }

// RIGHT — a ButtonStyle; call sites stay `Button("Save") { … }`
public struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.dsTheme) private var theme
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.body.weight(.semibold))
            .padding(.vertical, DSSpacing.sm).padding(.horizontal, DSSpacing.lg)
            .frame(minHeight: 44)                                  // min tap target, always
            .background(theme.accent.opacity(configuration.isPressed ? 0.8 : 1),
                        in: .rect(cornerRadius: DSRadius.control))
            .foregroundStyle(.white)
            .animation(DSMotion.quick, value: configuration.isPressed)
    }
}
public extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { .init() }        // Button(...) .buttonStyle(.dsPrimary)
}
```

Same pattern for the whole family: `ToggleStyle`, `LabeledContentStyle`, `ControlGroupStyle`, `ProgressViewStyle`, `DisclosureGroupStyle`, `TabViewStyle`. Apply once high in the tree — styles flow down the environment.

Containers that styles can't express → custom container views with `@ViewBuilder`:

```swift
public struct DSCard<Content: View>: View {
    @Environment(\.dsTheme) private var theme
    @ViewBuilder var content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: theme.cardRadius))
    }
}
```

Cross-cutting decoration → compositional `ViewModifier`s (`.modifier(DSSectionHeader())`), not copy-pasted chains.

**Accessibility-complete by default** — bake into the component, don't leave it to call sites:
- `frame(minWidth: 44, minHeight: 44)` on anything tappable.
- Icon-only controls ship with `.accessibilityLabel` required in the initializer (make it a non-optional `String` parameter).
- Compose rows: `.accessibilityElement(children: .combine)` on cards/rows so VoiceOver reads one sensible element.
- Every component previewed at `.environment(\.dynamicTypeSize, .accessibility3)` before it merges.

## 4. Packaging: local SPM package

```
DesignSystem/Package.swift
  ├─ DSTokens      (colors xcassets, fonts, spacing/typography enums)
  ├─ DSComponents  (depends: DSTokens; styles, DSCard, modifiers)
  └─ DSGallery     (depends: DSComponents; preview catalog views)
```

```swift
// Package.swift (swift-tools-version: 6.1)
.target(name: "DSTokens", resources: [.process("Resources")]),   // → Bundle.module
.target(name: "DSComponents", dependencies: ["DSTokens"]),
.testTarget(name: "DSSnapshotTests", dependencies: ["DSComponents",
    .product(name: "SnapshotTesting", package: "swift-snapshot-testing")]),
```

- All asset access uses `bundle: .module` — `Color("Accent")` without it silently resolves against the app bundle and renders clear.
- Register packaged fonts at app launch (`CTFontManagerRegisterFontsForURL`) or via a `DSTokens.registerFonts()` helper called in the App init.
- `DSGallery` = one screen per component showing every state; embed it behind a debug menu in the app so designers review on device.

### Snapshot tests are the design-system contract

Matrix: light/dark × 3 Dynamic Type sizes. A failed snapshot IS the review process for visual change.

```swift
import SnapshotTesting, SwiftUI, Testing
@testable import DSComponents

@MainActor @Suite struct ButtonSnapshotTests {
    @Test func primaryButtonMatrix() {
        let view = Button("Save changes") {}.buttonStyle(.dsPrimary).padding()
        for scheme in [UIUserInterfaceStyle.light, .dark] {
            for size in [UIContentSizeCategory.medium, .extraExtraLarge, .accessibilityExtraLarge] {
                assertSnapshot(of: UIHostingController(rootView: view),
                               as: .image(traits: .init(mutations: { t in
                                   t.userInterfaceStyle = scheme; t.preferredContentSizeCategory = size })),
                               named: "\(scheme == .dark ? "dark" : "light")-\(size.rawValue)")
            }
        }
    }
}
```

Record on ONE pinned simulator (document it in the test target README); snapshots differ across OS versions and devices.

## 5. Governance for agents

When generating any screen in a repo that has a design system: **consume tokens and components — never emit raw values.**

- No `Color(red:green:blue:)`, no hex initializers, no `Color.blue` for brand roles.
- No `.padding(17)`-style literals — only `DSSpacing.*` (or default `.padding()`).
- No inline `Font.system(size:)` for text roles — only `DSFont.*` / system text styles.
- New visual pattern needed? Add a token/style to the package first, then use it. Never inline a one-off.

Detect drift before committing:

```bash
grep -rnE 'Color\(red:|Color\(hex|#colorLiteral' App/ --include='*.swift'
grep -rnE '\.padding\([0-9]+(\.[0-9]+)?\)|spacing: [0-9]{2,}' App/ --include='*.swift' | grep -v DSSpacing
grep -rnE '\.font\(\.system\(size:|Font\.custom\(' App/ --include='*.swift' | grep -v DSFont
```

Zero hits outside the `DesignSystem/` package = clean. Wire the greps into CI or a pre-commit hook.

## 6. Worked mini-example (compiles as-is in one target)

```swift
import SwiftUI

// Tokens.swift
enum Space { static let sm: CGFloat = 12; static let md: CGFloat = 16 }
enum Radius { static let card: CGFloat = 16 }
extension Color { static let dsSurface = Color(.secondarySystemBackground); static let dsAccent = Color.accentColor }
enum DSFont { static let title = Font.system(.title3, weight: .semibold); static let body = Font.body }

// PrimaryButtonStyle.swift
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.body.weight(.semibold))
            .padding(.vertical, Space.sm).padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .background(.dsAccent.opacity(configuration.isPressed ? 0.8 : 1), in: .capsule)
            .foregroundStyle(.white)
    }
}
extension ButtonStyle where Self == PrimaryButtonStyle { static var dsPrimary: Self { .init() } }

// Card.swift
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSurface, in: .rect(cornerRadius: Radius.card))
            .accessibilityElement(children: .combine)
    }
}

// Usage + snapshot test (test target: swift-snapshot-testing)
struct Demo: View {
    var body: some View {
        VStack(spacing: Space.md) {
            Card { Text("Storage almost full").font(DSFont.title); Text("212 GB of 256 GB used").font(DSFont.body).foregroundStyle(.secondary) }
            Button("Manage storage") {}.buttonStyle(.dsPrimary)
        }.padding(Space.md)
    }
}
// @Test func demo() { assertSnapshot(of: UIHostingController(rootView: Demo()), as: .image) }
```
