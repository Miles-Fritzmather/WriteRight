import CoreGraphics
import Foundation

/// The persisted, PencilKit-independent representation of a single stroke.
/// Points are always stored in canvas space (see the architecture doc's
/// "the camera moves, the data never rotates" rule).
struct Stroke: Identifiable, Codable, Equatable {
    let id: UUID
    var pageID: UUID
    var points: [SamplePoint]
    var style: ToolStyle
    var boundingBox: CGRect
    var createdAt: Date

    init(id: UUID = UUID(), pageID: UUID, points: [SamplePoint], style: ToolStyle, createdAt: Date = Date()) {
        self.id = id
        self.pageID = pageID
        self.points = points
        self.style = style
        self.createdAt = createdAt
        self.boundingBox = Stroke.computeBoundingBox(points: points, width: style.width)
    }

    static func computeBoundingBox(points: [SamplePoint], width: CGFloat) -> CGRect {
        guard var minX = points.first?.x else { return .zero }
        var maxX = minX, minY = points.first!.y, maxY = minY
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        let inset = -width / 2
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.001), height: max(maxY - minY, 0.001))
            .insetBy(dx: inset, dy: inset)
    }
}
