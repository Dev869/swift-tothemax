# Ecosystem Libraries — Curated Third-Party Catalog

Purpose: libraries worth adding instead of hand-rolling, verified alive as of mid-2026 — consult before building effects, image loading, components, or test infrastructure from scratch.

## Contents

1. [Effects & Animation](#1-effects--animation)
2. [Image Loading](#2-image-loading)
3. [Components & Layout](#3-components--layout)
4. [Symbols & Assets](#4-symbols--assets)
5. [Dev Loop: Hot Reload & Testing](#5-dev-loop-hot-reload--testing)
6. [Architecture (use with caution)](#6-architecture-use-with-caution)
7. [Utilities](#7-utilities)
8. [Networking](#8-networking)
9. [Adding a Dependency Responsibly](#9-adding-a-dependency-responsibly)

---

## 1. Effects & Animation

**Default:** hand-roll simple transitions with native `.animation`/`.transition`/`PhaseAnimator`. Reach for **Pow** for polished one-off effects, **ConfettiSwiftUI** for celebration moments, **Lottie** when designers hand you After Effects files, **Rive** for interactive state-machine animations.

### Pow
- SPM: `https://github.com/EmergeTools/Pow` (originally movingparts; free/MIT since the Emerge Tools acquisition)
- What: a bag of production-quality SwiftUI transitions and "change effects" (shine, shake, spray, jump, ping, smoke...).
- Reach for it when: a button/state change needs delight and hand-tuning a spring choreography would take hours.
- Maintenance (mid-2026): stable and maintained, low churn by design — last tagged release 1.0.5, repo activity through April 2026.
- Min platform: iOS 15 / macOS 12.

### ConfettiSwiftUI
- SPM: `https://github.com/simibac/ConfettiSwiftUI`
- What: one-modifier configurable confetti cannon.
- Reach for it when: a success/achievement moment needs confetti; do not build a particle system for this.
- Maintenance: maintained — 3.0.0 shipped January 2026.

### Lottie (lottie-ios)
- SPM: `https://github.com/airbnb/lottie-ios`
- What: renders After Effects/Bodymovin JSON animations natively (Core Animation engine).
- Reach for it when: design ships `.json`/`.lottie` files — onboarding illustrations, animated icons, loaders.
- Maintenance: very active (Airbnb) — 4.6.1 released June 2026.
- Note: use `LottieView` (SwiftUI wrapper is first-class since 4.x).

### Rive (rive-ios)
- SPM: `https://github.com/rive-app/rive-ios`
- What: runtime for Rive files — vector animations with interactive state machines and data binding.
- Reach for it when: animations must respond to input/state (toggles, characters, gamified UI), beyond Lottie's playback model.
- Maintenance: very active — commits through June 2026. The runtime is open source; the Rive editor is a commercial product with a free tier.
- Min platform: iOS 14.

## 2. Image Loading

**Default: Nuke.** Swift-first, async/await-native, excellent performance, and `LazyImage` is a proper SwiftUI citizen. Use **Kingfisher** if the team already knows it (largest community, equally solid). Use **SDWebImageSwiftUI** only when you need the SDWebImage plugin ecosystem (animated WebP/APNG coders). Do not use plain `AsyncImage` for lists — it has no configurable caching.

### Nuke
- SPM: `https://github.com/kean/Nuke` (SwiftUI views ship in the `NukeUI` product of the same package)
- What: image loading pipeline — memory/disk cache, prefetching, progressive decoding, `LazyImage` for SwiftUI.
- Reach for it when: any remote images in scrolling content.
- Maintenance: active — 13.0.6 released May 2026.

### Kingfisher
- SPM: `https://github.com/onevcat/Kingfisher`
- What: downloading + caching with `KFImage` for SwiftUI, processors, and a huge option set.
- Reach for it when: you prefer its API or need its image-processor chain; a fine co-default with Nuke.
- Maintenance: very active — 8.10.0 released June 2026.

### SDWebImageSwiftUI
- SPM: `https://github.com/SDWebImage/SDWebImageSwiftUI`
- What: SwiftUI layer (`WebImage`, `AnimatedImage`) over the veteran SDWebImage ObjC core.
- Reach for it when: you need SDWebImage's coder plugins (animated WebP, AVIF) or interop with an existing SDWebImage codebase.
- Maintenance: maintained — releases through February 2026; carries an ObjC core as a transitive dep.

## 3. Components & Layout

**Default:** native first — `Layout` protocol, `ViewThatFits`, native `sheet`/`alert`, Swift Charts. Reach for these when native falls short.

### swiftui-introspect (escape hatch)
- SPM: `https://github.com/siteline/swiftui-introspect`
- What: reaches into the underlying UIKit/AppKit views behind SwiftUI views.
- Reach for it when: a platform view needs one knob SwiftUI doesn't expose (e.g. `UIScrollView` deceleration). Last resort — each use is version-fragile by nature; the library scopes introspection per OS version to keep it safe.
- Maintenance: very active — 27.x line (versioned to track OS releases), commits July 2026.

### SwiftUI-Flow (wrapping/flow layout)
- SPM: `https://github.com/tevelee/SwiftUI-Flow`
- What: `HFlow`/`VFlow` — tag-cloud style wrapping layouts built on the native `Layout` protocol.
- Reach for it when: tag lists, chip groups, wrapping toolbars.
- Maintenance: active — 3.4.0 June 2026. **Avoid `dkk/WrappingHStack`** — unmaintained since October 2023; Flow supersedes it.
- Min platform: iOS 16 (needs `Layout`).

### PopupView
- SPM: `https://github.com/exyte/PopupView`
- What: toasts, snackbars, floaters, and custom popups as a modifier.
- Reach for it when: you need toast/snackbar UX (no native equivalent) with drag-to-dismiss and auto-hide. Skip it for plain sheets/alerts — native covers those.
- Maintenance: active (Exyte) — commits June 2026.

### MarkdownUI (swift-markdown-ui)
- SPM: `https://github.com/gonzalezreal/swift-markdown-ui`
- What: GitHub-flavored Markdown rendering with themable styling — far beyond `Text(markdown:)` (tables, images, code blocks).
- Reach for it when: rendering rich Markdown (chat/LLM output, docs, release notes).
- Maintenance: **maintenance mode** as of late 2025 (2.4.1 is current; still fine to use). The author's successor project is **Textual** (`https://github.com/gonzalezreal/textual`, active June 2026) — newer and smaller; prefer MarkdownUI for stability today, watch Textual.

### RichTextKit
- SPM: `https://github.com/danielsaidi/RichTextKit`
- What: rich text *editing* (`RichTextEditor`) over UITextView/NSTextView with format controls.
- Reach for it when: you need an editable rich-text field; native `TextEditor` + `AttributedString` editing is still limited.
- Maintenance: active — releases through June 2026.

### DSKit (optional)
- SPM: `https://github.com/imodeveloper/dskit-swiftui` (moved from `imodeveloperlab/dskit`)
- What: a prebuilt design system — tokens, themes, 60+ example screens.
- Reach for it when: prototyping a full app fast without a design team. Small community; for production, prefer building on native + your own tokens.
- Maintenance: active (June 2026) but niche.

### Charts
- **Default: native Swift Charts** (iOS 16+) — covers most bar/line/area/point/heatmap needs, plus `chartScrollableAxes` and 3D charts on recent OSes.
- Fallback: **DGCharts** — SPM: `https://github.com/ChartsOrg/Charts` (the renamed danielgindi/Charts). MPAndroidChart port, UIKit-based (wrap in `UIViewRepresentable`). Reach for it only for chart types Swift Charts can't do (candlestick, radar) or pre-iOS 16 support. Maintenance: alive but slow — activity March 2026.

## 4. Symbols & Assets

### SFSafeSymbols
- SPM: `https://github.com/SFSafeSymbols/SFSafeSymbols`
- What: compile-time-safe enum for every SF Symbol (`Image(systemSymbol: .checkmarkCircle)`), availability-annotated per OS.
- Reach for it when: any project using more than a handful of SF Symbols — kills stringly-typed symbol-name typos.
- Maintenance: maintained — 7.0.0 (October 2025) covers the current symbol set; updates track Apple's yearly symbol releases.

## 5. Dev Loop: Hot Reload & Testing

**Default:** Previews for view iteration; add **Inject** for in-simulator hot reload on complex flows; **swift-snapshot-testing** is the default UI regression tool; add **ViewInspector** for logic-level view assertions and **AccessibilitySnapshot** for a11y regressions.

### Inject + InjectionIII / InjectionNext
- SPM: `https://github.com/krzysztofzablocki/Inject` (app-side shim), paired with the injection app: `https://github.com/johnno1962/InjectionIII` or the newer `https://github.com/johnno1962/InjectionNext`
- What: hot reload — edit a view, save, see it update in the running simulator without rebuilding.
- Reach for it when: iterating on screens deep behind navigation/state that Previews can't reach.
- Maintenance: all three active (commits April–June 2026). Dev-only: gate behind `#if DEBUG`; Inject compiles to a no-op in release.

### swift-snapshot-testing
- SPM: `https://github.com/pointfreeco/swift-snapshot-testing`
- What: snapshot assertions — render views/view controllers to reference images (or text dumps) and diff on CI.
- Reach for it when: guarding visual regressions on design-system components and full screens.
- Maintenance: active — 1.19.2 (March 2026). Pin simulator/OS on CI; snapshots are device-rendering-sensitive.

### ViewInspector
- SPM: `https://github.com/nalexn/ViewInspector`
- What: runtime introspection of SwiftUI view hierarchies in unit tests — find a button, tap it, assert state.
- Reach for it when: testing view *logic* (conditional content, callbacks) where a snapshot is too blunt.
- Maintenance: maintained — 0.10.3 (September 2025), commits March 2026.

### AccessibilitySnapshot
- SPM: `https://github.com/cashapp/AccessibilitySnapshot`
- What: snapshot tests of the accessibility hierarchy (VoiceOver labels/order) as annotated images.
- Reach for it when: a11y matters enough to gate regressions in CI (it should).
- Maintenance: active (Cash App) — commits June 2026.

## 6. Architecture (use with caution)

**Default: no architecture library.** Plain `@Observable` model objects + environment injection (MV/MVVM) covers most apps with zero dependency risk. Adopt these only with team buy-in — they shape every file you write.

### swift-composable-architecture (TCA)
- SPM: `https://github.com/pointfreeco/swift-composable-architecture`
- What: Redux-style unidirectional architecture — reducers, stores, exhaustive `TestStore` testing, first-class navigation state.
- Fits when: complex shared state, deep feature composition, a team that wants enforced consistency and exhaustive tests, or heavy cross-feature effect orchestration.
- Does NOT fit when: small/medium apps, prototypes, or teams new to Swift — steep learning curve, pervasive coupling (it's in every feature), boilerplate per interaction, and major-version migrations are real work.
- Maintenance: very active — 1.26.0 (June 2026), Point-Free's flagship.

### swift-dependencies
- SPM: `https://github.com/pointfreeco/swift-dependencies`
- What: `@Dependency`-style dependency injection modeled on SwiftUI's environment; usable standalone without TCA.
- Reach for it when: you want controllable/testable deps (clock, UUID, API clients) with a lighter footprint than TCA.
- Maintenance: active — releases June 2026.

### Factory
- SPM: `https://github.com/hmlongco/Factory`
- What: compile-time-safe container-based DI — registrations, scopes (singleton/cached), previews/test overrides.
- Reach for it when: you want conventional container DI rather than environment-style; simpler mental model than swift-dependencies.
- Maintenance: active — 3.2.1 (June 2026).

## 7. Utilities

### Defaults
- SPM: `https://github.com/sindresorhus/Defaults`
- What: strongly-typed UserDefaults with `Codable` support, SwiftUI `@Default` property wrapper, iCloud sync, observation.
- Reach for it when: more than trivial `@AppStorage` use — typed keys, custom types, defaults observation.
- Maintenance: very active — 9.0.9 (June 2026). Note: tracks recent OS baselines aggressively; check the current minimum before adding.

### swift-collections / swift-algorithms
- SPM: `https://github.com/apple/swift-collections`, `https://github.com/apple/swift-algorithms`
- What: Apple-maintained `Deque`, `OrderedDictionary`, `OrderedSet`, `Heap`; and `chunked`, `windows`, `uniqued`, combinations/permutations.
- Reach for it when: you're about to hand-write any of those. Zero-risk dependencies.
- Maintenance: active (Apple).

### Keychain: KeychainAccess or swift-security
- `https://github.com/kishikawakatsumi/KeychainAccess` — the long-standing standard. **Dormant** (no commits since May 2024) but stable and battle-tested; the Keychain API underneath doesn't move fast.
- Modern alternative: `https://github.com/dm-zharov/swift-security` — Swift-first, property-wrapper API, maintained through December 2025.
- Reach for either when: storing tokens/credentials. For one or two values, a ~40-line `SecItem` wrapper is also acceptable (see §9).

## 8. Networking

Nothing to add. **`URLSession` + async/await + `Codable` suffices** for UI-adjacent networking — Alamofire and friends add little for typical REST/JSON work and a lot of surface area. For images specifically, the loaders in §2 already own their networking. Only consider a networking library for genuinely exotic needs (multipart upload orchestration, request retrying at scale) — and even then, write the ~100-line client first.

## 9. Adding a Dependency Responsibly

Before `Package.swift` grows a line, run this checklist:

1. **Could native do it in ~50 lines?** If a first-party API gets you within ~50 lines of the library's value, write the 50 lines. A dependency you don't add never breaks your build.
2. **Pin sanely.** Use `.package(url:, from: "X.Y.Z")` — semver-ranged, not `branch:` or `revision:`. Commit `Package.resolved`. Upgrade deliberately, reading release notes, not via blanket "Update to Latest".
3. **Audit transitive dependencies.** `swift package show-dependencies` — a "small" package pulling six others is not small. Prefer leaf packages (most of this catalog is dependency-free or Apple-only).
4. **Check the license.** MIT/Apache-2.0/BSD are fine; GPL-family is generally a no for App Store apps. Everything above is permissively licensed — re-verify on major version bumps.
5. **Check privacy manifest presence.** Binary/SDK dependencies that touch required-reason APIs (UserDefaults, file timestamps, etc.) must ship a `PrivacyInfo.xcprivacy`; App Store review enforces this for listed SDKs. Missing manifest in an actively-shipped library is a maintenance red flag.
6. **Check vital signs.** Recent releases, responsive issues, more than one contributor with commit access. Archived repo = plan your exit before you enter.
7. **Vend a wrapper.** Put the dependency behind your own thin interface in one module — e.g. an `ImageLoading` protocol with a `NukeImageLoader` implementation, or a `HapticEffects` namespace wrapping Pow. App code imports your module, not theirs. Swapping or dropping the library then touches one file, not two hundred. Exceptions: dev-only tools (§5) and pervasive-by-design architecture libraries (§6), which you're consciously marrying.
