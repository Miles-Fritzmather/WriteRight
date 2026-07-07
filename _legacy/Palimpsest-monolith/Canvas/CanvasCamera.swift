import CoreGraphics
import Combine
import Foundation

/// The single source of truth for where the "camera" sits over the infinite
/// canvas plane. This is Phase 0 of the build: everything else — tiling,
/// rotation, hit-testing — is downstream of getting this transform right.
///
/// The core invariant: `transform` always maps canvas space -> screen space.
/// Captured ink is converted through `transform.inverted()` *before* it is
/// stored, so a `Stroke`'s points never change when the camera pans, zooms,
/// or rotates. The data is never rotated — the camera is.
final class CanvasCamera: ObservableObject {
    @Published private(set) var transform: CGAffineTransform = .identity

    private(set) var minScale: CGFloat = 0.2
    private(set) var maxScale: CGFloat = 8.0

    // MARK: - Space conversion (the two lines that matter)

    func canvasPoint(fromScreen screenPoint: CGPoint) -> CGPoint {
        screenPoint.applying(transform.inverted())
    }

    func screenPoint(fromCanvas canvasPoint: CGPoint) -> CGPoint {
        canvasPoint.applying(transform)
    }

    /// The axis-aligned bounding box, in canvas space, of a screen-space rect.
    /// Because the camera can be rotated, the true visible region is a
    /// rotated rectangle in canvas space — this returns its bounding box,
    /// a safe superset for tile-visibility queries.
    func canvasBoundingRect(ofScreenRect rect: CGRect) -> CGRect {
        let corners = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ].map(canvasPoint(fromScreen:))
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    var currentScale: CGFloat { transform.currentScale }
    var currentRotationRadians: CGFloat { transform.currentRotation }

    // MARK: - Gesture-driven incremental updates
    //
    // Pan/pinch/rotate recognizers all run simultaneously. Each call takes an
    // *incremental* delta (the recognizer's value since the last callback,
    // with the recognizer reset to identity afterward by the caller) and an
    // anchor point in screen space so pinch/rotate keep the touch point fixed.

    func applyIncrementalPan(_ translation: CGVector) {
        transform = transform.concatenating(CGAffineTransform(translationX: translation.dx, y: translation.dy))
    }

    func applyIncrementalScale(_ scale: CGFloat, anchor: CGPoint) {
        guard scale.isFinite, scale > 0 else { return }
        let prospective = currentScale * scale
        let clampedScale = min(max(prospective, minScale), maxScale) / currentScale
        transform = transform.concatenating(scaleAbout(anchor, scale: clampedScale))
    }

    func applyIncrementalRotation(_ radians: CGFloat, anchor: CGPoint) {
        guard radians.isFinite else { return }
        transform = transform.concatenating(rotateAbout(anchor, radians: radians))
    }

    private func scaleAbout(_ anchor: CGPoint, scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    private func rotateAbout(_ anchor: CGPoint, radians: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    // MARK: - Absolute setters (search jump, reset, initial layout)

    func center(on canvasPoint: CGPoint, in viewSize: CGSize, animated: Bool = true) {
        let scale = currentScale
        let rotation = currentRotationRadians
        var t = CGAffineTransform(translationX: -canvasPoint.x, y: -canvasPoint.y)
        t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        t = t.concatenating(CGAffineTransform(rotationAngle: rotation))
        t = t.concatenating(CGAffineTransform(translationX: viewSize.width / 2, y: viewSize.height / 2))
        transform = t
    }

    func resetToIdentity(centeredIn viewSize: CGSize) {
        transform = CGAffineTransform(translationX: viewSize.width / 2, y: viewSize.height / 2)
    }
}

extension CGAffineTransform {
    /// Magnitude of the linear part, assuming no shear (true for a transform
    /// built only from translation + uniform scale + rotation).
    var currentScale: CGFloat {
        (a * a + b * b).squareRoot()
    }

    var currentRotation: CGFloat {
        atan2(b, a)
    }
}
