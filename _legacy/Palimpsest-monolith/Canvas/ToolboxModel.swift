import Combine
import Foundation

/// Holds the currently-selected ink style and the small "last two tools"
/// history that powers the Apple-Pencil double-tap quick-switch.
final class ToolboxModel: ObservableObject {
    @Published var currentStyle: ToolStyle = .default(for: .pen)
    @Published var isPopupPresented = false
    @Published var popupAnchor: CGPoint = .zero

    private var lastNonEraserStyle: ToolStyle = .default(for: .pen)

    func select(_ style: ToolStyle) {
        currentStyle = style
        if style.tool != .eraser {
            lastNonEraserStyle = style
        }
    }

    /// Apple Pencil double-tap: toggle between the eraser and whatever was
    /// last used, mirroring the system-wide gesture users already know.
    func quickToggleTool() {
        if currentStyle.tool == .eraser {
            currentStyle = lastNonEraserStyle
        } else {
            lastNonEraserStyle = currentStyle
            currentStyle = .default(for: .eraser)
        }
    }

    func presentPopup(at anchor: CGPoint) {
        popupAnchor = anchor
        isPopupPresented = true
    }
}
