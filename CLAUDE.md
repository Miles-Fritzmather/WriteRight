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
- `App/Sources` — thin app shell (SwiftUI + UIKit canvas host). Phase 0's prototype
  files are prefixed `Prototype`/`CanvasPrototype` and are throwaway by design.
- `_legacy/Palimpsest-monolith` — last session's pre-spec monolithic app, kept only as
  reference (PDF export/import, Vision OCR, GRDB patterns). Never build or extend it.

## Build & test
- The `.xcodeproj` is **generated, git-ignored, never hand-edited**. After adding
  files/targets: `xcodegen generate`.
- Logic tests run on the Mac host, no simulator needed:
  `swift test --package-path Packages/CanvasCore`
- App build (simulator):
  `xcodebuild -project WriteRight.xcodeproj -scheme WriteRight -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build`
- Smoke-run in a simulator: boot an iOS 26.x iPad from `xcrun simctl list devices`,
  `simctl install` + `simctl launch` + `simctl io booted screenshot`.
- **Pencil work needs a physical iPad** — the simulator has no pressure/tilt/hover.
  Device runs go through SweetPad (VS Code/Cursor). Signing: no DEVELOPMENT_TEAM is
  set yet; first device deploy needs one (one-time Xcode signing setup, SPEC §11).
- Hot reload is wired (Inject package, Debug-only, `-Xlinker -interposable`); it's a
  no-op until the InjectionIII/InjectionNext Mac app is installed and running.
