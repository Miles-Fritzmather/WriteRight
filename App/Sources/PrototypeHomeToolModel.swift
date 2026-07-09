import CoreGraphics
import Observation

/// Active pen tool + ink for the diegetic home page. Shared across the whole
/// navigation stack (root + folder screens) so the chosen tool persists as you
/// move between folders. Mirrors the tool/color rules of `PrototypeCanvasModel`
/// so the two surfaces feel identical.
@MainActor
@Observable
final class PrototypeHomeToolModel {
    var selectedTool: PrototypeToolKind = .selection
    var selectedInkColor: PrototypeInkColor = .black
    var selectedHighlighterColor: PrototypeInkColor = .yellow

    /// The tools that make sense on the library page. (No plain "pencil" vs
    /// "pen" distinction is needed here — the drawing tools all recolor folders
    /// identically — but keeping the full set makes the palette feel continuous
    /// with the editor and leaves room for per-tool recolor styling later.)
    static let homeTools: [PrototypeToolKind] = [.selection, .eraser, .pen, .pencil, .marker, .highlighter]

    var toolStyle: PrototypeToolStyle {
        PrototypeToolStyle.resolved(
            kind: selectedTool,
            inkColor: selectedInkColor,
            highlighterColor: selectedHighlighterColor
        )
    }

    /// True when the active tool leaves ink (recolors folders) rather than
    /// issuing a manipulation command.
    var isDrawingTool: Bool {
        switch selectedTool {
        case .pen, .pencil, .marker, .highlighter: true
        case .eraser, .selection: false
        }
    }

    func selectTool(_ tool: PrototypeToolKind) {
        selectedTool = tool
    }

    func selectInkColor(_ color: PrototypeInkColor) {
        selectedInkColor = color
        if selectedTool == .highlighter || selectedTool == .eraser || selectedTool == .selection {
            selectedTool = .pen
        }
    }

    func selectHighlighterColor(_ color: PrototypeInkColor) {
        selectedHighlighterColor = color
        if selectedTool != .highlighter {
            selectedTool = .highlighter
        }
    }
}
