# Interop/platforms research (haiku agent) — with lead-agent annotations

## Trustworthy
- Android SDK official in 6.3, download via swift.org/install, needs NDK 28; swift-java for Kotlin/JNI bridging.
- Static Linux SDK: musl, target x86_64-unknown-linux-musl; FoundationNetworking separate import; swift-foundation parity improving.
- WASM: Swift SDK since ~6.2, WasmKit runtime; component model still in development.
- Windows: winget install Swift; VS toolchain required.
- C++ interop docs at swift.org/documentation/cxx-interop/; SWIFT_SHARED_REFERENCE etc. annotations.
- Embedded: no existentials/reflection, @section/@used, Swift MMIO.

## CONFLICTS (lead annotations)
- @c attribute: agent says "not finalized in 6.3" citing forums.swift.org/t/77696 (older discussion). Official swift.org "Swift 6.3 Released" blog explicitly announces @c with generated C header declarations. TRUST THE RELEASE BLOG: @c shipped in 6.3.
- C++ interop: "virtual methods and templates supported, no namespaces" — partially garbled; namespaces historically import as enums. Verify against cxx-interop status page.
- Embedded Swift: "experimental flag, not production-ready" vs release-blog language "finished the Embedded Swift feature set" in 6.3. Reconcile: feature set complete, still opt-in mode; check current flag spelling.
- Android build invocation quoted (-enable-library-evolution) looks copied from an unrelated context; verify exact `swift build --swift-sdk <id>` form.
