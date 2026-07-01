# Swift Macros (Swift 6.x)

When to write a macro, the full role taxonomy, package anatomy, implementation, testing, debugging, and which existing macros to reuse instead. Stable = 6.3; 6.4 features are WWDC26 beta and marked as such.

## Contents
- [When a macro is warranted](#when-a-macro-is-warranted)
- [Taxonomy of roles](#taxonomy-of-roles)
- [Package anatomy](#package-anatomy)
- [swift-syntax versioning and prebuilts](#swift-syntax-versioning-and-prebuilts)
- [Implementation guide](#implementation-guide)
- [Testing](#testing)
- [Debugging](#debugging)
- [Reuse existing macros first](#reuse-existing-macros-first)

## When a macro is warranted

Macros are the **last resort**. Escalate in this order; stop at the first tool that works:

1. Function / generic function — behavior abstraction.
2. Protocol + default implementations, conditional conformance — type-family abstraction.
3. Property wrapper — per-property storage/access policy.
4. Result builder — declarative structure DSL.
5. **Macro** — only when the boilerplate requires *syntax-level* code generation: emitting new declarations derived from the shape of existing source (member lists, stored-property names, enum cases), compile-time validation of literals with diagnostics, or capturing source text (`#function`-style).

If a macro would just wrap a function call, write the function. Macros cost: a swift-syntax dependency, slower builds, harder debugging, opaque call sites for readers.

## Taxonomy of roles

Freestanding (spelled `#name` at use site):
- `@freestanding(expression)` — expands to an expression: `#URL("https://a.b")`.
- `@freestanding(declaration)` — expands to one or more declarations: `#warningIfDebug(...)`.

Attached (spelled `@Name` on a declaration; current full set, all 5.9+ unless noted):
- `@attached(peer)` — adds declarations *alongside* the annotated one (e.g. generate a completion-handler variant of an async func).
- `@attached(member)` — adds members *inside* the annotated type.
- `@attached(memberAttribute)` — adds attributes to each existing member (how `@Observable` sprays `@ObservationTracked`).
- `@attached(accessor)` — turns a stored property into computed by adding `get`/`set`/etc.
- `@attached(extension)` — adds an extension with conformances/members (replaced the 5.9-beta `conformance` role; SE-0402).
- `@attached(body)` (6.0+, SE-0415) — synthesizes or replaces a function's body; at most one per function.
- `@attached(preamble)` — accepted in SE-0415 alongside body macros (prepends statements to a body, e.g. logging); verify your toolchain supports it before relying on it — `body` is the widely supported role.

One macro can declare several roles; each expansion must produce what the role promises, and `names:` must declare everything it introduces (`named(x)`, `arbitrary`, `prefixed(_)`).

## Package anatomy

Three pieces: public declaration, compiler-plugin implementation, wiring.

```swift
// 1. Declaration target (what clients import) — Sources/MyMacros/
@attached(member, names: named(init(rawValue:)), named(rawValue))
@attached(extension, conformances: Codable)
public macro AutoCodable() = #externalMacro(module: "MyMacrosImpl", type: "AutoCodableMacro")
```

```swift
// 2. Implementation target — Sources/MyMacrosImpl/ (never imported by clients;
//    it runs inside the compiler as a separate plugin process)
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public struct AutoCodableMacro: MemberMacro, ExtensionMacro { /* expansions */ }

@main
struct MyMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [AutoCodableMacro.self]
}
```

```swift
// 3. Package.swift
let package = Package(
    name: "MyMacros",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .macro(name: "MyMacrosImpl", dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .target(name: "MyMacros", dependencies: ["MyMacrosImpl"]),
        .testTarget(name: "MyMacrosTests", dependencies: [
            "MyMacrosImpl",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        ]),
    ]
)
```

## swift-syntax versioning and prebuilts

- swift-syntax majors track compiler releases: 600.x ↔ Swift 6.0, 601.x ↔ 6.1, 602.x ↔ 6.2, 603.x ↔ 6.3. Because SwiftPM unifies to a single version per graph, two macro packages pinning different exact majors conflict. Library authors: declare the widest range you actually support, e.g. `"600.0.0"..<"604.0.0"`, and CI against the bounds.
- **Prebuilts** fix the build-time pain (building swift-syntax from source: ~4 min release builds). Timeline: preview in SwiftPM mid-2025 (opt-in `SWIFTPM_ENABLE_PREBUILTS=1`); Xcode 16.4 added support (opt-in via the `IDEPackageEnablePrebuilts` default); SwiftPM 6.1.1+ supports prebuilt swift-syntax via the opt-in `--enable-experimental-prebuilts` flag (still experimental, not on by default, through 6.3) when your dependency resolves to a published release tag; 6.3 extends prebuilts to shared libraries used only from macro targets. Practical rule: depend on plain release tags of `swiftlang/swift-syntax` (no forks, no branch pins) so prebuilts can kick in.
- A stable `SwiftSyntaxMacros` ABI (so macros stop rebuilding/re-pinning swift-syntax entirely) has been discussed on the forums but has **not shipped** as of 6.3 — prebuilts are the shipping mitigation.

## Implementation guide

Expansion methods receive syntax nodes plus a `MacroExpansionContext` (note the exact protocol name). Key context services: `makeUniqueName(_:)` for hygienic identifiers, `diagnose(_:)` for warnings/errors, `location(of:)` for source positions.

Throwing an error aborts expansion and shows the error's description at the use site. For precise, actionable failures, emit a `Diagnostic` with a fix-it and then throw `DiagnosticsError`:

```swift
public struct URLMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let literal = node.arguments.first?.expression
                .as(StringLiteralExpressionSyntax.self),
              let text = literal.representedLiteralValue,   // nil if interpolated
              URL(string: text) != nil
        else {
            let diag = Diagnostic(
                node: node,
                message: MacroError.invalidURL,              // a DiagnosticMessage
                fixIts: [FixIt(message: MacroError.removeIt,
                               changes: [/* .replace(...) */])])
            context.diagnose(diag)
            throw DiagnosticsError(diagnostics: [diag])
        }
        return "URL(string: \(literal))!"                    // ExprSyntax via interpolation
    }
}
```

Conventions:
- Build output with `SwiftSyntaxBuilder` string interpolation (`"let \(raw: name) = ..."` as `DeclSyntax`/`ExprSyntax`) rather than hand-assembling nodes; interpolation re-parses and validates.
- Don't fight whitespace — expansions are auto-formatted (BasicFormat); only add trivia when layout is semantic.
- Expansions must be deterministic and side-effect free: no file/network/env access (the plugin runs sandboxed), no reliance on type information — you get *syntax only*, as written, unresolved.

## Testing

Baseline: `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport` — assert exact expanded source and diagnostics:

```swift
import SwiftSyntaxMacrosTestSupport
import XCTest

func testURL() {
    assertMacroExpansion(
        #"#URL("https://swift.org")"#,
        expandedSource: #"URL(string: "https://swift.org")!"#,
        macros: ["URL": URLMacro.self]
    )
}
```

Better ergonomics: Point-Free's `swift-macro-testing` (`assertMacro`) records the expansion as an inline snapshot on first run and diffs thereafter — use it for macros with large expansions; it also works under Swift Testing suites. (`SwiftSyntaxMacrosGenericTestSupport` exists for non-XCTest harnesses.)

Test the failure paths too: pass malformed input and assert `diagnostics:` (message, line, column, fix-its), not just happy-path expansion.

## Debugging

- `swift build -Xswiftc -Xfrontend -Xswiftc -dump-macro-expansions` prints every expansion the compiler performs (`-dump-macro-expansions` is a frontend flag, hence the double indirection).
- Xcode: right-click the macro use site → **Expand Macro** to see (and step into) generated code inline; breakpoints work inside expansions.
- Crashing plugin? Run the test target — macro implementations are ordinary library code under test, so debug there, not through the compiler.

## Reuse existing macros first

Before authoring, check whether the ecosystem already ships the macro:

| Macro | Source | Use |
|---|---|---|
| `@Observable` | Observation (5.9+) | Observation-tracked model classes; replaces ObservableObject boilerplate |
| `@Model` | SwiftData | Persistent model classes |
| `@Test`, `#expect`, `#require`, `@Suite` | Swift Testing (6.0+ toolchains) | Test declarations and assertions |
| `@DebugDescription` | Standard library (6.0+, SE-0440) | Debugger summaries without running code; not on protocols/generic types |
| `@Entry` | SwiftUI (Xcode 16+) | EnvironmentValues/Transaction keys without the key-struct dance |
| `#Preview` | SwiftUI/UIKit (Xcode 15+) | Previews |
| `@CasePathable` (swift-case-paths), `@DependencyClient` (swift-dependencies) | Point-Free | Enum key paths, dependency clients |

## Cost warning

Every macro package drags swift-syntax into your dependency graph and (without prebuilts) into your build. Prebuilt swift-syntax in SwiftPM 6.1.1+ / Xcode 16.4+ (opt-in: `--enable-experimental-prebuilts` / `IDEPackageEnablePrebuilts`) largely mitigates this **when the resolved version is a stock release tag** — forks and branch pins fall back to source builds. Weigh a macro's per-call-site savings against: build-time cost for every consumer, version-pinning friction across the graph, and reader opacity. A 10-line manual conformance is often cheaper than a macro dependency.
