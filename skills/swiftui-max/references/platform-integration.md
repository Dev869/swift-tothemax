# Platform Integration

UIKit/AppKit bridging, widgets, App Intents, and multiplatform structure. Concurrency details of bridged code → **swift-language**.

## Bridging in: UIKit/AppKit views inside SwiftUI

First ask: does SwiftUI have it natively now? (26) added `WebView`, rich-text `TextEditor`; (17+) `ContentUnavailableView`, `Map` improvements. Bridge only for genuinely missing components (PHPickerViewController, UIKit-only third-party SDKs, camera preview layers).

```swift
struct DocumentCamera: UIViewControllerRepresentable {   // NSViewRepresentable on macOS
    var onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator          // delegate goes to Coordinator, never to a view struct
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        init(onScan: @escaping ([UIImage]) -> Void) { self.onScan = onScan }
        // delegate methods call onScan(...)
    }
}
```

Rules:
- **`update*` must be idempotent and diff-aware.** It runs on every SwiftUI update; setting `text` unconditionally fights the user's typing. Compare before writing:

```swift
// WRONG
func updateUIView(_ tv: UITextView, context: Context) { tv.text = text }   // caret jumps, IME breaks
// RIGHT
func updateUIView(_ tv: UITextView, context: Context) {
    if tv.text != text { tv.text = text }
}
```

- The representable struct is recreated constantly; the `Coordinator` persists. State that must survive updates lives in the coordinator or the UIKit object — never in the struct.
- Size negotiation: implement `sizeThatFits(_:uiView:context:)` (16+) when the UIKit view's intrinsic size matters; otherwise SwiftUI proposes and the view fills.
- Pass SwiftUI Environment through: `context.environment` gives you colorScheme, layoutDirection, etc. — respect them.
- (26) UIKit/AppKit gained **automatic observation tracking**: `@Observable` model reads inside `layoutSubviews`, `viewWillLayoutSubviews`, and the new `updateProperties()` override invalidate automatically — shared models now drive both worlds without NotificationCenter glue.

## Bridging out: SwiftUI inside UIKit/AppKit apps

- `UIHostingController(rootView:)` / `NSHostingController` — embed as child VC; add to hierarchy properly (`addChild`, `didMove(toParent:)`).
- Sizing: `hostingController.sizingOptions = [.intrinsicContentSize]` (16+) so Auto Layout sees SwiftUI's ideal size; on macOS `NSHostingView` similarly.
- Share state via one `@Observable` model injected into the root view and retained by the UIKit side — don't rebuild the hosting controller to "update" it; mutate the model.
- `UIHostingConfiguration` for SwiftUI cells inside `UICollectionView`/`UITableView` — the sane path for incremental migration of list-heavy apps:

```swift
cell.contentConfiguration = UIHostingConfiguration { RecipeRow(recipe: recipe) }
```

- Incremental migration order that works: leaf views → cells (`UIHostingConfiguration`) → whole screens (`UIHostingController`) → navigation shell last.

## Widgets & Live Activities (brief)

Widgets are **timeline snapshots**, not mini-apps: no scrolling, no arbitrary interaction, budgeted refreshes.

```swift
struct StandupWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "standup", intent: SelectTeamIntent.self, provider: Provider()) { entry in
            StandupView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)   // required since iOS 17
        }
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
```

- Interactivity = App Intents: `Button(intent: CompleteTaskIntent(id:))` / `Toggle(isOn:intent:)` inside the widget — the intent runs in your process, then the timeline reloads.
- Push data with `WidgetCenter.shared.reloadTimelines(ofKind:)` after model changes; don't poll aggressively — the system throttles.
- (26) widgets render with Liquid Glass treatment automatically; keep `containerBackground` semantic so tinted/clear rendering modes work. Widgets extended to visionOS and CarPlay with the 26 SDKs.
- **Live Activities** (ActivityKit): `ActivityAttributes` + `ActivityConfiguration`; design all Dynamic Island states (compact leading/trailing, minimal, expanded). Update via `activity.update(_:)` or remote push (`pushType: .token`); always `end(_:dismissalPolicy:)`. Budget: frequent-update entitlement only if genuinely live (scores, rides).
- Shared code target: widget extension + app share models via a framework/package; persist shared state in an App Group container.

## App Intents (brief)

One `AppIntent` definition serves Shortcuts, Siri, Spotlight, widgets, controls, and Apple Intelligence surfaces:

```swift
struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    @Parameter(title: "Minutes") var minutes: Int
    func perform() async throws -> some IntentResult { 
        try await TimerService.shared.start(minutes: minutes); return .result()
    }
}
```

- Expose entities with `AppEntity` + `EntityQuery` so parameters autocomplete with real user data.
- `AppShortcutsProvider` publishes zero-setup phrases. Keep `perform()` fast; long work → `openAppWhenRun = true` or background continuation.

## Documents (27β)

The 26-era `FileDocument`/`ReferenceFileDocument` remain the shipping APIs. The WWDC26 betas add `ReadableDocument`/`WritableDocument` with `nonisolated async` incremental read/write (off-main-thread I/O, progress reporting) plus `DocumentCreationSource` + `NewDocumentButton` for multiple "new document" flows. Adopt behind availability checks; mark beta in code review.

## Multiplatform structure

Default to **one multiplatform target**, not per-platform targets; diverge surgically.

| Divergence level | Tool |
|---|---|
| API exists everywhere, values differ | shared code + computed constants (`horizontalSizeClass`, platform-agnostic spacing) |
| Modifier missing on one platform | small extension: `func glassToolbarIfAvailable()` with `#if os(...)` inside |
| Compile-time platform API | `#if os(iOS)` / `#if canImport(UIKit)` around the *smallest* expression |
| Whole different idiom (menu bar vs tab bar) | separate root views per platform, shared feature views |

```swift
// WRONG — forking entire views per platform duplicates 90% shared layout.
#if os(macOS)
struct SettingsView: View { /* 200 lines */ }
#else
struct SettingsView: View { /* 195 identical lines */ }
#endif

// RIGHT — isolate the difference.
content
    #if os(macOS)
    .frame(minWidth: 420)
    #endif
```

- Idioms to respect per platform: macOS — `Settings` scene, menu commands (`Commands`), keyboard shortcuts, resizable windows (`windowResizeAnchor` (26)); iPadOS — pointer/keyboard, `NavigationSplitView` over stacked navigation; watchOS — glanceable single-purpose screens, (27β) gains reorderable containers; visionOS — depth via `glassBackgroundEffect`, ornaments, RealityKit scenes (26 added deeper SwiftUI↔RealityKit unification: attachments as components, spatial layout modifiers).
- **(27β)** iPhone apps become user-resizable (iPhone mirroring, windows on iPad): audit fixed-width assumptions, use `ViewThatFits`/adaptive grids, and test with Xcode 27 preview resize handles. Treat as the forcing function to delete `UIScreen.main.bounds` remnants.
- Conditional modifiers: never `if condition { view.modifier() } else { view }` in a way that changes identity (see performance ref); write availability-safe modifier extensions returning `some View` from a single branch shape where possible.
