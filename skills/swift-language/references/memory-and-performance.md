# Memory & Performance

Reference for writing and reviewing memory-correct, fast Swift 6.x code (stable = 6.3; 6.4 features marked beta).

## Contents
1. [ARC essentials](#arc-essentials)
2. [Copy-on-write (COW)](#copy-on-write-cow)
3. [Ownership: borrowing / consuming (5.9+)](#ownership-borrowing--consuming-59)
4. [6.2 performance toolkit: InlineArray, Span](#62-performance-toolkit)
5. [6.3: @inline(always) and @specialized](#63-inlinealways-and-specialized)
6. [Strict memory safety mode (6.2+)](#strict-memory-safety-mode-62)
7. [Existential and generic costs](#existential-and-generic-costs)
8. [Hot-path checklist](#hot-path-checklist)
9. [Tooling](#tooling)
10. [Unsafe escalation ladder](#unsafe-escalation-ladder)

## ARC essentials

Reference decision table:

| Use | When | Behavior |
|---|---|---|
| `strong` (default) | Ownership; parent → child | Retains; keeps object alive |
| `weak` | Back-reference whose target may die first (delegate, parent) | Optional, zeroed to `nil` on dealloc |
| `unowned` | Back-reference whose target provably outlives self (child → owning parent) | Non-optional; **traps** if accessed after dealloc |
| `unowned(unsafe)` | Never in new code | Dangling pointer, UB — no |

Prefer `weak` when in doubt: `unowned` converts a lifetime bug into a crash; `weak` converts it into an `if let`.

### Closure capture lists — when `[weak self]` is actually needed

`[weak self]` is required only when a **reference type stores an escaping closure that captures `self`** (retain cycle: self → closure → self), or when the closure is retained indefinitely by an external system (long-lived observers, timers, subscriptions).

```swift
final class Downloader {
    var onProgress: ((Double) -> Void)?          // stored escaping closure
    func start() {
        onProgress = { [weak self] p in           // ✅ needed: self→onProgress→self cycle
            guard let self else { return }
            self.render(p)
        }
    }
}
```

Cargo-cult usage — do NOT reflexively add `[weak self]` here:

```swift
// ❌ pointless: Task retains self only until the body finishes; no cycle,
// because self does not store the task's closure.
Task { [weak self] in await self?.refresh() }

// ✅ fine — brief strong capture just delays dealloc until the task ends:
Task { await refresh() }
```

Use `[weak self]` in a `Task` only if the task is long-running/looping (e.g., `for await` over a stream) or the task handle is stored on `self`, where holding `self` alive is itself the problem. `Timer.scheduledTimer`, `NotificationCenter` block observers, and Combine `sink` stored in `self` all need `weak`.

`withExtendedLifetime(obj) { ... }` guarantees `obj` is not released before the closure ends — use when ARC's "last use" analysis would free an object whose side tables/associated resources you still need (e.g., an object whose `deinit` unregisters a callback you are mid-flight on). Never rely on end-of-scope release timing; ARC may release after last *use*, not at scope exit.

## Copy-on-write (COW)

`Array`, `Dictionary`, `Set`, `String`, `Data` share storage on copy and clone lazily on first mutation of a non-uniquely-referenced buffer. Copies are O(1) until you mutate a shared value.

Custom COW type:

```swift
struct BigValue {
    private final class Storage { var bytes: [UInt8] = [] }
    private var storage = Storage()
    mutating func append(_ b: UInt8) {
        if !isKnownUniquelyReferenced(&storage) {   // must be a `var` class ref, direct stored property
            storage = Storage()                     // deep-copy here in real code
        }
        storage.bytes.append(b)
    }
}
```

Accidental copies via mid-mutation reads — a second live reference during mutation forces a full clone every iteration:

```swift
// ❌ closure holds a second reference to `items` → COW clone on each append
var items = [Int]()
let snapshot = { items }        // captures items
for i in 0..<1_000_000 { items.append(i) }  // may repeatedly copy

// ❌ same trap: reading self.buffer while mutating self.buffer through another path
// ✅ fix: avoid aliasing during mutation; mutate via one variable; use `consume` to end the other.
```

Also: `array[i].mutateInPlace()` on a struct element is fine, but going through a computed property or `didSet`-observed property makes a temporary copy per access.

## Ownership: borrowing / consuming (5.9+)

`borrowing` (default-like for most params, but explicit disables implicit copies at the boundary) and `consuming` parameter modifiers (SE-0377, 5.9+) declare transfer of ownership; `consume x` (5.9+) ends a variable's lifetime and forwards its value without retain/release or COW-triggering aliases.

```swift
func store(_ value: consuming LargeStruct) { self.slot = value }  // no copy; caller gives it up
func hash(_ value: borrowing LargeStruct) -> Int { ... }          // read-only, no ownership transfer

var config = makeConfig()
registry.store(consume config)   // config is dead after this line; compiler enforces it
```

When they matter: large structs on hot paths (avoids retain/release traffic on their class fields), **noncopyable types** (`~Copyable`, 5.9+ — here `borrowing`/`consuming` is mandatory API design, since there is no copy), and ending aliases before mutation to keep COW buffers uniquely referenced. Intuition: values are cheap until they *escape* (stored, captured, returned) — escape forces a copy or retain; `consuming` lets escape happen by move instead.

Don't sprinkle these on ordinary code: for small structs and classes the default conventions are already optimal, and the annotations constrain callers.

## 6.2 performance toolkit

### InlineArray (6.2+)

`InlineArray<count, Element>` (SE-0453): fixed-size, storage inline in the containing value (stack, or inline in a struct/class/array element) — no heap allocation, no COW, copied eagerly like a tuple. Sugar: `[4 of Int]` (SE-0483, 6.2+).

```swift
var buf: InlineArray<16, UInt8> = .init(repeating: 0)   // no allocation
struct Header { var magic: [4 of UInt8] }               // inline in Header
```

Use for small fixed-size hot buffers, embedded Swift, avoiding allocator traffic. Avoid for large or frequently passed-around values (every copy is a full element-wise copy — no COW to save you). It is not `Collection` (no implicit slicing); iterate by index or `span`.

### Span / RawSpan / MutableSpan (6.2+)

`Span<Element>` (SE-0447), `RawSpan`, `MutableSpan` (SE-0467) are safe, bounds-checked views over contiguous memory — the default replacement for `withUnsafeBufferPointer`. They are `~Escapable`: the compiler ties the span's lifetime to the value it borrows, so it cannot outlive or alias-mutate its source. No closure nesting needed:

```swift
func checksum(_ bytes: Span<UInt8>) -> UInt32 { ... }
let data: [UInt8] = ...
let sum = checksum(data.span)     // .span property on Array/ArraySlice/String.UTF8View etc. (6.2+)
```

Prefer `Span` parameters over `UnsafeBufferPointer` and over generic `some Sequence<UInt8>` when you require contiguous memory: safety of the former, monomorphic speed without generic bloat.

## 6.3: @inline(always) and @specialized

- `@inline(always)` (SE-0496, 6.3+): guarantees inlining at direct call sites; compile error if impossible. Use for tiny wrappers/accessors where call overhead dominates and you have **measured** it.
- `@specialized(where T == Int)` (SE-0460, 6.3+): emits a pre-specialized copy of a generic function for the listed concrete types; unspecialized entry re-dispatches to it at runtime. Stack multiple attributes for multiple types.

```swift
@specialized(where T == Int)
@specialized(where T == Double)
func sum<T: Numeric>(_ xs: [T]) -> T { xs.reduce(0, +) }
```

When NOT to use: both trade code size for speed — avoid on large functions, cold paths, or "just in case". `@inline(always)` also defeats the optimizer's own cost model and bloats every caller. For cross-module inlining of resilient libraries the tool is still `@inlinable`/`@usableFromInline` (which lock your implementation into the ABI — see api-design doc).

## Strict memory safety mode (6.2+)

Opt-in (SE-0458): `-strict-memory-safety` / SPM `.strictMemorySafety()`. The compiler then diagnoses every use of unsafe constructs (`Unsafe*Pointer`, `unsafeBitCast`, `@unchecked Sendable`, uses of `@unsafe`-marked APIs) unless acknowledged with the `unsafe` expression keyword (like `try`/`await`):

```swift
let value = unsafe ptr.pointee        // explicit acknowledgment
@unsafe func poke(_ p: UnsafeMutableRawPointer)   // marks your own API unsafe
@safe   func wrapped()                // asserts a safe interface despite unsafe internals
```

Enable it for security-critical code, parsers of untrusted input, embedded/firmware, and libraries advertising memory-safety guarantees. It produces warnings, not semantic changes — cheap to adopt module-by-module. Not worth the annotation noise for ordinary app targets that barely touch pointers.

## Existential and generic costs

- `any P` boxes the value: 3-word inline buffer, **heap allocation if the concrete type is larger**, plus witness-table dynamic dispatch and blocked inlining/specialization.
- `some P` / generic parameters are statically dispatched and specializable within a module — prefer them in hot paths and return positions.

```swift
// ❌ per-call boxing + dynamic dispatch
func total(_ xs: [any Numeric]) -> Double
// ✅ specialized per concrete type
func total<T: Numeric>(_ xs: [T]) -> T
```

Existentials are fine for heterogeneous storage and API boundaries — the cost only matters in loops. **Measure before optimizing**: check Instruments/benchmarks first; `any`→generic rewrites of cold code are churn.

## Hot-path checklist

- `array.reserveCapacity(n)` before loops of `append` when the count is known — avoids geometric reallocation and re-copies.
- `ContiguousArray` when elements are classes/`@objc` and you never bridge to `NSArray` — skips the NSArray-compatible storage check on Darwin.
- String building: repeated `s += piece` / `s.append(piece)` on one owned `String` is amortized O(n); `parts.joined()` is good; `s = s + a + b` in a loop creates temporaries — avoid.
- Bridging: crossing `String`↔`NSString`, `Array`↔`NSArray` repeatedly (e.g., Objective-C API in a loop) re-bridges each time; hoist the conversion out of the loop.
- `lazy` sequences recompute on every pass and every `count`/`contains`; materialize with `Array(...)` if consumed more than once. Never return `LazyMapSequence` across an API boundary.
- Complexity traps: `contains`/`firstIndex(of:)` on `Array` is O(n) — use `Set`/`Dictionary` for repeated membership tests; `sorted()` allocates a copy, `sort()` is in-place; `insert(_:at: 0)` / `removeFirst()` on `Array` is O(n) — use a `Deque` (swift-collections).
- Struct size: >~64 bytes structs passed around widely cost memcpy; consider class, COW wrapper, or `borrowing`/`consuming`.

## Tooling

- **Instruments**: Allocations (transient vs persistent, heap growth), Time Profiler (invert call tree, weight by self time), Swift Concurrency template (task/actor contention), Leaks. Profile release builds (`-O`) only.
- **Signposts**: `OSSignposter` (iOS 15+/macOS 12+; preferred over raw `os_signpost`) for intervals visible in Instruments:
  ```swift
  let sp = OSSignposter(subsystem: "app", category: "parse")
  let state = sp.beginInterval("parse")
  defer { sp.endInterval("parse", state) }
  ```
- **Micro-benchmarks**: `package-benchmark` (ordo-one) — statistically sound, tracks mallocs/syscalls/ARC traffic, CI thresholds; Google `swift-benchmark` is the lighter alternative. Never benchmark debug builds or single runs.
- **Inspection**: `swiftc -O -emit-sil file.swift` to check specialization/exclusivity/COW copies; godbolt.org supports Swift for asm diffing.
- **Backtraces**: on-crash backtracer built in since 5.9, on by default on Linux; enable elsewhere with `SWIFT_BACKTRACE=enable=yes`. Programmatic `Backtrace` capture API (6.2+).

## Unsafe escalation ladder

Escalate only when the previous rung measurably fails:

1. **`Span` / `MutableSpan` / `RawSpan` (6.2+)** — contiguous access, bounds-checked, lifetime-checked. Default choice; no rules to remember.
2. **Scoped `withUnsafe*` calls** (`withUnsafeBufferPointer`, `withUnsafeTemporaryAllocation`, `String(unsafeUninitializedCapacity:)`, `Array(unsafeUninitializedCapacity:)`). Rules: the pointer is valid **only inside the closure** — never store, return, or capture it; don't mutate the collection inside the closure.
3. **Raw `UnsafePointer` / manual `allocate`** — last resort (FFI, custom allocators). Rules: pair every `allocate` with `deallocate`; `initialize` before use and `deinitialize` non-trivial types; respect memory binding (`bindMemory`/`withMemoryRebound`, or `loadUnaligned` for raw bytes); document lifetime ownership at the API boundary; mark `@unsafe` under strict memory safety (6.2+).

Wrap any rung-3 code in a small `@safe` façade and test it under Address/Thread Sanitizer.
