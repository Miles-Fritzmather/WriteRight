import SwiftUI

/// SwiftUI wrapper for the Phase 0 canvas.
struct CanvasPrototypeView: UIViewRepresentable {
    let model: PrototypeCanvasModel
    /// Passed as a plain value (not read off `model` in here) so SwiftUI
    /// reliably re-runs `updateUIView` when the HUD toggle flips.
    let fingerDrawing: Bool

    func makeUIView(context: Context) -> CanvasPrototypeUIView {
        let view = CanvasPrototypeUIView()
        view.fingerDrawingEnabled = fingerDrawing
        view.onChange = { [weak model] camera, strokeCount in
            model?.apply(camera: camera, strokeCount: strokeCount)
        }
        model.canvasView = view
        return view
    }

    func updateUIView(_ view: CanvasPrototypeUIView, context: Context) {
        view.fingerDrawingEnabled = fingerDrawing
    }
}
