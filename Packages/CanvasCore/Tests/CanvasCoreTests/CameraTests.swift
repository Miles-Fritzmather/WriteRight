import CoreGraphics
import Model
import Testing
@testable import CanvasCore

/// Deterministic RNG so any failure reproduces exactly.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func randomCamera(_ rng: inout SplitMix64) -> Camera {
    Camera(
        translation: CGVector(
            dx: CGFloat.random(in: -2000...2000, using: &rng),
            dy: CGFloat.random(in: -2000...2000, using: &rng)
        ),
        scale: CGFloat.random(in: 0.05...40, using: &rng),
        rotation: CGFloat.random(in: -2 * .pi...2 * .pi, using: &rng)
    )
}

struct CameraTests {
    /// SPEC §5 asks for the translate → scale → rotate order to be verified
    /// empirically: a canvas point must be rotated first, then scaled, then
    /// translated.
    @Test func transformAppliesRotateThenScaleThenTranslate() {
        let camera = Camera(translation: CGVector(dx: 100, dy: 50), scale: 2, rotation: .pi / 2)
        let p = camera.toScreen(CanvasPoint(x: 10, y: 0))
        // rotate 90°: (10,0) → (0,10); scale ×2: (0,20); translate: (100,70)
        #expect(abs(p.x - 100) < 1e-9)
        #expect(abs(p.y - 70) < 1e-9)
    }

    @Test func identityCameraIsANoOp() {
        let p = Camera().toScreen(CanvasPoint(x: 12.5, y: -3.25))
        #expect(p.x == 12.5)
        #expect(p.y == -3.25)
    }

    /// Phase 0 acceptance: toCanvas ∘ toScreen must be exact (to double
    /// precision) across wild cameras and far-out canvas points.
    @Test func roundTripIsExact() {
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<500 {
            let camera = randomCamera(&rng)
            let p = CanvasPoint(
                x: Double.random(in: -1e5...1e5, using: &rng),
                y: Double.random(in: -1e5...1e5, using: &rng)
            )
            let rt = camera.toCanvas(camera.toScreen(p))
            let tol = 1e-9 * max(1, abs(p.x), abs(p.y))
            #expect(abs(rt.x - p.x) <= tol)
            #expect(abs(rt.y - p.y) <= tol)
        }
    }

    /// Pinch-zoom must keep the canvas point under the fingers stationary.
    @Test func zoomKeepsPivotFixed() {
        var rng = SplitMix64(seed: 1)
        for _ in 0..<200 {
            var camera = randomCamera(&rng)
            let pivot = ScreenPoint(
                x: Double.random(in: 0...1366, using: &rng),
                y: Double.random(in: 0...1024, using: &rng)
            )
            let before = camera.toCanvas(pivot)
            camera.zoomBy(CGFloat.random(in: 0.2...5, using: &rng), about: pivot)
            let after = camera.toCanvas(pivot)
            let tol = 1e-6 * max(1, abs(before.x), abs(before.y))
            #expect(abs(after.x - before.x) <= tol)
            #expect(abs(after.y - before.y) <= tol)
        }
    }

    /// Two-finger twist must keep the canvas point under the fingers
    /// stationary.
    @Test func rotationKeepsPivotFixed() {
        var rng = SplitMix64(seed: 2)
        for _ in 0..<200 {
            var camera = randomCamera(&rng)
            let pivot = ScreenPoint(
                x: Double.random(in: 0...1366, using: &rng),
                y: Double.random(in: 0...1024, using: &rng)
            )
            let before = camera.toCanvas(pivot)
            camera.rotateBy(CGFloat.random(in: -.pi ... .pi, using: &rng), about: pivot)
            let after = camera.toCanvas(pivot)
            let tol = 1e-6 * max(1, abs(before.x), abs(before.y))
            #expect(abs(after.x - before.x) <= tol)
            #expect(abs(after.y - before.y) <= tol)
        }
    }

    @Test func panShiftsEveryPointByTheScreenDelta() {
        var camera = Camera(translation: CGVector(dx: 30, dy: -12), scale: 1.7, rotation: 0.6)
        let p = CanvasPoint(x: 250, y: -80)
        let before = camera.toScreen(p)
        camera.panBy(dx: 41, dy: -13)
        let after = camera.toScreen(p)
        #expect(abs(after.x - (before.x + 41)) < 1e-9)
        #expect(abs(after.y - (before.y - 13)) < 1e-9)
    }

    @Test func gestureOpsUpdateOnlyTheirParameters() {
        var camera = Camera()
        camera.zoomBy(2, about: ScreenPoint(x: 100, y: 100))
        #expect(abs(camera.scale - 2) < 1e-12)
        #expect(camera.rotation == 0)

        camera.rotateBy(.pi / 4, about: ScreenPoint(x: 50, y: 10))
        #expect(abs(camera.rotation - .pi / 4) < 1e-12)
        #expect(abs(camera.scale - 2) < 1e-12)
    }
}
