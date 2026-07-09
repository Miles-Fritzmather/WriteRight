# WriteRight (spec codename “Palimpsest”)

iPadOS 26+ handwritten-note app: infinite rotatable canvas, Apple Pencil, on-device AI,
eventually a fully hand-drawn UI. The authoritative build plan is **docs/SPEC.md** —
build **phase by phase** (SPEC §8), never skipping ahead; a phase is done only when its
acceptance criteria pass. If reality conflicts with the spec, stop and surface it.

## Phase status
- [x] **Phase 0 — canvas & camera prototype** (built 2026-07-07; compiles, transform
  tests green; awaiting Miles's on-device “feels right” confirmation before Phase 1)
- [ ] Phase 1 — ink capture, tools, undo, Theme scaffold
- [ ] Phase 2 — persistence (GRDB, R-tree)
- [ ] Phase 3 — tiled rendering & performance
- [ ] Phases 4–9 — see SPEC §8
- **Phase 8 de-risk (2026-07-07, Miles-approved out-of-order work):** the hand-drawn
  UI engine (wobble/boil/scribble, grug-style) was prototyped early:
  `Packages/SketchKit` + `SketchDemoScreen` ("Sketch demo" HUD button) +
  `Prototypes/sketch-playground.html` (reference implementation & tuning tool — keep
  in sync with SketchKit). Tuned parameters live as `SketchStyle` defaults. Phase
  order otherwise unchanged; Phase 8 builds `HandDrawnTheme` on top of SketchKit.
- **Phase 8 de-risk, part 2 (2026-07-08, Miles-approved):** the prototype toolbar now
  renders through a partial `HandDrawnTheme` (`App/Sources/HandDrawnTheme.swift` —
  `SketchElementView` boil/entrance renderer + all Theme primitives) with hand-drawn
  tool icons (`SketchIcons.swift`, `IconSource.builtIn`), scoped to the toolbar via
  `.environment(\.theme, …)` in `PrototypeEditorScreen`. `SystemTheme` stays the app
  default. Still Phase 8's to do: theme-flip setting, user-drawn icons, whole-app
  coverage. Full documentation set (style language, SketchKit pipeline reference,
  cookbook for extending it): **`docs/hand-drawn/README.md`**.
- **Home-screen format mockup (2026-07-08, Miles-requested, not in SPEC):** a library
  home page (`PrototypeHomeScreen` + `PrototypeLibraryModel` + `PrototypeEditorScreen`)
  is now the app root — note grid with real-ink thumbnails, one-level folders
  (`folders.json` beside the note files, `folderID` on `PrototypeNoteDocument`),
  create/rename/move/delete via context menus, canvas presented full screen with
  save-on-close. **Deliberately plain SwiftUI, not themed** — it exists to validate
  the format; once Miles approves it, spec it and rebuild in the hand-drawn style.
- **Diegetic UI, first cut (2026-07-09, Miles-approved out-of-SPEC):** the home
  page is now a pen-driven "desk" — the eraser deletes a card, the lasso grabs a
  note and drops it into a folder, and the drawing tools leave real ink on folder
  icons. Pencil = tools, finger = navigate (tap-to-open/scroll unchanged);
  destructive gestures commit immediately with a hand-drawn **undo ribbon**. This
  **replaced** the home page's popup action system (long-press action menu, move
  chooser, delete confirmation — all deleted from `HandDrawnPopups.swift`; the
  rename/new-folder prompt + new-note chooser stay, since text/creation has no pen
  gesture yet). New code: `DiegeticInteraction.swift` (pure core + classifier),
  `DiegeticInputSurface.swift` (pencil-only UIKit capture), `PrototypeHomeTool*`.
  Four locked design decisions + full architecture, gesture map, persistence
  seam, and extension guide: **`docs/diegetic-ui/README.md`**. Simulator can't
  test pen input — needs a physical iPad. Goal (SPEC §7/Phase 8) is to extend
  this to every screen.

## Iron rules
- **Coordinate discipline (SPEC §5):** strokes live in canvas space only, converted via
  `Camera.toCanvas` at capture time; branded `CanvasPoint`/`ScreenPoint` until the last
  possible moment; rotation applies to the camera, never to stored data.
- From Phase 1 on, all UI goes through the `Theme` abstraction (SPEC §7) — no raw
  `Button`/`Image` in feature code.
- Dependencies allowed without asking: GRDB, Inject, XcodeGen. Anything else needs
  Miles's explicit approval first.
- Swift 6 strict concurrency; `@Observable` view models; no force-unwraps on
  production paths.

## Layout
- `Packages/Model` — branded coordinate types (Stroke/Page/etc. arrive Phase 1).
- `Packages/CanvasCore` — `Camera` transform + gesture math; unit-tested; UI-agnostic.
  Store and AI packages get added in Phases 2 and 6/7.
- `Packages/SketchKit` — hand-drawn UI geometry engine (Phase 8 de-risk): deterministic
  wobble/boil/scribble/ink-ribbon pipeline + embedded Hershey stroke font; UI-agnostic;
  RNG must stay bit-identical to the JS reference (golden-value tests).
- `Prototypes/` — browser-based reference implementations / tuning tools (currently
  the sketch playground). Not part of any build target.
- `App/Sources` — thin app shell (SwiftUI + UIKit canvas host). Phase 0's prototype
  files are prefixed `Prototype`/`CanvasPrototype` and are throwaway by design.
- `_legacy/Palimpsest-monolith` — last session's pre-spec monolithic app, kept only as
  reference (PDF export/import, Vision OCR, GRDB patterns). Never build or extend it.

## Build & test
- The `.xcodeproj` is **generated, git-ignored, never hand-edited**. After adding
  files/targets: `xcodegen generate`.
- Logic tests run on the Mac host, no simulator needed:
  `swift test --package-path Packages/CanvasCore` (likewise `Packages/SketchKit`)
- App build (simulator):
  `xcodebuild -project WriteRight.xcodeproj -scheme WriteRight -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build`
- Smoke-run in a simulator: boot an iOS 26.x iPad from `xcrun simctl list devices`,
  `simctl install` + `simctl launch` + `simctl io booted screenshot`.
- **Pencil work needs a physical iPad** — the simulator has no pressure/tilt/hover.
  Device runs go through SweetPad (VS Code/Cursor). Signing: no DEVELOPMENT_TEAM is
  set yet; first device deploy needs one (one-time Xcode signing setup, SPEC §11).
- Hot reload is wired (Inject package, Debug-only, `-Xlinker -interposable`); it's a
  no-op until the InjectionIII/InjectionNext Mac app is installed and running.
