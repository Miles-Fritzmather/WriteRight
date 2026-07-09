/// Turns skeletons into ink: resample → wobble → ribbon, per boil variant.
/// Rendering-agnostic — the UI layer converts `RealizedStroke` polygons into
/// SwiftUI `Path`s (or, later, tiles/Metal) without touching this logic.

public enum SketchStrokeKind: Sendable, Equatable {
    /// Element outline. Full wobble; the only kind that gets the ghost pass.
    case border
    /// Text. Wobble scaled by `labelWobble` for legibility.
    case label
    /// Small secondary text. Wobble scaled by `labelWobble * 0.6`.
    case subtext
    /// Pressed-state fill. Slightly thinner ink, drawn behind the label.
    case hatch
    /// Decorations (sparks etc.). Full wobble, short taper.
    case accent
}

public struct SkeletonStroke: Sendable {
    public var points: [SketchPoint]
    public var kind: SketchStrokeKind

    public init(points: [SketchPoint], kind: SketchStrokeKind) {
        self.points = points
        self.kind = kind
    }
}

public enum SketchState: Sendable, Equatable {
    case normal
    case pressed
}

public struct RealizedStroke: Sendable {
    public let kind: SketchStrokeKind
    public let ribbon: RibbonGeometry
    /// Per-stroke offset direction for the ghost pass.
    public let ghostOffset: SketchPoint

    public init(kind: SketchStrokeKind, ribbon: RibbonGeometry, ghostOffset: SketchPoint) {
        self.kind = kind
        self.ribbon = ribbon
        self.ghostOffset = ghostOffset
    }
}

/// Realizes one boil variant of a skeleton. Deterministic: stroke `k` of
/// variant `v` always uses seed `hash(seed, k·7 + v, state)`, so geometry is
/// stable across rebuilds and the boil never "swims".
public func realize(
    _ skeleton: [SkeletonStroke],
    style: SketchStyle,
    seed: UInt32,
    variant: Int,
    state: SketchState
) -> [RealizedStroke] {
    let widthMultiplier = state == .pressed ? style.pressWidthMultiplier : 1
    var out = [RealizedStroke]()
    out.reserveCapacity(skeleton.count)
    for (k, stroke) in skeleton.enumerated() {
        var rng = SketchRandom(
            seed: sketchHash(seed, UInt32(truncatingIfNeeded: k * 7 + variant), state == .pressed ? 1 : 0)
        )
        let sampled = resample(stroke.points, spacing: style.spacing)
        let wobbleScale: Double = switch stroke.kind {
        case .label: style.labelWobble
        case .subtext: style.labelWobble * 0.6
        case .border, .hatch, .accent: 1
        }
        let wobbled = wobble(
            sampled,
            amplitude: style.amplitude * wobbleScale,
            wavelength: style.wavelength,
            jitter: style.jitter * wobbleScale,
            rng: &rng
        )
        let baseWidth: Double = switch stroke.kind {
        case .hatch: style.inkWidth * 0.8
        case .subtext: style.inkWidth * 0.75
        case .accent: style.inkWidth * 0.7
        case .border, .label: style.inkWidth
        }
        let taper = stroke.kind == .accent ? 6 : style.taper
        guard let geometry = ribbon(
            around: wobbled,
            baseWidth: baseWidth * widthMultiplier,
            widthVariance: style.widthVariance,
            taper: taper,
            rng: &rng
        ) else { continue }
        out.append(RealizedStroke(
            kind: stroke.kind,
            ribbon: geometry,
            ghostOffset: SketchPoint(
                x: rng.nextSigned() * style.ghostOffset,
                y: rng.nextSigned() * style.ghostOffset
            )
        ))
    }
    return out
}

/// Skeleton for a button: border strokes then label strokes, in writing
/// order (border first, then text — the order the entrance scribbles them).
/// Pressed state appends the hatch fill.
public func buttonSkeleton(
    in rect: SketchRect,
    label: String,
    labelSize: Double,
    style: SketchStyle,
    seed: UInt32,
    state: SketchState,
    font: HersheyFont = .futural
) -> [SkeletonStroke] {
    var rng = SketchRandom(seed: sketchHash(seed, 999, 0))
    var strokes = borderStrokes(
        in: rect, overshoot: style.overshoot, cornerRadius: style.cornerRadius
    ).map { SkeletonStroke(points: $0, kind: .border) }
    strokes += font.textStrokes(
        label,
        size: labelSize,
        centerX: rect.x + rect.width / 2,
        centerY: rect.y + rect.height / 2,
        rng: &rng
    ).map { SkeletonStroke(points: $0, kind: .label) }
    if state == .pressed {
        strokes += hatchStrokes(in: rect, spacing: style.hatchSpacing)
            .map { SkeletonStroke(points: $0, kind: .hatch) }
    }
    return strokes
}

/// Write-on timing for a realized element: strokes drawn sequentially at
/// constant pen speed with a pause between them. Times in seconds.
public struct EntranceSchedule: Sendable {
    public struct Entry: Sendable {
        public let start: Double
        public let duration: Double
        public var end: Double { start + duration }
    }

    public let entries: [Entry]
    public let totalDuration: Double

    public init(strokes: [RealizedStroke], penSpeed: Double, strokePause: Double) {
        var t = 0.0
        var entries = [Entry]()
        entries.reserveCapacity(strokes.count)
        for stroke in strokes where stroke.kind != .hatch {
            let duration = stroke.ribbon.totalLength / max(penSpeed, 1)
            entries.append(Entry(start: t, duration: duration))
            t += duration + strokePause
        }
        self.entries = entries
        totalDuration = t
    }
}
