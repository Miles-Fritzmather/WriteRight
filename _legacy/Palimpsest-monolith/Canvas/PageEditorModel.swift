import Combine
import CoreGraphics
import Foundation

/// Owns the in-memory working set of strokes for the page currently open in
/// the canvas, and mirrors every change through to `NotebookRepository`.
/// The canvas, tiled renderer, and recognition pipeline all read from here.
@MainActor
final class PageEditorModel: ObservableObject {
    @Published private(set) var page: Page
    @Published private(set) var strokes: [Stroke] = []

    private let repository: NotebookRepository
    private var recognitionTask: Task<Void, Never>?

    init(page: Page, repository: NotebookRepository) {
        self.page = page
        self.repository = repository
        loadStrokes()
    }

    private func loadStrokes() {
        strokes = (try? repository.allStrokes(onPage: page.id)) ?? []
    }

    /// Every stroke whose bounding box intersects `canvasRect` — the closure
    /// handed to `TiledCanvasView` as its `strokeProvider`.
    func strokes(intersecting canvasRect: CGRect) -> [Stroke] {
        strokes.filter { $0.boundingBox.intersects(canvasRect) }
    }

    /// Broad-phase eraser hit-test: any stroke whose bounding box comes
    /// within `radius` of `canvasPoint`. `canvasPoint` is already in canvas
    /// space — the caller inverted the camera transform before calling this,
    /// matching the "hit-testing inverts the same way" rule.
    func strokeIDs(near canvasPoint: CGPoint, radius: CGFloat) -> [UUID] {
        let testRect = CGRect(x: canvasPoint.x - radius, y: canvasPoint.y - radius, width: radius * 2, height: radius * 2)
        return strokes.filter { $0.boundingBox.intersects(testRect) }.map(\.id)
    }

    func commit(_ stroke: Stroke) {
        strokes.append(stroke)
        try? repository.insertStroke(stroke)
        scheduleRecognition()
    }

    func erase(strokeIDs: [UUID]) {
        guard !strokeIDs.isEmpty else { return }
        let idSet = Set(strokeIDs)
        strokes.removeAll { idSet.contains($0.id) }
        try? repository.deleteStrokes(ids: strokeIDs)
        scheduleRecognition()
    }

    /// Bounding boxes (canvas space) that changed, for `TiledCanvasView.invalidate`.
    func boundingBoxes(for strokeIDs: [UUID]) -> [CGRect] {
        let idSet = Set(strokeIDs)
        return strokes.filter { idSet.contains($0.id) }.map(\.boundingBox)
    }

    private func scheduleRecognition() {
        recognitionTask?.cancel()
        let pageID = page.id
        let snapshot = strokes
        let repository = repository
        recognitionTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1)) // debounce while the user keeps writing
            guard !Task.isCancelled else { return }
            let lines = await HandwritingRecognizer.recognize(strokes: snapshot, pageID: pageID)
            try? repository.replaceRecognizedText(lines, forPage: pageID)
        }
    }
}
