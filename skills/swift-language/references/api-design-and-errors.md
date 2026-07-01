# API Design & Error Architecture

Reference for naming, shaping, evolving, and documenting Swift 6.x APIs and for choosing/structuring error handling (stable = 6.3; 6.4 features marked beta).

## Contents
1. [API Design Guidelines, operationalized](#api-design-guidelines-operationalized)
2. [Library ergonomics](#library-ergonomics)
3. [Access control discipline](#access-control-discipline)
4. [Availability & evolution](#availability--evolution)
5. [Error architecture](#error-architecture)
6. [Typed throws (6.0+)](#typed-throws-60)
7. [Error anti-patterns](#error-anti-patterns)
8. [Documentation](#documentation)

## API Design Guidelines, operationalized

Optimize for **clarity at the point of use** — design by writing the call site first, then the declaration.

- **Omit needless words**: every word at the call site must carry information. `list.remove(x)` not `list.removeElement(x)`; but keep words needed to avoid ambiguity: `remove(at: index)` vs `remove(x)`.
- **Name by role, not type**: `var greeting: String`, not `var string: String`; parameter `of restaurant: Restaurant` reads at use, not `restaurantObject`.
- **Mutating/nonmutating pairs**: verb for mutating, past participle or `-ing` for nonmutating: `sort()`/`sorted()`, `append`/`appending`, `formUnion`/`union`. Nonmutating-as-noun when the operation is naturally a noun: `x.distance(to: y)`.
- **Argument labels read as prose**: `x.insert(y, at: z)` → "insert y at z". Prepositions go in the label (`move(to:)`, `fade(from:)`), not the base name.
- **First argument label**: omit when the first argument completes a grammatical phrase with the base name (`addSubview(v)`, `min(a, b)`) or is the direct object; keep it when it doesn't (`dismiss(animated: true)`, `tracks(withMediaType:)`).
- **Value-preserving conversions omit the label**: `String(cents)`, `UInt32(x)`; narrowing/lossy ones label the cost: `UInt32(truncating:)`, `String(format:)`.
- **Factory methods** begin with `make`: `makeIterator()`, `factory.makeSession(for: user)`. Initializers for plain construction; `make` when the receiver configures the product.
- **Bool names read as assertions**: `isEmpty`, `hasSuffix(_:)`, `canBecomeFirstResponder`, `allowsCellularAccess`. Never `empty`, `getValid()`.
- **No abbreviations** except universal terms of art (`URL`, `ID`, `min`): `background`, not `bg`; `index`, not `idx`. Acronyms uniformly cased: `userID`, `urlSession`.
- Methods that describe side effects use verbs (`print(x)`, `x.sort()`); those returning values without side effects use nouns (`x.count`, `x.successor()`).

```swift
// ❌ reads like a Java port; labels carry no information
func fetchDataFromServer(urlString: String, completionHandlerBlock: (Data) -> Void)
employeesArray.removeObject(atIndexValue: idx)

// ✅ reads as prose at the call site
func data(from url: URL) async throws -> Data
employees.remove(at: idx)
```

## Library ergonomics

- **Progressive disclosure via defaults**: one entry point, defaulted parameters for the 90% case — `func request(_ url: URL, method: Method = .get, timeout: Duration = .seconds(30))`. Order defaulted params after required ones; put trailing-closure candidates last.
- **`@discardableResult`** only when the result is a convenience, not the point: chaining builders, `@discardableResult func addTask(...) -> Task`. Never on pure functions — an ignored pure result is always a bug worth the warning.
- **`callAsFunction`** when the type *is* conceptually a function with configuration (parsers, predicates, style resolvers): `let matcher = Regexish("a+b"); matcher(input)`. Skip it if a named method is clearer.
- **`@dynamicMemberLookup`** sparingly: key-path-based overload for typed wrapper/proxy types (`Binding`, lenses) is good; string-based lookup erases compile-time checking — reserve for bridging dynamic data (JSON, Python interop).
- **`ExpressibleBy*Literal`** for config/value types so call sites stay flat: `ExpressibleByStringLiteral` for identifiers/paths, `ExpressibleByArrayLiteral` for option collections. Don't adopt on types where a literal hides an expensive or failable conversion.
- **Static-member lookup for "instances"** (the `.automatic` style): expose common configurations as `static let`/`static func` on the type (or on a protocol via extensions, 5.5+ generics lookup) so users write `.padding(.compact)`:
  ```swift
  struct Spacing { let value: Double
      static let compact = Spacing(value: 4)
      static let regular = Spacing(value: 8) }
  func padding(_ s: Spacing) -> Self
  ```

## Access control discipline

- Default is `internal`; declare `public` only what you commit to support — every `public` symbol is a semver contract.
- `public` vs `open` (classes/members): `public` = usable, not subclassable/overridable outside the module; `open` = subclassable contract. Default to `public`; `open` promises your class's invariants survive arbitrary overrides.
- **`package`** (5.9+, SE-0386): visible across targets of the same SPM package but not to clients — use for internal shared utilities instead of leaking `public` symbols out of multi-target packages.
- **`@inlinable` / `@usableFromInline`**: exposes the *body* to clients for cross-module optimization — the implementation becomes ABI you can't change for old, already-compiled clients. Use only on small, stable, performance-proven functions in binary frameworks; pointless churn risk elsewhere. `@usableFromInline` marks internal helpers reachable from inlinable bodies.
- **`@_spi(GroupName) public`**: underscore = unofficial, no source stability promised. Fine to consume knowingly (e.g., `@_spi(Testing)`), never in code that must survive toolchain/library updates. Same for all `@_` attributes and `_underscored` stdlib API.

## Availability & evolution

- Annotate platform-gated API: `@available(iOS 18, macOS 15, *)`; check at use sites with `if #available(...)`. The trailing `*` is mandatory for future platforms.
- Deprecate with direction, not just a warning:
  ```swift
  @available(*, deprecated, renamed: "connect(to:)", message: "Use connect(to:), which reports errors")
  public func open(_ host: String)
  ```
  `renamed:` powers Xcode's fix-it — always supply it when a successor exists. `unavailable` + `renamed:` gives a hard error with migration.
- **anyAppleOS** shorthand (6.4 beta): `@available(anyAppleOS 27, *)` expands to all five Apple platforms; layer exclusions with a second `@available(tvOS, unavailable)`. Do not use in code that must build with 6.3 toolchains.
- **Semver for packages**: additive API = minor; removing/renaming/narrowing `public` API, adding protocol requirements without defaults, adding enum cases to non-frozen public enums that clients switch exhaustively = major. Tag pre-1.0 honestly (`0.x` = anything goes).
- **Library evolution mode** (`-enable-library-evolution`, SPM: `swiftSettings: [.unsafeFlags…]` or xcframework builds): only for **binary-distributed** frameworks needing ABI stability. It makes structs/enums resilient (clients access via opaque layout) — do not enable for source-distributed packages; it costs performance and buys nothing.
- **`@frozen`** (evolution mode): promises no stored-property/case changes ever, restoring direct layout access. It trades all future flexibility for client performance — freeze only true value types (`Point`, currency codes).

## Error architecture

Four strategies — pick per failure, not per project:

| Strategy | Use when |
|---|---|
| `throws` | Recoverable failures the caller must consider; carries *why* |
| `Result<T, E>` | Failure is a **value** to store, pass across non-throwing boundaries (completion handlers), or aggregate; otherwise prefer `throws` |
| `Optional` return | Single obvious failure mode, cause uninteresting: `Int("abc")`, `first(where:)` |
| Trap (`fatalError`, `precondition`, `!`) | Programmer error / broken invariant; failure is a bug, not an input |

- **Enum errors** for closed domains you own end-to-end; adding a case is source-breaking for exhaustive switchers — that's a feature internally, a liability publicly.
- **Struct-with-code errors** for extensible public surfaces (the pattern of `POSIXError`/`URLError` and modern libraries):
  ```swift
  public struct NetworkError: Error {
      public struct Code: Hashable, Sendable { let raw: Int
          public static let timeout = Code(raw: 1)
          public static let unreachable = Code(raw: 2) }
      public let code: Code
      public let underlying: (any Error)?   // preserve the cause
  }
  ```
  New codes are additive, non-breaking, and you can attach context fields.
- **Wrap underlying errors**: keep the original in an `underlying`/associated value so debugging retains the root cause while your API exposes a stable vocabulary.
- **`LocalizedError`** only for errors actually shown to users — implement `errorDescription` (and optionally `recoverySuggestion`); plain `Error`'s `localizedDescription` is useless ("The operation couldn't be completed"). Internal errors need `CustomStringConvertible` for logs, not localization.

## Typed throws (6.0+)

`throws(SpecificError)` (SE-0413). The compiler enforces the error type; `catch` is exhaustive without a `catch { }` fallback.

```swift
enum ParseError: Error { case unexpectedEOF, badToken(at: Int) }

func parse(_ s: String) throws(ParseError) -> AST { ... }

do { let ast = try parse(source) }
catch .unexpectedEOF { ... }          // error is known to be ParseError
catch .badToken(let i) { ... }        // exhaustive — no generic fallback needed
```

Use when:
- **Closed domain** you fully control, where callers benefit from exhaustive `catch` (parsers, decoders, state machines).
- **Generic error propagation** — the modern replacement for `rethrows`: `func map<T, E>(_ f: (Element) throws(E) -> T) throws(E) -> [T]` propagates exactly the caller's error type, and `throws(Never)` composition makes the call non-throwing.
- **Embedded / no-allocation** contexts: a concrete error type avoids the existential box of `any Error`.

Avoid when:
- **Public app/library-level APIs that will grow failure modes** — adding a case to the error enum breaks exhaustive catchers; `throws` (i.e., `throws(any Error)`) keeps evolution room. Rule of thumb: typed throws at leaves and generic plumbing, untyped at broad module boundaries.
- You'd wrap everything in one `case underlying(any Error)` anyway — that's untyped throws with extra steps.

`Never` as the error type means "cannot throw": `throws(Never)` == non-throwing, which is what lets one generic implementation serve throwing and non-throwing callers.

## Error anti-patterns

- **`try?` swallowing**: `try? save()` silently discards *why* (and *that*) it failed. Legitimate only when the failure is truly equivalent to `nil`/no-op (best-effort cache warm). Otherwise catch and at minimum log:
  ```swift
  // ❌ let _ = try? store.save(user)
  // ✅
  do { try store.save(user) }
  catch { logger.error("save failed: \(error)"); throw PersistenceError(.saveFailed, underlying: error) }
  ```
- **Bare rethrow across module boundaries**: letting a `SQLiteError` escape your `ProfileStore` couples every caller to your storage choice and loses operation context. Wrap with what-you-were-doing + the underlying error (see struct pattern above). Within a module, plain propagation (`try`) is fine — wrap at the boundary, not at every level (over-wrapping creates onion errors that bury the cause).
- Don't use errors for control flow the caller always handles the same way; return an enum result instead.

## Documentation

All `public` API requires `///` doc comments — undocumented public API is unfinished API. Internal API: document the non-obvious.

```swift
/// Returns the user's profile, fetching from the network if the cache is stale.
///
/// - Parameters:
///   - id: The unique identifier of the user.
///   - policy: How stale a cached profile may be. Defaults to `.fiveMinutes`.
/// - Returns: The resolved ``Profile``.
/// - Throws: ``ProfileError/notFound`` if no user exists for `id`;
///   ``ProfileError/network(_:)`` for transport failures.
func profile(for id: User.ID, policy: CachePolicy = .fiveMinutes) async throws -> Profile
```

- First line: one-sentence abstract, third-person singular verb ("Returns…", "Creates…"). Blank `///` line before discussion.
- Use `- Parameters:`/`- Parameter x:`, `- Returns:`, `- Throws:`, plus `- Note:`, `- Important:`, `- Complexity:` where relevant.
- **DocC**: double backticks make symbol links (``Profile``), single backticks are code voice (`nil`); organize with articles and extension files in `Sources/<Target>/<Target>.docc/`; `@Comment { … }` for notes invisible in rendered docs. Build with `swift package generate-documentation` (swift-docc-plugin) or Xcode ▸ Product ▸ Build Documentation.
- Document *behavior and contract* (thread-safety/actor isolation, complexity, units, nullability semantics), not the implementation; a comment that restates the signature is noise.
