import CoreGraphics
import Foundation
import Model

/// The camera that maps the infinite canvas onto the screen.
///
/// `transform` composes translate → scale → rotate (SPEC §5), which means a
/// canvas point is rotated first, then scaled, then translated on its way to
/// screen space (order pinned down by `CameraTests`). Scale and rotation
/// therefore pivot on the canvas origin; the gesture helpers below rebase
/// them onto arbitrary screen-space pivots with closed-form parameter
/// updates, so the three stored parameters always describe the camera
/// exactly — nothing accumulates outside them.
///
/// Rotation is never applied to stored strokes — only to this camera.
public struct Camera: Equatable, Sendable {
    public var translation: CGVector
    public var scale: CGFloat
    /// Radians. Positive appears clockwise in UIKit's y-down space.
    public var rotation: CGFloat

    public init(translation: CGVector = .zero, scale: CGFloat = 1, rotation: CGFloat = 0) {
        self.translation = translation
        self.scale = scale
        self.rotation = rotation
    }

    public var transform: CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: translation.dx, y: translation.dy)
            .scaledBy(x: scale, y: scale)
            .rotated(by: rotation)
    }

    public func toScreen(_ p: CanvasPoint) -> ScreenPoint {
        ScreenPoint(cgPoint: p.cgPoint.applying(transform))
    }

    public func toCanvas(_ p: ScreenPoint) -> CanvasPoint {
        CanvasPoint(cgPoint: p.cgPoint.applying(transform.inverted()))
    }

    // MARK: - Gesture operations (screen-space)

    /// Slides the canvas by a screen-space delta.
    public mutating func panBy(dx: CGFloat, dy: CGFloat) {
        translation.dx += dx
        translation.dy += dy
    }

    /// Zooms by `factor`, keeping the canvas point under `pivot` fixed on
    /// screen: t' = pivot + factor · (t − pivot).
    public mutating func zoomBy(_ factor: CGFloat, about pivot: ScreenPoint) {
        translation = CGVector(
            dx: pivot.x + factor * (translation.dx - pivot.x),
            dy: pivot.y + factor * (translation.dy - pivot.y)
        )
        scale *= factor
    }

    /// Rotates by `angle` radians, keeping the canvas point under `pivot`
    /// fixed on screen: t' = pivot + R(angle) · (t − pivot).
    public mutating func rotateBy(_ angle: CGFloat, about pivot: ScreenPoint) {
        let c = cos(angle)
        let s = sin(angle)
        let vx = translation.dx - pivot.x
        let vy = translation.dy - pivot.y
        translation = CGVector(
            dx: pivot.x + c * vx - s * vy,
            dy: pivot.y + s * vx + c * vy
        )
        rotation += angle
    }
}
