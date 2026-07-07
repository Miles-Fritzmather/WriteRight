import CoreGraphics
import Model

/// Throwaway Phase 0 stroke. The real `Stroke` model (SPEC §6) with tools,
/// undo, and persistence arrives in Phase 1.
struct PrototypePoint {
    /// Canvas space, always — converted at capture time (SPEC §5).
    var position: CanvasPoint
    /// Raw `UITouch.force`; 0 for finger/mouse input.
    var force: CGFloat
}

struct PrototypeStroke {
    var points: [PrototypePoint]
    var style: PrototypeToolStyle

    func width(for force: CGFloat) -> CGFloat {
        guard style.pressureSensitive, force > 0 else { return style.width }
        return style.width * min(max(0.35 + 0.65 * force, 0.25), 2.5)
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
