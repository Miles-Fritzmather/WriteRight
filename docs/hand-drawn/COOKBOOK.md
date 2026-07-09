# Cookbook — Extending the Hand-Drawn Style

Task-oriented recipes. Each assumes you've read [STYLE.md](STYLE.md) (what it
should look like) and [PIPELINE.md](PIPELINE.md) (the vocabulary/types used
below).

## The one rule, restated

Feature code calls `AppButton`/`AppIcon`/`AppIconButton`/`AppColorSwatch`/
`AppToggle`/`AppToolbarContainer`/`AppLabel`/`AppDivider` — never raw
`Button`/`Image`/styling. If the `Theme` protocol doesn't have the primitive
you need, **add one** (Recipe 1) rather than reaching around it. The only
sanctioned exception is a fully bespoke, non-reusable screen (Recipe 3).

## Recipe 1 — Add a new `Theme` primitive

This is exactly how `toolbarContainer`, `label`, and `divider` were added
when the toolbar chrome needed them. Four steps, in order:

**1. Add the method to the protocol** (`App/Sources/Theme.swift`):

```swift
protocol Theme: Sendable {
    // ...existing methods...
    @MainActor
    func myNewPrimitive(_ title: String, isOn: Bool, action: @escaping () -> Void) -> AnyView
}
```

Every method returns `AnyView` (protocol methods can't return `some View`
across heterogeneous concrete implementations) and is `@MainActor` (these
build/mutate SwiftUI state).

**2. Implement it in `SystemTheme`** (same file) — a plain, boring SwiftUI
implementation. This one still has to work correctly and look reasonable; it's
the app's actual default.

**3. Implement it in `HandDrawnTheme`** (`App/Sources/HandDrawnTheme.swift`) —
this is almost always: pick a style variant (see Recipe 4), pick a stable
`seedKey`, build a `skeleton` closure, build a `color` closure, wrap in
`SketchElementView`, set a `.frame(...)`. Skeleton for anything with an
"in-progress" gesture concept (a button, a toggle, a selectable thing) needs
`pressable: true` and a real `SketchPressStyle` button wrapper — copy the
shape of `iconButton` or `toggle`, whichever is closer to what you're
building:

```swift
func myNewPrimitive(_ title: String, isOn: Bool, action: @escaping () -> Void) -> AnyView {
    let s = controlStyle                       // or chromeStyle/textStyle — see Recipe 4
    let seedKey = "myNewPrimitive.\(title)"     // stable identity — see PIPELINE.md determinism
    let seed = sketchSeed(seedKey)
    let inkColor = ink

    return AnyView(
        Button(action: action) { Color.clear }
            .buttonStyle(SketchPressStyle { pressed in
                AnyView(
                    SketchElementView(
                        seedKey: seedKey,
                        style: s,
                        pressed: pressed,
                        pressable: true,
                        entranceDelay: Self.entranceDelay(seedKey),
                        revision: isOn ? "on" : "off",   // re-realize when persistent state flips
                        color: { kind, state in
                            switch kind {
                            case .hatch: inkColor.opacity(state == .pressed ? 0.38 : 0.14)
                            default: inkColor.opacity(isOn ? 1 : 0.7)
                            }
                        },
                        skeleton: { rect, state in
                            let border = rect.insetBy(3.5)   // wobble/ghost headroom — always inset
                            var strokes = borderStrokes(in: border, overshoot: s.overshoot, cornerRadius: s.cornerRadius)
                                .map { SkeletonStroke(points: $0, kind: .border) }
                            strokes += hersheyTextSkeleton(
                                title, size: 9, center: SketchPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2),
                                seed: sketchHash(seed, 555, 0), kind: .label   // salt 555 — see PIPELINE.md
                            )
                            if state == .pressed || isOn {
                                strokes += hatchStrokes(in: border, spacing: s.hatchSpacing)
                                    .map { SkeletonStroke(points: $0, kind: .hatch) }
                            }
                            return strokes
                        }
                    )
                    .frame(width: 80, height: 30)
                )
            })
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")   // always set — see Gotchas
    )
}
```

**4. Add the `App*` wrapper view** (`App/Sources/Theme.swift`, bottom of
file), and use *that* from feature code — never call `theme.myNewPrimitive`
directly outside the wrapper:

```swift
struct AppMyNewPrimitive: View {
    @Environment(\.theme) private var theme
    let title: String
    let isOn: Bool
    let action: () -> Void
    var body: some View { theme.myNewPrimitive(title, isOn: isOn, action: action) }
}
```

## Recipe 2 — Add a new hand-drawn icon

Icons live in `App/Sources/SketchIcons.swift` as raw polylines, authored in a
fixed **24×24 design box, y grows downward**, then uniformly scaled/centered
into whatever rect they're rendered at (`SketchIconLibrary.skeleton(name:in:)`
does the fitting — you never write scaling logic yourself).

1. Draw your icon's strokes as a list of `[SketchPoint]` in the 24×24 box.
   Rules of thumb (from the existing six icons):
   - **1–3 strokes.** Each stroke is one pen pull in the write-on entrance —
     more than 3 starts to feel busy at icon scale.
   - **Bold, simple silhouettes.** At ~20pt render size the wobble will eat
     fine detail; favor a strong outline over internal linework.
   - **Stay ~2.5pt clear of the box edges.** The wobble needs headroom, or
     it'll visibly clip.
2. Add the entry to the `designs` dictionary:
   ```swift
   private static let designs: [String: [[SketchPoint]]] = [
       // ...existing entries...
       "star": [
           [p(12, 2), p(14.7, 8.8), p(22, 9.3), p(16.3, 13.9), p(18.4, 21), p(12, 16.8),
            p(5.6, 21), p(7.7, 13.9), p(2, 9.3), p(9.3, 8.8), p(12, 2)],
       ],
   ]
   ```
3. Wire it up wherever the icon is chosen — usually a `case` in some
   `IconSource` computed property, using
   `.builtIn(name: "star", fallbackSymbol: "star.fill")`. **Always give a
   real `fallbackSymbol`** — `SystemTheme` (and `HandDrawnTheme` when the
   name isn't found in the library) render that SF Symbol instead, and the
   app must still be usable and correct with `SystemTheme` active.
4. That's it — `HandDrawnTheme.icon`/`.iconButton` already look up any
   `.builtIn` name through `SketchIconLibrary` automatically; you don't
   touch the theme.

## Recipe 3 — Build a bespoke hand-drawn screen (not a `Theme` primitive)

Sometimes you want a one-off screen with custom animated behavior that isn't
a reusable control — press counters, particle bursts, anything with state
beyond "pressed/selected." Don't force this through `SketchElementView`;
model it directly on **`App/Sources/SketchDemoScreen.swift`**, which is the
reference example:

- An `@Observable` model holds: the tunable `SketchStyle`, cached
  `[RealizedStroke]`→prebuilt-`Path` arrays per boil variant (its own small
  `CachedStroke` type — same shape as `SketchCachedStroke`, don't share it,
  it's intentionally decoupled), an `EntranceSchedule`, and whatever custom
  animation state you need (the demo's press counter and spark-burst
  arrays).
- A `TimelineView(.animation) { Canvas { ... } }` view (no need for the
  variable-frame-rate trick unless you also care about idle cost — the demo
  screen is a full-screen modal, so it just runs at display refresh rate the
  whole time it's open).
- `.onGeometryChange` to rebuild geometry when the stage resizes; a
  `DragGesture(minimumDistance: 0)` (or whatever) for custom hit-testing,
  since you're not using `Button` here.
- One `draw(in:size:at:)` method that mirrors `SketchElementView.draw`'s
  ordering (hatch behind, then border/label with entrance truncation +
  ghost pass on completed border strokes) plus whatever extra layers your
  effect needs.

This screen also is *not* a `Theme` primitive itself and doesn't need to be —
it's reached via a direct call from a `SystemTheme`-rendered `AppButton`
("Sketch demo" in the debug HUD), which is correct: the chrome that opens a
bespoke showcase still goes through the theme; the showcase's own interior
doesn't have to.

## Recipe 4 — Tune proportions for a new control size class

`HandDrawnTheme` derives a few named, scaled copies of the base `style`
rather than hardcoding numbers per call site or mutating a shared instance:

```swift
private var controlStyle: SketchStyle {   // toolbar-scale controls (~1/4 the demo button)
    var s = style
    s.inkWidth = 2.3; s.amplitude = 1.5; s.jitter = 1.3; s.taper = 7
    s.spacing = 4; s.cornerRadius = 9; s.overshoot = 6
    s.hatchSpacing = 6.5; s.ghostOffset = 1.5
    return s
}
private var chromeStyle: SketchStyle {    // large container chrome — heavier ink, faster pen
    var s = style
    s.inkWidth = 2.9; s.cornerRadius = 12; s.penSpeed = 2800
    return s
}
private var textStyle: SketchStyle {      // free-standing text — no ghost (hurts legibility)
    var s = controlStyle; s.ghost = false; return s
}
```

If you're adding a genuinely new size class (say, a large hero card), copy
this pattern: start from `style` or the nearest existing derived style,
override only what actually needs to change for that scale, and **comment
why** (the ratio or reasoning), the way the three above do. Don't invent a
fourth one unless you actually need different proportions — reuse
`controlStyle` for anything toolbar-scale.

## Gotchas

- **Seed mismatch between measuring and rendering text.** If you call
  `hersheyTextSize(...)` to lay out a frame and `hersheyTextSkeleton(...)`
  (or `buttonSkeleton`, which lays out text internally) to actually draw it,
  **the `seed:` argument to both must be identical**. They aren't
  automatically kept in sync — there's no compiler check. A mismatch
  doesn't crash; it silently draws text at a slightly different width/
  jitter than what you measured, showing up as clipped or over-padded
  labels. This codebase's convention: text inside `buttonSkeleton` always
  uses `sketchHash(seed, 999, 0)`; everything laid out manually elsewhere
  uses `sketchHash(seed, 555, 0)`. Reuse one of those two rather than
  inventing a third salt, unless you have a real reason to.
- **Never use `Hasher`/`.hashValue`/`UUID()` for anything that affects
  wobble.** They're randomized per process launch and will make the UI
  reshuffle its hand-drawn look every time the app starts. Always derive
  seeds from `sketchSeed(_ key: String)` fed a stable identity string.
- **Always inset before calling `borderStrokes`.** Every existing call site
  does `rect.insetBy(3.5)` (or similar) before generating a border — drawing
  right at the container's edge leaves no room for the wobble/ghost pass and
  it'll visibly clip. `SketchRect.insetBy(_:)` lives at the bottom of
  `HandDrawnTheme.swift`.
- **Long/variable-length text needs a shrink-to-fit pass.** `iconButton`
  measures the title at a target size, and if it's wider than the button's
  text budget, scales the font size down proportionally
  (`fittedTitleSize *= 44 / measuredTitle.width`) before building the real
  skeleton at that adjusted size. Copy this pattern for any control whose
  label text isn't a fixed, known-short string.
- **Don't rebuild geometry inside a draw loop.** `realize(...)` and
  skeleton-building are the expensive steps; they belong in
  `SketchElementView`'s `rebuild(for:)` (triggered by size or `revision`
  changes only), never in `draw(in:size:at:)`, which should only touch
  already-cached `Path`s.
- **Accessibility isn't automatic.** Ink has no semantic text for
  VoiceOver — every `Theme` primitive implementation must still set
  `.accessibilityLabel` (and `.accessibilityValue` for anything with
  on/off or selected state), exactly like the existing ones do.
- **Don't hand-draw something just because you can.** Re-read STYLE.md's
  "where it's used, and where it deliberately isn't" before adding the
  treatment to a new screen — dense debug/utility UI is meant to stay on
  `SystemTheme`.

## Verifying a change

After touching anything in this system:

```bash
# If you touched Packages/SketchKit: run its unit tests (golden values + pipeline properties)
swift test --package-path Packages/SketchKit

# Regenerate the Xcode project if you added/removed files
xcodegen generate

# Build for the simulator
xcodebuild -project WriteRight.xcodeproj -scheme WriteRight \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
```

Then actually look at it — this is a visual system, and a clean build proves
nothing about whether it looks right:

```bash
# If no iOS 26 iPad simulator exists yet, create one against an installed iOS 26.x runtime:
xcrun simctl list runtimes                        # find the exact iOS 26.x runtime identifier
xcrun simctl create "WriteRight iPad" \
  "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB" \
  "com.apple.CoreSimulator.SimRuntime.iOS-26-5"    # match the runtime you found above

xcrun simctl boot "WriteRight iPad"
APP=$(find build/DerivedData/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "WriteRight.app")
xcrun simctl install "WriteRight iPad" "$APP"
xcrun simctl launch "WriteRight iPad" com.milesfritzmather.writeright
xcrun simctl io "WriteRight iPad" screenshot /tmp/check.png
```

Because the boil is a slow (2fps default) cycle and the entrance only plays
once on appear, a single screenshot a few seconds after launch is usually
enough to confirm layout/ink/color are right — but the *feel* (boil speed,
entrance timing, press response) can only really be judged live, ideally on
Miles's physical iPad per this project's usual verification path. Say so
explicitly if you've only screenshot-verified and haven't seen it move.

## Where it's wired today (for orientation, not to copy blindly)

- `App/Sources/RootView.swift` scopes `HandDrawnTheme` to just the bottom
  toolbar via `.environment(\.theme, HandDrawnTheme())` on that one subview
  — the rest of the view tree inherits the default `SystemTheme`.
- `App/Sources/PrototypeToolToolbar.swift` is the cleanest existing example
  of feature code written purely against `App*` wrappers, with zero
  awareness of which theme is active.
