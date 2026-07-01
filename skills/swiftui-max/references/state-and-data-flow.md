# State & Data Flow

Concurrency questions inside these patterns (MainActor isolation, Sendable models) → sibling skill **swift-language**.

## Observation: how it actually works (iOS 17+)

`@Observable` expands your class so every stored property read is *tracked*. When `body` runs, SwiftUI records exactly which properties it touched; only writes to those properties invalidate that view. This is the whole performance argument: `ObservableObject` invalidates every subscriber on any `@Published` write, `@Observable` invalidates per property, per view.

```swift
@Observable
final class Library {
    var books: [Book] = []
    var searchText = ""
    @ObservationIgnored var analytics = AnalyticsClient()  // opt out of tracking
}

struct LibraryView: View {
    @State private var library = Library()     // view OWNS it → @State
    var body: some View {
        BookList(books: library.books)          // updates only when .books changes
    }
}
```

Rules that follow from the tracking model:

- Tracking only covers properties read **during body** (and other tracked scopes). Reads inside an escaped closure or a background task aren't view-tracked.
- Computed properties are tracked through the stored properties they read. Fine to expose.
- Collections: replacing `books` invalidates; mutating a *reference-type element's* property invalidates only views that read that element (nest `@Observable` models for fine-grained rows).
- Outside SwiftUI, observe with `withObservationTracking` (one-shot) or the `Observations` async sequence (Swift 6.2+) — don't bolt Combine back on.

### Wrong vs right: ownership

```swift
// WRONG — child re-creates the model on every parent identity change,
// and @ObservedObject-style sharing is dead API for @Observable.
struct DetailView: View {
    @State private var model: DetailModel
    init(book: Book) { _model = State(initialValue: DetailModel(book: book)) } // smell if parent passes a model
}

// RIGHT — owner uses @State; everyone else takes the reference plainly.
struct DetailView: View {
    let model: DetailModel          // non-owner: just `let` — tracking still works
    var body: some View { Text(model.book.title) }
}

// Need bindings into someone else's @Observable? @Bindable, at point of use:
struct EditSheet: View {
    @Bindable var model: DetailModel
    var body: some View { TextField("Title", text: $model.book.title) }
}
```

iOS 27 beta: `@State` is now a macro and **classes in `@State` initialize lazily, once per view lifetime** — the classic "my model re-inits every parent update" hazard is gone on the 27 SDKs. Source-breaking edge: if you assign the state in `init`, remove the declaration's default value (`@State private var page: StickerPage`, then `self.page = StickerPage(title:)` — not both).

## Property-wrapper decision table

| You need | Use | Notes |
|---|---|---|
| Local, view-owned value or model | `@State private var` | Always `private`. Structs by default; `@Observable` class when shared downward |
| Read+write access to state owned elsewhere | `@Binding` | Pass `$value`. Don't bind when a `let` + callback is honest |
| Read-only data from parent | plain `let` | Most common; people over-wrap |
| Bindings into a passed-in `@Observable` | `@Bindable` | Can be created inline: `@Bindable var m = model` inside body |
| App-wide/subtree-wide dependency | `@Environment` | See DI below |
| System values (colorScheme, dismiss, locale…) | `@Environment(\.keyPath)` | |
| Tiny user prefs | `@AppStorage` / `@SceneStorage` | Not a database; primitives only |
| Legacy (< iOS 17) | `@StateObject`/`@ObservedObject`/`@EnvironmentObject` | Migration table in SKILL.md |

`@State` initial-value trap (pre-27 SDKs): `@State var x = expensive()` runs `expensive()` on *every* init of the struct and discards it after the first. Pre-27 fix: wrap in `@Observable` model created in `.task`, or accept it. On iOS 27 beta the macro makes it lazy automatically.

## Environment as dependency injection

```swift
extension EnvironmentValues {
    @Entry var router = Router()                 // iOS 18+: one line, default value required
}

@main struct ShopApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)              // by type: @Environment(Store.self)
                .environment(\.router, Router()) // by key
        }
    }
}

struct CheckoutView: View {
    @Environment(Store.self) private var store
    @Environment(\.router) private var router
    var body: some View {
        // Bindings from environment objects need a local @Bindable:
        @Bindable var store = store
        TextField("Promo", text: $store.promoCode)
    }
}
```

- `@Environment(Store.self)` **crashes if never injected**; use `@Environment(Store.self) private var store: Store?` for optional dependencies.
- Inject at the highest node that all readers share, not reflexively at the app root.
- Testability without ceremony: environment values *are* your seams. For previews/tests, inject a different instance; protocols only when you genuinely have multiple production implementations.
- Previews: `#Preview { CheckoutView().environment(Store.mock) }`; use `@Previewable @State` when a preview needs live state:

```swift
#Preview {
    @Previewable @State var text = ""
    TextField("Name", text: $text)
}
```

### Wrong vs right: god-object passing

```swift
// WRONG — leaf depends on the world; any Store change risks invalidation & kills reuse.
PriceLabel(store: store)

// RIGHT — pass the datum.
PriceLabel(amount: store.cart.total)
```

## Data flow patterns that scale

- **Navigation is state**: `@State private var path: [Route] = []` + `navigationDestination(for: Route.self)`. Deep links mutate the array; done.
- **Side effects**: `.task(id: query)` for load-on-change with auto-cancellation; `.onChange(of:) { old, new in }` for synchronous reactions only.
- **Derived state**: compute in body or the model — don't mirror one `@State` into another and sync with `onChange` (classic double-source-of-truth bug).
- **Sheets/alerts**: model as optional item state. `sheet(item: $selectedBook)`; on iOS 27 beta `alert`/`confirmationDialog` accept the same `item:` binding — prefer over boolean flags.

## SwiftData in views (brief)

SwiftData is the persistence layer that speaks Observation natively — `@Model` classes are observable, so rows update in place.

```swift
@main struct TripsApp: App {
    var body: some Scene {
        WindowGroup { TripList() }.modelContainer(for: Trip.self)
    }
}

struct TripList: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var context
    var body: some View {
        List(trips) { trip in TripRow(trip: trip) }
            .toolbar { Button("Add") { context.insert(Trip(name: "New")) } }
    }
}
```

- `@Query` lives in views; keep predicates in one place with `#Predicate` builders or static query helpers on the model — don't scatter stringly filters.
- Write through `modelContext`; autosave is on by default in the main container.
- iOS 18+: `#Index`, `#Unique`, history API; class inheritance for models arrived with the 26 SDKs.
- Deep modeling questions (schema migration, custom stores, CloudKit) are beyond this file — keep the view layer thin over it.

## ObservableObject → Observable migration checklist

1. `class Foo: ObservableObject` → `@Observable class Foo`; delete every `@Published`.
2. `@StateObject var m = Foo()` → `@State private var m = Foo()`.
3. `@ObservedObject var m: Foo` → `let m: Foo` (or `@Bindable var m: Foo` if you use `$m...`).
4. `@EnvironmentObject` → `@Environment(Foo.self)`; `.environmentObject(m)` → `.environment(m)`.
5. Manual `objectWillChange` sends → delete; if something depended on coarse invalidation, it was a bug wearing a feature costume.
6. Combine pipelines observing `@Published` → `Observations` sequence / `withObservationTracking`, or async streams from the model.
7. Sweep for `onReceive(model.objectWillChange)` — replace with tracked reads or `.onChange`.
