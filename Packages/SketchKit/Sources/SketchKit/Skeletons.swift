/// Ideal ("skeleton") geometry that the wobble roughs up. Skeletons are plain
/// polylines; hand-authored stroke assets (SPEC §7 `IconSource.userDrawn`)
/// plug into the same slot in a later phase.

/// Axis-aligned rectangle in element-local space (kept platform-free; the UI
/// layer converts from CGRect).
public struct SketchRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

private func segment(_ a: SketchPoint, _ b: SketchPoint) -> [SketchPoint] { [a, b] }

/// Button border skeleton.
///
/// `cornerRadius < 1`: four overshooting side strokes — the sharp sketchbook
/// box, corners formed by the crossing overshoots.
/// `cornerRadius >= 1`: one continuous swoop around a rounded rect; the pen
/// starts partway along the top edge, loops around, and closes by retracing
/// past its start (`overshoot` doubles as the overlap length).
public func borderStrokes(
    in rect: SketchRect,
    overshoot: Double,
    cornerRadius: Double
) -> [[SketchPoint]] {
    let (x, y, w, h) = (rect.x, rect.y, rect.width, rect.height)
    let r = min(cornerRadius, min(w, h) / 2 - 2)
    if r < 1 {
        let o = overshoot
        return [
            segment(.init(x: x - o, y: y), .init(x: x + w + o, y: y)),
            segment(.init(x: x + w, y: y - o), .init(x: x + w, y: y + h + o)),
            segment(.init(x: x + w + o, y: y + h), .init(x: x - o, y: y + h)),
            segment(.init(x: x, y: y + h + o), .init(x: x, y: y - o)),
        ]
    }

    var pts = [SketchPoint]()
    func arc(cx: Double, cy: Double, from a0: Double, to a1: Double) {
        let steps = max(3, Int((r * abs(a1 - a0) / 4).rounded(.up)))
        for i in 1...steps {
            let a = a0 + (a1 - a0) * Double(i) / Double(steps)
            pts.append(SketchPoint(x: cx + r * _cos(a), y: cy + r * _sin(a)))
        }
    }
    let startX = x + w * 0.32 // pen starts partway along the top edge
    pts.append(SketchPoint(x: startX, y: y))
    pts.append(SketchPoint(x: x + w - r, y: y))
    arc(cx: x + w - r, cy: y + r, from: -.pi / 2, to: 0)
    pts.append(SketchPoint(x: x + w, y: y + h - r))
    arc(cx: x + w - r, cy: y + h - r, from: 0, to: .pi / 2)
    pts.append(SketchPoint(x: x + r, y: y + h))
    arc(cx: x + r, cy: y + h - r, from: .pi / 2, to: .pi)
    pts.append(SketchPoint(x: x, y: y + r))
    arc(cx: x + r, cy: y + r, from: .pi, to: .pi * 1.5)
    pts.append(SketchPoint(x: startX + max(2, overshoot), y: y)) // retrace + overlap
    return [pts]
}

/// Diagonal hatch fill for the pressed state, drawn as alternating-direction
/// strokes (zig-zag pen travel) clipped to the inset rect.
public func hatchStrokes(in rect: SketchRect, spacing: Double) -> [[SketchPoint]] {
    let inset = 7.0
    let angle = -Double.pi / 4.6
    let (dx, dy) = (_cos(angle), _sin(angle))
    let x0 = rect.x + inset
    let y0 = rect.y + inset
    let iw = rect.width - 2 * inset
    let ih = rect.height - 2 * inset
    guard iw > 4, ih > 4, spacing > 0 else { return [] }

    // Signed distance across the hatch direction.
    func project(_ px: Double, _ py: Double) -> Double { px * -dy + py * dx }
    let corners = [
        project(x0, y0), project(x0 + iw, y0),
        project(x0, y0 + ih), project(x0 + iw, y0 + ih),
    ]
    let lo = corners.min() ?? 0
    let hi = corners.max() ?? 0

    // Clip the infinite line {base + t·(dx,dy)} to one axis range.
    func clip(_ p0: Double, _ d: Double, _ minV: Double, _ maxV: Double) -> (Double, Double)? {
        if abs(d) < 1e-9 {
            return (p0 >= minV && p0 <= maxV) ? (-1e9, 1e9) : nil
        }
        let a = (minV - p0) / d
        let b = (maxV - p0) / d
        return a < b ? (a, b) : (b, a)
    }

    var out = [[SketchPoint]]()
    var flip = false
    var s = lo + spacing / 2
    while s < hi {
        defer { s += spacing }
        let base = SketchPoint(x: -dy * s, y: dx * s)
        guard
            let cx = clip(base.x, dx, x0, x0 + iw),
            let cy = clip(base.y, dy, y0, y0 + ih)
        else { continue }
        let t0 = max(cx.0, cy.0)
        let t1 = min(cx.1, cy.1)
        guard t1 - t0 >= 4 else { continue }
        var a = SketchPoint(x: base.x + dx * t0, y: base.y + dy * t0)
        var b = SketchPoint(x: base.x + dx * t1, y: base.y + dy * t1)
        if flip { swap(&a, &b) }
        flip.toggle()
        out.append(segment(a, b))
    }
    return out
}

import Foundation

@inline(__always) private func _cos(_ a: Double) -> Double { Foundation.cos(a) }
@inline(__always) private func _sin(_ a: Double) -> Double { Foundation.sin(a) }
