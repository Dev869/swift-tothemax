# Visual Iteration Workflow — Give Yourself Eyes

Purpose: the closed-loop workflow that lets a coding agent *see* the SwiftUI it writes — render, screenshot, read the image, fix — so UI is never declared done blind.

**Contents**: [The Loop](#the-loop) · [Simulator CLI Mastery](#simulator-cli-mastery) · [Rendering Without a Full App](#rendering-without-a-full-app) · [Snapshot Testing as Agent Eyes](#snapshot-testing-as-agent-eyes) · [Hot Reload](#hot-reload) · [Accessibility & Layout Auditing](#accessibility--layout-auditing) · [MCP & Companion Tooling](#mcp--companion-tooling) · [Quickstart](#quickstart-give-yourself-eyes-in-6-commands)

## The Loop

You cannot judge UI you have not seen. Every UI task runs this cycle until the image looks right:

```
edit → build → render → SCREENSHOT → inspect (Read the PNG) → fix → repeat
```

1. **Edit** the SwiftUI source.
2. **Build** for the simulator (or render the component in isolation — see below).
3. **Render** — launch in the simulator, or write a PNG via `ImageRenderer`/snapshot test.
4. **Screenshot** to a file on disk.
5. **Inspect** — actually read the image file. Critique against HIG standards: spacing, alignment, hierarchy, truncation, dark-mode legibility, tap-target size.
6. **Fix** and go again.

Hard rule: **never declare UI work done without having looked at it.** "It compiles" and "the preview should look like…" are not evidence. One screenshot beats any amount of reasoning about layout math. When done, look at the *matrix*: light + dark, default + accessibility-XXL Dynamic Type, smallest + largest supported device.

## Simulator CLI Mastery

Everything below is verified against Xcode 26.x. `booted` targets the single booted device; use a UDID when several are booted.

### Devices: list, boot, shutdown

```bash
xcrun simctl list devices available          # names + UDIDs + state
xcrun simctl boot "iPhone 17 Pro"            # boots headless — fine for screenshots
open -a Simulator                            # only if you want the window visible
xcrun simctl shutdown all                    # or a specific name/UDID
xcrun simctl erase "iPhone 17 Pro"           # factory-reset a misbehaving device
```

A device booted via `simctl boot` renders fully without Simulator.app open — screenshots, launches, and video capture all work headless.

### Build for the simulator and find the .app

```bash
xcodebuild -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
```

With `-derivedDataPath build`, the product lands at a **predictable** path:

```
build/Build/Products/Debug-iphonesimulator/App.app
```

Without it, ask xcodebuild where things went instead of guessing at `~/Library/Developer/Xcode/DerivedData/App-<hash>/...`:

```bash
xcodebuild -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR'
```

For workspaces add `-workspace App.xcworkspace`; for bare projects `-project App.xcodeproj`. Add `-quiet` to keep logs readable, or pipe through `xcbeautify` if installed.

### Install, launch, screenshot

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch booted com.example.App              # add --console-pty to stream stdout/os_log
xcrun simctl io booted screenshot /tmp/ui/screen.png    # THEN READ THE IMAGE
xcrun simctl terminate booted com.example.App           # before relaunching a fresh build
xcrun simctl openurl booted "myapp://deep/link"         # drive deep links / universal links
```

`screenshot` accepts `--type png|jpeg|tiff` and `--mask ignored|black|alpha` for notched displays (default PNG is what you want).

### Record video (animations, transitions, scrolling)

```bash
xcrun simctl io booted recordVideo --codec h264 --force /tmp/ui/flow.mp4 &
REC=$!            # simctl prints "Recording started" to stderr when capturing
# ...drive the app (launch, openurl, UI test)...
kill -INT $REC    # SIGINT stops and finalizes the file
```

Default codec is HEVC; use `--codec h264` for broad playback. Extract frames to inspect an animation: `ffmpeg -i /tmp/ui/flow.mp4 -vf fps=10 /tmp/ui/frames/f%03d.png`.

### Clean status bar (do this before any screenshot you keep)

```bash
xcrun simctl status_bar booted override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl status_bar booted clear     # restore reality afterwards
```

### Appearance, Dynamic Type, contrast — the visual matrix from the CLI

```bash
xcrun simctl ui booted appearance dark          # or: light. No arg prints current.
xcrun simctl ui booted content_size extra-large # Dynamic Type from the CLI
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large  # AX5, the stress test
xcrun simctl ui booted content_size increment   # step up/down one category
xcrun simctl ui booted increase_contrast enabled
```

Note the spelling: `content_size` (underscore). Standard categories run `extra-small` → `extra-extra-extra-large`; extended range is `accessibility-medium` → `accessibility-extra-extra-extra-large`. Changes apply live to running apps — set, screenshot, set next, screenshot.

### Push notifications and privacy grants (no dialogs mid-run)

```bash
xcrun simctl push booted com.example.App payload.json   # payload: top-level "aps" dict, ≤4KB
xcrun simctl privacy booted grant photos com.example.App
xcrun simctl privacy booted grant location com.example.App   # also: contacts, calendar,
xcrun simctl privacy booted reset all                        # microphone, motion, reminders…
xcrun simctl addmedia booted /tmp/fixtures/*.jpg             # seed the photo library
```

Put `"Simulator Target Bundle": "com.example.App"` at the top level of the push payload and you can drop the bundle-id argument. Grant privacy *before* launching so permission alerts never block a screenshot.

## Rendering Without a Full App

### PreviewHost: a scratch target for isolated components

Building the whole app to look at one card is slow. Keep (or create) a minimal `PreviewHost` iOS app target in the workspace whose entire job is rendering one component full-screen, selected by launch argument:

```swift
@main struct PreviewHostApp: App {
    var body: some Scene {
        WindowGroup {
            switch ProcessInfo.processInfo.arguments.dropFirst().first {
            case "card":     ProductCard(.fixture)
            case "empty":    EmptyStateView(.noResults)
            default:         GalleryList()   // every registered component, in one scroll
            }
        }
    }
}
```

```bash
xcrun simctl launch booted com.example.PreviewHost card
xcrun simctl io booted screenshot /tmp/ui/card.png
```

Link the components via a local SwiftPM package so PreviewHost compiles in seconds and never drags in app-level dependencies (auth, networking, SwiftData stacks). Pass fixtures, not live data.

### ImageRenderer: PNGs with no simulator at all

`ImageRenderer` (iOS 16/macOS 13+) rasterizes a SwiftUI view directly. From a **macOS command-line tool or macOS XCTest** in the workspace, an agent can render a whole component matrix to files in one shot — no simulator, no app lifecycle:

```swift
@MainActor
func renderMatrix() {
    for scheme in [ColorScheme.light, .dark] {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = ProductCard(.fixture)
                .environment(\.colorScheme, scheme)
                .dynamicTypeSize(size)
                .frame(width: 393)                    // iPhone-width column
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                write(cg, to: "/tmp/ui/card-\(scheme)-\(size).png")
            }
        }
    }
}
```

Render, then read every PNG. **Limits — know when this lies to you:**

- Only pure SwiftUI renders. UIKit/AppKit-backed views come out blank: `Map`, `WebView`/`WKWebView`, `UIViewRepresentable`/`NSViewRepresentable` content, `VideoPlayer`, some `ScrollView` internals.
- No app environment: async `task {}` work won't have run, `AsyncImage` shows its placeholder. Inject loaded fixtures.
- Must run on `@MainActor`; give the view an explicit `.frame` or you get intrinsic-size surprises.
- macOS renders with macOS styling for some controls — final verification of navigation bars, sheets, and toolbars still needs the simulator loop.

Use `ImageRenderer` for fast inner-loop iteration on leaf components; use the simulator for anything with chrome, navigation, or interaction.

## Snapshot Testing as Agent Eyes

[pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) turns "looked at it once" into "checked on every test run" — and its failure artifacts are images an agent can read.

```swift
// Package.swift: .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0")
import SnapshotTesting
import XCTest

final class ProductCardSnapshots: XCTestCase {
    func testCard() {
        let view = ProductCard(.fixture)
        for (name, config) in [("phone", ViewImageConfig.iPhone13), ("phoneLandscape", .iPhone13(.landscape))] {
            assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, layout: .device(config: config)), named: name)
            assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, layout: .device(config: config),
                                                traits: .init(userInterfaceStyle: .dark)), named: "\(name)-dark")
        }
        assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13),
                                            traits: .init(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)),
                       named: "ax5")
    }
}
```

- **Record mode**: first run records references into `__Snapshots__/` next to the test file. Re-record deliberately with `withSnapshotTesting(record: .all) { … }`, a `record:` argument, or env var `SNAPSHOT_TESTING_RECORD=all` on the test run. Never blind-re-record to silence a failure — that deletes your eyes.
- **`perceptualPrecision: 0.98`** (with `precision: 1`) tolerates GPU/OS anti-aliasing drift while still catching real regressions; exact-match snapshots flake across machines.
- **Reading failures**: a failed assertion prints the paths of the reference and the freshly-rendered failure image (also attached to the `.xcresult`). Read *both* PNGs, diff them mentally, and decide: regression (fix code) or intended change (re-record that one test).
- **Snapshots as acceptance criteria**: for a UI task, write the snapshot test first against the target device/trait matrix, implement until it records clean, then hand the recorded PNGs over as the "here's what I built" evidence. Run on **one pinned simulator model + OS** (e.g. iPhone 17 Pro / iOS 26.5) — snapshots are per-device-resolution.

## Hot Reload

For live iteration, [InjectionNext](https://github.com/johnno1962/InjectionNext) (successor to InjectionIII) recompiles edited files and swaps implementations into the running simulator app, paired with the [Inject](https://github.com/krzysztofzablocki/Inject) package:

```swift
// Package: krzysztofzablocki/Inject. In each iterable view:
import Inject
struct ProductCard: View {
    @ObserveInjection var inject
    var body: some View {
        content.enableInjection()
    }
}
```

Setup: run the InjectionNext app (or InjectionIII from the Mac App Store), add `-Xlinker -interposable` to *Other Linker Flags* for Debug simulator builds, launch the app in the simulator, save a file — the view re-renders in ~1s. Screenshot after each save with `simctl io booted screenshot`.

**Can** reload: `body` implementations, method bodies, computed properties, most view-layer logic. **Cannot** reload: adding/removing stored properties (memory layout), new types, `@main`/App-struct changes, protocol conformances — those need a real rebuild.

Agent cost/benefit: hot reload shines in long polish sessions on one screen (10+ consecutive tweaks) — save → screenshot beats a 30–90s rebuild each cycle. For one-or-two-shot changes, or anything touching model/stored state, skip the setup and just rebuild; `xcodebuild`'s incremental builds plus the PreviewHost target are usually fast enough and never lie about layout.

## Accessibility & Layout Auditing

Accessibility Inspector (Xcode → Open Developer Tool) is GUI-only; the scriptable equivalent is the XCTest audit API (iOS 17+), which runs Accessibility-Inspector-class checks from a UI test:

```swift
func testAccessibility() throws {
    let app = XCUIApplication()
    app.launch()
    try app.performAccessibilityAudit()                       // all audit types
    try app.performAccessibilityAudit(for: [.dynamicType, .contrast, .textClipped]) { issue in
        issue.auditType == .contrast && issue.element == knownFalsePositive   // return true to ignore
    }
}
```

Audit types: `.contrast`, `.elementDetection`, `.hitRegion`, `.sufficientElementDescription`, `.dynamicType`, `.textClipped`, `.trait`, `.all`. Run it per-screen as you navigate in the test; each violation fails with the element and reason. Wire it into the same `xcodebuild test` invocation as snapshots.

For **previews and ImageRenderer**, bake the stress matrix into environment overrides instead of device settings:

```swift
ProductCard(.fixture)
    .dynamicTypeSize(.accessibility3)              // does it wrap or clip?
    .environment(\.colorScheme, .dark)
    .environment(\.layoutDirection, .rightToLeft)  // RTL: chevrons, leading/trailing sanity
    .environment(\.locale, Locale(identifier: "de")) // long-word truncation check
```

Render that matrix (ImageRenderer loop or snapshot variants) and *look* at every cell. The three classic blind-agent failures — text clipped at AX sizes, unreadable dark-mode contrast, broken RTL mirroring — are all invisible in code and obvious in a screenshot.

## MCP & Companion Tooling

If an XcodeBuildMCP-class MCP server is connected (`mcp__XcodeBuildMCP__*` tools: build, simulator management, launch, screenshot), prefer its typed tools over raw `xcodebuild`/`simctl` strings — same loop, fewer quoting bugs.
If the `figma:figma-swiftui` skill is available and the task starts from a Figma design, load it: the design frame becomes the reference image you diff your screenshots against.
Either way the discipline is identical: render, read the image, compare, fix.

## Quickstart: Give Yourself Eyes in 6 Commands

```bash
# From a clean checkout to a screenshot on disk:
xcrun simctl boot "iPhone 17 Pro"                                              # 1. boot (headless OK)
xcodebuild -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build -quiet build                                          # 2. build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/App.app # 3. install
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100  # 4. clean chrome
xcrun simctl launch booted com.example.App                                     # 5. launch
xcrun simctl io booted screenshot /tmp/ui/screen.png                           # 6. screenshot — now READ it
```

Then flip the matrix and reshoot: `xcrun simctl ui booted appearance dark`, `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`. The task is done when the *images* are right, not when the code compiles.
