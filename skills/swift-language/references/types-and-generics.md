# Types & Generics (Swift 6.x)

Decision frameworks and patterns for Swift's type system: `some`/`any`, protocol design, generics, noncopyable types, enums, result builders. Stable = 6.3; 6.4 features are WWDC26 beta and marked as such.

## Contents
- [some vs any](#some-vs-any)
- [Protocol design](#protocol-design)
- [Generics](#generics)
- [Parameter packs (5.9+)](#parameter-packs-59)
- [Noncopyable and nonescapable types](#noncopyable-and-nonescapable-types)
- [Enums to the max](#enums-to-the-max)
- [Result builders](#result-builders)
- [Module selectors (6.3+)](#module-selectors-63)
- [Iterable (6.4 beta)](#iterable-64-beta)
- [Value semantics discipline](#value-semantics-discipline)

## some vs any

Default to `some` (opaque type) or a generic parameter; reach for `any` (existential) only when you need runtime type erasure.

- `some P` / `<T: P>`: one concrete type per use site, static dispatch, full specialization, no boxing. Zero-cost.
- `any P`: boxed existential (inline buffer is 3 words; larger values heap-allocate), dynamic dispatch through a witness table, blocks specialization. Pay this cost only for genuine heterogeneity or storage of "some unknown type decided at runtime".

```swift
// Prefer: caller picks the type, fully specialized.
func render(_ shape: some Shape) -> Image { shape.rasterize() }

// Justified `any`: heterogeneous collection.
var layers: [any Shape] = [Circle(), Rect(), Path()]
```

Primary associated types (5.7+) let you constrain both forms: `some Collection<Int>`, `any Collection<Int>` (constrained existentials). Declare them on your own protocols:

```swift
protocol Cache<Key, Value> {
    associatedtype Key: Hashable
    associatedtype Value
    func value(for key: Key) -> Value?
}
func warm(_ cache: some Cache<URL, Data>) { ... }   // generic, dispatch-free
let caches: [any Cache<URL, Data>] = [...]          // heterogeneous, boxed
```

Opening existentials: passing `any P` to a `some P` parameter implicitly "opens" the box (5.7+), so write generic functions and let callers hold existentials — don't propagate `any` through your whole API.

## Protocol design

**The customization-point trap.** Only protocol *requirements* dispatch dynamically. A method defined only in an extension is statically dispatched on the declared type — conformers can "override" it and never be called:

```swift
protocol Greeter { }                       // WRONG: no requirement
extension Greeter { func greet() -> String { "Hello" } }
struct Pirate: Greeter { func greet() -> String { "Arrr" } }
let g: any Greeter = Pirate()
g.greet()                                  // "Hello" — extension wins, shadow ignored

protocol Greeter2 { func greet() -> String }  // RIGHT: requirement = customization point
extension Greeter2 { func greet() -> String { "Hello" } }  // default impl
struct Pirate2: Greeter2 { func greet() -> String { "Arrr" } }
(Pirate2() as any Greeter2).greet()        // "Arrr"
```

Rule: if conformers may customize it, make it a requirement with a default implementation in an extension. Extension-only methods are for derived behavior that must *not* vary.

**Avoid protocol-for-one-conformer.** A protocol with exactly one conformer (usually "for testability") adds dispatch cost, blocks specialization, and obscures code. Prefer concrete types; introduce the protocol when the second conformer actually arrives, or inject a struct of closures for test seams.

**Retroactive conformances.** Conforming a type you don't own to a protocol you don't own risks collision when the owning module adds the conformance later (behavior is then ambiguous per linker whim). Since 6.0 (accepted for 5.10, SE-0364) the compiler warns; acknowledge deliberately:

```swift
extension Date: @retroactive Identifiable {   // explicit: "I accept the risk"
    public var id: TimeInterval { timeIntervalSince1970 }
}
```

Prefer wrapping in your own type over retroactive conformance in library code.

## Generics

`where` clauses express relationships the angle-bracket list can't:

```swift
func merge<S: Sequence, T: RangeReplaceableCollection>(_ s: S, into t: inout T)
    where S.Element == T.Element { t.append(contentsOf: s) }
```

Conditional conformance — conform only when element types qualify:

```swift
extension Stack: Equatable where Element: Equatable {
    static func == (a: Self, b: Self) -> Bool { a.items == b.items }
}
```

Specialization: within a module (or with libraries built for cross-module optimization), the compiler clones generic functions per concrete type — generics are usually free. `@inlinable` on public generic API lets clients specialize too; it freezes the body as ABI, so use deliberately in libraries.

## Parameter packs (5.9+)

Abstract over *arity*: APIs that take N values of N different types without overload explosion. Pack iteration `for x in repeat each pack` is 6.0+ (SE-0408).

```swift
// Run N throwing producers, return a tuple of their results.
func gatherResults<each T>(_ producer: repeat () throws -> each T) rethrows -> (repeat each T) {
    (repeat try (each producer)())
}
let (n, s) = try gatherResults({ 42 }, { "hi" })   // (Int, String)

// Compare two packs element-wise (pack iteration, 6.0+).
func allEqual<each T: Equatable>(_ lhs: repeat each T, to rhs: repeat each T) -> Bool {
    for (l, r) in repeat (each lhs, each rhs) where l != r { return false }
    return true
}
```

Use packs to replace families like `zip3`/`zip4` or `AnyView`-style erasure of fixed-arity tuples. Don't reach for them when an array of a single generic type suffices.

## Noncopyable and nonescapable types

`~Copyable` (5.9+, SE-0390; usable in generics 6.0+, SE-0427) suppresses the implicit copy. Use for values where two copies would be a bug: file descriptors, unique handles, one-shot tokens, locks. Structs gain `deinit`; ownership is explicit via parameter modifiers:

```swift
struct FileHandle: ~Copyable {
    private let fd: Int32
    init(fd: Int32) { self.fd = fd }
    consuming func close() {          // takes ownership; value is dead after
        discard self                  // suppress deinit — we closed manually
        // (real impl calls close(fd) before discard)
    }
    borrowing func bytesAvailable() -> Int { ... }  // read-only access, no transfer
    deinit { /* close(fd) — safety net */ }
}
let h = FileHandle(fd: 3)
h.close()
// h.bytesAvailable()   // error: 'h' consumed — double-close is a compile error
```

- `borrowing` (read without ownership, the default for most params), `consuming` (take ownership; enables `discard self` and move-out), `inout` (exclusive mutable). These modifiers (SE-0377, 5.9+) also work on copyable types to avoid retain/release traffic in hot paths.
- Generic use requires opt-out: `func take<T: ~Copyable>(_ t: consuming T)` — plain `T` still implies `Copyable`.

`~Escapable` (6.2+ in practice; SE-0446) marks values that cannot outlive their source — the mechanism behind `Span`/`RawSpan` (6.2+, SE-0447), which give bounds-checked, pointer-free views into contiguous memory with compile-time lifetime enforcement. Lifetime-dependency annotations (`@lifetime`) remain experimental as of 6.3 — use stdlib `~Escapable` types freely, but don't design public API around custom `~Escapable` returns yet.

## Enums to the max

- Raw values = serialization convenience (`String`/`Int` mapping); associated values = real payloads. Don't contort a design to keep raw representability — write explicit `Codable` instead.
- `indirect` for recursive payloads: `indirect enum Expr { case num(Double); case sum(Expr, Expr) }`.
- `CaseIterable` for menus/tests; it's synthesized only when there are no associated values.
- Switch exhaustively **without** `default` on enums you own — adding a case then produces compile errors at every switch, which is the point.
- For nonfrozen enums from binary frameworks (Apple SDKs), handle future cases explicitly:

```swift
switch phase {                       // e.g. a nonfrozen SDK enum
case .active: start()
case .background: pause()
@unknown default: pause()            // still warns if you missed a *known* case
}
```

Prefer `@unknown default` over `default` even when forced to be non-exhaustive: it keeps the missing-known-case warning alive.

## Result builders

Use only for declarative DSLs where value *structure* is the API (view trees, regexes, charts) — not to avoid writing an array literal. Minimal anatomy:

```swift
@resultBuilder
enum QueryBuilder {
    static func buildPartialBlock(first: Clause) -> [Clause] { [first] }
    static func buildPartialBlock(accumulated: [Clause], next: Clause) -> [Clause] {
        accumulated + [next]
    }
    static func buildOptional(_ c: [Clause]?) -> [Clause] { c ?? [] }        // enables `if`
    static func buildEither(first c: [Clause]) -> [Clause] { c }             // enables if/else
    static func buildEither(second c: [Clause]) -> [Clause] { c }
    static func buildArray(_ cs: [[Clause]]) -> [Clause] { cs.flatMap { $0 } } // enables `for`
}
func query(@QueryBuilder _ clauses: () -> [Clause]) -> Query { ... }
```

`buildPartialBlock` (5.7+) replaces the old arity-N `buildBlock` overload pile — prefer it; it composes pairwise and keeps type-checking tractable.

## Module selectors (6.3+)

`ModuleName::Name` (SE-0491, implemented 6.3) disambiguates identical names from different modules anywhere an existing declaration is referenced:

```swift
let color = AppKit::Color(...)         // vs. your own `Color`
func scrub() -> NASA::Scrubber { ... }
#MyMacros::stringify(x)                // works on macros too
```

Use instead of the old fully-qualified `Module.Type` spelling when that is itself ambiguous (e.g. a type named like a module). Invalid on *new* declaration names.

## Iterable (6.4 beta)

**Beta — WWDC26, Swift 6.4 only.** `Iterable` (SE-0516) is the borrowing counterpart to `Sequence`: iteration *borrows* elements instead of copying them out. Conforming types and their elements may be noncopyable or nonescapable — this is how `for` loops over `Span` and `InlineArray` of `~Copyable` elements work. Its iterator vends elements in span batches, skipping per-element retain/release. `for` loops prefer `Sequence` when both are available and fall back to `Iterable`. Do not use in code that must build with 6.3.

## Value semantics discipline

- Model with structs/enums; mark in-place mutation `mutating` so callers see it at the use site and `let` values stay frozen.
- If a struct must wrap class-backed storage (buffers, reference-only APIs), preserve value semantics with copy-on-write:

```swift
struct Bitmap {
    private var storage: PixelBuffer            // a class
    mutating func setPixel(_ p: Pixel, at i: Int) {
        if !isKnownUniquelyReferenced(&storage) {  // shared? copy before write
            storage = storage.copy()
        }
        storage[i] = p
    }
}
```

`isKnownUniquelyReferenced` must be called on a `var` stored property of class type, not a computed one, or it always returns false and you copy every time. Never let the inner reference escape (`storage` stays `private`), or aliasing silently breaks value semantics.
