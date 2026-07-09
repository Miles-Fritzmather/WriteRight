# The Hand-Drawn Visual Language

This is the design spec, in prose. Read it before writing or judging any
hand-drawn UI code — it's what "looks right" means for this project. The
technical implementation of every ingredient below lives in
[PIPELINE.md](PIPELINE.md); this file is deliberately code-light.

## The metaphor

Every hand-drawn element on screen is drawn by an imaginary pen, once, in one
continuous take, in the order a hand would actually draw it (outline first,
then label or icon, then fill). It isn't a static vector shape wearing a
"sketchy" filter — it's closer to a looping hand-drawn animation: the line
never sits perfectly still, and when an element first appears, you watch it
get written on rather than having it pop into existence.

## The ingredients

### Wobble
No line is straight or perfectly curved. Every stroke has a slow, smooth
perpendicular waver along its length (a lazy sine-like drift, not jitter), a
smaller tangential waver, and a slight extra nudge at both endpoints — this
last one is what makes corners and stroke joins look hand-placed rather than
mathematically snapped together. Text wobbles noticeably less than shapes
(letters need to stay legible), and small secondary text wobbles less still.

### Boil
The wobble isn't one fixed shape — a small number of slightly-different
wobbly variants of the same stroke are pre-drawn, and the UI quietly cycles
between them a couple of times a second, even while nothing else is
happening. This is the classic hand-drawn-animation "boil": a static shape
that never quite holds still, reading as alive/hand-inked rather than frozen.
It's subtle by design — you should notice the UI feels alive, not that it's
visibly flickering.

### Ink, not vector lines
Every stroke is a filled variable-width ribbon, not a 1-point vector line: it
narrows near both ends (like a pen lifting or landing) and its width drifts
slightly along its length (like real ink flow), rather than holding a
constant caliper width.

### The ghost pass
Borders get a second, fainter line traced just barely offset from the main
one — like sketching over a shape a second time, the way you'd correct or
reinforce a line in a notebook. It uses next moment's boil variant, so the
"second pass" itself is quietly alive too, not a static duplicate.

### Write-on entrance
When an element first appears, it doesn't fade or pop in — it draws itself,
stroke by stroke, at a constant pen speed, with a short pause between
strokes, in natural drawing order (outline, then icon, then label/caption).
Elements in a group (e.g. a whole toolbar) each start their entrance a little
staggered from their neighbors, so the group writes on like a wave rather
than snapping in all at once — but each element's own stagger is always the
same, not re-randomized on every launch.

### Press feedback
Pressing a control squashes it slightly (like paper giving a little under a
thumb) and reveals a diagonal hatch fill underneath — like quickly shading it
in with a pencil — which itself scribbles in over a fraction of a second
rather than appearing instantly. Both effects reverse the moment the press
ends.

### Persistent selection
A control that's in a lasting "on" state — the currently-selected tool, an
enabled toggle — is *not* shown with the momentary press hatch. It gets its
own, persistent version of the same idea: a lighter hatch wash that stays
while selected, plus bolder/fuller-opacity ink on its outline and label. The
distinction matters: press feedback is transient and always fades back;
selection state persists and is drawn every frame while true.

### Color swatches — the crayon
Color swatches aren't flat-filled circles. Each is a hand-drawn ring in the
swatch's own color with a loose inward scribble-spiral filling it, like
coloring in a small circle with a crayon rather than filling a vector shape.
A selected swatch gets one more ink-colored ring drawn loosely around the
outside, like it's been circled to mark it.

### Hand-drawn type
Captions, labels, and button text are not the system font — they're drawn as
single-stroke pen strokes using a bundled vintage engineering/plotter font
(Hershey "futural"), laid out and wobbled through the exact same pipeline as
every other stroke, with the same very-slight per-letter spacing jitter a
hand would introduce. This is deliberate: it means text has the *same* ink
quality as borders and icons, instead of looking like crisp system type
pasted onto a sketchy background — a very common tell that breaks the
illusion in other "hand-drawn style" UIs.

### Hand-drawn icons
Icons are drawn the same way: small (1–3 stroke) polyline pictograms — a
fountain-pen nib, a pencil, a highlighter mid-swipe, a lasso with a trailing
rope — rather than crisp system glyphs. They run through the exact same
wobble/boil pipeline as everything else, at a smaller, less-wobbly setting so
they stay readable at toolbar-icon size.

### Determinism — "hand-drawn," not "random"
Nothing about this is unpredictable from one run to the next. Every element
has a stable identity (a short string like `"tool.Pen"` or `"swatch.blue"`),
and that identity always produces exactly the same family of wobbly variants,
the same entrance timing, the same letter-spacing jitter — on this launch, on
the next launch, on someone else's device. Only *which* pre-drawn variant is
currently showing changes over time (the boil clock); the underlying
geometry never "swims" or reshuffles. This is a hard requirement, not a nice-
to-have — see PIPELINE.md's determinism section for why and how.

### Palette
Ink is a warm near-black (`#2b2723`), not pure black; paper is a warm
off-white (`#f7f2e7`), not pure white. Both are tunable per `SketchStyle`
instance, but the warmth is intentional — it reads as paper and pen, not a
black-on-white UI wireframe.

### Paper texture
The infinite canvas isn't a flat fill of the paper color — it carries a faint
scatter of small specks (darker-beige and warm-gray), like the grain of real
paper stock. The scatter is procedural and **infinite**: it's anchored in
canvas space (glued to the plane, so it pans/zooms/rotates with the ink) and
every region regenerates the same specks deterministically from its
coordinates, so it never tiles, repeats, or stores anything. Because a speck
has a fixed size in canvas space, the texture works across the whole zoom
range by cross-fading two decade-spaced density tiers as you zoom — you
should always see roughly the same on-screen speckle whether zoomed way in or
out, never a bald expanse or a solid wall of dots. It is *texture*, not
decoration: subtle enough that you notice the surface feels like paper, not
that there are dots on it. The reference-grid lines and origin axes are drawn
in the same warm ink as everything else (very low opacity), not a neutral
gray, so the whole surface reads as one warm ink-on-paper world. Unlike the
controls, the paper does **not** boil — the surface is static; only the ink
drawn on it is alive.

## Where it's used, and where it deliberately isn't

The treatment covers the bottom tool toolbar, the library home screen, and —
as of the app-wide pass — the chrome that used to drop to Apple's default UI:

- **Status bar.** The real iOS status bar can't be restyled, so the app hides
  it (`project.yml` `UIStatusBarHidden`) and draws its own: clock, date,
  Wi-Fi, and battery, all ink. Honesty limits — clock and battery
  level/charging are real; Wi-Fi *signal strength* has no public API, so the
  Wi-Fi mark is binary (online → full arcs, offline → slashed).
- **Keyboard.** A full hand-drawn on-screen keyboard (`HandDrawnKeyboard`)
  replaces the system keyboard entirely; text fields in this world
  (`HandDrawnTextField`) are display-only ink with a blinking caret, so the
  system keyboard is never summoned. Keys are the one place we deliberately
  turn the boil *off* (`variants = 1`) — a jittering 30-key grid reads as
  noise, not charm — while keeping press squash + hatch and a write-on entrance.
- **Popups.** Text prompts (rename, new folder) and choosers (the "new
  canvas" page-type picker) are hand-drawn cards over a dim backdrop
  (`HandDrawnPromptConfig` / `HandDrawnChooserConfig`), replacing `.alert` and
  the system `Menu`.

Still on system UI, deliberately or not-yet: the long-press **context menus**
on cards (Rename/Move/Delete) and the **delete confirmation** dialogs — both
are launched from system chrome and haven't been converted; the debug HUD and
any dense utility screens also stay conventional. SPEC.md §7 says to scope the
hand-drawn treatment to where it delights first and let dense utility/debug
surfaces stay conventional longer — so don't hand-draw something just because
you can; check whether it's one of the places this project wants it.

Two calm-on-purpose exceptions worth remembering when judging "does it look
right": **text you read doesn't boil** — the keyboard keys, the status strip,
and text-field contents render a single static wobble variant, because motion
on a reading surface reads as broken rather than alive. Boil is for chrome you
act on (buttons, cards, tool icons), not for surfaces you parse.

## Live reference

`Prototypes/sketch-playground.html` is a standalone, dependency-free HTML/JS
page that renders the exact same algorithm live in a browser, with sliders
for every `SketchStyle` parameter. If you're unsure whether something "still
looks right," or want to explore a new parameter value before touching
Swift, open that file — it's the fastest way to see the effect of a change,
and it's the tuning tool the current defaults were locked in from.

## Glossary — design term → code

| What you'd call it | Swift symbol | Where |
|---|---|---|
| Wobble | `wobble(_:amplitude:wavelength:jitter:rng:)` | `Packages/SketchKit/Sources/SketchKit/SketchGeometry.swift` |
| Boil | `SketchStyle.boilFps`, `.variants`; the variant-picking logic in `SketchElementView.draw` | `SketchGeometry.swift`; `App/Sources/HandDrawnTheme.swift` |
| Ink ribbon | `ribbon(around:baseWidth:widthVariance:taper:rng:)` → `RibbonGeometry` | `SketchGeometry.swift` |
| Ghost pass | `SketchStyle.ghost` / `.ghostAlpha` / `.ghostOffset`; drawn in `SketchElementView.draw` | `SketchStyle.swift`; `HandDrawnTheme.swift` |
| Write-on entrance | `EntranceSchedule` | `Packages/SketchKit/Sources/SketchKit/SketchRealizer.swift` |
| Press squash + hatch | `SketchStyle.pressSquash` / `.pressWidthMultiplier`; `hatchStrokes(in:spacing:)` | `SketchStyle.swift`; `Packages/SketchKit/Sources/SketchKit/Skeletons.swift` |
| Persistent selection wash | `revision` parameter + `.hatch`-kind strokes appended when `isSelected` | `HandDrawnTheme.swift` (`iconButton`, `colorSwatch`, `toggle`) |
| Crayon swatch | `ringPoints`, `spiralPoints` | `HandDrawnTheme.swift` |
| Hand-drawn type | `HersheyFont`, `textStrokes(_:size:centerX:centerY:rng:)` | `Packages/SketchKit/Sources/SketchKit/HersheyFont.swift` |
| Hand-drawn icons | `SketchIconLibrary` | `App/Sources/SketchIcons.swift` |
| Paper texture | `drawPaperFlecks` / `drawFleckTier`, `PaperFleck` constants | `App/Sources/CanvasPrototypeUIView.swift` |
| Determinism | `SketchRandom`, `sketchHash(_:_:_:)`, `sketchSeed(_:)` | `Packages/SketchKit/Sources/SketchKit/SketchRandom.swift`; `App/Sources/SketchSwiftUIBridge.swift` |
