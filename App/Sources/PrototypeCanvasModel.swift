import CanvasCore
import CoreGraphics
import Observation
import UIKit

/// Bridges the prototype canvas UIView to the SwiftUI HUD.
@MainActor
@Observable
final class PrototypeCanvasModel {
    var scale: CGFloat = 1
    var rotationDegrees: Double = 0
    var strokeCount = 0
    var fingerDrawing = false

    weak var canvasView: CanvasPrototypeUIView?

    func resetCamera() { canvasView?.resetCamera() }
    func clearInk() { canvasView?.clearInk() }

    /// Called at up to 120 Hz during gestures; writes only on real change
    /// so SwiftUI isn't invalidated needlessly.
    func apply(camera: Camera, strokeCount: Int) {
        if camera.scale != scale { scale = camera.scale }

        var degrees = camera.rotation * 180 / .pi
        degrees.formTruncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        if degrees != rotationDegrees { rotationDegrees = degrees }

        if strokeCount != self.strokeCount { self.strokeCount = strokeCount }
    }
}
