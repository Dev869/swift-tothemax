# SwiftPM & Tooling (Swift 6.x)

Reference for authoring packages, managing toolchains, cross-compiling, and CI with Swift 6.x (stable 6.3; 6.4 = WWDC26 beta).

**Contents:** [Package.swift](#packageswift-authoring) · [Traits](#package-traits-61) · [Dependencies](#dependencies) · [Plugins](#plugins) · [Swift Build](#swift-build-in-swiftpm-63-preview) · [swiftly](#swiftly-toolchain-manager) · [Executables & formatting](#executables--formatting) · [Cross-compilation](#cross-compilation-with-swift-sdks) · [CI](#ci-notes) · [Prebuilt swift-syntax](#prebuilt-swift-syntax-61)

## Package.swift authoring

- `// swift-tools-version: 6.3` (first line, mandatory) gates which `PackageDescription` API you may use AND sets the default language mode for all targets to Swift 6 when ≥ 6.0. Raising it is a breaking change for consumers on older toolchains — keep it as low as your features allow.
- **Targets** are build units (modules); **products** are what consumers import/link. A library product with no explicit `type:` lets the consumer choose static/dynamic — prefer that over forcing `.dynamic`.

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyLib",
    platforms: [.macOS(.v14), .iOS(.v17)],   // deployment targets for Apple platforms only; Linux etc. ignore this
    products: [.library(name: "MyLib", targets: ["MyLib"])],
    targets: [
        .target(
            name: "MyLib",
            swiftSettings: [
                .swiftLanguageMode(.v6),                    // per-target override; package-level: swiftLanguageModes: [.v6, .v5]
                .enableUpcomingFeature("ExistentialAny"),   // stable-toolchain, opt-in-early feature
                .enableExperimentalFeature("Embedded"),     // unstable; requires matching snapshot support
                .defaultIsolation(MainActor.self),          // 6.2+ tools; MainActor.self or nil (= nonisolated) only
                .strictMemorySafety(),                      // 6.2+ tools; SE-0458 strict memory safety diagnostics
            ]
        ),
        .testTarget(name: "MyLibTests", dependencies: ["MyLib"]),
    ]
)
```

- Omitting `platforms` gives you the oldest supported deployment targets — you'll hit `@available` errors on modern APIs; set it deliberately.
- `swiftLanguageModes(_:)` at package level declares which modes the package supports; per-target `.swiftLanguageMode(.v5)` is the escape hatch for a target not yet migrated to Swift 6 mode.

## Package traits (6.1+)

Compile-time feature flags for packages; conditionalize dependencies and code with `#if TraitName`.

```swift
let package = Package(
    name: "MetricsKit",
    traits: [
        .default(enabledTraits: ["Prometheus"]),          // enabled unless consumer opts out
        .trait(name: "Prometheus"),
        .trait(name: "OTel", description: "OpenTelemetry export", enabledTraits: []),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-otel", from: "1.0.0"),
    ],
    targets: [.target(name: "MetricsKit", dependencies: [
        .product(name: "OTel", package: "swift-otel", condition: .when(traits: ["OTel"])),
    ])]
)
```

Consuming: `.package(url: "…", from: "1.0.0", traits: [.defaults, "OTel"])`. In code: `#if OTel … #endif`.
- Use cases: optional heavy dependencies (crypto/backends), Embedded-Swift-safe variants of a library, server-vs-client feature sets.
- Traits are unified across the whole graph (a trait enabled by any consumer is on for everyone) — never use them for mutually exclusive behavior.
- `swift package show-traits <package>` lists a dependency's traits (6.3+).

## Dependencies

- `from: "1.2.0"` (up-to-next-major) is the default and correct choice for SemVer libraries. `exact:` freezes upgrades and causes graph conflicts — reserve for known-broken ranges. `revision:`/`branch:` are unresolvable-by-SemVer and banned in published library manifests (SwiftPM rejects them when the package is itself a dependency); fine for apps and pre-release coordination.
- **Commit `Package.resolved`** for apps and CI-reproducibility; for pure libraries it's ignored by consumers but still useful for your own CI. `swift package resolve` honors it; `swift package update` rewrites it.
- Local development against a dependency: `.package(path: "../MyDep")` — path deps override version requirements; don't commit that change. Alternative without editing the manifest: `swift package edit MyDep --path ../MyDep` / `swift package unedit MyDep`.
- Registries (`swift package-registry set https://…`) give namespace-verified, immutable releases (`scope.name` identifiers) vs. source-control URLs; most open-source flow is still git URLs — don't invent registry IDs for GitHub-hosted deps.

## Plugins

- **Build tool plugins** (`.buildTool()`) run automatically during build, declare inputs/outputs (`buildCommand`) or run every build (`prebuildCommand`); use for codegen that must track source changes (protobuf, OpenAPI).
- **Command plugins** (`.command(intent:permissions:)`) run on demand via `swift package <verb>`; use for lint/format/release chores.
- Plugins run **sandboxed**: no network, writes only to their `pluginWorkDirectory`. Command plugins may request `.writeToPackageDirectory(reason:)`; users approve or pass `--allow-writing-to-package-directory`. Network is not grantable via manifest — a plugin that must download needs `--disable-sandbox` (smell; prefer vendoring).
- Choosing codegen strategy: **macro** when output derives from Swift source and should stay invisible (member/peer synthesis); **build tool plugin** when input is a non-Swift artifact (.proto, .yaml) regenerated per build; **checked-in code** when generation is rare and reviewability beats automation — plugins add build-time and toolchain-fragility cost.

## Swift Build in SwiftPM (6.3 preview)

Swift Build is the open-sourced Xcode build engine; the preview makes SwiftPM, Xcode, and cross-platform builds share one engine (consistent flags, better scheduling/diagnostics).

```bash
swift build --build-system swiftbuild     # opt in (works on 6.2/6.3; official preview in 6.3)
swift build --build-system native        # explicit old engine
```

- Caveats (6.3): preview quality — some plugin/edge-case behaviors differ from the native engine; report issues. On current `main`, swiftbuild is already the **default** (native via `--build-system native`), so expect the flip in 6.4 (beta) — don't hardcode assumptions about intermediate `.build` layout.

## swiftly toolchain manager

Official installer/manager (macOS + Linux). Install swiftly itself per swift.org/install, then:

```bash
swiftly install latest        # newest stable release
swiftly install 6.3           # specific release (also: main-snapshot, 6.4-snapshot)
swiftly use 6.3               # select active toolchain
swiftly list                  # installed toolchains
swiftly update                # upgrade selected toolchain in place
```

- **Per-project pinning:** a `.swift-version` file at repo root (content e.g. `6.3`, no trailing newline) makes swiftly-managed `swift` invocations in that tree use that version; bare `swiftly install` reads it and installs the pinned toolchain. Commit it.
- **CI:** install swiftly, then `swiftly install` (picks up `.swift-version`) — one line keeps CI and contributors on identical toolchains. GitHub Actions: `vapor/swiftly-action` or the setup script from swift.org.

## Executables & formatting

- `swift run [tool] [args…]` builds and runs; `swift run -c release` for perf-sensitive tools.
- ArgumentParser skeleton (dependency: `apple/swift-argument-parser`):

```swift
import ArgumentParser

@main struct Greet: AsyncParsableCommand {
    @Argument var name: String
    @Flag(name: .shortAndLong) var verbose = false
    func run() async throws { print("hi \(name)") }
}
```

- **swift-format is bundled with the toolchain since Swift 6.0** — run as `swift format` (subcommand, no hyphen): `swift format lint -r Sources`, `swift format -i -r Sources`. Config via `.swift-format` JSON. Roles: swift-format = formatting + basic style lint; **SwiftLint** = deeper semantic/style rules (separate install). They coexist; don't ask SwiftLint to fight the formatter's whitespace decisions.

## Cross-compilation with Swift SDKs

Host toolchain version must match the SDK's version. General flow: `swift sdk install <artifactbundle-url> --checksum <sha256>`, verify with `swift sdk list`, build with `--swift-sdk <id-or-triple>`.

```bash
# Static Linux (musl) — fully static binaries for containers/lambdas
swift sdk install https://download.swift.org/swift-6.3-release/static-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz --checksum <sha256>
swift build --swift-sdk x86_64-swift-linux-musl        # or aarch64-swift-linux-musl

# WASM/WASI — swift.org publishes SDKs alongside releases (6.2+; SwiftWasm project earlier)
swift sdk install https://download.swift.org/swift-6.3-release/wasm-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_wasm.artifactbundle.tar.gz --checksum <sha256>
swift build --swift-sdk swift-6.3-RELEASE_wasm         # id from `swift sdk list`; triple wasm32-unknown-wasi

# Android (official in 6.3) — also requires the Android NDK installed
swift sdk install <swift-6.3 android artifactbundle URL from swift.org/install> --checksum <sha256>
swift build --swift-sdk aarch64-unknown-linux-android28 --static-swift-stdlib   # 28 = min API level
```

Exact URLs/checksums per release live on swift.org/install — always copy them from there rather than constructing.
Editor support against an SDK: `.sourcekit-lsp/config.json` → `{ "swiftPM": { "swiftSDK": "<id>" } }`.

## CI notes

- Cache `.build/` keyed on `Package.resolved` hash (plus OS + toolchain version) — dependency checkouts and build artifacts both live there; invalidate on toolchain bumps.
- `swift test --parallel` runs test *processes* in parallel (Swift Testing is additionally in-process parallel by default); add `--num-workers N` to bound it.
- `--disable-sandbox` is needed when the manifest/plugins must do things the sandbox forbids (network, writing outside work dirs) and when building inside an already-sandboxed environment (e.g. some containers/Nix) where nested sandboxing fails. Don't make it the default.
- Xcode-driven CI: pipe `xcodebuild … | xcbeautify` for readable logs; raw xcodebuild output buries failures.

## Prebuilt swift-syntax (6.1+)

Macro targets normally compile all of swift-syntax from source (minutes). SwiftPM can instead download a prebuilt swift-syntax matching your pinned version:

```bash
swift build --enable-experimental-prebuilts     # CLI (6.1.1+)
defaults write com.apple.dt.Xcode IDEPackageEnablePrebuilts -bool YES   # Xcode 16.4+
```

- Prebuilts exist only for swift.org-published swift-syntax versions/platforms (manifests under `download.swift.org/prebuilts/swift-syntax/`); anything else silently falls back to source builds.
- 6.3 extends this: shared macro-implementation *library* targets can also use swift-syntax prebuilts, so multi-macro packages get the speedup too.
