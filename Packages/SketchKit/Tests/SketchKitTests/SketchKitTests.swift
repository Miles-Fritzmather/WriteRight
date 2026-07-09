import Testing
@testable import SketchKit

// MARK: - RNG (cross-language determinism)

struct SketchRandomTests {
    /// Golden values generated from the JS reference implementation
    /// (Prototypes/sketch-playground.html) with Node 22. Exact equality is
    /// intentional: both sides do 32-bit integer ops then divide by 2^32,
    /// which is exact in IEEE 754 doubles.
    @Test func matchesJSMulberry32() {
        var rng = SketchRandom(seed: 123_456_789)
        #expect(rng.next() == 0.25779074383899570)
        #expect(rng.next() == 0.97077211155556142)
        #expect(rng.next() == 0.78532801428809762)
        #expect(rng.next() == 0.20616457983851433)
    }

    @Test func matchesJSHash() {
        #expect(sketchHash(7, 7, 0) == 2_590_974_131)
        #expect(sketchHash(1, 2, 3) == 3_983_810_697)
    }

    @Test func seededSequenceMatchesJS() {
        var rng = SketchRandom(seed: sketchHash(7, 7, 0))
        #expect(rng.next() == 0.41507326951250434)
        #expect(rng.next() == 0.31677829031832516)
    }
}

// MARK: - Geometry pipeline

struct GeometryTests {
    @Test func resampleIsEvenAndKeepsEndpoints() {
        let pts = [SketchPoint(x: 0, y: 0), SketchPoint(x: 100, y: 0)]
        let sampled = resample(pts, spacing: 5)
        #expect(sampled.first == pts.first)
        #expect(sampled.last == pts.last)
        for i in 1..<(sampled.count - 1) {
            let gap = sampled[i - 1].distance(to: sampled[i])
            #expect(abs(gap - 5) < 1e-9)
        }
    }

    @Test func wobbleIsDeterministicAndSeedSensitive() {
        let pts = resample(
            [SketchPoint(x: 0, y: 0), SketchPoint(x: 200, y: 0)], spacing: 5
        )
        var rngA = SketchRandom(seed: sketchHash(7, 1, 0))
        var rngB = SketchRandom(seed: sketchHash(7, 1, 0))
        var rngC = SketchRandom(seed: sketchHash(7, 2, 0))
        let a = wobble(pts, amplitude: 2.2, wavelength: 38, jitter: 2.5, rng: &rngA)
        let b = wobble(pts, amplitude: 2.2, wavelength: 38, jitter: 2.5, rng: &rngB)
        let c = wobble(pts, amplitude: 2.2, wavelength: 38, jitter: 2.5, rng: &rngC)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func wobbleDisplacementIsBounded() {
        let pts = resample(
            [SketchPoint(x: 0, y: 0), SketchPoint(x: 300, y: 40)], spacing: 4
        )
        var rng = SketchRandom(seed: 42)
        let wobbled = wobble(pts, amplitude: 3, wavelength: 30, jitter: 2, rng: &rng)
        // normal ≤ amp, tangential ≤ 0.35·amp, endpoint jitter ≤ √2·jitter
        let bound = 3.0 * 1.35 + 2.0 * 1.4143 + 1e-6
        for (p, q) in zip(pts, wobbled) {
            #expect(p.distance(to: q) <= bound)
        }
    }

    @Test func ribbonWidthsStayWithinTaperAndVarianceBounds() throws {
        let pts = resample(
            [SketchPoint(x: 0, y: 0), SketchPoint(x: 200, y: 0)], spacing: 5
        )
        var rng = SketchRandom(seed: 1)
        let geometry = try #require(ribbon(
            around: pts, baseWidth: 3.4, widthVariance: 0.5, taper: 14, rng: &rng
        ))
        let maxWidth = 3.4 * 1.5 + 1e-9
        for (l, r) in zip(geometry.left, geometry.right) {
            let width = l.distance(to: r)
            #expect(width > 0)
            #expect(width <= maxWidth)
        }
    }

    @Test func indexAtLengthIsMonotonicAndClamped() throws {
        let pts = resample(
            [SketchPoint(x: 0, y: 0), SketchPoint(x: 100, y: 0)], spacing: 5
        )
        var rng = SketchRandom(seed: 1)
        let geometry = try #require(ribbon(
            around: pts, baseWidth: 3, widthVariance: 0, taper: 0, rng: &rng
        ))
        var previous = 0
        for length in stride(from: 0.0, through: geometry.totalLength + 10, by: 2.5) {
            let index = geometry.index(atLength: length)
            #expect(index >= previous)
            #expect(index >= 1 && index < geometry.center.count)
            previous = index
        }
        #expect(geometry.index(atLength: 1e9) == geometry.center.count - 1)
    }
}

// MARK: - Hershey font

struct HersheyFontTests {
    @Test func parsesAllPrintableASCII() {
        #expect(HersheyFont.futural.glyphs.count == 96)
    }

    @Test func capitalAHasThreeStrokesAndKnownMargins() {
        let a = HersheyFont.futural.glyph(for: "A")
        #expect(a.strokes.count == 3)
        #expect(a.leftMargin == -9)
        #expect(a.rightMargin == 9)
    }

    @Test func layoutCentersOnRequestedPoint() {
        var rng = SketchRandom(seed: 7)
        let strokes = HersheyFont.futural.textStrokes(
            "press me", size: 34, centerX: 50, centerY: -20, rng: &rng
        )
        #expect(!strokes.isEmpty)
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for stroke in strokes {
            for p in stroke {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        #expect(abs((minX + maxX) / 2 - 50) < 1e-9)
        #expect(abs((minY + maxY) / 2 - -20) < 1e-9)
    }

    @Test func everyGlyphSurvivesTheFullPipeline() throws {
        let style = SketchStyle()
        for code in 32...126 {
            guard let scalar = Unicode.Scalar(code) else { continue }
            var rng = SketchRandom(seed: UInt32(code))
            let strokes = HersheyFont.futural.textStrokes(
                String(Character(scalar)), size: 34, centerX: 0, centerY: 0, rng: &rng
            )
            for stroke in strokes {
                var strokeRNG = SketchRandom(seed: UInt32(code))
                let wobbled = wobble(
                    resample(stroke, spacing: style.spacing),
                    amplitude: style.amplitude,
                    wavelength: style.wavelength,
                    jitter: style.jitter,
                    rng: &strokeRNG
                )
                let geometry = ribbon(
                    around: wobbled,
                    baseWidth: style.inkWidth,
                    widthVariance: style.widthVariance,
                    taper: style.taper,
                    rng: &strokeRNG
                )
                let g = try #require(geometry)
                for p in g.left + g.right {
                    #expect(p.x.isFinite && p.y.isFinite)
                }
            }
        }
    }
}

// MARK: - Skeletons & realizer

struct SkeletonTests {
    let rect = SketchRect(x: 0, y: 0, width: 280, height: 100)

    @Test func sharpCornersProduceFourStrokes() {
        let strokes = borderStrokes(in: rect, overshoot: 10, cornerRadius: 0)
        #expect(strokes.count == 4)
    }

    @Test func roundedCornersProduceOneSwoopClosingOnTopEdge() {
        let strokes = borderStrokes(in: rect, overshoot: 10, cornerRadius: 14)
        #expect(strokes.count == 1)
        let swoop = strokes[0]
        // Starts and ends on the top edge, end overlapping past the start.
        #expect(swoop.first?.y == 0)
        #expect(swoop.last?.y == 0)
        #expect((swoop.last?.x ?? 0) > (swoop.first?.x ?? 0))
    }

    @Test func hatchOnlyAppearsWhenPressed() {
        let style = SketchStyle()
        let normal = buttonSkeleton(
            in: rect, label: "hi", labelSize: 34, style: style, seed: 7, state: .normal
        )
        let pressed = buttonSkeleton(
            in: rect, label: "hi", labelSize: 34, style: style, seed: 7, state: .pressed
        )
        #expect(!normal.contains { $0.kind == .hatch })
        #expect(pressed.contains { $0.kind == .hatch })
        // Border+label part of the skeleton is identical across states.
        #expect(normal.count < pressed.count)
    }

    @Test func realizeIsDeterministicPerVariant() {
        let style = SketchStyle()
        let skeleton = buttonSkeleton(
            in: rect, label: "hello world!", labelSize: 34,
            style: style, seed: 7, state: .normal
        )
        let a = realize(skeleton, style: style, seed: 7, variant: 0, state: .normal)
        let b = realize(skeleton, style: style, seed: 7, variant: 0, state: .normal)
        let c = realize(skeleton, style: style, seed: 7, variant: 1, state: .normal)
        #expect(a.count == b.count && a.count == c.count)
        for (x, y) in zip(a, b) {
            #expect(x.ribbon.center == y.ribbon.center)
        }
        #expect(zip(a, c).contains { pair in pair.0.ribbon.center != pair.1.ribbon.center })
    }

    @Test func entranceScheduleIsSequentialAndSkipsHatch() {
        let style = SketchStyle()
        let skeleton = buttonSkeleton(
            in: rect, label: "hi", labelSize: 34, style: style, seed: 7, state: .pressed
        )
        let realized = realize(skeleton, style: style, seed: 7, variant: 0, state: .pressed)
        let schedule = EntranceSchedule(
            strokes: realized, penSpeed: style.penSpeed, strokePause: style.strokePause
        )
        #expect(schedule.entries.count == realized.filter { $0.kind != .hatch }.count)
        var previousEnd = -1.0
        for entry in schedule.entries {
            #expect(entry.duration > 0)
            #expect(entry.start >= previousEnd)
            previousEnd = entry.end
        }
        #expect(schedule.totalDuration >= previousEnd)
    }
}
