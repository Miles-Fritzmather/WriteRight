import Foundation
import SketchKit

/// Bundled hand-drawn icon assets (SPEC §7 `IconSource.builtIn`), authored as
/// polyline skeletons in a 24×24 design box (y down) and scaled into a target
/// rect at render time. They occupy the same `[[SketchPoint]]` slot that
/// user-drawn icons will feed in Phase 8 — same pipeline, different author.
///
/// Authoring rules of thumb: 1–3 strokes per icon (each stroke is one pen
/// pull in the write-on entrance), bold silhouettes that survive the wobble
/// at ~20 pt, nothing closer than ~2.5 pt to the box edge (wobble headroom).
enum SketchIconLibrary {
    /// Returns the icon's skeleton fitted into `rect`, or nil for unknown
    /// names (caller falls back to the SF Symbol).
    static func skeleton(name: String, in rect: SketchRect) -> [SkeletonStroke]? {
        guard let design = designs[name] else { return nil }
        return design.map { SkeletonStroke(points: fit($0, into: rect), kind: .label) }
    }

    static func exists(name: String) -> Bool {
        designs[name] != nil
    }

    /// Uniformly scales a 24-box polyline into `rect`, centered.
    private static func fit(_ points: [SketchPoint], into rect: SketchRect) -> [SketchPoint] {
        let scale = min(rect.width, rect.height) / designBox
        let offsetX = rect.x + (rect.width - designBox * scale) / 2
        let offsetY = rect.y + (rect.height - designBox * scale) / 2
        return points.map {
            SketchPoint(x: offsetX + $0.x * scale, y: offsetY + $0.y * scale)
        }
    }

    private static let designBox = 24.0

    private static func p(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: x, y: y)
    }

    /// Open ellipse arc for the lasso loop: sweeps most of the way around,
    /// leaving a gap where the rope "exits" into the tail.
    private static func lassoLoop() -> [SketchPoint] {
        let (cx, cy, rx, ry) = (12.0, 9.0, 7.6, 5.2)
        var pts = [SketchPoint]()
        var degrees = 150.0
        while degrees <= 460 { // gap between 100° and 150°
            let a = degrees * .pi / 180
            pts.append(p(cx + rx * Foundation.cos(a), cy + ry * Foundation.sin(a)))
            degrees += 18
        }
        return pts
    }

    /// One continuous figure-eight for the infinite canvas icon.
    private static func infinityLoop() -> [SketchPoint] {
        var pts = [SketchPoint]()
        for index in 0...36 {
            let t = Double(index) / 36 * 2 * Double.pi
            pts.append(p(12 + 8.1 * Foundation.sin(t), 12 + 4.6 * Foundation.sin(2 * t)))
        }
        return pts
    }

    private static let designs: [String: [[SketchPoint]]] = [
        // Fountain-pen nib, tip down: kite outline + slit.
        "pen": [
            [p(12, 21), p(7.2, 13.5), p(12, 3.5), p(16.8, 13.5), p(12, 21)],
            [p(12, 21), p(12, 11.5)],
        ],
        // Classic diagonal pencil: tip → body loop, plus the wood line.
        "pencil": [
            [p(4, 20.3), p(6.2, 16.2), p(16.6, 5.8), p(18.6, 7.8), p(8.2, 18.2), p(4, 20.3)],
            [p(6.2, 16.2), p(8.2, 18.2)],
        ],
        // Upright marker: cap/body box, cap seam, tapered felt tip.
        "marker": [
            [p(7.5, 3.2), p(16.5, 3.2), p(16.5, 11.5), p(7.5, 11.5), p(7.5, 3.2)],
            [p(7.5, 6.2), p(16.5, 6.2)],
            [p(9, 11.5), p(15, 11.5), p(13.4, 18.6), p(10.6, 18.6), p(9, 11.5)],
        ],
        // Angled highlighter: body, chisel tip, and the swipe it just made.
        "highlighter": [
            [p(6.5, 12.8), p(13.4, 3.6), p(18.4, 7.4), p(11.5, 16.6), p(6.5, 12.8)],
            [p(6.5, 12.8), p(4.6, 15.9), p(8.6, 18.9), p(11.5, 16.6)],
            [p(3.5, 22), p(19, 22)],
        ],
        // Slanted eraser block with its band.
        "eraser": [
            [p(5, 15.2), p(11.6, 7.2), p(19, 12.6), p(12.4, 20.6), p(5, 15.2)],
            [p(8, 11.0), p(14.6, 15.8)],
        ],
        // Lasso: open loop + trailing rope.
        "lasso": [
            lassoLoop(),
            [p(5.9, 13.0), p(4.4, 16.2), p(7.6, 17.8), p(11.4, 20.6), p(15.6, 21.2)],
        ],
        // Folder tile: tab, body, and slightly sagging lower edge.
        "folder": [
            [p(3.4, 7.2), p(9.2, 7.2), p(11.2, 9.3), p(20.5, 9.3),
             p(18.9, 19.3), p(4.8, 19.3), p(3.4, 7.2)],
        ],
        // Loose document sheet with a folded corner and two ruled lines.
        "page": [
            [p(6.2, 3.4), p(14.7, 3.4), p(18.6, 7.5), p(18.6, 20.7), p(6.2, 20.7), p(6.2, 3.4)],
            [p(14.7, 3.4), p(14.7, 8.0), p(18.6, 8.0)],
            [p(8.6, 11.6), p(16.0, 11.6), p(8.6, 15.2), p(15.0, 15.2)],
        ],
        // Infinite canvas: single figure-eight loop.
        "infinity": [
            infinityLoop(),
        ],
        // Small warning mark for recoverable library errors.
        "warning": [
            [p(12, 3.6), p(21, 20.4), p(3, 20.4), p(12, 3.6)],
            [p(12, 8.8), p(12, 14.7), p(12.1, 17.2)],
        ],
        // Trash: lid, bucket sides, and two quick inner slashes.
        "trash": [
            [p(6, 7.2), p(18, 7.2), p(16.8, 20.2), p(7.2, 20.2), p(6, 7.2)],
            [p(5, 5.4), p(19, 5.4), p(14.8, 3.5), p(9.2, 3.5)],
            [p(10, 10.2), p(10.7, 17.1), p(14, 10.2), p(13.3, 17.1)],
        ],
    ]
}
