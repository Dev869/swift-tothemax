# Performance & Debugging

Order of operations: **reproduce → measure → name the guilty view → fix → re-measure**. Never "optimize" SwiftUI by rewriting blind; the tools point at the exact body.

## Tooling ladder

### 1. `Self._printChanges()` — 30-second triage

```swift
var body: some View {
    let _ = Self._printChanges()   // debug builds only; prints WHY this body ran
    ...
}
```

Output decoder:
- `@self` — the view's stored properties changed (parent passed new values).
- `@identity` — the view's *identity* changed: it was destroyed and recreated. Red flag — look for `if/else` swaps, changing `.id()`, or unstable `ForEach` ids.
- `_someState` — that state/environment dependency changed.
- `unchanged` spam from a parent → parent re-inits children needlessly (big struct diffing or closure churn).

`Self._logChanges()` sends the same to unified logging (`com.apple.SwiftUI`, category `Changed Body Properties`) for on-device runs.

### 2. Instruments 26 — SwiftUI template (the real tool)

Profile (⌘I) → SwiftUI template. Lanes to read, in order:

1. **Update Groups** — how long each SwiftUI update transaction took.
2. **Long View Body Updates** — bodies exceeding budget, highlighted orange/red. This lane is your work queue: each entry names the view type.
3. **Cause & Effect graph** (26) — select an update and walk *what wrote which attribute → which bodies re-ran*. Answers "why did this update happen" definitively.
4. Pair with **Hangs** and **Hitches** instruments: main-thread stalls > 250 ms are hangs (unresponsive), dropped frames during scroll are hitches. A long body during scroll = hitch; during a tap = hang.

Rules of thumb: any single body > ~1 ms on the hot path deserves a look; anything doing I/O, formatting, sorting, or image decoding in body is a bug, full stop.

### 3. When it's not SwiftUI

Time Profiler shows heavy stacks under your model code, decoding, or Core Data/SwiftData fetches → fix the data layer (background work, caching), not the view. Route concurrency restructuring to **swift-language**.

## Identity: the root of 80% of weird bugs

SwiftUI tracks views by (type, position in hierarchy, explicit id). Identity change ⇒ state reset (`@State` wiped), transition fired, animation broken.

```swift
// WRONG — two IDENTITIES: toggling swaps views, resets internal state, breaks animation.
if isFavorite { StarButton(filled: true) } else { StarButton(filled: false) }

// RIGHT — one identity, animated property change.
StarButton(filled: isFavorite)

// WRONG — index-based ids: reorder/delete makes SwiftUI update the WRONG rows.
ForEach(Array(items.enumerated()), id: \.offset) { _, item in Row(item) }

// RIGHT — stable domain identity.
ForEach(items) { Row($0) }        // items: Identifiable, id survives edits

// WRONG — id() tied to churning value: full teardown every keystroke.
ChartView(data: data).id(searchText)

// RIGHT — use id() only to deliberately reset (e.g. restart animation), keyed on a rare event.
```

`AnyView` erases type identity: SwiftUI can't structurally diff, so it tears down and rebuilds on change. In branches, `@ViewBuilder` already unifies types via `_ConditionalContent` — you almost never need AnyView.

## View body purity & cheapness

- Bodies run *often*. Budget accordingly: no allocation of formatters/scanners/models, no `.sorted()`/`.filter()` over large arrays, no synchronous image decode, no date math in loops.
- Move computation to the `@Observable` model (compute on write, not on read), or cache: `static let formatter` / `Date.FormatStyle` values are cheap to reuse.
- Extract subviews aggressively. A child view whose inputs didn't change **doesn't re-run its body** — extraction is an invalidation firewall, not just tidiness:

```swift
// WRONG — one mega-body: any of 6 state vars re-renders everything, including the expensive chart.
var body: some View { VStack { header; ExpensiveChart(model: model); footer } }

// RIGHT — chart takes only what it reads; header state churn no longer touches it.
ChartSection(points: model.points)
```

- Closures passed to children: capturing fresh closures is fine (they're not diffed as inequality), but capturing *whole models* to read one property forces coarse dependencies — pass the property.

## Equatable views

For hot subtrees with many inputs, conform the view to `Equatable`; SwiftUI then skips body when `==` says nothing changed (compare only what body reads):

```swift
struct WaveformView: View, Equatable {
    let samples: [Float]
    let color: Color
    static func == (a: Self, b: Self) -> Bool {
        a.color == b.color && a.samples.count == b.samples.count && a.samples.last == b.samples.last
    }
    var body: some View { /* expensive drawing */ }
}
```

Prefer restructuring (smaller inputs) first; `Equatable` is the tool when inputs are inherently bulky. Never lie in `==` — stale UI is worse than slow UI.

## Lazy containers

- `List`, `LazyVStack`, `LazyVGrid` build views on demand — mandatory for unbounded data. But they **retain** created views for the session; a 10k-row scroll accumulates 10k live rows. Keep rows tiny; push images through downsampled thumbnails, not full-size `UIImage(data:)`.
- Don't wrap a lazy stack in another lazy stack or give it `fixedSize()`/unbounded height — you silently make it eager (everything builds at once). Same for `ScrollView { VStack }` with thousands of children: that's eager by definition.
- Row `id` stability matters double here: unstable ids defeat reuse *and* cause scroll jumps.
- `drawingGroup()` flattens complex static vector subtrees into one Metal layer — good for graphs/badges, wrong for text-heavy or frequently-diffed content.

## Async work & state churn

- `.task(id:)` over `onChange` + `Task {}`: previous task auto-cancels when id changes or view disappears. Debounce searches with `try await Task.sleep(for: .milliseconds(250))` at the top, then check `Task.isCancelled`.
- Batch model writes: five property writes in one MainActor turn coalesce into one update — but writing state at 120 Hz from a gesture should go through `visualEffect`/`GeometryEffect` paths or transaction-scoped changes instead of invalidating body per frame.
- Timers/`AsyncSequence` feeding state: isolate to the leaf view that displays them (a ticking clock in the root re-renders the app).
- **(27β)** `AsyncImage` now HTTP-caches by default — delete bespoke caching layers after verifying server headers; custom `URLCache` via `asyncImageURLSession(_:)`.

## Hitch-fixing checklist (scroll jank)

1. Instruments: confirm hitches lane + find long bodies during scroll.
2. Row bodies: kill formatters/sorting/decoding (move to model, precompute).
3. Check ids: stable? `ForEach` over Identifiable?
4. Kill per-row `GeometryReader`; replace with `scrollTransition`/`visualEffect`/`onGeometryChange`.
5. Images: downsample to display size off-main; `AsyncImage` or a thumbnail pipeline.
6. Shadows/blurs on every row are GPU tax — flatten with `drawingGroup()` or simplify.
7. Re-measure. If Update Groups are now short but hitches persist → Core Animation / image decode lanes, not SwiftUI.

## Quick reference: smells → fixes

| Smell | Fix |
|---|---|
| `@identity` in `_printChanges` | Unify branches into one view with parameters |
| Whole screen re-renders on keystroke | Extract; pass `searchText` only to the field + results |
| `@State` resets "randomly" | Parent identity churn (`if/else`, `.id()`, ForEach id) |
| Slow first render of long screen | Eager container — switch to Lazy / List |
| Animation stutters on toggle | Transition on identity change you didn't intend |
| CPU burn while idle | Timer/task writing state nobody displays; `TimelineView` misuse |
| Body allocating models | Move to `@State`/model; (27β) `@State` macro makes class init lazy |
