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
    var selectedTool: PrototypeToolKind = .pen
    var selectedInkColor: PrototypeInkColor = .black
    var selectedHighlighterColor: PrototypeInkColor = .yellow

    weak var canvasView: CanvasPrototypeUIView?

    func resetCamera() { canvasView?.resetCamera() }
    func clearInk() { canvasView?.clearInk() }

    var currentToolStyle: PrototypeToolStyle {
        PrototypeToolStyle.resolved(
            kind: selectedTool,
            inkColor: selectedInkColor,
            highlighterColor: selectedHighlighterColor
        )
    }

    func selectTool(_ tool: PrototypeToolKind) {
        selectedTool = tool
    }

    func selectInkColor(_ color: PrototypeInkColor) {
        selectedInkColor = color
        if selectedTool == .highlighter || selectedTool == .eraser {
            selectedTool = .pen
        }
    }

    func selectHighlighterColor(_ color: PrototypeInkColor) {
        selectedHighlighterColor = color
        if selectedTool != .highlighter {
            selectedTool = .highlighter
        }
    }

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
