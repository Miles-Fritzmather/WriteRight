# Hand-Drawn UI Style — Documentation Set

This is the handoff package for WriteRight's hand-drawn UI treatment: what it's
supposed to look like, how it's actually built, and how to extend it without
breaking its rules. It assumes no prior context on this codebase.

## The one thing to internalize first

This app renders every piece of UI through a `Theme` protocol
(`App/Sources/Theme.swift`), per **SPEC.md §7**. Feature code never writes raw
`Button` / `Image` / `Circle` styling — it calls `AppButton`, `AppIcon`,
`AppIconButton`, `AppColorSwatch`, `AppToggle`, `AppToolbarContainer`,
`AppLabel`, `AppDivider`, and those resolve through whichever `Theme` is active
in the environment. Two themes exist:

- **`SystemTheme`** — thin wrappers over stock SwiftUI controls. The app default.
- **`HandDrawnTheme`** — every primitive rendered through a deterministic
  wobble → boil → ink-ribbon pipeline (package `SketchKit`), giving the whole
  UI a hand-lettered, slightly-alive sketchbook look.

**If you're asked to make some UI "hand-drawn," you are almost never writing
new drawing code.** You're either (a) using an existing `Theme` primitive that
already renders correctly in `HandDrawnTheme`, or (b) adding a new primitive to
the `Theme` protocol and implementing it in both themes. Raw `Canvas`/`Path`
drawing in feature code is the exception, reserved for one-off bespoke screens
(see COOKBOOK.md, Recipe 3) — not the default path.

## Reading order

1. **[STYLE.md](STYLE.md)** — the visual language in plain terms: what makes
   it read as "hand-drawn," ingredient by ingredient. Read this first even if
   you're only going to touch code — it's the spec for what "correct" looks
   like.
2. **[PIPELINE.md](PIPELINE.md)** — the technical reference: the `SketchKit`
   package's geometry pipeline, every type and function, the determinism
   scheme, and the SwiftUI renderer (`SketchElementView`) that drives it.
3. **[COOKBOOK.md](COOKBOOK.md)** — task-oriented recipes: add a new themed
   control, add an icon, build a bespoke animated screen, tune proportions,
   the gotchas that will bite you, and the exact commands to verify a change.

## Where this is live today

| Where | What | Theme |
|---|---|---|
| Bottom tool toolbar (`App/Sources/PrototypeToolToolbar.swift`) | Tool buttons, color swatches, palette labels, dividers, container chrome | `HandDrawnTheme`, scoped via `.environment(\.theme, HandDrawnTheme())` in `App/Sources/RootView.swift` |
| "Sketch demo" screen (`App/Sources/SketchDemoScreen.swift`) | Full pipeline showcase: a boiling/scribbling button with press counter and spark bursts | Bespoke — not a `Theme` primitive, hand-rolled `Canvas` render loop (see COOKBOOK.md Recipe 3) |
| Everything else (debug HUD, etc.) | `SystemTheme` | Deliberate — SPEC §7 says to scope hand-drawn treatment to where it delights first; dense debug/utility UI stays conventional |

## Key files

| File | Role |
|---|---|
| `Packages/SketchKit/Sources/SketchKit/*.swift` | Pure, UI-agnostic geometry engine — wobble, ink ribbon, skeletons, the Hershey stroke font, RNG. No SwiftUI import. Unit-tested with golden values ported from the JS reference. |
| `Prototypes/sketch-playground.html` | Interactive HTML/JS reference implementation and tuning tool. This is where new parameters get explored (instant feedback, no Xcode rebuild) before being ported to `SketchStyle`'s Swift defaults. Keep it in sync. |
| `App/Sources/SketchSwiftUIBridge.swift` | The only place `SketchKit` geometry touches `SwiftUI.Path` / `Color` — `Path(polygon:)`, `Path(polyline:)`, `Color(hex:)`, and `sketchSeed(_:)`. |
| `App/Sources/HandDrawnTheme.swift` | The theme itself: every `Theme` method, plus `SketchElementView` (the generic boiling/scribbling renderer every primitive is built from). |
| `App/Sources/SketchIcons.swift` | Bundled hand-drawn icon skeletons (pen, pencil, marker, highlighter, eraser, lasso), authored as polylines in a 24×24 box. |
| `App/Sources/Theme.swift` | The `Theme` protocol, `IconSource`, `SystemTheme`, and the `App*` wrapper views feature code actually calls. |
| `App/Sources/SketchDemoScreen.swift` | The original de-risk prototype and still the most complete single example of the render loop (entrance, boil, press, plus effects `HandDrawnTheme` doesn't need: press counters, spark bursts). |

## Phase status (don't skip this)

This app is built phase-by-phase per `docs/SPEC.md` §8, and the hand-drawn
system is formally **Phase 8** work. It has been pulled forward twice, each
time with explicit approval, each time recorded as a de-risk note in
`docs/SPEC.md` §8 and `CLAUDE.md`'s "Phase status": once to prove the engine
itself (`SketchKit` + the demo screen), once to move the toolbar onto it. If
you're asked to extend the hand-drawn treatment further, **that's normal and
consistent with how this project has been run** — but say so explicitly in
whatever record-of-work this project keeps, the way the existing notes do, and
check `CLAUDE.md` first in case the phase status has moved on since this was
written.

Still explicitly unbuilt (real Phase 8 scope, not yet started):
- A setting that flips the whole app between `SystemTheme` and `HandDrawnTheme`.
- `DrawIconView` — a small canvas where a user draws and saves their own icon,
  stored as strokes and referenced via `IconSource.userDrawn` (declared in
  spec, not yet added to the `IconSource` enum in code).
- Whole-app hand-drawn coverage — today it's the toolbar only.
