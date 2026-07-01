# Interop & Platforms (Swift 6.x)

Reference for Objective-C/C/C++ interop and non-Apple platforms (Android, Linux, Embedded, WASM, Windows) on Swift 6.x (stable 6.3; 6.4 = WWDC26 beta).

**Contents:** [Obj-C](#objective-c-interop) · [C](#c-interop) · [C++](#c-interop-1) · [Android](#android-sdk-63) · [Linux/server](#linuxserver) · [Embedded](#embedded-swift) · [WASM](#wasmwasi) · [Windows](#windows)

## Objective-C interop

- `@objc` exposes a single declaration to the Obj-C runtime; `@objcMembers` on a class exposes everything exposable. Expose the minimum — every `@objc` member blocks dead-stripping and forces message-send-compatible representations.
- **App targets** use a bridging header (`*-Bridging-Header.h`) to import Obj-C into Swift. **Frameworks and SwiftPM targets cannot use bridging headers** — use the framework umbrella header or a module map / dedicated C target instead.
- `NS_SWIFT_NAME` renames Obj-C API *as seen from Swift* (the ObjC→Swift direction). The Swift→ObjC direction is `@objc(objcSelectorName:)`.

```objc
- (void)fetchUserWithID:(NSString *)uid NS_SWIFT_NAME(fetchUser(id:));
```

- Nullability annotations drive optionality: `nonnull` → `T`, `nullable` → `T?`, unannotated → `T!` (implicitly unwrapped, crash-prone). Wrap headers in `NS_ASSUME_NONNULL_BEGIN/END` and annotate exceptions — unannotated headers are the #1 source of `T!` in mixed codebases.
- Methods with a trailing `NSError **` param import as `throws`; return `BOOL`/nullable-object becomes the success signal and disappears from the Swift signature.
- Completion-handler methods import as `async` automatically (trailing completion block, last param). `NS_SWIFT_ASYNC(...)`/`NS_SWIFT_DISABLE_ASYNC` tune or suppress this; `NS_SWIFT_ASYNC_NAME` renames the async form. `NS_SWIFT_UI_ACTOR` marks Obj-C API as `@MainActor`. Delegate callbacks do NOT auto-translate — wrap them yourself:

```swift
func locations() -> AsyncStream<CLLocation> {
    AsyncStream { continuation in
        let delegate = Adapter { continuation.yield($0) }   // retains adapter for stream lifetime
        continuation.onTermination = { _ in delegate.stop() }
        delegate.start()
    }
}
```
- **Bridging costs:** `String↔NSString`, `Array↔NSArray`, `Dictionary↔NSDictionary`, `Data↔NSData` conversions can copy. In hot loops, avoid round-tripping per element:

```swift
// WRONG: bridges the same NSArray every iteration
for i in 0..<1_000_000 { process((objcObj.items as! [Item])[i % n]) }
// RIGHT: bridge once outside the loop
let items = objcObj.items as! [Item]
for i in 0..<1_000_000 { process(items[i % n]) }
```

## C interop

- Import C into SwiftPM via a C target with `include/` headers (auto-modularized), or `systemLibrary(name:pkgConfig:providers:)` with a hand-written `module.modulemap` for installed libs:

```
// Sources/CSQLite/module.modulemap
module CSQLite {
    header "shim.h"        // shim.h: #include <sqlite3.h>
    link "sqlite3"
    export *
}
```
- Pointer mapping:

| C | Swift |
|---|---|
| `const T *` | `UnsafePointer<T>?` |
| `T *` | `UnsafeMutablePointer<T>?` |
| `const void *` / `void *` | `UnsafeRawPointer?` / `UnsafeMutableRawPointer?` |
| `T **` | `UnsafeMutablePointer<UnsafeMutablePointer<T>?>?` |
| `struct Opaque *` (no definition) | `OpaquePointer?` |
| `const char *` | `UnsafePointer<CChar>?` (accepts Swift `String` directly, valid for that call only) |

(Non-nullable variants when the header is nullability-annotated.)
- Use scoped accessors — never store the pointer past the closure (it dangles):

```swift
var value = 42
withUnsafeMutablePointer(to: &value) { c_api_fill($0) }
let bytes: [UInt8] = …; bytes.withUnsafeBufferPointer { c_consume($0.baseAddress, $0.count) }
```

- C strings out: `String(cString:)` copies; for buffers the C side fills, use `withUnsafeTemporaryAllocation(of: CChar.self, capacity: n) { … }` then `String(cString:)`.
- **Exposing Swift TO C — `@c` (6.3+, SE-0495):** the formalized replacement for the old underscored `@_cdecl`. Annotated functions/enums get declarations in the generated compatibility header (`-emit-clang-header-path Out.h` / Xcode's generated header); `@c("CustomName")` overrides the symbol. Unlike `@_cdecl` it is official, supports enums, and composes with `@implementation` to implement a pre-declared C function in Swift:

```swift
@c public func mylib_add(_ a: Int32, _ b: Int32) -> Int32 { a + b }
@c enum MyStatus: CInt { case ok = 0, fail = 1 }   // emitted as a C enum
```

```c
#include "Out.h"
int r = mylib_add(1, 2);
```

Only C-representable types allowed in signatures (no classes, generics, or non-@c enums). `@_cdecl` still compiles but is legacy — prefer `@c` on 6.3+.

## C++ interop

- Enable per target: `swiftSettings: [.interoperabilityMode(.Cxx)]` (Xcode: "C++ and Objective-C Interoperability" = C++/Objective-C++). It's viral — consumers of a library with C++ in its public API also need it.
- Maps well: C++ value types (imported as Swift structs with copy/destroy semantics), member functions, `std::string`/`std::vector`/`std::map` etc. via the `CxxStdlib` overlay (`String(cxxString)`, `std.string(swiftString)`, direct `for` iteration over vectors), function templates (instantiated from Swift call sites).
- Current limitations (6.3): **class templates** must be instantiated on the C++ side (`using IntBox = Box<int>;`) before Swift sees a concrete type; C++ exceptions cannot be caught in Swift (they terminate at the boundary); some STL and SFINAE-heavy APIs import partially or not at all; virtual dispatch and inheritance work best through reference types annotated `SWIFT_SHARED_REFERENCE(retain, release)` — plain polymorphic value types slice. Move-only C++ types import as non-copyable (`~Copyable`) Swift types on recent toolchains; older ones skipped them.
- Incremental adoption: don't expose raw C++ across module boundaries. Wrap C++ in a small Swift (or C) facade target with a Swift-native API, keep `.interoperabilityMode(.Cxx)` confined to that target, and convert at the edge:

```swift
// WRONG: converts per call, leaks C++ types into the public API
public func names() -> std.vector<std.string> { engine.getNames() }
// RIGHT: convert once at the boundary, expose Swift types
public func names() -> [String] { engine.getNames().map { String($0) } }
```

## Android SDK (6.3+)

- 6.3 ships the first official Swift SDK for Android. Needs three pieces: host toolchain (via swiftly), the Android Swift SDK bundle (`swift sdk install <url> --checksum <sha>` — URL from swift.org/install), and the **Android NDK** (point `ANDROID_NDK_HOME` at it).

```bash
swift build --swift-sdk aarch64-unknown-linux-android28 --static-swift-stdlib   # 28 = min API level; also x86_64 triple
```

- In the box: Swift stdlib plus core libraries **Foundation and Dispatch** — portable server-style/business-logic code generally just builds. No UI framework; UI stays Kotlin/Compose.
- Kotlin/Java ↔ Swift: the official **swift-java** project (github.com/swiftlang/swift-java) — `jextract` (with a JNI mode) and `wrap-java` generate the JNI bindings both directions, replacing hand-written `JNIEXPORT` glue.
- Packaging: build one `.so` per ABI and place under the app's `app/src/main/jniLibs/<abi>/` (e.g. `arm64-v8a`), plus the Swift runtime `.so`s from the SDK unless statically linked; Gradle bundles `jniLibs` automatically. `System.loadLibrary("yourlib")` at runtime.
- Availability checks work: `@available(Android 33, *)`.

## Linux/server

- Foundation on Linux is the **swift-foundation** Swift rewrite (default since Swift 6) — near-parity for the core (String/Data/Date/JSON/FileManager…), and identical implementation to Apple platforms, so old "corelibs-foundation diverges" lore is mostly obsolete.
- Split modules on Linux: `import FoundationNetworking` (URLSession) and `import FoundationXML` (XMLParser) explicitly — plain `import Foundation` does not pull them in (keeps the curl/libxml dependency optional). Portable pattern:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // no-op on Apple platforms, required on Linux for URLSession
#endif
```

- Prefer AsyncHTTPClient over URLSession on servers anyway — FoundationNetworking's URLSession wraps curl and lags the Darwin implementation.
- Not available anywhere off Apple platforms: UIKit/AppKit/SwiftUI, Combine (use AsyncSequence or OpenCombine), CoreData (use SQLite/GRDB/Fluent), os.log's unified logging (use swift-log).
- Containers: cross-compile with the static musl SDK (`--swift-sdk x86_64-swift-linux-musl`) → a single static binary that runs `FROM scratch`/distroless; otherwise use official images: `docker run swift:6.3` (build) and `swift:6.3-slim` (runtime).
- Ecosystem, one line each: **Vapor** — batteries-included web framework; **Hummingbird** — lighter modular alternative; **AsyncHTTPClient** — the standard HTTP client; **swift-nio** — the event-loop networking substrate under all of them; plus swift-log/swift-metrics for observability.

## Embedded Swift

- A compilation mode producing tiny, runtime-free binaries; still enabled via the experimental flag (no stable flag as of 6.3): `-enable-experimental-feature Embedded` + whole-module (`-wmo`). SwiftPM:

```swift
.executableTarget(name: "Firmware", swiftSettings: [
    .enableExperimentalFeature("Embedded"),
    .unsafeFlags(["-wmo"]),
])
```
- The subset (by design, still enforced in 6.3): **no runtime reflection/Mirror**, typed `throws` only (no untyped throws), no calling generic methods through existentials (existentials heavily restricted; generics are fine — they're monomorphized), no `Codable`, no Objective-C interop, no library evolution. `String`/`Array`/`Dictionary` work (allocating).
- 6.3 additions: Float/Double printing (`description` in pure Swift), `@c` interop, better LLDB (value printing, core-dump inspection, armv7m unwinding), and **`@section`/`@used`** (SE-0492, 6.3+, no feature flag) for linker placement — essential for interrupt vectors/firmware layout:

```swift
@section("__DATA,config") @used let bootFlags: UInt32 = 0x1   // ELF targets: "config"; gate with #if objectFormat(ELF)
```

- **Swift MMIO** (github.com/apple/swift-mmio): type-safe, volatile-correct register access generated from SVD files — use it instead of raw pointer pokes.
- Typical targets: ARM Cortex-M (STM32, Nordic), ESP32 (RISC-V and Xtensa via ESP-IDF), Raspberry Pi Pico (RP2040/RP2350). Start from github.com/swiftlang/swift-embedded-examples.

## WASM/WASI

- Officially supported: swift.org publishes WASM Swift SDKs with each release (6.2+; earlier via the SwiftWasm project). Install the `_wasm` artifactbundle with `swift sdk install`, build with `--swift-sdk <id>` (triple `wasm32-unknown-wasi`; a `wasip1-threads` variant exists for threading experiments):

```bash
swift sdk install https://download.swift.org/swift-6.3-release/wasm-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_wasm.artifactbundle.tar.gz --checksum <sha256>
swift build --swift-sdk swift-6.3-RELEASE_wasm -c release
wasmtime .build/release/mytool.wasm
```
- Good for: CLI-style WASI modules (run under wasmtime/WasmKit) and browser apps. Browser DOM/JS access goes through **JavaScriptKit** (swiftwasm/JavaScriptKit); `carton` streamlines dev-serve workflows. Binary size is the main constraint — consider Embedded-Swift-for-WASM for small modules.

## Windows

Windows is a fully supported platform: install via `winget install --id Swift.Toolchain` (plus Visual Studio Build Tools for the MSVC linker/SDK); you get SwiftPM, swift-format, LLDB, Foundation/Dispatch, and VS Code (SourceKit-LSP) as the primary editor — no Xcode. x86_64 and arm64 are both supported. Expect the occasional Windows-specific path/encoding edge case in third-party packages; core toolchain and server-side libraries are generally solid.
