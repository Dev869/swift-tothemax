# Code Review: SettingsManager

Reviewed against modern Swift 6.x practice. Corrected version in `fixed.swift`
(verified with `swiftc -typecheck -swift-version 6`, Swift 6.3.3).

## Crash bugs (force unwraps / force try)

1. **`update(name: String?, age: Int?)` force-unwraps its own optional parameters**
   (`name!`, `age!`). The signature promises nil is acceptable; the body crashes on
   nil. Contradictory API. **Fix:** take non-optional `name: String, age: Int` —
   the caller resolves optionality, the type system documents the requirement.

2. **`try! JSONSerialization.data(...)`** crashes if encoding ever fails. **Fix:**
   `update` is now `throws` and propagates encoding/storage errors to the caller.

3. **`getAge()` force-unwrap cascade** — `(dict!)!["age"]!` plus `Int(...)!`. Any
   missing key, corrupt payload, or non-numeric string crashes. It also stacks a
   double optional (`try?` + `as?` produces `[String: String]??`), hence the ugly
   `(dict!)!`. **Fix:** typed `Codable` decode with `guard`/`throws`; zero `!`.

## Error-handling design

4. **`-1` sentinel return value** in `getAge()` — an in-band magic number callers
   must remember to check (and `-1` is a plausible-looking `Int`). **Fix:**
   `func age() throws -> Int?` — `nil` means "never saved", a thrown decoding
   error means "data exists but is corrupt". The two failure modes are now
   distinguishable instead of both collapsing to `-1` or a crash.

5. **`try?` swallowing the decode error** — the original discarded *why* (and
   *that*) deserialization failed, then immediately force-unwrapped the result
   anyway (worst of both worlds). **Fix:** propagate the error.

6. **`Storage.save` could not report failure** — persistence that fails silently.
   **Fix:** `save(_:forKey:) throws`.

## Concurrency (Swift 6 data-race safety)

7. **`DispatchQueue.main.async` is legacy** in new code and defeats compiler
   isolation checking. The hop to main reveals the intent: `onChange` is a
   UI-facing callback. **Fix:** make `SettingsManager` `@MainActor`; the callback
   is invoked directly, and the compiler now *proves* main-actor delivery.

8. **Cargo-cult `[weak self]` + `guard let self`** for a closure that fires
   almost immediately and isn't retained long-term — no retain cycle existed
   (the closure wasn't stored on `self`). It could also silently drop the change
   notification if the manager deallocated between save and dispatch. Gone
   entirely in the fix.

9. **Not data-race safe** — a non-final class with mutable `var storage` and
   `var onChange`, touched from an escaping closure, is not `Sendable` and would
   draw diagnostics once shared across isolation domains in Swift 6 mode.
   **Fix:** `@MainActor final class` with `let storage`.

## Type and data modeling

10. **Stringly-typed `[String: String]` via `JSONSerialization`** — `age` is
    round-tripped through `String(a)` / `Int(...)!`, so type information is
    thrown away and re-parsed on read. **Fix:** a `Codable` `Settings` struct
    with `JSONEncoder`/`JSONDecoder`; `age` stays `Int` end to end.

11. **`var storage: any Storage`** — a mutable existential where neither
    mutability nor heterogeneity is needed. Existentials cost boxing and dynamic
    dispatch. **Fix:** generic `SettingsManager<Store: Storage>` with
    `private let storage` ("some/generics before any"); also encapsulated
    (`private`) instead of publicly reassignable.

12. **Magic string `"settings"` duplicated** in two methods — drift risk.
    **Fix:** single `private let settingsKey`.

## API design (Swift API Design Guidelines)

13. **`save(_:key:)` / `load(key:)`** don't read as prose at the call site.
    **Fix:** `save(data, forKey: ...)` / `load(forKey: ...)`, matching the
    conventional preposition-in-label style (`Foundation`'s `object(forKey:)`).

14. **`getAge()`** — Swift avoids `get` prefixes; a side-effect-free value
    accessor should read as a noun. **Fix:** `age()` (kept as a throwing method
    since computed properties can't throw).

15. **No documentation** on what was effectively public API surface. **Fix:**
    `///` doc comments including the throws contract and isolation behavior.
