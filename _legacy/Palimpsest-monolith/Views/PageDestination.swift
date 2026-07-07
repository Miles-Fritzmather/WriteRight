import CoreGraphics
import Foundation

/// Navigation payload for opening a page, optionally jumping straight to a
/// canvas-space point (a search hit) instead of the default centered view.
struct PageDestination: Hashable {
    let page: Page
    var focusCanvasPoint: CGPoint?
}
