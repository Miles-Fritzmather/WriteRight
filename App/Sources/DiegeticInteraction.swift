import CoreGraphics
import SwiftUI

/// Diegetic interaction layer (2026-07-09, Miles-approved out-of-spec work).
///
/// The home page is a piece of paper you act on with the pen: the eraser
/// deletes, the lasso grabs-and-drops, and the drawing tools leave marks on
/// folder icons. This file holds the *pure* vocabulary and geometry — the
/// bits with no UIKit or storage — so they can be reasoned about and reused.
/// The UIKit capture surface lives in `DiegeticInputSurface.swift`; the full
/// design writeup lives in `docs/diegetic-ui/README.md`.

/// Identifies a pen-actionable card on a diegetic screen.
enum DiegeticTargetID: Hashable {
    case note(UUID)
    case folder(UUID)
}

/// A card's on-screen rectangle, resolved in the diegetic coordinate space
/// (see `diegeticCoordinateSpace`). Cards publish these up via a preference;
/// the pen surface reads them to decide what a stroke landed on.
struct DiegeticTargetFrame: Equatable {
    var id: DiegeticTargetID
    var frame: CGRect
}

/// The shared coordinate space that both the scrollable card grid and the pen
/// surface live in. Because it is anchored on the viewport-fixed container
/// (not on the scrolling content), a card's reported frame already reflects
/// its current on-screen position, so it lines up with raw touch points.
let diegeticCoordinateSpace = "diegetic.surface"

struct DiegeticTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [DiegeticTargetFrame] = []
    static func reduce(value: inout [DiegeticTargetFrame], nextValue: () -> [DiegeticTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Publishes this card's frame (in the diegetic space) so the pen surface
    /// can hit-test strokes against it. Apply to each note/folder card.
    func diegeticTarget(_ id: DiegeticTargetID) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DiegeticTargetPreferenceKey.self,
                    value: [DiegeticTargetFrame(id: id, frame: proxy.frame(in: .named(diegeticCoordinateSpace)))]
                )
            }
        )
    }
}

/// A recognized command, emitted by the pen surface for the screen to execute.
/// Extend this enum (and the classifier + `DiegeticInputUIView`) when adding a
/// new pen gesture — see the cookbook section of the design doc.
enum DiegeticGesture: Equatable {
    case deleteNote(UUID)
    case deleteFolder(UUID)
    /// nil destination = the library root ("drop it back on the desk").
    case moveNote(UUID, toFolder: UUID?)
    case decorateFolder(UUID, marks: [DiegeticFolderMark])
}

// MARK: - Pure geometry / classification

enum DiegeticClassifier {
    /// The topmost folder whose frame contains `point`, or nil. Later entries
    /// win ties (drawn on top); notes are ignored — only folders receive drops.
    static func folder(at point: CGPoint, in targets: [DiegeticTargetFrame]) -> UUID? {
        var hit: UUID?
        for target in targets {
            guard case .folder(let id) = target.id, target.frame.contains(point) else { continue }
            hit = id
        }
        return hit
    }

    /// The topmost card of any kind under `point`.
    static func target(at point: CGPoint, in targets: [DiegeticTargetFrame]) -> DiegeticTargetID? {
        var hit: DiegeticTargetID?
        for target in targets where target.frame.contains(point) {
            hit = target.id
        }
        return hit
    }

    /// The card a stroke is "on": the one holding the most sampled points, as
    /// long as the stroke commits to it (enough points, enough coverage) so a
    /// grazing tick doesn't nuke a neighbor. Later entries win ties.
    static func primaryTarget(
        for polyline: [CGPoint],
        in targets: [DiegeticTargetFrame],
        minimumInside: Int = 3,
        minimumFraction: CGFloat = 0.3
    ) -> DiegeticTargetID? {
        guard !polyline.isEmpty else { return nil }
        var best: (id: DiegeticTargetID, count: Int)?
        for target in targets {
            let count = polyline.reduce(into: 0) { total, point in
                if target.frame.contains(point) { total += 1 }
            }
            guard count > 0 else { continue }
            if best == nil || count >= best!.count {
                best = (target.id, count)
            }
        }
        guard let best else { return nil }
        let fraction = CGFloat(best.count) / CGFloat(polyline.count)
        guard best.count >= minimumInside, fraction >= minimumFraction else { return nil }
        return best.id
    }

    /// Notes a stroke selects: any note the stroke passes over, plus — when the
    /// stroke is a closed loop — any note whose center it encloses. Covers both
    /// "circle around notes" and "swipe across notes".
    static func selectedNotes(by polyline: [CGPoint], in targets: [DiegeticTargetFrame]) -> [UUID] {
        let closed = isClosedLoop(polyline)
        var ids: [UUID] = []
        for target in targets {
            guard case .note(let id) = target.id else { continue }
            let touched = polyline.contains { target.frame.contains($0) }
            let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
            let enclosed = closed && pointInPolygon(center, polygon: polyline)
            if touched || enclosed { ids.append(id) }
        }
        return ids
    }

    /// A back-and-forth scribble (the canvas's scribble-to-delete gesture,
    /// ported to screen space): long, dense, many direction reversals.
    static func isScribble(_ points: [CGPoint]) -> Bool {
        guard points.count >= 10 else { return false }
        let box = diegeticBoundingRect(points)
        let diagonal = max(hypot(box.width, box.height), 1)
        guard diagonal >= 24 else { return false }
        return diegeticPathLength(points) / diagonal >= 3.2 && diegeticReversals(points) >= 3
    }

    /// A closed loop big enough to read as a deliberate circle/lasso.
    static func isClosedLoop(_ points: [CGPoint]) -> Bool {
        guard let first = points.first, let last = points.last, points.count >= 8 else { return false }
        let box = diegeticBoundingRect(points)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= 40 else { return false }
        let threshold = max(24, min(90, diagonal * 0.28))
        return hypot(first.x - last.x, first.y - last.y) <= threshold
    }

    /// Converts a surface-space polyline into a folder mark, with geometry
    /// normalized to the folder's frame (0…1) and width expressed as a
    /// fraction of the frame's width, so it renders correctly at any card size.
    static func folderMark(
        polyline: [CGPoint],
        in frame: CGRect,
        color: PrototypeInkColor,
        strokeWidth: CGFloat,
        opacity: CGFloat,
        isHighlighter: Bool
    ) -> DiegeticFolderMark? {
        guard frame.width > 0, frame.height > 0, polyline.count > 1 else { return nil }
        let normalized = polyline.map { point in
            CGPoint(
                x: (point.x - frame.minX) / frame.width,
                y: (point.y - frame.minY) / frame.height
            )
        }
        return DiegeticFolderMark(
            points: normalized,
            color: color,
            width: max(strokeWidth / frame.width, 0.004),
            opacity: opacity,
            isHighlighter: isHighlighter
        )
    }
}

// MARK: - Geometry (ported from the canvas's stroke math, screen-space)

private func diegeticBoundingRect(_ points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .zero }
    var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
    for point in points.dropFirst() {
        minX = min(minX, point.x); minY = min(minY, point.y)
        maxX = max(maxX, point.x); maxY = max(maxY, point.y)
    }
    return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
}

private func diegeticPathLength(_ points: [CGPoint]) -> CGFloat {
    guard points.count > 1 else { return 0 }
    var length: CGFloat = 0
    for index in 1..<points.count {
        length += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
    }
    return length
}

private func diegeticReversals(_ points: [CGPoint]) -> Int {
    guard points.count > 2 else { return 0 }
    let box = diegeticBoundingRect(points)
    let useX = box.width >= box.height
    var lastSign = 0
    var reversals = 0
    for index in 1..<points.count {
        let delta = useX ? points[index].x - points[index - 1].x : points[index].y - points[index - 1].y
        guard abs(delta) >= 3 else { continue }
        let sign = delta > 0 ? 1 : -1
        if lastSign != 0, sign != lastSign { reversals += 1 }
        lastSign = sign
    }
    return reversals
}

private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
    guard polygon.count > 2 else { return false }
    var isInside = false
    var j = polygon.count - 1
    for i in polygon.indices {
        let pi = polygon[i], pj = polygon[j]
        if (pi.y > point.y) != (pj.y > point.y) {
            let x = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
            if point.x < x { isInside.toggle() }
        }
        j = i
    }
    return isInside
}
