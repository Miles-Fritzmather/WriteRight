import CoreGraphics
import Foundation
import Model

/// Throwaway Phase 0 stroke. The real `Stroke` model (SPEC §6) with tools,
/// undo, and persistence arrives in Phase 1.
struct PrototypePoint: Codable {
    /// Canvas space, always — converted at capture time (SPEC §5).
    var position: CanvasPoint
    /// Raw `UITouch.force`; 0 for finger/mouse input.
    var force: CGFloat
}

struct PrototypeStroke: Codable {
    let id: UUID
    var points: [PrototypePoint]
    var style: PrototypeToolStyle

    init(id: UUID = UUID(), points: [PrototypePoint], style: PrototypeToolStyle) {
        self.id = id
        self.points = points
        self.style = style
    }

    var renderWidth: CGFloat { style.width }

    var renderBounds: CGRect {
        renderBounds(for: points)
    }

    mutating func append(_ samples: [PrototypePoint]) {
        for sample in samples {
            append(sample)
        }
    }

    func layerPath(include predictedPoints: [PrototypePoint] = []) -> CGPath {
        let allPoints = points + predictedPoints
        let bounds = renderBounds(for: allPoints)
        let path = CGMutablePath()
        guard let first = allPoints.first else { return path }

        if allPoints.count == 1 {
            let radius = renderWidth / 2
            path.addEllipse(in: CGRect(
                x: first.position.x - bounds.minX - radius,
                y: first.position.y - bounds.minY - radius,
                width: radius * 2,
                height: radius * 2
            ))
            return path
        }

        path.move(to: localPoint(first.position, in: bounds))

        // Smooth the stored polyline into one stroked path instead of
        // issuing one draw call per segment.
        for index in 1..<allPoints.count {
            let previous = allPoints[index - 1].position
            let current = allPoints[index].position
            let midpoint = CanvasPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(
                to: localPoint(midpoint, in: bounds),
                control: localPoint(previous, in: bounds)
            )
        }

        if let last = allPoints.last {
            path.addLine(to: localPoint(last.position, in: bounds))
        }
        return path
    }

    func renderBounds(include predictedPoints: [PrototypePoint] = []) -> CGRect {
        renderBounds(for: points + predictedPoints)
    }

    func width(for force: CGFloat) -> CGFloat {
        renderWidth
    }

    func contains(_ point: CanvasPoint, eraserRadius: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        let target = point.cgPoint
        if points.count == 1 {
            let radius = eraserRadius + width(for: first.force) / 2
            return distance(target, to: first.position.cgPoint) <= radius
        }

        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let radius = eraserRadius + max(width(for: start.force), width(for: end.force)) / 2
            if distance(target, toSegmentFrom: start.position.cgPoint, to: end.position.cgPoint) <= radius {
                return true
            }
        }
        return false
    }

    private mutating func append(_ sample: PrototypePoint) {
        guard let last = points.last else {
            points.append(sample)
            return
        }

        if distance(last.position.cgPoint, to: sample.position.cgPoint) >= minStoredPointDistance {
            points.append(sample)
        } else if points.count == 1 {
            points[0] = sample
        }
    }

    private var minStoredPointDistance: CGFloat {
        max(0.75, min(renderWidth * 0.18, 3))
    }

    private func renderBounds(for points: [PrototypePoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.position.x
        var minY = first.position.y
        var maxX = first.position.x
        var maxY = first.position.y

        for point in points.dropFirst() {
            minX = min(minX, point.position.x)
            minY = min(minY, point.position.y)
            maxX = max(maxX, point.position.x)
            maxY = max(maxY, point.position.y)
        }

        let inset = Double(renderWidth)
        return CGRect(
            x: minX - inset,
            y: minY - inset,
            width: max(maxX - minX + inset * 2, 1),
            height: max(maxY - minY + inset * 2, 1)
        )
    }
}

private func localPoint(_ point: CanvasPoint, in bounds: CGRect) -> CGPoint {
    CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
}

private func distance(_ a: CGPoint, to b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > .ulpOfOne else {
        return distance(point, to: start)
    }

    let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
    let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
    return distance(point, to: projection)
}
