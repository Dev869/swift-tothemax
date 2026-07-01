# ImageLoader: Migration to Swift 6 Concurrency

Verified: `swiftc -swift-version 6 -typecheck migrated.swift` passes with no
warnings or errors (Swift 6.3.3, macOS).

## Changes

### 1. `final class` + DispatchQueue → `actor`
The original used a concurrent `DispatchQueue` with `.barrier` writes to guard
`cache`. An `actor` gives the same mutual exclusion at the language level: all
access to `cache` is serialized by actor isolation, checked by the compiler.
The queue property is deleted entirely. This is also what makes the type
`Sendable`, so `static let shared` is legal in Swift 6 (a non-Sendable class
with a shared mutable singleton would be a compile error).

### 2. Completion-handler dataTask → `async` API
`URLSession.shared.dataTask(with:) { ... }.resume()` becomes
`try await URLSession.shared.data(from: url)`. The force-unwrap `data!` and
manual error branching disappear — the async API throws on failure and returns
non-optional `Data` on success.

### 3. Primary API is now `func load(_ url: URL) async throws -> Data`
Same logic, in order: return cached data if present, otherwise fetch, store in
cache, return. The cache write after the `await` is unconditional, matching the
original barrier write (last fetch wins). Note the actor is *not* held across
the network call, so — exactly like the original — two concurrent requests for
an uncached URL may both hit the network; behavior is preserved, not "fixed".

### 4. Legacy completion-handler shim kept for existing call sites
A `nonisolated` overload with the original signature wraps the async method in
a `Task`. The original always delivered results via `DispatchQueue.main.async`;
the shim preserves that contract by typing the closure `@MainActor`, so the
runtime hops to the main actor before invoking it. Once all call sites adopt
`async`/`await`, this overload can be deleted.

### 5. `private init()`
Added so the singleton is actually the only instance (the implicit `init()`
was previously internal). Drop this line if other code constructs its own
`ImageLoader` instances.

## Behavior preserved
- Cache-first lookup, network fetch on miss, result cached for later calls.
- Errors propagate to the caller (`throws` / `.failure`).
- Completion-handler callers still get their callback on the main thread.
- No request de-duplication (same as before). If coalescing concurrent
  fetches of the same URL is desired later, track in-flight
  `Task<Data, Error>` values in the actor — but that would be a behavior
  change, so it was deliberately not done here.

## Behavior differences (intentional, edge-case only)
- A failed request no longer crashes: the old code force-unwrapped `data!`,
  which could trap if a request completed with neither data nor error. The
  async API makes that state unrepresentable.
- Cache hits are returned without first hopping through a background queue,
  so callers may see cached results slightly sooner. Ordering guarantees for
  independent requests were never specified and remain unspecified.
