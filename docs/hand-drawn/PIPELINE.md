# SketchKit Pipeline & Renderer — Technical Reference

This is the precise technical reference for how [STYLE.md](STYLE.md)'s look
is actually produced: the geometry pipeline in the `SketchKit` package, and
the SwiftUI renderer (`SketchElementView`) that drives it on screen. Read
STYLE.md first if you haven't — this document uses its vocabulary without
re-explaining the "why."

## Module boundary

```
Packages/SketchKit/Sources/SketchKit/   ← pure Swift, no SwiftUI/UIKit import
    SketchGeometry.swift                    SketchPoint, resample, wobble, ribbon
    SketchRandom.swift                      deterministic RNG + hashing
    Skeletons.swift                         SketchRect, borderStrokes, hatchStrokes
    SketchRealizer.swift                    SkeletonStroke/RealizedStroke, realize(),
                                             buttonSkeleton(), EntranceSchedule
    SketchStyle.swift                       every tunable parameter, in one struct
    HersheyFont.swift                       embedded single-stroke vector font

App/Sources/
    SketchSwiftUIBridge.swift               Path(polygon:)/Path(polyline:)/Color(hex:),
                                             sketchSeed(_:) — the ONLY place SketchKit
                                             geometry touches SwiftUI types
    HandDrawnTheme.swift                     the Theme implementation + SketchElementView
    SketchIcons.swift                       bundled icon skeletons
    SketchDemoScreen.swift                  bespoke full-pipeline showcase screen
```

`SketchKit` knows nothing about SwiftUI, `Color`, screen coordinates, or even
which platform it's running on — it only works in plain `Double`s and
`SketchPoint`s in "element-local space" (whatever rect you hand it). This is
deliberate: it's independently unit-tested (see "Testing" below), and it
means the same geometry engine could target a different renderer (Metal,
tiled textures) later without touching a single wobble/boil calculation. All
`Path`/`Color` conversion, and the only per-app determinism helper
(`sketchSeed`), live app-side in `SketchSwiftUIBridge.swift` — if you find
yourself wanting to `import SketchKit` from inside `Packages/SketchKit`
itself and also touch `SwiftUI`, stop; that conversion belongs in the bridge
file instead.

## The pipeline, stage by stage

```
skeleton                resample            wobble              ribbon
[[SketchPoint]]  ────►  even arc-length ──► perpendicular/  ──► variable-width
(ideal shape,           spacing              tangential          ink polygon
 ~2-4 pts/stroke)                            noise + endpoint    (RibbonGeometry:
                                              jitter              left/right edges,
                                                                   cumulative length)
                                                                        │
                                                                        ▼
                                                                 RealizedStroke
                                                          (kind, ribbon, ghostOffset)
                                                                        │
                                        ┌───────────────────────────────┤
                                        ▼                                ▼
                              SketchCachedStroke                EntranceSchedule
                          (Path pre-built once per                (per-stroke start/
                           size/revision/variant)                   duration, from
                                        │                          ribbon.totalLength
                                        ▼                              / penSpeed)
                              composited every frame
                             (SketchElementView.draw)
```

### 1. Skeletons — the ideal shape

A **skeleton** is a plain array of `SkeletonStroke`, each just a polyline
(`[SketchPoint]`) tagged with a `SketchStrokeKind`:

```swift
public enum SketchStrokeKind: Sendable, Equatable {
    case border   // outline; the only kind that gets the ghost pass
    case label    // primary text
    case subtext  // secondary/smaller text, wobbles less than label
    case hatch    // press/selection fill, drawn behind, budget-revealed
    case accent   // decorations: checkmarks, divider ticks, ring highlights, sparks
}
```

Skeletons are the *only* thing a caller authors by hand — everything after
this stage is automatic. `Skeletons.swift` provides two general-purpose
generators:

- **`borderStrokes(in rect: SketchRect, overshoot: Double, cornerRadius: Double) -> [[SketchPoint]]`**
  — the shape every bordered control uses.
  - `cornerRadius >= 1`: **one continuous stroke** — a swoop that starts
    32% along the top edge, goes clockwise around all four (rounded)
    corners, and closes by retracing past its own start point by
    `overshoot` points. This "one pen stroke" property is what makes the
    write-on entrance for a rounded box look like a single natural pen
    movement instead of four disconnected sides.
  - `cornerRadius < 1`: **four separate overshooting strokes**, one per
    side, each overshooting past where it would meet its neighbor — the
    sharp "sketchbook box" look, corners formed by the crossing overshoots
    rather than a miter join. Used for things too small/square for the
    swoop treatment (e.g. the toggle checkbox in `HandDrawnTheme.toggle`).
- **`hatchStrokes(in rect: SketchRect, spacing: Double) -> [[SketchPoint]]`**
  — a diagonal zig-zag fill (alternating direction each line, simulating
  continuous pen travel rather than lifting between lines), inset 7pt from
  the rect. This is the press/selection fill.

`SketchRealizer.swift` adds one composed helper: **`buttonSkeleton(in:label:labelSize:style:seed:state:font:)`**
builds a complete button skeleton — border, then label text (via
`HersheyFont.textStrokes`, seeded internally with `sketchHash(seed, 999, 0)`
— see "The 999/555 salt convention" below), then (if `state == .pressed`)
hatch — in that order, which is the order the entrance draws them in.

### 2. Resample — even spacing

`resample(_ points: [SketchPoint], spacing: Double) -> [SketchPoint]`
re-samples a polyline at (nearly) even arc-length intervals. The wobble noise
is sampled *per resampled point*, so this spacing (`SketchStyle.spacing`,
default 5pt) sets the wobble's effective resolution — too coarse and the
wobble looks faceted, too fine and it's wasted computation. The first point
is kept exactly; the last is kept unless it falls within a quarter-spacing
of the previous sample (avoids a near-zero-length trailing segment).

### 3. Wobble — the hand-drawn displacement

```swift
public func wobble(
    _ points: [SketchPoint], amplitude: Double, wavelength: Double,
    jitter: Double, rng: inout SketchRandom
) -> [SketchPoint]
```

For each point: a **normal-direction** displacement from a smooth low-
frequency noise curve (`NoiseCurve`, control points every `wavelength` apart,
smoothstep-interpolated between them — this smoothness is what keeps it
"lazy waver" rather than jagged), plus a smaller **tangential** displacement
from a second, shorter-wavelength (`wavelength * 0.7`) noise curve, plus a
**per-endpoint jitter** (`jitter`, random per stroke instance) blended in
over the first/last ~25 points of arc length so it doesn't distort the
stroke's middle. `SketchRealizer.realize` scales `amplitude`/`jitter` by
`style.labelWobble` for `.label` kind (and an extra `× 0.6` for `.subtext`)
so text stays legible while shapes wobble at full strength.

### 4. Ribbon — ink, not a line

```swift
public func ribbon(
    around points: [SketchPoint], baseWidth: Double, widthVariance: Double,
    taper: Double, rng: inout SketchRandom
) -> RibbonGeometry?
```

Builds two offset polylines (`left`/`right`) around the wobbled centerline,
at a width that (a) drifts with a third noise curve scaled by
`widthVariance`, and (b) tapers toward both ends over `taper` points of arc
length — but never below ~26% of the target width (`0.22 + 0.78 * max(0.05,
tp)`, `tp` = normalized taper progress), so tips come to a point rather than
vanishing to zero. `RealizedStroke`'s width-per-kind convention
(set in `realize`, see below) is: `.hatch` = 80% of `style.inkWidth`,
`.subtext` = 75%, `.accent` = 70%, `.border`/`.label` = 100%; `.accent` also
gets a short fixed 6pt taper instead of `style.taper`.

`RibbonGeometry` exposes:
- `polygon(upTo: Int?) -> [SketchPoint]` — the fill polygon
  (`left + right.reversed()`), optionally truncated at a centerline index —
  this is what makes the "still being drawn" partial-stroke render possible.
- `index(atLength:) -> Int` — binary search from arc length to centerline
  index, used every frame during the entrance to find how far to truncate.
- `totalLength` — used by `EntranceSchedule` to convert length into duration.

### 5. Realize — one skeleton, one boil variant

```swift
public func realize(
    _ skeleton: [SkeletonStroke], style: SketchStyle, seed: UInt32,
    variant: Int, state: SketchState
) -> [RealizedStroke]
```

Runs resample → wobble → ribbon over every stroke in a skeleton, producing
`[RealizedStroke]` (`kind`, `ribbon: RibbonGeometry`, `ghostOffset:
SketchPoint`). **Determinism**: stroke `k` of boil variant `v` in state
`state` always uses RNG seed `sketchHash(seed, k*7 + v, state == .pressed ?
1 : 0)` — same inputs, bit-identical geometry, every time. Call `realize`
once per `(variant, state)` pair you need (typically `0..<style.variants`,
× normal and, for interactive controls, pressed) and cache the result —
never call it from inside a per-frame draw loop.

### 6. Entrance — writing it on

```swift
public struct EntranceSchedule {
    public struct Entry { let start: Double; let duration: Double; var end: Double }
    public init(strokes: [RealizedStroke], penSpeed: Double, strokePause: Double)
}
```

Walks the realized strokes **in skeleton order**, skipping `.hatch` (which
is press/selection-revealed separately, not part of the write-on), assigning
each a `start`/`duration` (`duration = ribbon.totalLength / penSpeed`) with
`strokePause` seconds of gap between strokes. `totalDuration` is the full
time until the last stroke finishes — used to know when an element has
"finished writing" and can start responding to hatch/selection state (see
`SketchElementView.draw`'s `entranceComplete` gate).

## Determinism & seeding

Nothing here is meant to be unpredictable — see STYLE.md's "Determinism"
section for *why*. Mechanically:

- **`sketchSeed(_ key: String) -> UInt32`** (`SketchSwiftUIBridge.swift`) —
  deterministic FNV-1a hash over UTF-8 bytes. Turns a stable identity string
  (`"tool.Pen"`, `"swatch.blue"`, `"toolbar.container"`) into the base seed
  for an element. **Never use Swift's `Hasher`/`.hashValue` for this** — it's
  deliberately randomized per process launch (hash-flooding protection),
  which would make every element wobble differently every time you run the
  app. `sketchSeed` is the one and only sanctioned way to go from "an
  element's identity" to "a seed."
- **`sketchHash(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32`**
  (`Packages/SketchKit/Sources/SketchKit/SketchRandom.swift`) — a 3-way
  FNV-style combine, used everywhere a base seed needs to be split into
  independent sub-seeds (per-stroke, per-variant, per-state, per-purpose)
  without those sub-streams correlating with each other.
- **`SketchRandom`** — a from-scratch Swift port of the `mulberry32` PRNG
  used by the JS reference, chosen specifically so both languages produce
  **bit-identical** output for the same seed (verified by golden-value
  tests — see "Testing" below). `.next()` is uniform `[0, 1)`, `.nextSigned()`
  is `[-1, 1)`.

### The 999 / 555 salt convention

Any text that goes through `buttonSkeleton` (i.e. `HandDrawnTheme.button`,
`.menu`) has its label strokes generated with an RNG seeded internally by
`sketchHash(seed, 999, 0)` — that's `buttonSkeleton`'s own reserved salt,
set in `SketchRealizer.swift` and not visible to the caller. Anywhere the
caller needs to *measure* that same label before laying out a frame around
it (so the button can be sized to fit), it must measure with the identical
expression: `hersheyTextSize(label, size:, seed: sketchHash(seed, 999, 0))`.

Everywhere else this codebase lays out standalone text manually — outside
`buttonSkeleton`, via the app-side helpers `hersheyTextSkeleton`/
`hersheyTextSize` (`HandDrawnTheme.swift`) — it uses salt `555` by
convention (`iconButton`'s caption, `toggle`'s label, `label(_:)`'s
caption). Both numbers are **arbitrary** — pick a new one if you like — but
whatever you pick, **the seed expression used to measure a piece of text
must be pixel-for-pixel identical to the seed expression used to render
it**, or the measured bounding box and the rendered strokes will silently
disagree (usually showing up as clipped or oddly-padded text). See
COOKBOOK.md's gotchas section for the concrete failure mode.

## `SketchStyle` — every tunable, in one place

`Packages/SketchKit/Sources/SketchKit/SketchStyle.swift`. All fields are
`var` with defaults locked in from the HTML playground on 2026-07-07;
`HandDrawnTheme` derives scaled copies for different control classes (see
COOKBOOK.md Recipe 4) rather than mutating a shared instance.

| Field | Default | Meaning |
|---|---|---|
| `spacing` | 5 | Resample interval before wobbling (pt) |
| `amplitude` | 2.2 | Max perpendicular wobble displacement (pt) |
| `wavelength` | 38 | Arc-length distance between wobble noise control points — larger = lazier waver |
| `jitter` | 2.5 | Random endpoint offset, blended over ~25pt |
| `labelWobble` | 0.35 | Multiplier on amplitude+jitter for `.label` strokes; `.subtext` gets this again `× 0.6` |
| `boilFps` | 2 | How often the boil swaps to a different pre-generated variant |
| `variants` | 3 | Number of pre-generated wobble variants per element/state |
| `inkWidth` | 3.4 | Base ribbon width (pt) |
| `widthVariance` | 0.5 | Noise-modulated width variance (0 = uniform) |
| `taper` | 14 | Pen-pressure taper length at both stroke ends (pt) |
| `ghost` | true | Whether the second, offset "sketched over" pass is drawn |
| `ghostAlpha` | 0.28 | Opacity of the ghost pass |
| `ghostOffset` | 2 | Max offset of the ghost pass (pt) |
| `penSpeed` | 1400 | Write-on entrance pen travel speed (pt/s) |
| `strokePause` | 0.06 | Pause between entrance strokes (s) |
| `pressWidthMultiplier` | 1.35 | Ink-width multiplier in `.pressed` state |
| `pressSquash` | 0.94 | Vertical scale applied on press (paired with a `2 - pressSquash` horizontal scale in the renderer) |
| `hatchSpacing` | 13 | Gap between press/selection hatch lines (pt) |
| `cornerRadius` | 14 | `>= 1`: rounded swoop; `< 1`: sharp overshooting-side box |
| `overshoot` | 10 | Overshoot past each corner (sharp mode) / closing retrace length (swoop mode) |
| `inkHex` | `#2b2723` | Ink color |
| `paperHex` | `#f7f2e7` | Paper/background color |

## The SwiftUI renderer — `SketchElementView`

`App/Sources/HandDrawnTheme.swift`. This is the one generic building block
every `HandDrawnTheme` primitive is built from — you should essentially
never need another rendering mechanism for a themed control (see
COOKBOOK.md Recipe 1). Parameters:

```swift
struct SketchElementView: View {
    let seedKey: String                                     // identity → determinism
    let style: SketchStyle
    var pressed: Bool = false
    var pressable: Bool = false                              // also realize .pressed variants
    var entranceDelay: Double? = nil                         // nil = no write-on entrance
    var paperFill: Color? = nil                              // fill the border's own centerline loop
    var revision: String = ""                                // bump to force re-realize (e.g. selection change)
    let color: (SketchStrokeKind, SketchState) -> Color
    let skeleton: (SketchRect, SketchState) -> [SkeletonStroke]
}
```

- **`skeleton`** is the one thing every call site actually authors — a
  closure from `(elementRect, normalOrPressedState)` to the skeleton, using
  `borderStrokes`/`hatchStrokes`/`hersheyTextSkeleton`/`SketchIconLibrary`
  building blocks. **`color`** maps a rendered stroke's kind (and current
  press state) to the `Color` to fill it with — this is where selection/
  press opacity differences live (e.g. `.hatch` drawn at a lower opacity
  than `.border`).
- **Caching (`rebuild`)**: on first layout, and again whenever `revision`
  changes, it calls `skeleton`+`realize` once per `(variant, state)` pair
  needed, wraps every `RealizedStroke` in a `SketchCachedStroke` (which
  pre-builds the SwiftUI `Path`s — `fullPath`, `centerPath`, `centerLoop` —
  so the draw loop never touches geometry), and — if `entranceDelay` is
  set — builds one `EntranceSchedule`. This is the only expensive step;
  everything below re-runs every frame but touches only already-built
  `Path`s.
- **Frame-rate strategy**: driven by `TimelineView(.animation(minimumInterval:))`.
  Normally `minimumFrameInterval` is `1 / style.boilFps` (i.e. redraws only
  a couple of times a second — cheap, and correct, since between boil ticks
  nothing has actually changed). Whenever the entrance starts, or `pressed`
  toggles, `holdFastFrames(seconds)` pushes a `fastUntil` deadline forward
  (never backward — see the `candidate > $0` guard), which switches
  `minimumFrameInterval` to `1/120` until that deadline passes, so the
  write-on / squash-and-hatch transitions feel fluid. A `.task(id:
  fastUntil)` sleeps until the deadline, then clears it, dropping back to
  boil cadence automatically. **This is why a real toolbar full of boiling
  controls stays cheap**: only the element currently mid-entrance or
  mid-press is ticking at 120fps; every idle neighbor is ticking at 2fps.
- **`draw(in:size:at:)`** per frame: picks the current boil `variant` from
  wall-clock time, offset by a per-element phase (`sketchSeed(seedKey) %
  997`) so a whole toolbar's controls don't all flip variant on the same
  tick; applies the press squash transform if `pressed`; fills `paperFill`
  into the border's centerline loop if set (so the paper itself boils with
  the ink); then, only once the entrance has finished (`entranceComplete`,
  or always while `pressed`), draws `.hatch` strokes with a length budget
  (full length normally, or ramped in over ~130ms right after a press
  begins); then draws every remaining stroke — either the **entrance-
  truncated partial polygon** (via `ribbon.index(atLength:)`) if the pen
  hasn't reached the end of that stroke yet, or the **full path** plus, for
  `.border` strokes only, the ghost pass traced from *next* variant's
  centerline.

`SketchCachedStroke` is the small value type that holds a realized stroke's
prebuilt `Path`s (`fullPath`, `centerPath`, `centerLoop`) alongside its
`RibbonGeometry` (still needed for the entrance's length-based truncation)
and `ghostOffset`.

## Testing & the JS playground relationship

`Packages/SketchKit/Tests/SketchKitTests/SketchKitTests.swift` pins down two
kinds of correctness:

1. **Cross-language golden values** — `SketchRandom`'s output and
   `sketchHash`'s output are checked against exact values generated by
   running the JS reference (`Prototypes/sketch-playground.html`) under
   Node. Exact equality is intentional and meaningful here: both sides do
   32-bit integer ops then divide by 2³², which is *exact* in IEEE 754
   doubles — if these ever mismatch, the Swift port has actually diverged
   from the reference, not just accumulated float error.
2. **Pipeline property tests** — resample keeps endpoints and even spacing;
   wobble is deterministic for a given seed and different for a different
   one, and bounded in displacement; ribbon widths stay within taper/
   variance bounds; `index(atLength:)` is monotonic and clamped; every
   printable-ASCII Hershey glyph survives the full pipeline without
   producing non-finite output; skeleton/realize/entrance-schedule
   invariants (hatch only when pressed, deterministic per variant, etc).

**If you touch anything in `Packages/SketchKit`**, run
`swift test --package-path Packages/SketchKit` before you're done, and if
you changed tuning values or algorithm behavior, update
`Prototypes/sketch-playground.html` to match (or vice versa — tune there
first, then port the numbers back). The two are meant to never drift apart;
that's the entire point of keeping a JS reference around.
