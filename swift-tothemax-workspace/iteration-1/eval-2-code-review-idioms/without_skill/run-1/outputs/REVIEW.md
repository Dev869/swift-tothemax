# Code Review: SettingsManager

## Issues Found

### Crash hazards (force unwraps / force try)

1. **Force-unwrapping optional parameters in `update(name:age:)`** — `let n = name!` and
   `let a = age!` crash whenever a caller passes `nil` for either argument. The signature
   advertises that `nil` is acceptable, but the implementation makes it a runtime trap.
   **Fix:** treat the optionals as a partial update — only apply the values that are non-nil.

2. **`try!` on `JSONSerialization.data(withJSONObject:)`** — any serialization failure
   crashes the app. **Fix:** use `do/catch` (and `JSONEncoder`, see #5).

3. **Force-unwrap pile-up in `getAge()`** — `return Int((dict!)!["age"]!)!` has four
   force unwraps. `try? ... as? [String: String]` produces a *double optional*
   (`[String: String]??`), hence the bizarre `(dict!)!`. Any of these crash the app if the
   stored data is missing, malformed, of a different shape, or if `"age"` isn't a valid
   integer string. **Fix:** decode safely with `guard`/optional chaining and return `nil`
   on failure.

### API and design issues

4. **`-1` sentinel return value in `getAge()`** — magic sentinel values are un-Swifty and
   error-prone (callers must remember to check for `-1`, and `-1` could collide with real
   data). **Fix:** return `Int?` so "no value" is expressed in the type system.

5. **Stringly-typed JSON via `JSONSerialization`** — `age` is converted to a `String`
   (`String(a)`) just to fit a `[String: String]` dictionary, then parsed back with
   `Int(...)!`. **Fix:** use a `Codable` struct (`Settings`) with `JSONEncoder`/`JSONDecoder`,
   which keeps `age` an `Int`, eliminates key typos, and removes the double-optional mess.

6. **Destructive "update" semantics** — even if the force unwraps were fixed, `update`
   rewrites the entire settings blob from only the passed arguments, silently discarding
   any previously stored fields. A method taking optionals implies partial update.
   **Fix:** load existing settings, merge the non-nil values, then save.

7. **Hard-coded `"settings"` key duplicated in two methods** — a typo in one place would
   silently break the round-trip. **Fix:** single `private static let settingsKey` constant.

### Minor / stylistic

8. **`var storage` should be `let`** — the storage dependency is never reassigned;
   `let` (and `private`) better communicates intent and prevents accidental mutation.

9. **`class` should be `final`** — nothing is designed for subclassing; `final` documents
   that and enables devirtualization.

10. **Verbose weak-self dance** — `guard let self = self else { return }` just to call an
    optional closure can be `self?.onChange?()`. (The `[weak self]` capture itself is fine.)

11. **No error signal on the save path** — `Storage.save` can't report failure and `update`
    had no failure path other than crashing. The fix at minimum avoids the crash
    (`do/catch` + `assertionFailure` in debug); a fuller redesign could make
    `save`/`update` throwing.

## Summary of Changes in `fixed.swift`

- Introduced `struct Settings: Codable` and switched to `JSONEncoder`/`JSONDecoder`.
- `update(name:age:)` merges non-nil values into existing settings; no force unwraps.
- Replaced `try!` with `do/catch`.
- `getAge()` (and a symmetric `getName()`) return optionals instead of sentinels.
- Extracted a private `loadSettings()` helper and a `settingsKey` constant.
- `final class`, `private let storage`, simplified closure to `self?.onChange?()`.
