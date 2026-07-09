import Foundation

/// A point in element-local space (not canvas or screen space — SketchKit is
/// UI-agnostic; callers place realized geometry wherever they render it).
public struct SketchPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: SketchPoint) -> Double {
        ((other.x - x) * (other.x - x) + (other.y - y) * (other.y - y)).squareRoot()
    }
}

@inline(__always)
private func smoothstep(_ f: Double) -> Double { f * f * (3 - 2 * f) }

// MARK: - Resampling

/// Resamples a polyline at (nearly) even arc-length intervals. Keeps the
/// first point exactly; keeps the last unless it falls within a quarter
/// spacing of the previous sample.
public func resample(_ points: [SketchPoint], spacing: Double) -> [SketchPoint] {
    guard points.count >= 2, spacing > 0 else { return points }
    var out = [points[0]]
    var prev = points[0]
    var acc = 0.0
    for i in 1..<points.count {
        let target = points[i]
        var d = prev.distance(to: target)
        while acc + d >= spacing, d > 1e-6 {
            let t = (spacing - acc) / d
            let next = SketchPoint(
                x: prev.x + (target.x - prev.x) * t,
                y: prev.y + (target.y - prev.y) * t
            )
            out.append(next)
            prev = next
            d = prev.distance(to: target)
            acc = 0
        }
        acc += d
        prev = target
    }
    if let last = points.last, let tail = out.last,
       tail.distance(to: last) > spacing * 0.25 {
        out.append(last)
    }
    return out
}

/// Cumulative arc length per point; `last` is the total length.
public func arcLengths(_ points: [SketchPoint]) -> [Double] {
    var cum = [0.0]
    cum.reserveCapacity(points.count)
    for i in 1..<max(points.count, 1) {
        cum.append(cum[i - 1] + points[i - 1].distance(to: points[i]))
    }
    return cum
}

// MARK: - Noise

/// Smooth low-frequency 1D noise sampled along arc length: random control
/// values every `wavelength`, smoothstep-interpolated between them.
public struct NoiseCurve: Sendable {
    private let control: [Double]
    private let total: Double

    public init(total: Double, wavelength: Double, rng: inout SketchRandom) {
        self.total = max(total, 1e-9)
        let k = max(2, Int((total / max(4, wavelength)).rounded(.up)) + 1)
        var values = [Double]()
        values.reserveCapacity(k)
        for _ in 0..<k { values.append(rng.nextSigned()) }
        control = values
    }

    /// Value in [-1, 1] at arc length `s`.
    public func value(at s: Double) -> Double {
        let u = min(0.9999, max(0, s / total)) * Double(control.count - 1)
        let i = Int(u)
        let f = smoothstep(u - Double(i))
        return control[i] * (1 - f) + control[i + 1] * f
    }
}

// MARK: - Wobble

/// The hand-drawn displacement: perpendicular + slight tangential noise along
/// the path, plus jittered endpoints (blended in over the first/last ~25pt).
/// Deterministic for a given rng seed — the same stroke always wobbles the
/// same way, which is what keeps the boil from "swimming".
public func wobble(
    _ points: [SketchPoint],
    amplitude: Double,
    wavelength: Double,
    jitter: Double,
    rng: inout SketchRandom
) -> [SketchPoint] {
    let n = points.count
    guard n >= 2 else { return points }
    let cum = arcLengths(points)
    let total = max(cum[n - 1], 1e-9)
    let normalNoise = NoiseCurve(total: total, wavelength: wavelength, rng: &rng)
    let tangentNoise = NoiseCurve(total: total, wavelength: wavelength * 0.7, rng: &rng)
    let e0 = SketchPoint(x: rng.nextSigned() * jitter, y: rng.nextSigned() * jitter)
    let e1 = SketchPoint(x: rng.nextSigned() * jitter, y: rng.nextSigned() * jitter)

    var out = [SketchPoint]()
    out.reserveCapacity(n)
    for i in 0..<n {
        let a = points[max(0, i - 1)]
        let b = points[min(n - 1, i + 1)]
        var tx = b.x - a.x
        var ty = b.y - a.y
        let tl = max((tx * tx + ty * ty).squareRoot(), 1e-9)
        tx /= tl
        ty /= tl
        let (nx, ny) = (-ty, tx)
        let oN = normalNoise.value(at: cum[i]) * amplitude
        let oT = tangentNoise.value(at: cum[i]) * amplitude * 0.35
        let w0 = max(0, 1 - cum[i] / 25)
        let w1 = max(0, 1 - (total - cum[i]) / 25)
        out.append(SketchPoint(
            x: points[i].x + nx * oN + tx * oT + e0.x * w0 + e1.x * w1,
            y: points[i].y + ny * oN + ty * oT + e0.y * w0 + e1.y * w1
        ))
    }
    return out
}

// MARK: - Ink ribbon

/// A variable-width ink polygon around a wobbled centerline. `left`/`right`
/// are the two edges; the fill polygon is `left + right.reversed()`.
public struct RibbonGeometry: Sendable {
    public let center: [SketchPoint]
    public let left: [SketchPoint]
    public let right: [SketchPoint]
    /// Cumulative arc length of the centerline.
    public let cumulative: [Double]
    public let totalLength: Double

    /// Full or partial (scribble-in) fill polygon, up to point index `upTo`.
    public func polygon(upTo: Int? = nil) -> [SketchPoint] {
        let m = min(max(upTo ?? left.count - 1, 1), left.count - 1)
        return Array(left[0...m]) + right[0...m].reversed()
    }

    /// Index of the centerline point at arc length `length` — binary search,
    /// used to cut the ribbon while the pen is mid-stroke.
    public func index(atLength length: Double) -> Int {
        if length >= totalLength { return cumulative.count - 1 }
        var lo = 0
        var hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < length { lo = mid + 1 } else { hi = mid }
        }
        return max(1, lo)
    }
}

/// Builds the ink ribbon: noise-modulated width with pen-pressure tapers at
/// both ends. This is what makes strokes read as ink rather than shaky vectors.
public func ribbon(
    around points: [SketchPoint],
    baseWidth: Double,
    widthVariance: Double,
    taper: Double,
    rng: inout SketchRandom
) -> RibbonGeometry? {
    let n = points.count
    guard n >= 2 else { return nil }
    let cum = arcLengths(points)
    let total = max(cum[n - 1], 1e-9)
    let widthNoise = NoiseCurve(total: total, wavelength: 30, rng: &rng)

    var left = [SketchPoint]()
    var right = [SketchPoint]()
    left.reserveCapacity(n)
    right.reserveCapacity(n)
    for i in 0..<n {
        let a = points[max(0, i - 1)]
        let b = points[min(n - 1, i + 1)]
        var tx = b.x - a.x
        var ty = b.y - a.y
        let tl = max((tx * tx + ty * ty).squareRoot(), 1e-9)
        tx /= tl
        ty /= tl
        let (nx, ny) = (-ty, tx)
        var w = baseWidth * (1 + widthVariance * widthNoise.value(at: cum[i]))
        let tp = taper > 0 ? min(1, cum[i] / taper, (total - cum[i]) / taper) : 1
        w *= 0.22 + 0.78 * max(0.05, tp)
        left.append(SketchPoint(x: points[i].x + nx * w / 2, y: points[i].y + ny * w / 2))
        right.append(SketchPoint(x: points[i].x - nx * w / 2, y: points[i].y - ny * w / 2))
    }
    return RibbonGeometry(
        center: points, left: left, right: right, cumulative: cum, totalLength: total
    )
}
