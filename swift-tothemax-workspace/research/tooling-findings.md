# SwiftPM/tooling research (haiku agent) — with lead-agent annotations

## Trustworthy
- Swift Build preview: `--build-system swiftbuild` (6.3), parity roadmap → default later. docs.swift.org swiftpm SwiftBuildPreview.
- swiftly 1.0+: official toolchain manager, .swift-version file supported.
- SwiftSetting.defaultIsolation(MainActor.self) and .strictMemorySafety() — confirmed spellings (6.2+).
- Prebuilt swift-syntax: --enable-experimental-prebuilts, SwiftPM 6.1+/Xcode 16.4, downloads from download.swift.org/prebuilts.
- swift-format bundled with toolchain since Swift 6 / Xcode 16; `swift format` subcommand.
- Swift SDKs: `swift sdk install <url>` then `swift build --swift-sdk <id>`; musl id like x86_64-swift-linux-musl.

## Minor doubts
- Package traits "enableIf" spelling looks garbled — actual API is a `traits:` collection on Package + `#if TraitName` in code; verify exact initializer.
