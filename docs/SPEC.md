# Palimpsest — Design & Build Specification

> A native iPadOS handwritten-note app. Working codename **Palimpsest** (rename at will).
> This document is written to be handed to an LLM coding agent. Build **phase by phase**, in order. Do not skip ahead. Each phase has explicit acceptance criteria — treat a phase as done only when all criteria pass. If a requirement here conflicts with something you discover while building, stop and surface the conflict rather than guessing.

---

## 0. How to use this document (instructions for the build agent)

- Target the phases in `§8` sequentially. Phase 0 is a throwaway prototype that de-risks the hardest assumption; build it first and confirm it feels right before proceeding.
- Prefer small, compiling increments. After each phase, the app should build and run.
- Respect the coordinate-space discipline in `§5` — most canvas bugs come from mixing screen and canvas coordinates. Use the branded point types provided.
- Build all UI against the **design-system abstraction** in `§7`, not against raw SwiftUI controls. During early phases the abstraction is backed by plain system controls; later it is swapped for hand-drawn rendering with zero changes to feature code.
- Ask before introducing new third-party dependencies beyond those listed in `§3`.
- **Before scaffolding, read `§11`.** The project is built outside Xcode as SwiftPM logic modules plus a thin generated app shell, with on-device hot reload. Set it up that way from the start rather than as a monolithic Xcode project.

---

## 1. Product summary

A note-taking app for students and heavy note-takers, iPad-first, built around an infinite **rotatable** canvas with deep Apple Pencil integration and free on-device AI. The long-term visual identity is a fully **hand-drawn aesthetic** — ink-on-paper UI, not a skin over standard controls — inspired by the app *grug* (Ocho studio), which renders its entire interface through a custom stroke engine. Because this app is *already* a stroke-rendering engine, the same ink pipeline that draws notes will eventually draw the UI itself, including **user-drawn custom icons**.

### Core differentiators
1. Deep Apple Pencil integration — custom radial/popup tool menu, double-tap and squeeze (Pencil Pro) quick actions, hover preview.
2. Infinite, rotatable canvas — pan / zoom / rotate over an unbounded plane; ink stays crisp and hit-testing correct at any orientation.
3. Export / import — PDF in and out (searchable text layer), plus a native bundle format.
4. Hand-drawn UI — eventually every control rendered as ink; users can draw their own icons.
5. On-device AI — handwriting search, auto-tagging, summarization, Q&A; local, private, free.

### Non-goals (v1)
Android/web, real-time multi-device collaboration, interop with competitors' proprietary formats.

---

## 2. Platform & constraints

- **iPadOS 26+** (required for the Foundation Models framework).
- **Swift 6**, **Xcode 26**, strict concurrency enabled.
- Apple-Intelligence-capable device required for semantic AI features; the app must **degrade gracefully** when Foundation Models is unavailable (recognition and all core features still work; AI features hidden or disabled with a clear message).
- Portrait and landscape; primary form factor is iPad with Apple Pencil (Pro or 2nd-gen preferred for hover/squeeze).

---

## 3. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| App shell / UI | SwiftUI | Screens, navigation, chrome |
| Canvas host | UIKit via `UIViewRepresentable` | View-level touch + transform control |
| Live ink | PencilKit (`PKCanvasView`) | Low-latency predictive stroke rendering |
| Committed rendering | Core Graphics / `CATiledLayer` first, migrate hot paths to **Metal** if profiling requires | Don't start with Metal; earn it |
| Persistence | **GRDB** (SQLite) | R-tree spatial index + FTS5 full-text; WAL mode |
| Handwriting OCR | Vision (`RecognizeTextRequest`, `RecognizeDocumentsRequest`) | On-device, free |
| Semantic AI | Foundation Models framework | On-device ~3B LLM; `@Generable` structured output; `contentTagging` use case |
| PDF | PDFKit / `UIGraphicsPDFRenderer` | Import backgrounds, export with text layer |
| Sync (later) | CloudKit | Per-stroke records keyed by UUID |

Only add dependencies beyond GRDB with explicit approval.

---

## 4. Architecture — six layers + design system

```
┌──────────────────────────────────────────────┐
│  Note app — iPadOS                             │
│  1. Input & Pencil   (PencilKit, interactions) │
│  2. Canvas & camera  (affine transform)        │
│  3. Data model & store  ← HUB (SQLite)         │
│  4. Rendering        (tiled, cached)           │
│  5. AI & indexing    (Vision, Foundation Models)│
│  6. Export/import/sync (PDFKit, CloudKit)      │
│                                                │
│  Design system (§7) — cross-cutting; every UI  │
│  primitive resolves through the active theme   │
└──────────────────────────────────────────────┘
```

Layer 3 is the hub: layers 1–2 write strokes into it, layer 4 reads from it, layer 5 reads pages out and writes recognized text + tags back in.

### Suggested module / group layout
```
Palimpsest/
  App/            App entry, root scene, navigation
  Model/          Stroke, Page, Section, Notebook, ToolStyle, coordinate types
  Canvas/         CanvasView (UIViewRepresentable), Camera, gestures, coordinate conversion
  Ink/            PencilKit bridge (live layer), committed renderer, TileManager
  Store/          GRDB setup, migrations, repositories, R-tree + FTS5 queries
  AI/             Vision OCR pipeline, FoundationModels services, semantic index
  ExportImport/   PDF export/import, native bundle (.palimpsest)
  DesignSystem/   Theme protocol, SystemTheme, HandDrawnTheme, UI primitives, Icon system
  Sync/           (later) CloudKit
```

---

## 5. Coordinate-space discipline (read before writing canvas code)

Two coordinate spaces exist and must never be confused:
- **Canvas space** — the infinite plane. All strokes are stored here.
- **Screen space** — points as they appear on the device, after the camera transform.

Use branded types so the compiler catches mix-ups:

```swift
struct CanvasPoint { var x: Double; var y: Double }
struct ScreenPoint { var x: Double; var y: Double }
```

The camera is a single affine transform. Rotation is *never* applied to stored data — only to the camera.

```swift
struct Camera {
    var translation: CGVector = .zero
    var scale: CGFloat = 1
    var rotation: CGFloat = 0   // radians

    // Order: translate → scale → rotate. Verify empirically in Phase 0.
    var transform: CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: translation.dx, y: translation.dy)
            .scaledBy(x: scale, y: scale)
            .rotated(by: rotation)
    }

    func toScreen(_ p: CanvasPoint) -> ScreenPoint {
        let t = CGPoint(x: p.x, y: p.y).applying(transform)
        return ScreenPoint(x: t.x, y: t.y)
    }
    func toCanvas(_ p: ScreenPoint) -> CanvasPoint {
        let t = CGPoint(x: p.x, y: p.y).applying(transform.inverted())
        return CanvasPoint(x: t.x, y: t.y)
    }
}
```

**Rule:** every incoming Pencil sample is converted to canvas space via `toCanvas` at capture time and stored that way. Every render converts back via `toScreen`. Hit-testing (eraser, selection) inverts identically. If ink lands in the wrong place after rotating, the bug is a coordinate-space violation, not a transform-math error — check capture first.

---

## 6. Data model

```swift
struct SamplePoint {          // one Pencil sample, canvas space
    var point: CanvasPoint
    var pressure: Float
    var altitude: Float
    var azimuth: Float
    var timestamp: TimeInterval
}

struct ToolStyle {
    enum Kind { case pen, marker, pencil, eraser }
    var kind: Kind
    var colorHex: String
    var width: Double
    var blend: BlendMode
}

struct Stroke: Identifiable, Codable {
    let id: UUID
    var pageID: UUID
    var points: [SamplePoint]     // ordered, canvas space
    var tool: ToolStyle
    var boundingBox: CGRect       // canvas space; cached; indexed in R-tree
}

enum PageBackground: Codable { case blank, ruled, grid, pdfPage(pdfID: UUID, index: Int) }

struct Page: Identifiable, Codable {
    let id: UUID
    var sectionID: UUID
    var background: PageBackground
    var objectIDs: [UUID]         // images, text boxes, shapes
}

struct Section: Identifiable, Codable { let id: UUID; var notebookID: UUID; var title: String; var order: Int }
struct Notebook: Identifiable, Codable { let id: UUID; var title: String; var createdAt: Date }
```

Recognized text is a **separate table** keyed by `pageID`, each row carrying its canvas-space bounding box so a search hit can pan the camera to the exact spot:

```swift
struct RecognizedText { let id: UUID; var pageID: UUID; var text: String; var box: CGRect }
```

### Storage requirements
- SQLite via GRDB, **WAL mode**.
- **R-tree** virtual table over stroke bounding boxes → fast viewport queries (`strokes intersecting rect`).
- **FTS5** table over `RecognizedText.text` → instant search.
- Every entity has a stable UUID (required for undo and future sync).
- Native document format `.palimpsest` = the SQLite database (optionally zipped with imported PDF assets).

---

## 7. Design system (system controls now → hand-drawn later)

This is the mechanism that lets us build with default controls today and swap in hand-drawn designs later **without touching feature code**. Set it up in Phase 1.

Every UI primitive resolves through an active `Theme`. Feature code calls `AppButton`, `AppIcon`, `AppToggle`, etc. — never raw `Button`/`Image`.

```swift
protocol Theme {
    func button(_ label: String, action: @escaping () -> Void) -> AnyView
    func icon(_ source: IconSource, size: CGFloat) -> AnyView
    func toggle(_ isOn: Binding<Bool>, label: String) -> AnyView
    // extend as primitives are needed
}

struct SystemTheme: Theme { /* thin wrappers over stock SwiftUI controls */ }
struct HandDrawnTheme: Theme { /* renders each primitive through the ink renderer (Phase 8) */ }
```

Inject via environment; a single setting flips the whole app:

```swift
@Entry var theme: Theme = SystemTheme()   // becomes HandDrawnTheme() later
```

### Icons — including user-drawn (the "draw your own icons" feature)
Icons are just small stroke drawings rendered through the same ink pipeline as notes. This unifies built-in and user-created icons:

```swift
enum IconSource {
    case builtIn(name: String)      // bundled hand-drawn stroke asset
    case userDrawn(strokeSetID: UUID)   // strokes drawn by the user, stored in the DB
    case systemSymbol(String)       // SF Symbol fallback for early phases
}
```

- A `DrawIconView` presents a small bounded canvas (reuse the core ink capture) where the user draws an icon. The result is a set of `Stroke`s saved to the store and referenced by `IconSource.userDrawn`.
- Anywhere an icon appears (tool menu, tabs, notebook covers), it accepts an `IconSource`, so a user-drawn icon can replace any built-in one.
- Early phases use `.systemSymbol` (SF Symbols) so the UI is functional before hand-drawn assets exist.

Design intent: the app's chrome and the user's notes share one hand-drawn visual language, rendered by one engine. Scope the hand-drawn treatment to where it delights (canvas, tool menus, key screens, icons) first; dense utility screens can stay conventional longer.

---

## 8. Build phases (each with acceptance criteria)

### Phase 0 — Canvas & camera prototype *(throwaway, de-risk first)*
Build a single screen: a `UIViewRepresentable` canvas that captures Apple Pencil strokes into canvas space and lets you pan (one/two-finger), zoom (pinch), and **rotate** (two-finger twist) the camera.
- **Done when:** strokes stay correctly positioned and crisp through pan/zoom/rotate; drawing *while rotated* lands ink at the correct canvas location; `toCanvas`/`toScreen` round-trip is exact.

### Phase 1 — Ink capture, tools, undo, design-system scaffold
Real stroke capture with coalesced + predicted touches; pen/marker/pencil/eraser with color + width; PencilKit live layer commits finished strokes to the model; undo/redo. Stand up the `Theme` abstraction (`§7`) backed by `SystemTheme`; build the tool menu against `AppButton`/`AppIcon` using SF Symbols.
- **Done when:** all four tools work; finished strokes persist in the in-memory model; undo/redo works; all UI goes through the theme abstraction.

### Phase 2 — Persistence (SQLite)
GRDB store with migrations for Notebook/Section/Page/Stroke; WAL mode; R-tree over stroke bounding boxes; save/load.
- **Done when:** strokes and structure survive relaunch; R-tree viewport query returns exactly the visible strokes; relaunch restores the exact canvas state.

### Phase 3 — Tiled rendering & performance
Tile the canvas; cull to viewport via R-tree; cache committed tiles as textures/images; re-render a tile only when its strokes change.
- **Done when:** a 10,000-stroke document pans/zooms/rotates smoothly (target 120fps on ProMotion); memory stays bounded while scrolling a large canvas.

### Phase 4 — Pages, backgrounds, PDF import
Multi-page notebooks; blank/ruled/grid backgrounds; import a PDF and use its pages as annotatable backgrounds (PDFKit).
- **Done when:** create/reorder pages and sections; switch backgrounds; import a PDF and draw on top of its pages.

### Phase 5 — Export
Export a notebook to PDF via PDFKit, rendering background + strokes per page.
- **Done when:** exported PDF visually matches the notebook; (text layer added in Phase 6).

### Phase 6 — Handwriting OCR & search
Background Vision recognition over rasterized page regions; store recognized text with canvas-space boxes; FTS5 search UI; tap a result to pan the camera to the location. Embed recognized text as an invisible layer in PDF export.
- **Done when:** searching handwritten notes returns results; tapping a result jumps to the spot; exported PDFs are text-searchable.

### Phase 7 — On-device AI (Foundation Models)
Availability check with graceful degradation. Features: summarize a page/notebook; auto-tag pages (`contentTagging`); Q&A over a notebook's recognized text. Use `@Generable` for structured outputs (e.g., extracted action items).
- **Done when:** each feature works on-device on a capable device and is cleanly hidden/disabled on an incapable one.

### Phase 8 — Hand-drawn design system & custom icons
Implement `HandDrawnTheme` rendering primitives through the ink renderer; add bundled hand-drawn icon assets; build `DrawIconView` so users can draw and save custom icons; wire `IconSource.userDrawn` through the icon system. Add a setting to switch themes.
- **Done when:** flipping the theme flag swaps the whole UI to hand-drawn with no feature-code changes; a user can draw a custom icon and use it in the tool menu.

> **De-risk note (2026-07-07, approved by Miles):** the hand-drawn rendering
> engine was prototyped ahead of order, Phase 0-style, to prove the look was
> achievable: `Packages/SketchKit` implements the deterministic
> wobble → boil → ink-ribbon → scribble pipeline (parameters tuned in
> `Prototypes/sketch-playground.html`, kept as the reference implementation),
> and a single demo button runs behind the Phase 0 HUD's "Sketch demo" button.
> Phase 8 remains the phase where `HandDrawnTheme` is built on top of
> SketchKit and wired through `§7`; nothing else was pulled forward.
>
> **De-risk note, part 2 (2026-07-08, approved by Miles):** the prototype
> toolbar and main library screen were moved onto the hand-drawn look ahead
> of order, exercising `§7` exactly as designed: a partial `HandDrawnTheme`
> implements the needed Theme primitives via SketchKit (boil, write-on
> entrance, ghost pass, press squash + hatch), bundled hand-drawn icons ship
> as stroke skeletons behind `IconSource.builtIn(name:fallbackSymbol:)`, and
> the theme is scoped through the environment — feature code and phase order
> are otherwise unchanged. Phase 8 still owns the theme-flip setting,
> user-drawn icons (`DrawIconView`), and whole-app hand-drawn coverage.

### Phase 9+ — Polish & CloudKit sync
Daily-driver reliability; then CloudKit with per-stroke records keyed by UUID (last-writer-wins at stroke granularity to start).

---

## 9. Coding conventions

- Swift 6 strict concurrency; `async`/`await`; `@Observable` for view models.
- Protocol-oriented boundaries for `Theme` and the store (repository protocols) to keep layers swappable and testable.
- No force-unwraps on production paths; model absence explicitly.
- Keep canvas/screen coordinates in their branded types until the last possible moment.
- Strokes are always stored in canvas space. Never persist screen-space geometry.
- Unit-test the coordinate transforms and the R-tree viewport query; snapshot-test rendering where practical.

---

## 10. Risks & guidance

- **The canvas is the hard part.** Tiling + rotation + crisp ink + correct hit-testing is the real engineering; everything else is standard app plumbing. Phase 0 exists to prove it early.
- **Ink latency is sacred.** Keep the live PencilKit layer in the hot path; commit to the tiled renderer off the critical path.
- **On-device AI has a ceiling.** The ~3B model is excellent at shaping recognized text (summaries, tags, extraction) and weak on world knowledge / long documents. Scope AI features accordingly; a cloud model can be added later behind the same interface if needed, reintroducing cost/privacy tradeoffs.
- **Don't start with Metal.** Prove the architecture with Core Graphics / `CATiledLayer`; migrate only the hot paths to Metal when profiling demands it.

---

## 11. Development environment & toolchain

This project is developed **outside Xcode** — in Cursor / VS Code with Claude Code — with Xcode installed only as the background toolchain (SDKs, simulators, code signing, `xcodebuild`, `sourcekit-lsp`). Scaffold to fit this workflow from the start.

### Project structure: SwiftPM modules + thin app shell
- Put pure-logic layers (`Model`, `Store`, `Camera`/coordinate math, `AI` services) in **Swift Package Manager modules** under `Packages/`. These get first-class SourceKit-LSP, unit testing, and agent tooling with zero Xcode-project involvement.
- Keep the app target a **thin shell** containing only what needs the app bundle: the SwiftUI screens, the PencilKit/Metal canvas host, and entitlements. It depends on the packages.
- Define the app project in text via **XcodeGen** (`project.yml`) or **Tuist** (Swift manifests) and generate the `.xcodeproj`. Never hand-edit `.pbxproj`. Regenerate after adding targets/files.

Suggested top-level layout:
```
Palimpsest/
  Packages/
    Model/        SwiftPM  — Stroke, Page, coordinate types
    Store/        SwiftPM  — GRDB, R-tree, FTS5, repositories
    CanvasCore/   SwiftPM  — Camera transform, tiling math (UI-agnostic)
    AI/           SwiftPM  — Vision + FoundationModels services
  App/            thin app target (SwiftUI + PencilKit/Metal host + entitlements)
  project.yml     XcodeGen spec (or Tuist manifests)
  buildServer.json  generated by xcode-build-server
```

### Toolchain / editor setup
- Editor: Cursor or VS Code; Claude Code in the terminal for agentic work.
- Extensions: **SweetPad** (build / run / debug / test to simulator and device from the sidebar), the official **Swift** extension (`swiftlang.swift-vscode`, SourceKit-LSP language features), **CodeLLDB** (debugging). A pre-wired "Swift Cursor/VS Code extension pack" bundles these.
- Homebrew: `xcode-build-server`, `xcbeautify`, `swift-format`.
- **xcode-build-server** generates `buildServer.json` so SourceKit-LSP understands the app target's build settings — required for full-project completion/diagnostics on an app (packages work without it). SweetPad wires this up.
- Build, run, debug, and device/simulator log streaming go through SweetPad. The standalone `sweetpad` CLI emits JSON and is the interface for Claude Code / scripts / CI.

### On-device iteration & hot reload (critical for Pencil work)
- The iOS **Simulator cannot simulate Apple Pencil** — no pressure, tilt, azimuth, hover, or squeeze. All Pencil, ink, and canvas work must run on a **physical iPad**. Sequence the canvas/ink/tool-menu phases to develop on-device.
- Deploy to the physical iPad from SweetPad (build & run to a connected device). This is the primary loop — the real app on real hardware, not simulator-only.
- Add **hot reloading** to avoid rebuild-redeploy on every edit: use **Inject** (`krzysztofzablocki/Inject`) with **InjectionNext** (or InjectionIII). Steps: add the package; add `-Xlinker -interposable` to the Debug target's Other Linker Flags; load the injection bundle at startup under `#if DEBUG`; per SwiftUI view add `@ObserveInjection var inject` + `.enableInjection()` (NO-OP in release). Injection supports **real devices** (enable device unlock in the InjectionIII app; app and Mac connect over the local network). Works from Cursor/VS Code — no Xcode required.
- Result: edit stroke rendering, pressure curves, gesture params, hand-drawn UI, or colors and see it live on the iPad while drawing, without losing app state. Structural changes (new types, changed signatures/storage) need a rebuild — a one-keystroke SweetPad run to the device.

### Where you still open Xcode (occasionally)
- **Signing & capabilities** — enabling entitlements (Foundation Models, CloudKit) is a one-time GUI convenience.
- **Instruments** — profiling the tiled renderer (Phase 3) is Xcode-only; open it for the session, then return to Cursor.
- **SwiftUI Previews** are unavailable in Cursor; on-device hot reload via Inject replaces them.
