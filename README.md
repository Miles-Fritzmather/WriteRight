# WriteRight

WriteRight is an iPadOS 26+ handwritten-note app prototype, built under the spec codename
Palimpsest. The product direction is an infinite rotatable canvas with Apple Pencil-first
ink, on-device AI features, and an eventual hand-drawn UI system.

The authoritative build plan is [docs/SPEC.md](docs/SPEC.md). Work proceeds phase by
phase and a phase is complete only when its acceptance criteria pass.

## Current Status

- Phase 0, canvas and camera prototype, is implemented.
- Phase 0 still needs on-device confirmation that drawing while panned, zoomed, and
  rotated feels correct on a physical iPad.
- Phase 1 has started only as a narrow toolbar/design-system slice. Full Phase 1 still
  requires real ink capture, PencilKit live ink commit, undo/redo, and complete tool
  behavior.

## Project Layout

```text
App/
  Sources/             SwiftUI app shell, UIKit canvas host, prototype toolbar
  Resources/           App bundle resources and Info.plist
Packages/
  Model/               Branded canvas/screen coordinate types
  CanvasCore/          Camera transform and gesture math, with unit tests
docs/
  SPEC.md              Product and build specification
scripts/
  run-device.sh        Device-oriented helper script
_legacy/
  Palimpsest-monolith/ Reference-only legacy implementation
project.yml            XcodeGen project definition
```

The generated `WriteRight.xcodeproj` is disposable and should not be edited by hand.
After adding files or targets, run `xcodegen generate`.

## Architecture Notes

The core invariant is coordinate discipline: strokes live in canvas space only.
Incoming samples are converted from screen space with `Camera.toCanvas` at capture time;
rendering converts back through the camera transform. Rotation belongs to the camera, not
to stored stroke data.

The app is intentionally split into SwiftPM logic packages and a thin app shell. Logic
tests run directly on the Mac host, while Pencil behavior must be validated on a physical
iPad because the simulator cannot provide pressure, tilt, hover, or squeeze input.

## Build And Test

Run camera/unit tests:

```sh
swift test --package-path Packages/CanvasCore
```

Regenerate the app project after source/project changes:

```sh
xcodegen generate
```

Build the app for an iOS simulator:

```sh
xcodebuild -project WriteRight.xcodeproj \
  -scheme WriteRight \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  build
```

## Development Rules

- Use Swift 6 strict concurrency and `@Observable` view models.
- Keep production paths free of force unwraps.
- Do not add dependencies without approval, except for GRDB, Inject, and XcodeGen.
- From Phase 1 onward, feature UI should go through the `Theme` abstraction instead of
  using raw SwiftUI `Button` or `Image` controls.
- Do not build or extend `_legacy/Palimpsest-monolith`; it is reference material only.

## Device Workflow

Apple Pencil work needs a physical iPad. Simulator testing is useful for build smoke
checks and basic touch behavior, but pressure, tilt, hover, squeeze, and real Pencil feel
must be validated on-device through the SweetPad/Xcode toolchain.
