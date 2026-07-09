# Diegetic UI — the pen *is* the cursor

> Status: **first cut, home page only** (built 2026-07-09, Miles-approved
> out-of-spec work — not yet a SPEC phase). Prototype-grade, throwaway like the
> rest of the `Prototype*` surface. This document is the design contract for
> extending it.

## The vision

WriteRight's UI is **diegetic**: everything is a piece of paper on a desk, and
you manipulate it the way you'd manipulate real paper with a pen. There is no
separate "chrome" mode. The pen, eraser, and lasso you draw notes with are the
*same* tools you use to run the app:

- **Erase a note** → it's deleted.
- **Lasso a note and drag it onto a folder** → it moves into that folder.
- **Draw on a folder** → your marks stay on the icon, giving it a custom look/color.

The eventual goal (SPEC §7, Phase 8) is that *every* screen works this way. This
first cut replaces the home page's old popup-driven action system (long-press →
action menu → rename/move/delete; move chooser; delete confirmation) with direct
pen manipulation. **The popups it replaced are gone** — the action menu, move
chooser, and delete confirmation were deleted from `HandDrawnPopups.swift`.

## The four locked decisions (2026-07-09, from Miles)

These are settled. Don't relitigate them without asking; do build on them.

1. **Input split — Pencil = tools, finger = navigate.** The pen surface claims
   *only* Apple Pencil touches. Finger scrolls the grid and taps a note to open
   it, exactly as before. The app stays fully usable without a pencil (finger +
   the retained rename/create prompts).
2. **Ink is transient now, but modeled for persistence.** A pen stroke is read
   as a *command* and then fades. Nothing free-drawn is stored **yet** — except
   folder decorations (decision 3), which are real stored ink. The data types
   are shaped so persistent "desk doodles" can be layered in later without a
   rewrite. See [Persistence seam](#persistence-seam).
3. **Recolor keeps the actual scribble.** Drawing on a folder does *not* flatten
   to a single tint — it stores the real strokes (`DiegeticFolderMark`) and
   renders them on the icon, in whatever ink color is active.
4. **Erase deletes immediately + an undo ribbon.** No modal. Destructive pen
   gestures commit instantly; a hand-drawn "Undo" ribbon slides up as the safety
   net and auto-retires after ~6s.

## Interaction map (what's wired today)

**Finger** (passes straight through the pen surface):
| Gesture | Result |
|---|---|
| Tap a note | Open the canvas editor |
| Tap a folder | Navigate into it |
| Long-press a note/folder | Rename prompt (hand-drawn keyboard) |
| Tap New Note / New Folder | Create (chooser / name prompt) |
| Drag | Scroll |
| Tap the undo ribbon's Undo | Reverse the last pen action |

**Apple Pencil** (active tool from the bottom palette — default is **Select**):
| Tool | On a note | On a folder | On the bare desk |
|---|---|---|---|
| **Eraser** | delete note (+undo) | delete folder (+undo) | — |
| **Select** (lasso) | start on a note → grab & drag it (drop on a folder → move in; drop on desk → move to root). Start on a *selected* note → drag the whole selection | — (can't grab a folder yet) | lasso around/across notes → select them (dashed highlight) |
| **Pen/Pencil/Marker/Highlighter** | **scribble** → delete note (+undo); **circle** around notes → select them; a plain doodle is *transient* and fades | leave colored marks on the icon (+undo) | **circle** notes → select; else *transient* — fades (persistence seam) |

Selection is a visible dashed highlight the surface draws around chosen notes
(it scrolls with them). Lasso empty desk to deselect; a move or delete clears it.
Both the lasso (Select tool) and the pen circle feed the same selection, and the
pen scribble/eraser feed the same delete — so the desk speaks the canvas's
gesture language.

Text entry (rename, new-folder name) and the new-note page-type choice still use
the hand-drawn keyboard **prompt** and **chooser** (kept in `HandDrawnPopups.swift`).
There is no pen gesture for entering text yet — that arrives with on-device
handwriting recognition (SPEC Phase 6). Those prompts are *diegetic* (hand-drawn
keyboard, no system keyboard), so they are **not** part of the "simplistic popup
system" that was removed.

## Architecture

Data flows: **card grid publishes frames → Pencil recognizer feeds the surface a
stroke → surface classifies it into a `DiegeticGesture` → screen calls the
library model → model mutates the store and registers an undo.**

```
PrototypeHomeScreen                         (owns the shared tool model)
  └─ PrototypeNoteGridScreen                (root + each folder; the "desk")
       ├─ ScrollView { cards }              each card: .diegeticTarget(.note/.folder(id))
       │     └─ every card publishes its frame via DiegeticTargetPreferenceKey
       ├─ .coordinateSpace("diegetic.surface")
       ├─ .overlayPreferenceValue(...) { targets in
       │      DiegeticInputSurface(toolStyle, targets, noteTitle, onGesture: handle)
       │   }                                ← pencil-only UIKit capture layer
       ├─ .safeAreaInset(bottom) { PrototypeHomeToolbar(toolModel) }
       └─ .overlay(bottom) { undoRibbon }   ← reads library.activeUndo
```

### Files

| File | Role |
|---|---|
| `App/Sources/DiegeticInteraction.swift` | **Pure core.** `DiegeticTargetID`, the frame-publishing `PreferenceKey` + `.diegeticTarget(_:)` modifier, the `diegeticCoordinateSpace` name, the `DiegeticGesture` vocabulary, and `DiegeticClassifier` (all the UIKit-free hit-test/geometry math). Start here. |
| `App/Sources/DiegeticInputSurface.swift` | The UIKit capture layer: `DiegeticInputSurface` (`UIViewRepresentable`) + `DiegeticInputUIView` + `DiegeticPencilRecognizer` (mechanics 1–2). Live transient ink, the grab-and-drop chip, folder hover highlight, and stroke → `DiegeticGesture` classification on lift. |
| `App/Sources/PrototypeHomeToolModel.swift` | `@Observable` active tool + ink for the home page (mirrors `PrototypeCanvasModel`'s tool rules). Shared across the nav stack. |
| `App/Sources/PrototypeHomeToolbar.swift` | The bottom pen palette (same Theme primitives as the editor's `PrototypeToolToolbar`). |
| `App/Sources/PrototypeHomeScreen.swift` | Wires it together; `handle(_:)` dispatches gestures; `undoRibbon`. Folder decorations render via `DiegeticFolderMarkCanvas`. |
| `App/Sources/PrototypeLibraryModel.swift` | CRUD + the single-level undo stack (`activeUndo`, `registerUndo`) + ID-based dispatch used by the surface. |
| `App/Sources/PrototypeNoteStore.swift` | Persistence. `DiegeticFolderMark`, `PrototypeFolder.decorations`, `setFolderDecorations`, `addFolder` (undo restore). |

### The three mechanics that make it work

**1. A Pencil-only recognizer on the scroll view — NOT a hit-test.** The first
implementation gated capture in `hitTest` by inspecting `event.allTouches` for a
`.pencil` touch. **This does not work on device** — at hit-test time the event
didn't carry the Pencil, so the touch fell through as a plain tap and the surface
never drew. The reliable approach: the surface takes *no touches itself*
(`isUserInteractionEnabled = false`, fully transparent), and a
`DiegeticPencilRecognizer` (a `UIGestureRecognizer` with
`allowedTouchTypes = [.pencil]`, plus `.direct` in the Simulator) is installed on
the enclosing `UIScrollView` in `didMoveToWindow`. UIKit routes touches to a
recognizer by touch type *reliably*. Living on the scroll view, it receives
Pencil touches that hit any descendant card, and it forwards them to the surface
(`beginStroke`/`moveStroke`/`endStroke`). It begins on touch-down with
`cancelsTouchesInView`, so a Pencil stroke suppresses the underlying card's tap.
Finger touches are never routed to it, so scroll and tap-to-open stay 100%
native. **If the Pencil ever stops drawing, this recognizer is the first place to
look.**

**2. The Pencil must never scroll.** A `UIScrollView`'s pan accepts *all* touch
types by default, so it would scroll on a Pencil drag and cancel drawing. In
`didMoveToWindow` the surface sets `panGestureRecognizer.allowedTouchTypes =
[.direct]` (finger scrolls, Pencil never does) and, belt-and-suspenders, hard-sets
`isScrollEnabled = false` for the length of a stroke (reverted on lift; this is
also what lets a Simulator trackpad drag draw without scrolling).

**3. Coordinate alignment.** The surface lives **inside** the scroll content (a
descendant of the `UIScrollView`, which is also how it finds the scroll view to
attach the recognizer), so it shares the cards' coordinate space and scrolls
*with* them — no viewport math. Both cards and surface sit under
`.coordinateSpace(name: diegeticCoordinateSpace)` on the content stack; each card
reports `proxy.frame(in: .named(diegeticCoordinateSpace))`, and the recognizer's
touch points (`touch.preciseLocation(in: surface)`) are in that same space. We
feed the surface its target frames via `overlayPreferenceValue` (not
`onPreferenceChange`) so they flow in synchronously and we sidestep Swift 6
`@Sendable`-closure friction.

## Persistence seam (decision 2)

Today, a drawing-tool stroke that lands on a note or the bare desk is **dropped**
(`DiegeticInputUIView.finish`, the `.draw` case — it only emits a gesture for a
folder target; otherwise it just `fadeAndClearInk()`s). To make desk ink
persistent later:

1. Add a `deskInk` collection (normalized to the page, like `DiegeticFolderMark`)
   to a per-screen store.
2. In the `.draw` case, when there's no card target, emit a new
   `DiegeticGesture.addDeskInk(...)` instead of dropping it.
3. Render it under the grid (a `Canvas` behind the cards).

The mark geometry is already normalized and `Codable`, so this is additive.

## Undo model

`PrototypeLibraryModel` keeps a **single** most-recent `DiegeticUndo`
(`activeUndo`), surfaced as the ribbon. Every mutating pen action registers its
inverse:

- delete note → the full `PrototypeNoteDocument` is captured *before* delete and
  re-saved on undo.
- delete folder → the folder (with its decorations) is re-added and its orphaned
  notes are reparented.
- move note → moved back to the previous folder.
- decorate folder → decorations reset to the prior set.

It auto-clears after ~6s (guarded by action `id` so a later action's timer can't
wipe a newer ribbon). This is deliberately *not* the canvas's full undo stack —
it's a lightweight "oops" for the desk.

## How to extend

**Add a new pen gesture** (e.g. "circle a folder to favorite it"):
1. Add a case to `DiegeticGesture` in `DiegeticInteraction.swift`.
2. Add any needed pure geometry to `DiegeticClassifier` (keep it UIKit-free and
   unit-testable).
3. Recognize it in `DiegeticInputUIView.endStroke` (or `beginStroke` for a
   drag-style gesture) and call `onGesture?(...)`.
4. Handle it in `PrototypeNoteGridScreen.handle(_:)` → a model method that
   mutates the store and calls `registerUndo` if it's reversible.

**Bring the surface to a new screen:** put the cards in a
`.coordinateSpace(name: diegeticCoordinateSpace)` container, tag each actionable
element with `.diegeticTarget(_:)`, drop a `DiegeticInputSurface` in via
`.overlayPreferenceValue(DiegeticTargetPreferenceKey.self)`, and route
`onGesture`. Reuse the shared `PrototypeHomeToolModel` (or a screen-specific one)
for the toolbar.

## Known limitations / open questions (for Miles)

- **Selection lives only in the surface.** The dashed highlight is drawn by the
  pen layer, not by the SwiftUI cards, and isn't exposed to the rest of the app
  (no selection binding, no toolbar "N selected" affordance). Enough to lasso →
  drag, but if a future feature needs to *act on* the selection from SwiftUI,
  it'll need a real binding.
- **Drawing a plain doodle on a note is a no-op** (fades) — only a scribble
  (delete) or a circle (select) does something. Reserved a future "annotate the
  note without opening it" gesture for the plain-doodle case.
- **Gesture thresholds are first-pass and screen-space.** `isScribble` /
  `isClosedLoop` / `primaryTarget` (in `DiegeticClassifier`) were ported from the
  canvas and lightly re-tuned; expect to adjust the constants once you feel them
  on-device (a lazy scribble mustn't read as delete, a loose circle must still
  read as select).
- **Rename still needs the keyboard prompt** (long-press). No pen gesture exists
  for text until handwriting recognition lands.
- **Can't grab a folder** with the lasso yet (no folder-into-folder nesting;
  the format is one level deep per the home-screen mockup).
- **Simulator testing is best-effort** — the Simulator has no Pencil, so
  `isToolTouch` treats trackpad/mouse (`.direct`) touches as tool touches in
  Simulator builds. That lets you exercise draw/erase/lasso there, but *pressure,
  tilt, and true Pencil vs. finger separation only exist on a physical iPad*
  (SPEC §11 / CLAUDE.md). Trust the device for how it actually feels.

## Relationship to the rest of the codebase

- The **look** of every element here (cards, toolbar, ribbon, prompts) comes from
  `HandDrawnTheme` via the `Theme` primitives — see `docs/hand-drawn/`. This doc
  is about *interaction*, that set is about *rendering*.
- The canvas editor (`CanvasPrototypeUIView`) is the original diegetic surface
  and the reference for pencil/finger separation, scribble-to-delete, and lasso
  geometry. Several `DiegeticClassifier`-style ideas are borrowed from it.
- Per SPEC §8, this is out-of-order Phase 8 work, approved case-by-case. When the
  format is blessed, it gets spec'd and folded into the phase plan.
