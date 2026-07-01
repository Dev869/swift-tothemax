# ImageLoader: Migration to Swift 6 Concurrency

Verified: `swiftc -typecheck -swift-version 6 migrated.swift` passes with no warnings (Swift 6.3.3).

## Changes

### 1. `final class` + concurrent `DispatchQueue` → `actor`
The original protected `cache` with a concurrent queue and `.barrier` writes — thread safety by convention, invisible to the compiler (and the class would fail Swift 6's `Sendable` checking as a shared singleton). An `actor` gives the same serialization of mutable state, but the compiler now *proves* there are no data races. `static let shared` stays; actors are inherently `Sendable`, so a shared instance is fine.

### 2. Completion handler → `async throws -> Data`
`load(_:completion:)` becomes `func load(_ url: URL) async throws -> Data`. Callers get typed control flow (`try await`), automatic cancellation propagation, and no callback-on-which-queue ambiguity. `URLSession.dataTask` + `resume()` is replaced by the native `try await URLSession.shared.data(from: url)`, which also removes the `data!` force unwrap — errors surface as thrown errors instead of a crash path.

### 3. Main-queue dispatch removed
The original hopped to `DispatchQueue.main` because it couldn't know the caller's context. With async/await the caller resumes in its own isolation automatically (a `@MainActor` caller resumes on the main actor), so the explicit hops are gone. For unmigrated call sites, a deprecated `nonisolated` compatibility overload preserves the old signature and delivers the result via a `@MainActor` completion — same observable behavior as `DispatchQueue.main.async`.

### 4. In-flight request deduplication (`[URL: Task<Data, any Error>]`)
Actors are *reentrant*: every `await` is a suspension point where other calls interleave, so a naive port would let N concurrent requests for the same URL each start a download (the original had this same race — the cache write happened in a detached barrier block after the request finished, so concurrent loads duplicated network calls, and a completion could even arrive before the cache was written). The `inFlight` dictionary is the standard fix: the first caller creates the download `Task`, later callers `await` the same task's `.value`. Cache and in-flight state are only touched from actor-isolated code, and state is re-checked before each suspension.

## Behavior preserved
- Global shared instance (`ImageLoader.shared`).
- Cache hit returns stored data without a network call.
- Errors are propagated to the caller (now thrown; via `Result` in the compat shim).
- Completion-handler callers (via the shim) still get their callback on the main thread.

## Behavior improved (intentional, flagged)
- Duplicate concurrent downloads for the same URL are coalesced (the original could fire several).
- No force unwrap of `data` — the modern URLSession API can't return nil data without an error.
- Cancellation semantics are deliberate: the download runs in an unstructured `Task`, so one caller cancelling does **not** kill the shared download for other waiters (and matches the original, where the `URLSessionDataTask` always ran to completion). If a failure does occur, the task is removed from `inFlight` via `defer`, so a later retry starts a fresh request instead of replaying a cached error.
