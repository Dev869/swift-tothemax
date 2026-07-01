# Swift Concurrency (6.x)

Reference for writing and reviewing Swift 6.x concurrency code: isolation, actors, tasks, streams, diagnostics, and anti-patterns. Stable = 6.3; 6.4 features are WWDC26 beta and marked as such.

## Contents
1. [Mental model](#mental-model)
2. [Swift 6 language mode & migration](#swift-6-language-mode--migration)
3. [Approachable concurrency (6.2+)](#approachable-concurrency-62)
4. [Actors vs Mutex vs @MainActor class](#actors-vs-mutex-vs-mainactor-class)
5. [Tasks](#tasks)
6. [AsyncSequence / AsyncStream](#asyncsequence--asyncstream)
7. [Diagnostics decoded](#diagnostics-decoded)
8. [6.3 / 6.4-beta changes](#63--64-beta-changes)
9. [Anti-patterns](#anti-patterns)

## Mental model

- Every value lives in an **isolation domain**: a specific actor (`@MainActor`, actor instance), or nonisolated. The compiler proves no domain reads/writes another domain's mutable state concurrently.
- **`Sendable` is the contract** for values that may be *referenced from* multiple domains simultaneously: value types of Sendable parts, actors, `final class` with immutable state, `Mutex`-guarded types.
- **Region-based isolation (SE-0414, 6.0)**: non-`Sendable` values can still cross domains if the compiler proves the sender's region never touches the value afterward. This is why `let m = NonSendableModel(); await actor.take(m)` compiles when `m` isn't used again — the whole region *transfers*.
- **`sending` (SE-0430, 6.0)** parameters/results make transfer part of an API signature: callee receives a disconnected value it may safely isolate.

```swift
func process(_ model: sending Model) async { ... } // caller loses access; Model need not be Sendable
```

Prefer `sending` over conforming marginal types to `Sendable`; it encodes ownership transfer instead of forcing thread-safety.

## Swift 6 language mode & migration

Swift 6 *language mode* makes data-race safety errors, not warnings. Migration order per module:

1. Stay in Swift 5 mode, enable `-strict-concurrency=complete` (SwiftPM: `.enableExperimentalFeature("StrictConcurrency")` or `-Xswiftc -strict-concurrency=complete`). Fix warnings.
2. Adopt upcoming feature flags one at a time (`DisableOutwardActorInference`, `GlobalConcurrency`, `InferSendableFromCaptures`, ...).
3. Flip the mode: `.swiftLanguageMode(.v6)` in `Package.swift` / `SWIFT_VERSION = 6` in Xcode.

For dependencies that predate concurrency annotations:

```swift
@preconcurrency import LegacySDK // downgrades that module's Sendable errors to warnings/silence
```

Use `@preconcurrency` on protocol conformances and imports as a *bridge*, not a destination; remove when the dependency updates. Migrate leaf modules first, app target last.

## Approachable concurrency (6.2+)

Three opt-in settings (Xcode 26 templates enable them for new app projects):

**Default MainActor isolation (SE-0466, 6.2)** — everything unannotated in the module is implicitly `@MainActor`:

```swift
// Package.swift
swiftSettings: [.defaultIsolation(MainActor.self)]
// Xcode: SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

**`nonisolated(nonsending)` / caller-isolation inheritance (SE-0461, 6.2)** — under the `NonisolatedNonsendingByDefault` upcoming feature, a `nonisolated async` function runs on the **caller's actor** instead of hopping to the global executor. This kills a large class of "sending non-Sendable across the await" errors because nothing crosses domains. Write `nonisolated(nonsending)` explicitly to get this semantic without the module-wide flag.

**`@concurrent` (SE-0461, 6.2)** — explicit opt-out: always run on the global concurrent executor. Use for CPU-bound work that must not occupy the caller's actor:

```swift
@concurrent func decodeLargeJSON(_ data: Data) async throws -> Payload { ... }
```

When to enable:
- **App targets / UI-heavy modules**: enable both `defaultIsolation(MainActor.self)` and `NonisolatedNonsendingByDefault`. Single-threaded by default; introduce concurrency deliberately via `@concurrent`.
- **Libraries**: enable `NonisolatedNonsendingByDefault` (it changes your public API's execution semantics — do it before stabilizing). Usually skip default MainActor isolation unless the library is UI-facing; general-purpose libraries should stay nonisolated so callers choose.

## Actors vs Mutex vs @MainActor class

| Need | Use |
|---|---|
| UI-adjacent state, called from UI | `@MainActor` class (no hops from views, simplest) |
| Serialize access + async work inside (I/O, awaits while holding logical ownership) | `actor` |
| Tiny synchronous critical sections (counters, caches, token storage) | `Mutex<State>` (SE-0433, 6.0, `import Synchronization`) — no await, no reentrancy, usable from sync code |
| Lock-free primitives | `Atomic<Int>` etc. (SE-0410, 6.0) |

```swift
final class TokenStore: Sendable {
    private let state = Mutex<String?>(nil)
    func set(_ t: String?) { state.withLock { $0 = t } }
    var token: String? { state.withLock { $0 } }
}
```

**Reentrancy**: actors are reentrant — every `await` inside an actor method is a suspension where *other* calls can interleave and mutate state. Re-read/validate state after each `await`; never assume an invariant checked before an `await` still holds after it.

```swift
actor Cache {
    var entries: [URL: Data] = [:]
    func data(for url: URL) async throws -> Data {
        if let d = entries[url] { return d }
        let d = try await download(url)      // suspension: another call may have populated entries[url]
        entries[url] = d                     // fine (last write wins), but don't double-charge side effects
        return d
    }
}
```
Dedupe in-flight work with a `[URL: Task<Data, Error>]` dictionary instead of a boolean flag.

**Hopping costs**: each cross-actor `await` is an executor hop. Chatty per-element calls into an actor are slow — batch (`func add(_ items: [Item])` not N× `add(_ item:)`). `@MainActor`→`@MainActor` calls don't hop.

**Custom executors** (SE-0392): give an actor `nonisolated var unownedExecutor` to pin it to a specific dispatch queue/thread — mainly for interop with thread-bound C/ObjC libraries. Rarely needed otherwise.

## Tasks

Prefer structured concurrency; it propagates cancellation, priority, and task-locals automatically.

```swift
// Fixed fan-out
async let user = fetchUser(id)
async let posts = fetchPosts(id)
return try await Profile(user: user, posts: posts)

// Dynamic fan-out
try await withThrowingTaskGroup(of: Image.self) { group in
    for url in urls { group.addTask { try await load(url) } }
    return try await group.reduce(into: []) { $0.append($1) }
}

// Fire-and-forget children with no results (6.0)
await withDiscardingTaskGroup { group in
    for conn in connections { group.addTask { await conn.serve() } } // results discarded eagerly, no accumulation
}
```

- `Task { }` (unstructured): inherits actor context, priority, task-locals — but *you* own cancellation. Store the handle and cancel it (e.g. in `deinit`/`onDisappear`). Use only at boundaries where sync code must start async work.
- `Task.detached { }`: inherits *nothing* (no actor, no priority, no task-locals). Almost always wrong; prefer `@concurrent` functions or a group. Legit uses: work that must escape the current actor *and* current priority.
- `Task(name:)` (SE-0469, 6.2) names tasks for debugging/instruments.
- `Task.immediate` (SE-0472, 6.2) starts synchronously on the caller's context until the first suspension — for UI cases where the first partial result must land before the next runloop tick.

**Cancellation is cooperative** — nothing stops unless code checks:

```swift
try Task.checkCancellation()            // throw CancellationError at checkpoints in loops
if Task.isCancelled { return partial }  // non-throwing variant
await withTaskCancellationHandler {
    try await urlSession.data(from: url)
} onCancel: {
    connection.forceClose()             // runs immediately, possibly concurrently — must be thread-safe
}
```
Cancellation never interrupts running code and doesn't skip `defer`. Check it inside every long loop and before expensive phases.

**Task-locals** — implicit context (request IDs, loggers) flowing to child tasks:

```swift
enum Trace { @TaskLocal static var requestID: String? }
try await Trace.$requestID.withValue(id) { try await handle(request) } // visible in all structured children
```
Unstructured `Task {}` inherits task-locals at creation; `Task.detached` does not.

## AsyncSequence / AsyncStream

- Build streams with `AsyncStream.makeStream(of:bufferingPolicy:)` (SE-0388, 5.9) — avoids the escaping-continuation-from-init dance:

```swift
let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(16))
continuation.yield(event)
continuation.onTermination = { _ in stopProducer() } // fires on cancel too — always clean up here
```

- **AsyncStream has no back-pressure**: `yield` never suspends. `.unbounded` (default) grows memory without limit under a slow consumer; `.bufferingNewest/Oldest(n)` silently drop. If the producer must slow down to match the consumer, use **`AsyncChannel` / `AsyncThrowingChannel`** from `swift-async-algorithms` — `await channel.send(x)` suspends until consumed.
- One consumer per AsyncStream. Multiple `for await` loops on the same stream split elements unpredictably; broadcast needs an explicit multicast layer.
- `for await x in seq` checks cancellation at each iteration for well-behaved sequences; ending consumption cancels the stream (`onTermination`).

## Diagnostics decoded

**"Capture of 'x' with non-Sendable type 'T' in a `@Sendable` closure"**
1. Make `T` genuinely Sendable (value type, or guard state with `Mutex`).
2. Don't cross domains: run the closure on the same actor (e.g. `nonisolated(nonsending)`, or a `@MainActor` closure).
3. Capture Sendable pieces instead of the whole object: `let id = model.id; Task { await use(id) }`.

**"Sending 'x' risks causing data races" / "'x' used after being sent"**
1. Stop using `x` after the transfer point — the region must fully hand off (reorder code, or make a copy to keep).
2. Accept it as `sending` in the callee to make the transfer explicit.
3. If the value is logically immutable/thread-safe, make it `Sendable` properly (not `@unchecked`).

**"Main actor-isolated property 'p' cannot be referenced from a nonisolated context"**
1. Hop: `await MainActor.run { p }` or make the calling function `@MainActor`.
2. Move the *function* to the right domain — often it belongs on `@MainActor` anyway (or enable default MainActor isolation for the module).
3. If `p` is immutable and safe, mark it `nonisolated` (stored `let` of Sendable type is implicitly accessible; computed needs explicit `nonisolated`).

## 6.3 / 6.4-beta changes

- **6.3**: region-based isolation sharpened (fewer false positives); `weak let` (SE-0481) lets classes with weak refs drop `@unchecked Sendable`.
- **6.4 beta** (Xcode 27 / WWDC26 — do not present as stable):
  - `await` in `defer` bodies (SE-0493): async cleanup without `do/catch` wrappers; implicitly awaited at scope exit, does not hide cancellation.
  - `withTaskCancellationShield` (SE-0504): suppress cancellation observation during must-complete cleanup.
  - New Task diagnostics (SE-0520): warning when a throwing `Task {}`'s value/handle is discarded — "Unstructured throwing task was not used, which may accidentally ignore errors." Fix: `try await task.value`, store the handle, or handle the error inside.
  - Async `Result` initializer (SE-0530) for capturing async success/failure.

## Anti-patterns

- **Fire-and-forget `Task {}` with no owner**: errors vanish, work outlives the screen, no cancellation. Store handles, use `.task {}` in SwiftUI (auto-cancelled), or a task group.
- **Mixing DispatchQueue with actors**: `DispatchQueue.main.async` from actor code defeats compiler checking and reorders relative to actor jobs. Use `@MainActor` / `await MainActor.run`.
- **`@unchecked Sendable` as a shortcut**: it's an unverified promise; every future edit can silently introduce a race. Reach for `Mutex<State>`, actors, or `sending` first. Acceptable only with a real lock inside and a comment saying which one.
- **Blocking the cooperative pool**: `Thread.sleep`, `DispatchSemaphore.wait`, `.sync`, blocking file/network IO inside async functions can deadlock the whole pool (width = core count). Use `try await Task.sleep(for: .seconds(1))`, continuations around callback APIs, and async IO.
- **Semaphores to "bridge" sync→async** (`semaphore.wait()` after `Task {}`): classic pool deadlock. Restructure so the boundary is async, or use a callback.
- **Actor for a hot synchronous counter**: every access is an async hop. Use `Mutex`/`Atomic`.
- **Assuming actor state is unchanged across `await`**: see reentrancy above — revalidate after every suspension.
