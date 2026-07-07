import CoreGraphics

/// A point on the infinite canvas plane.
///
/// All persisted geometry — strokes, recognized-text boxes, icon drawings —
/// lives in canvas space. Branded separately from `ScreenPoint` so the
/// compiler rejects cross-space math (SPEC §5).
public struct CanvasPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A point in device coordinates as presented after the camera transform.
/// Never persisted.
public struct ScreenPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - CoreGraphics bridging
//
// Conversions to/from CGPoint are spelled out at call sites on purpose:
// they mark the exact boundary where branded geometry meets UIKit/CG.

public extension CanvasPoint {
    init(cgPoint p: CGPoint) { self.init(x: p.x, y: p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public extension ScreenPoint {
    init(cgPoint p: CGPoint) { self.init(x: p.x, y: p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
