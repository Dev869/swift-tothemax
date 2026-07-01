# Layout & Animation

Version tags: untagged = iOS 16-era baseline; (17)/(18) = iOS 17/18; (26) = iOS 26 / macOS Tahoe; **(27β)** = WWDC26 betas — mark as beta in output code.

## Layout: pick the simplest tool that wins

| Need | Tool |
|---|---|
| Linear flow | `VStack`/`HStack` + `Spacer`/`.frame(maxWidth: .infinity, alignment:)` |
| Aligned columns (forms, stats) | `Grid`/`GridRow` — columns align across rows, unlike nested HStacks |
| Scrolling collections | `LazyVGrid`/`LazyHGrid` with `adaptive`/`flexible` items |
| "Fit whichever variant fits" | `ViewThatFits` |
| Size relative to scroll container | `containerRelativeFrame` (17) |
| Overlap/badging | `.overlay(alignment:)` / `.background` — not ZStack + offset math |
| Truly custom arrangement | `Layout` protocol |
| Reading size (last resort) | `GeometryReader` in `.background`, or `onGeometryChange` (18, backported) |

```swift
Grid(alignment: .leading, horizontalSpacing: 12) {
    GridRow { Text("Calories"); Text("420").gridColumnAlignment(.trailing) }
    Divider().gridCellUnsizedAxes(.horizontal)   // don't let divider stretch the grid
    GridRow { Text("Protein");  Text("32 g") }
}

ViewThatFits(in: .horizontal) {
    HStack { icon; title; statsBadge }   // roomy
    HStack { icon; title }               // tight
    icon                                 // watch-sized
}
```

### Layout protocol (custom containers)

Implement two methods; cache expensive math in `Cache`.

```swift
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(for: subviews, in: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, point) in rows(for: subviews, in: bounds.width).placements {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                          proposal: .unspecified)
        }
    }
}
```

- Respect the proposal contract: a subview may return any size; never force-place with a fixed proposal unless that's the design.
- Use `LayoutValueKey` to let children pass per-item data (e.g. flex weight) up to the layout.
- Switch layouts with identity preserved: `AnyLayout(isWide ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout()))` — animates children between arrangements instead of rebuilding them.

### Wrong vs right: GeometryReader

```swift
// WRONG — GeometryReader as a container: greedy sizing, breaks intrinsic layout.
GeometryReader { geo in Text(title).frame(width: geo.size.width * 0.8) }

// RIGHT — measure without disturbing layout.
Text(title)
    .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }   // (18)
// or: containerRelativeFrame(.horizontal) { length, _ in length * 0.8 }  (17)
```

## ScrollView APIs by version

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 16) {
        ForEach(cards) { card in
            CardView(card)
                .containerRelativeFrame(.horizontal, count: 3, spacing: 16)   // (17)
                .scrollTransition { content, phase in                          // (17)
                    content.opacity(phase.isIdentity ? 1 : 0.4)
                           .scaleEffect(phase.isIdentity ? 1 : 0.92)
                }
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)          // (17) paging: .paging
.scrollPosition($position)                   // (17 id-based; 18 adds ScrollPosition type: offsets/edges programmatically)
```

- (18) `onScrollGeometryChange(for:of:action:)` — offset-driven effects without GeometryReader hacks; `onScrollVisibilityChange` for "play video when 50% visible"; `onScrollPhaseChange` for idle/dragging/decelerating.
- (26) `scrollEdgeEffectStyle(_:for:)` — control the Liquid Glass edge treatment where content meets bars; `.hard` for pinned headers, `.soft` default.
- (26) `tabBarMinimizeBehavior(.onScrollDown)` on TabView; `tabViewBottomAccessory` for mini-player-style bars.
- **(27β)** `toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)` — nav bar collapses on scroll.
- **(27β)** swipe actions escape List: rows in any ScrollView via `.swipeActions { }` on the row + `.swipeActionsContainer()` on the ScrollView.
- **(27β)** reorderable containers — drag-to-rearrange in `List`, `LazyVGrid`, custom stacks (first watchOS reordering support):

```swift
ForEach(stickers) { StickerRow($0) }
    .reorderable()
.reorderContainer(for: Sticker.self) { diff in diff.apply(to: &stickers) }   // (27β)
```

## Transitions & matched geometry

- `.transition(.move(edge: .bottom).combined(with: .opacity))` fires on **identity change** (`if`/`ForEach` insertion) — and only inside an animation (`withAnimation` or `.animation(_, value:)`).
- `.transition(.asymmetric(insertion:removal:))` when in/out differ. Custom: conform to `Transition` (17) instead of AnyTransition modifier pairs.
- `matchedGeometryEffect(id:in:)` for hero moves **within one screen**: both views share a `@Namespace`; exactly one has `isSource: true` at any moment or you get flicker.
- (18) zoom navigation transition for push/present hero animation — use this instead of abusing matchedGeometry across navigation:

```swift
NavigationLink(value: photo) { thumb.matchedTransitionSource(id: photo.id, in: ns) }
// destination:
PhotoDetail(photo).navigationTransition(.zoom(sourceID: photo.id, in: ns))
```

- (26) glass shapes morph between states with `glassEffectID(_:in:)` inside a `GlassEffectContainer` — see SKILL.md.

## Animation: choose by shape of the problem

| Problem | API |
|---|---|
| React to a state change | `.animation(.snappy, value: state)` (scoped) or `withAnimation` |
| Different animations per property | `.animation(.spring) { $0.scaleEffect(s) }` content-closure form (17) |
| Fire-and-forget multi-step (banners, pulses) | `PhaseAnimator` (17) |
| Choreographed timeline, parallel tracks | `KeyframeAnimator` (17) |
| Custom animatable property | `@Animatable` macro (26); `animatableData` below 26 |
| Completion hooks | `withAnimation(.bouncy) { } completion: { }` (17) |
| Fully custom curve/physics | `CustomAnimation` protocol (17) |

```swift
// PhaseAnimator: discrete phases, auto-advancing (or driven by `trigger:`)
Image(systemName: "bell")
    .phaseAnimator([0, -18, 12, -6, 0], trigger: alertCount) { view, angle in
        view.rotationEffect(.degrees(angle))
    } animation: { _ in .spring(duration: 0.15) }

// KeyframeAnimator: continuous tracks over a value type
KeyframeAnimator(initialValue: BadgeState(), trigger: unlocked) { view, state in
    view.scaleEffect(state.scale).offset(y: state.y)
} keyframes: { _ in
    KeyframeTrack(\.scale) { SpringKeyframe(1.3, duration: 0.2); SpringKeyframe(1.0, duration: 0.3) }
    KeyframeTrack(\.y)     { CubicKeyframe(-20, duration: 0.25); CubicKeyframe(0, duration: 0.25) }
}

// (26) @Animatable — SwiftUI interpolates stored properties for you
@Animatable
struct Gauge: View, /* shape/view */ {
    var progress: Double                       // animates smoothly
    @AnimatableIgnored var tickCount: Int      // opt out
    var body: some View { /* draw with progress */ }
}
```

### Wrong vs right: classic animation bugs

```swift
// WRONG — unscoped legacy animation: animates EVERYTHING that ever changes this view.
.animation(.easeInOut)                       // deprecated for good reason

// RIGHT
.animation(.easeInOut, value: isExpanded)

// WRONG — animating identity change without transition awareness: view "jumps".
if showBanner { Banner() }                   // inserted with no transition, outside withAnimation

// RIGHT
if showBanner { Banner().transition(.move(edge: .top)) }
// toggled via: withAnimation(.snappy) { showBanner = true }
```

- Respect `accessibilityReduceMotion`: gate large movement/parallax; crossfade instead.
- Scroll-linked effects: prefer `scrollTransition`/`visualEffect` (17) — they run without invalidating body.

## WWDC25/26 additions worth reaching for

- (26) Rich text editing: `TextEditor(text: $attributedString)` with `AttributedString` + `AttributedTextSelection` — build formatting UI without wrapping UITextView.
- (26) `WebView`/`WebPage` (WebKit for SwiftUI) — stop writing `WKWebView` representables.
- (26) `Slider` tick marks & neutral value; `windowResizeAnchor`, expanded `navigationSubtitle` on iOS/iPadOS.
- **(27β)** `Tab(role: .prominent)` for a visually emphasized tab (e.g. Cart).
- **(27β)** Toolbar control: `visibilityPriority(_:)` on toolbar groups, `ToolbarOverflowMenu { }` for permanent overflow items, pinned-trailing top bar placement for must-see actions.
- **(27β)** `AsyncImage` respects HTTP cache headers by default; customize via `asyncImageURLSession(_:)` with your own `URLCache` — many DIY image loaders can be deleted.
- **(27β)** Resizable iPhone apps: stop assuming fixed widths; test with Xcode 27 preview resize handles. `ViewThatFits` + adaptive grids are the prep work.
