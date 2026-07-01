# Component Recipes

Canonical, compilable implementations of the components agents most often rebuild badly — copy the recipe, don't reinvent. Version tags: untagged = iOS 16 floor; (17)/(18) = iOS 17/18; (26) = iOS 26; **(27β)** = WWDC26 beta.

1. [Bottom sheet](#1-bottom-sheet) · 2. [Custom tab bar](#2-custom-tab-bar-and-when-not-to) · 3. [Stretchy header](#3-parallax--stretchy-header) · 4. [Infinite scroll](#4-infinite-scroll--pagination) · 5. [Skeleton/shimmer](#5-skeleton--shimmer-loading) · 6. [Search + debounce](#6-searchable-list-with-debounce) · 7. [Form validation](#7-form-with-inline-validation) · 8. [Async image grid](#8-async-image-grid) · 9. [Onboarding carousel](#9-onboarding-carousel) · 10. [Charts](#10-swift-charts-quickstart) · 11. [Toast overlay](#11-toast--snackbar-overlay) · 12. [List state machine](#12-list-state-machine--pull-to-refresh) · [Decision table](#component-decision-table)

## 1. Bottom sheet
**Why this way**: `presentationDetents` gives the system's gesture physics, resize animation, accessibility, and (26) Liquid Glass for free — hand-rolled drag-offset sheets get all of those wrong.
```swift
struct MapScreen: View {
    @State private var detent: PresentationDetent = .height(96)
    var body: some View {
        MapContent().sheet(isPresented: .constant(true)) {   // persistent, Maps-style panel
            ResultsList()
                .presentationDetents([.height(96), .medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)   // affordance that it resizes
                .presentationBackgroundInteraction(.enabled(upThrough: .medium)) // map stays live
                .interactiveDismissDisabled()                // chrome, not a modal
        }
    }
}
struct CompactBar: CustomPresentationDetent {                // when fixed/fraction won't do
    static func height(in context: Context) -> CGFloat? { max(64, context.maxDetentValue * 0.12) }
}
// .presentationDetents([.custom(CompactBar.self), .medium, .large], selection: $detent)
```
- The `selection` value **must** be a member of the detents set or the sheet jumps; keep the set stable while presented; a sheet presented *from* a sheet needs its own detents.
- Don't set `presentationBackground` on 26+ (sheets get glass + concentric corners automatically), and never rebuild this with `offset` + `DragGesture` — a truly custom inline panel is a bottom-aligned overlay, not a fake sheet.

## 2. Custom tab bar (and when not to)
**Why this way**: keep native `TabView` for content (state preservation, scroll-to-top, iPad sidebar adaptivity, a11y) and replace only the *bar*; a single `matchedGeometryEffect` capsule gives the sliding indicator.
```swift
// DEFAULT — stay native (18+/26); custom bars forfeit all of this:
TabView(selection: $selection) {
    Tab("Home", systemImage: "house", value: AppTab.home) { HomeView() }
    Tab(value: AppTab.search, role: .search) { SearchView() }   // system search tab treatment
}
.tabBarMinimizeBehavior(.onScrollDown)         // (26)
.tabViewBottomAccessory { MiniPlayerView() }   // (26) Music-style bar; inside it, read
// @Environment(\.tabViewBottomAccessoryPlacement): .inline (bar minimized) / .expanded

// ONLY if the brand demands it (AppTab: String enum of SF symbols, CaseIterable + Identifiable):
struct CustomTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button { withAnimation(.snappy(duration: 0.25)) { selection = tab } } label: {
                    Image(systemName: tab.rawValue)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(selection == tab ? .primary : .secondary)
                        .background {
                            if selection == tab {    // exactly one live copy of the id, or it glitches
                                Capsule().fill(.tint.opacity(0.15)).matchedGeometryEffect(id: "indicator", in: ns)
                            }
                        }
                }
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(6).background(.bar, in: .capsule)   // 26+: .glassEffect(.regular, in: .capsule)
    }
}
// Host: TabView(selection:) { … }.toolbar(.hidden, for: .tabBar)          ← keeps per-tab state
//           .overlay(alignment: .bottom) { CustomTabBar(selection: $selection).padding() }
```
- Don't switch content with `switch selection` in a ZStack — each switch destroys tab state; hide the system bar and keep `TabView` underneath. And say what a custom bar costs before building one: iPad sidebar adaptation, (26) minimize behavior, and the bottom accessory all go away.

## 3. Parallax / stretchy header
**Why this way**: `visualEffect` (17) reads scroll-relative geometry with no `GeometryReader` + preference-key plumbing, and can't cause layout loops because it only applies render effects.
```swift
ScrollView {
    VStack(spacing: 0) {
        Image(.hero)
            .resizable().scaledToFill()
            .frame(height: 300).clipped()
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                return content
                    .scaleEffect(1 + max(0, minY) / 300, anchor: .bottom) // stretch on pull-down
                    .offset(y: minY < 0 ? -minY / 2 : 0)                  // parallax on scroll-up
            }
        ArticleBody().background(.background)   // opaque → parallaxing image slides *under* it
    }
}
.ignoresSafeArea(edges: .top)
```
- `visualEffect` can't change layout — the stretch is a scale (`anchor: .bottom` fills the pulled gap), which is exactly why it's cheap and safe. No negative-padding `GeometryReader` hacks.
- Fade header text as it exits with `.scrollTransition(.interactive) { c, phase in c.opacity(phase.isIdentity ? 1 : 0) }` (17); (26) pair with `scrollEdgeEffectStyle(.soft, for: .top)` / `backgroundExtensionEffect()` under Liquid Glass bars.

## 4. Infinite scroll + pagination
**Why this way**: a sentinel row with `.task` fires exactly when pagination should (the row materializes near the viewport), auto-cancels on disappear, and avoids "onAppear on the last cell" bugs (missed triggers after fast scrolls, double fires on rebuild).
```swift
@Observable final class FeedStore {
    private(set) var items: [FeedItem] = []; private(set) var hasMore = true
    private var isLoading = false; private var page = 0
    func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true; defer { isLoading = false }
        do { let new = try await API.feed(page: page)
             items += new; page += 1; hasMore = !new.isEmpty }
        catch is CancellationError {}
        catch { /* keep hasMore true — sentinel retries when re-shown; toast the error */ }
    }
}
struct FeedList: View {
    @State private var store = FeedStore()
    var body: some View {
        List {
            ForEach(store.items) { FeedRow(item: $0) }
            if store.hasMore {
                ProgressView().frame(maxWidth: .infinity)
                    .task { await store.loadNextPage() }   // sentinel: fires when this row builds
            }
        }
        .task { await store.loadNextPage() }               // first page
    }
}
```
- The `isLoading` guard is load-bearing — the sentinel can be rebuilt several times per append. It lives *outside* the `ForEach`; never trigger from "is this the last item" inside rows.
- Stable `Identifiable` ids; if API pages can overlap, dedupe on append or diffing breaks. (18) `onScrollTargetVisibilityChange` enables eager prefetch; the sentinel is the portable default.

## 5. Skeleton / shimmer loading
**Why this way**: `redacted(reason: .placeholder)` turns your *real* layout into the skeleton — no parallel placeholder view to keep in sync; shimmer is one animated-gradient mask, no `GeometryReader`.
```swift
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false
    func body(content: Content) -> some View {
        content
            .mask {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: 0.5),
                                       .init(color: .black.opacity(0.35), location: 1)],
                               startPoint: animating ? .init(x: 1, y: 0.5) : .init(x: -1, y: 0.5),
                               endPoint:   animating ? .init(x: 2, y: 0.5) : .init(x: 0, y: 0.5))
            }
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: animating)
            .onAppear { if !reduceMotion { animating = true } }   // Reduce Motion → static redaction
    }
}
extension View {
    @ViewBuilder func skeleton(_ active: Bool) -> some View {
        if active { redacted(reason: .placeholder).modifier(Shimmer()).allowsHitTesting(false) }
        else { self }
    }
}
// The skeleton IS the real layout, fed sample data:
List(store.isLoading ? FeedItem.samples : store.items) { FeedRow(item: $0) }.skeleton(store.isLoading)
```
- `repeatForever` animations run as long as the view lives — the `if active` branch removes the modifier entirely when loading ends; `unredacted()` opts specific children (logos, headers) out.

## 6. Searchable list with debounce
**Why this way**: `.task(id: query)` cancels the previous task on every keystroke, so `Task.sleep` *is* the debounce — no Combine, no manual `Task` bookkeeping.
```swift
struct SearchScreen: View {
    @State private var query = ""; @State private var results: [Item] = []
    var body: some View {
        NavigationStack {
            List(results) { ItemRow(item: $0) }
                .overlay { if results.isEmpty && query.count >= 2 { ContentUnavailableView.search(text: query) } }
                .navigationTitle("Search")
                .searchable(text: $query, prompt: "Search items")
                .task(id: query) {                                   // cancelled on each keystroke
                    guard query.count >= 2 else { results = []; return }
                    try? await Task.sleep(for: .milliseconds(300))   // ← the debounce
                    guard !Task.isCancelled else { return }
                    do { results = try await API.search(query) }
                    catch is CancellationError {} catch let e as URLError where e.code == .cancelled {}
                    catch { /* real failure → error state / toast */ }
                }
        }
    }
}
```
- Attach `.searchable` to content *inside* `NavigationStack` or the field won't dock in the bar. With `.searchScopes($scope) { … }`, key the task on a `Hashable` query+scope pair.
- Both cancellation catches matter — a cancelled `URLSession` throws `URLError(.cancelled)`; treating it as failure flashes bogus error UI per keystroke. Check `Task.isCancelled` after *every* await.

## 7. Form with inline validation
**Why this way**: `@FocusState` drives both keyboard flow (`onSubmit` → next field) and validate-on-blur; errors live in state keyed by field, rendered inline where the user is looking.
```swift
struct SignupForm: View {
    enum Field: Hashable, CaseIterable { case email, password }
    @State private var email = "", password = ""
    @State private var errors: [Field: String] = [:]
    @FocusState private var focus: Field?
    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .focused($focus, equals: .email).keyboardType(.emailAddress)
                    .textContentType(.username).textInputAutocapitalization(.never).submitLabel(.next)
                errorText(for: .email)
                SecureField("Password", text: $password)
                    .focused($focus, equals: .password).textContentType(.newPassword).submitLabel(.go)
                errorText(for: .password)
            }
            Button("Create Account") { submit() }
        }
        .onSubmit { if focus == .email { focus = .password } else { submit() } }  // "next" advances
        .onChange(of: focus) { old, _ in if let old { validate(old) } }           // validate on blur
    }
    @ViewBuilder private func errorText(for field: Field) -> some View {
        if let message = errors[field] { Text(message).font(.footnote).foregroundStyle(.red) }
    }
    private func validate(_ field: Field) {
        switch field {
        case .email:    errors[.email] = email.contains("@") ? nil : "Enter a valid email."
        case .password: errors[.password] = password.count >= 8 ? nil : "At least 8 characters."
        }
    }
    private func submit() {
        Field.allCases.forEach(validate)
        if let bad = Field.allCases.first(where: { errors[$0] != nil }) { focus = bad }
        else { focus = nil /* run async signup; disable the button while in flight */ }
    }
}
```
- Validate on blur and submit — never on every keystroke (yelling at half-typed emails). Error rows changing height is fine in `Form`; don't reserve blank space. `textContentType` is not optional polish: it enables autofill and password managers.

## 8. Async image grid
**Why this way**: size cells with `Color.clear.aspectRatio` + `overlay` so the *grid* decides size and the image just fills — `AsyncImage` inside frame-guessing cells causes layout feedback.
```swift
LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
    ForEach(photos) { photo in
        Color.clear
            .aspectRatio(1, contentMode: .fit)      // square cell, grid-driven width
            .overlay {
                AsyncImage(url: photo.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").foregroundStyle(.tertiary)
                    default: Rectangle().fill(.quaternary)
                    }
                }
            }
            .clipped()                              // scaledToFill bleeds without it
            .contentShape(.rect)                    // tap target = the clipped cell
    }
}
```
- `AsyncImage` limits (pre-27): **no** memory-cache control, downsampling, or prefetching; requests cancelled by lazy-container scrolling re-download from scratch. **(27β)** adds URLCache-backed HTTP caching — fixes the re-download, not the decode cost.
- Cutover rule: one-off images (hero, avatar) → `AsyncImage`; scrolling feeds/grids → **Nuke** (NukeUI `LazyImage` + resize processor so you decode thumbnail pixels, not 12 MP originals; Kingfisher fine if already adopted). And request pre-sized thumbnail URLs — no client library fixes full-size images in a 100 pt cell.

## 9. Onboarding carousel
**Why this way**: `ScrollView` + `.scrollTargetBehavior(.paging)` (17) gives paging with a `scrollPosition` binding you can both read (dots) and write (buttons) — `TabView(.page)` can't be driven or styled as cleanly.
```swift
struct OnboardingCarousel: View {
    let pages: [OnboardingPage]                     // Identifiable
    @State private var current: OnboardingPage.ID?  // page = scroll position, one source of truth
    var body: some View {
        VStack(spacing: 24) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {            // spacing MUST be 0 with .paging, or pages drift
                    ForEach(pages) { page in
                        OnboardingPageView(page: page)
                            .containerRelativeFrame(.horizontal)   // exactly one page wide
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging).scrollPosition(id: $current).scrollIndicators(.hidden)
            HStack(spacing: 8) {                    // page dots: readable AND tappable
                ForEach(pages) { page in
                    Circle().fill(page.id == current ? Color.primary : .secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .onTapGesture { withAnimation { current = page.id } }
                }
            }
            // "Continue" button: withAnimation { current = next id }; on last page, finish onboarding
        }
        .onAppear { current = current ?? pages.first?.id }   // scrollPosition starts nil — seed it
    }
}
```
- Never infer the page from scroll-offset math; the `scrollPosition` id binding is the source of truth for dots and buttons alike. iOS 16 floor: `TabView(selection:).tabViewStyle(.page)` + `.indexViewStyle(.page(backgroundDisplayMode: .always))` — or the system dots vanish on light content.

## 10. Swift Charts quickstart
**Why this way**: `chartXSelection` (17) does all gesture recognition (tap/drag; hover on macOS) into a plain binding — never hand-roll `DragGesture` + `ChartProxy` for simple scrubbing.
```swift
import Charts
struct RevenueChart: View {
    struct Point: Identifiable { let id = UUID(); let day: Date; let value: Double }
    let points: [Point]; @State private var selectedDay: Date?
    private var selected: Point? {   // nearest data point to the (interpolated) selected Date
        guard let d = selectedDay else { return nil }
        return points.min { abs($0.day.timeIntervalSince(d)) < abs($1.day.timeIntervalSince(d)) }
    }
    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.day), y: .value("Revenue", p.value))
                    .foregroundStyle(.blue.opacity(0.2)).interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", p.day), y: .value("Revenue", p.value))
                    .interpolationMethod(.catmullRom)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.day)).foregroundStyle(.secondary)
                    .annotation(position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(selected.value, format: .currency(code: "USD"))
                            .font(.caption.bold()).padding(4).background(.regularMaterial, in: .rect(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: $selectedDay)   // (17) all gesture handling in one binding
        .frame(height: 220)
    }
}
```
- The selection binding's type must match the x value's plottable type exactly (`Date?` here) or nothing selects; range selection is just a `ClosedRange<Date>?` binding. `annotation`'s `overflowResolution` keeps the callout inside the plot — omit it and it clips at the edges.
- Multiple series: one `foregroundStyle(by: .value("Series", name))` — legend comes free. (18) `chartGesture` + `ChartProxy` only for genuinely custom gestures.

## 11. Toast / snackbar overlay
**Why this way**: one `@Observable` center in the environment + one overlay at the root — any view can announce, and a single presentation point means toasts never fight sheets or duplicate. No dependency for 30 lines.
```swift
struct Toast: Identifiable, Equatable { let id = UUID(); var message: String; var icon: String? }
@Observable final class ToastCenter {
    var current: Toast?
    func show(_ message: String, icon: String? = nil) {
        current = Toast(message: message, icon: icon)   // fresh id restarts the dismiss timer
    }
}
// At the TRUE root (above NavigationStack/TabView), with @State private var toasts = ToastCenter():
AppContent()
    .environment(toasts)
    .overlay(alignment: .bottom) {
        if let toast = toasts.current {
            Label(toast.message, systemImage: toast.icon ?? "info.circle")
                .font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)  // 26+: .glassEffect(in: .capsule)
                .padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {                        // new toast → timer restarts
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { toasts.current = nil }
                }
        }
    }
    .animation(.snappy, value: toasts.current)
// Any descendant: @Environment(ToastCenter.self) private var toasts … toasts.show("Saved")
```
- Toasts inside a tab's content disappear on tab switch and sit under bars — root overlay only. Announce for VoiceOver: `AccessibilityNotification.Announcement(toast.message).post()` (17). Toasts are passive confirmations only — failures needing action get an alert or inline error, not a "Retry" nobody hits in 2.5 s.

## 12. List state machine + pull-to-refresh
**Why this way**: one enum makes empty/error/loading mutually exclusive by construction — no `isLoading && !hasError && items.isEmpty` boolean soup — and refresh deliberately *keeps* stale content instead of flashing a spinner.
```swift
enum Loadable<Value> { case loading, loaded(Value), failed(String) }
@Observable final class ArticlesStore {
    private(set) var state: Loadable<[Article]> = .loading
    func load() async { state = .loading; await fetch() }   // initial + retry: full takeover
    func refresh() async { await fetch() }                  // pull-to-refresh: old content stays
    private func fetch() async {
        do { state = .loaded(try await API.articles()) }
        catch is CancellationError {}
        catch { if case .loaded = state {} else { state = .failed(error.localizedDescription) } }
    }
}
struct ArticlesScreen: View {
    @State private var store = ArticlesStore()
    var body: some View {
        Group {
            switch store.state {
            case .loading: ArticlesSkeleton()               // recipe 5
            case .loaded(let a) where a.isEmpty:            // empty IS a successful load
                ContentUnavailableView("No Articles", systemImage: "newspaper")
            case .loaded(let articles):
                List(articles) { ArticleRow(article: $0) }
                    .refreshable { await store.refresh() }  // await the REAL work directly
            case .failed(let message):
                ContentUnavailableView { Label("Couldn't Load", systemImage: "wifi.exclamationmark") }
                    description: { Text(message) }
                    actions: { Button("Retry") { Task { await store.load() } } }
            }
        }
        .task { await store.load() }
    }
}
```
- `refreshable` must directly `await` the work — an unawaited `Task { }` dismisses the spinner instantly (dodging that is where the classic capture crashes come from).
- Failed *refresh* over good content keeps the content (toast it); failed *load* takes over the screen. Encoding that split in `load()` vs `refresh()` is the whole pattern.

## Component decision table

| Component | Verdict | Notes |
|---|---|---|
| Bottom sheet | **Native** `presentationDetents` | Recipe 1 for persistent/Maps-style; never a drag-offset rebuild |
| Tab bar | **Native `TabView`** first | Recipe 2 only when brand demands; keep TabView underneath |
| Stretchy header | **Recipe 3** | `visualEffect`; no GeometryReader hacks, no library |
| Pagination | **Recipe 4** | Sentinel row + `.task`; no library needed |
| Skeleton/shimmer | **Recipe 5** | `redacted` is the skeleton; skip skeleton libraries |
| Search + debounce | **Recipe 6** | `searchable` + `task(id:)`; no Combine |
| Forms/validation | **Recipe 7** | Native `Form` + `@FocusState`; form-builder libs age badly |
| One-off images | **Native `AsyncImage`** | Fine for heroes/avatars; (27β) adds HTTP caching |
| Image feeds/grids | **Library: Nuke** (NukeUI `LazyImage`) | Kingfisher if already adopted; recipe 8 grid sizing either way |
| Carousel/paging | **Recipe 9** | `.scrollTargetBehavior(.paging)`; `TabView(.page)` as 16 fallback |
| Charts | **Native Swift Charts** | Recipe 10; DGCharts only for exotic financial charts |
| Toast/snackbar | **Recipe 11** | Own it — toast libraries lag OS releases and fight your architecture |
| List states + refresh | **Recipe 12** | One `Loadable` enum, `ContentUnavailableView`, `refreshable` |
| Celebration/juice effects | **Library: Pow** | Shakes, confetti, shine transitions — don't hand-animate these |
| Designer vector motion | **Library: lottie-ios** | Only for handed .lottie/.json assets; else phase/keyframe animators |
