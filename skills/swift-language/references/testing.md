# Swift Testing (6.x)

Reference for writing tests with Swift Testing (the default framework), remaining XCTest use cases, and structuring code for testability. Stable = 6.3; 6.4 features are WWDC26 beta and marked as such.

## Contents
1. [Core API](#core-api)
2. [Traits](#traits)
3. [Parameterized tests](#parameterized-tests)
4. [Async patterns: confirmation, actors, clocks](#async-patterns-confirmation-actors-clocks)
5. [Exit tests (6.2+)](#exit-tests-62)
6. [Attachments (6.2+)](#attachments-62)
7. [XCTest: when and interop](#xctest-when-and-interop)
8. [Structuring testable code](#structuring-testable-code)
9. [Running tests & parallelism](#running-tests--parallelism)
10. [Migration table: XCTest → Swift Testing](#migration-table-xctest--swift-testing)

## Core API

```swift
import Testing

@Suite("Cart")
struct CartTests {
    let cart: Cart

    init() throws { cart = try Cart.empty() }   // per-test setup: a NEW instance per @Test (replaces setUp)
    // deinit for teardown — only on classes/actors, or use `defer` in the test body

    @Test func addingItemIncreasesCount() {
        cart.add(.stub)
        #expect(cart.count == 1)                 // failure shows sub-expression values; test continues
    }

    @Test func firstItemIsRetrievable() throws {
        let item = try #require(cart.items.first) // unwraps or aborts THIS test; use for preconditions
        #expect(item.quantity > 0)
    }
}
```

- `#expect(expr)` takes any Bool expression — write `#expect(a == b)`, `#expect(list.contains(x))`; the macro captures and prints operand values on failure. No assertEqual/assertTrue zoo.
- `#expect(throws: StoreError.self) { try store.checkout() }` for errors; use the returned error for further checks. `#expect(throws: Never.self)` asserts no throw.
- `#require(...)` throws on failure (aborts the test); `#expect` records and continues. Use `#require` when later lines depend on the condition.
- Suites: any type with `@Test` members works; `@Suite` adds a name/traits and applies traits to all members. Nest types for grouping. Structs are preferred — value semantics guarantee test isolation.
- `withKnownIssue("flaky upstream") { ... }` replaces XCTExpectFailure.

## Traits

```swift
@Test(.tags(.networking), .enabled(if: Env.hasNetwork), .timeLimit(.minutes(1)), .bug("https://github.com/org/repo/issues/42"))
func syncsRemoteState() async throws { ... }

@Suite(.serialized) struct DatabaseTests { ... }  // members run one at a time (and any nested suites)
```

- `.tags(.x)` — declare via `extension Tag { @Tag static var networking: Self }`; filter with `swift test --filter tag:networking` or in Xcode's Test Plan.
- `.enabled(if:)` / `.disabled("reason")` — conditional runs; the condition is evaluated at run time, and disabled tests still typecheck (unlike commenting out).
- `.timeLimit(.minutes(1))` — minimum granularity is minutes; it's a crash-net, not a precision timer.
- `.serialized` — opts a suite or parameterized test out of parallel execution. Escape hatch, not a default; see [parallelism](#running-tests--parallelism).
- `.bug(_:id:)` — links failures to your tracker in results.

## Parameterized tests

```swift
@Test(arguments: [Fixture.empty, .single, .many])
func encodesRoundTrip(_ fixture: Fixture) throws {
    let data = try encode(fixture)
    #expect(try decode(data) == fixture)
}

@Test(arguments: zip(inputs, expectedOutputs))   // zip = pairwise
func parses(_ input: String, expected: Token) { ... }
```

Each argument is an independent test case: runs in parallel, reported and re-runnable individually. Two unzipped collections produce the full cross-product — use `zip` when you mean pairs. Prefer parameterization over `for` loops inside one test (a loop stops at first failure and hides which case broke).

## Async patterns: confirmation, actors, clocks

Tests are async-friendly: mark `@Test func f() async throws` and `await` directly.

**confirmation()** — assert that an event/callback fires during a bounded async operation:

```swift
@Test func deliversEvent() async {
    await confirmation("delegate called", expectedCount: 1) { confirm in
        let sut = Downloader(onProgress: { _ in confirm() })
        await sut.download(url)
    }   // fails if count != 1 when the closure returns
}
```
`expectedCount: 0` asserts something never happens. `confirmation` does not wait — the operation must complete within the closure; it is not `XCTestExpectation.wait`. For "eventually true", await the actual async result instead.

**Testing actors**: just `await` into them; suspension is natural in async tests.

```swift
@Test func cacheDedupes() async throws {
    let cache = Cache(loader: StubLoader())
    async let a = cache.data(for: url)
    async let b = cache.data(for: url)
    _ = try await (a, b)
    #expect(await cache.loadCount == 1)   // read actor state with await
}
```
To test `@MainActor` code, annotate the test or suite `@MainActor`.

**Avoiding flaky time-based tests** — never `Task.sleep` and hope. Inject a `Clock`:

```swift
struct Debouncer<C: Clock> {
    let clock: C
    func debounce(for d: C.Duration) async throws { try await clock.sleep(for: d) }
}
// Production: Debouncer(clock: ContinuousClock())
// Tests: a manual/test clock (e.g. swift-clocks' TestClock) advanced explicitly:
await testClock.advance(by: .seconds(3))   // deterministic, instant
```
Same principle for `Date()` — inject `now: () -> Date`. If a test contains a real sleep >10ms, treat it as a bug.

## Exit tests (6.2+)

Test `fatalError`/`precondition` paths without killing the test run — the body executes in a child process:

```swift
@Test func emptyCartCheckoutTraps() async {
    await #expect(processExitsWith: .failure) {
        Cart.empty().forceCheckout()   // hits precondition
    }
}

@Test func exitCodeAndOutput() async throws {
    let result = try await #require(processExitsWith: .exitCode(2),
                                    observing: [\.standardOutputContent]) {
        runCLI(["--bad-flag"])
    }
    #expect(result.standardOutputContent.contains(UTF8.self, "usage:"))
}
```
Requirements: must `await`; body captures nothing from the enclosing context (fresh process); macOS/Linux/Windows only — not iOS simulators/devices.

## Attachments (6.2+)

Attach debugging artifacts to results (surfaced in Xcode 26+ result bundles / `--attachments-path`):

```swift
import Testing

@Test func rendersLayout() throws {
    let output = render(fixture)
    Attachment.record(output.debugDescription, named: "layout-dump.txt")
    Attachment.record(try #require(output.pngData), named: "render.png")
    #expect(output.isValid)
}
```
`String`, `Data`, and `Encodable` types attach out of the box; conform your own types to `Attachable` for custom serialization. Attach on failure paths especially — it's the difference between a red CI dot and a diagnosable one.

## XCTest: when and interop

Still required for:
- **UI automation** — `XCUIApplication`, `XCUIElement` have no Swift Testing equivalent.
- **Performance** — `measure(metrics: [XCTClockMetric(), XCTMemoryMetric()])` and friends.
- (Rare) ObjC test code.

Both frameworks coexist in one target today: Swift Testing tests and `XCTestCase` subclasses run side by side under `swift test` and Xcode. Through 6.3, don't mix *APIs across frameworks* (no `#expect` inside `XCTestCase`, no XCTAssert inside `@Test`) — failures get misattributed or lost.

**6.4 beta (Xcode 27)**: two-way interop lands — XCTest assertion failures are reported as Swift Testing issues and Swift Testing APIs work inside `XCTestCase`, with modes (limited/complete/strict/none; Xcode 27 enables it by default, cross-framework issues as warnings unless upgraded). Until you're on the 6.4 toolchain, keep the APIs separated.

## Structuring testable code

- **Protocol seams** for multi-method dependencies with state:

```swift
protocol Persisting { func save(_ item: Item) throws; func load(id: Item.ID) throws -> Item? }
// prod: SQLiteStore; tests: in-memory fake (a real fake with a Dictionary beats a mock with expectations)
```

- **Closure injection** for single-operation dependencies — lighter than a protocol:

```swift
struct Uploader { var send: @Sendable (Data) async throws -> Void }
let sut = FeatureModel(uploader: Uploader(send: { captured.append($0) }))
```
Rule of thumb: 1–2 functions → closures; cohesive behavior/state → protocol. Either way, inject at `init`; singletons are untestable seams.

- **`@testable import`** lifts `internal` into tests. Fine for app targets (the test suite is the only client). For libraries, prefer testing through `public` API — `@testable` couples tests to internals and requires disabling library evolution; heavy reliance on it usually signals the public API is untestable.

## Running tests & parallelism

```bash
swift test                                   # builds + runs all (Swift Testing and XCTest)
swift test --filter CartTests                # by suite/test name (regex)
swift test --filter tag:networking           # by tag
swift test --no-parallel                     # serialize everything (debugging aid)
xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

- **Swift Testing runs tests in parallel by default** — including tests within a suite, in-process via the cooperative pool (XCTest parallelism is per-process/per-class). Implications: no shared mutable globals, no fixed ports/paths (use unique temp dirs per test), no test-order dependencies. This is a feature — it flushes hidden coupling.
- `.serialized` on a suite is the targeted escape hatch for genuinely shared resources (one database file, a global cache). Serializing everything to hide races just defers the pain.
- Because suites are instantiated per test (`init` each time), expensive shared fixtures need explicit management (`static let`, or a `.serialized` suite) — don't assume `setUp`-style reuse.

## Migration table: XCTest → Swift Testing

| XCTest | Swift Testing |
|---|---|
| `class FooTests: XCTestCase` | `@Suite struct FooTests` (struct preferred) |
| `func testBar()` | `@Test func bar()` (any name; no `test` prefix) |
| `setUp()` / `setUpWithError()` | `init()` / `init() throws` |
| `tearDown()` | `deinit` (class/actor suites) or `defer` in test body |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(x)` / `XCTAssertFalse(x)` | `#expect(x)` / `#expect(!x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertNotNil(x)` + force unwrap | `let v = try #require(x)` |
| `XCTAssertThrowsError(try f())` | `#expect(throws: MyError.self) { try f() }` |
| `XCTAssertNoThrow(try f())` | `#expect(throws: Never.self) { try f() }` or just `try f()` |
| `XCTUnwrap(x)` | `try #require(x)` |
| `XCTFail("msg")` | `Issue.record("msg")` |
| `XCTSkipIf(cond)` | `.enabled(if: !cond)` trait |
| `XCTestExpectation` + `wait` | `await` the work directly, or `confirmation()` for event counts |
| `XCTExpectFailure` | `withKnownIssue { ... }` |
| `measure { }` | stays in XCTest |
| `XCUIApplication` UI tests | stays in XCTest |
