import SwiftUI

/// SwiftUI wrapper for the Phase 0 canvas.
struct CanvasPrototypeView: UIViewRepresentable {
    let model: PrototypeCanvasModel
    let toolStyle: PrototypeToolStyle

    func makeUIView(context: Context) -> CanvasPrototypeUIView {
        let view = CanvasPrototypeUIView()
        view.toolStyle = toolStyle
        view.pageType = model.currentPageType
        view.pageCount = model.currentPageCount
        view.onChange = { [weak model] camera, strokeCount, selectedStrokeCount in
            model?.apply(
                camera: camera,
                strokeCount: strokeCount,
                selectedStrokeCount: selectedStrokeCount
            )
        }
        view.onPencilQuickAccess = { [weak model] anchor in
            model?.togglePencilQuickToolbar(at: anchor)
        }
        view.onPageCountChange = { [weak model] pageCount in
            model?.currentPageCount = pageCount
        }
        model.attach(view)
        return view
    }

    func updateUIView(_ view: CanvasPrototypeUIView, context: Context) {
        view.toolStyle = toolStyle
        view.pageType = model.currentPageType
        view.pageCount = model.currentPageCount
        view.onPencilQuickAccess = { [weak model] anchor in
            model?.togglePencilQuickToolbar(at: anchor)
        }
        view.onPageCountChange = { [weak model] pageCount in
            model?.currentPageCount = pageCount
        }
    }
}
