import CoreGraphics
import Foundation

/// A single raw sample along a stroke, always expressed in canvas space —
/// never screen space. See `CameraTransform` for the space conversion.
struct SamplePoint: Codable, Equatable {
    var x: Double
    var y: Double
    var pressure: Float
    var altitude: Float
    var azimuth: Float
    var timestamp: TimeInterval

    var location: CGPoint { CGPoint(x: x, y: y) }
}
