import Foundation
import Inject
import SketchKit
import SwiftUI

/// Demo stage for the hand-drawn UI engine — early Phase 8 de-risk, approved
/// 2026-07-07. Direct port of `Prototypes/sketch-playground.html`, with the
/// tuned parameters living as `SketchStyle`'s defaults.
///
/// Theme note (SPEC §7): the screen's chrome goes through `AppButton` as
/// required; the sketch button itself is raw Canvas drawing because it *is*
/// the future `HandDrawnTheme` renderer being proven, not feature UI.
struct SketchDemoScreen: View {
    @ObserveInjection var inject
    @Environment(\.dismiss) private var dismiss
    @State private var model = SketchDemoModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            SketchStageView(model: model)
                .ignoresSafeArea()
            HStack(spacing: 10) {
                AppButton(label: "Close") { dismiss() }
                AppButton(label: "Replay") { model.replayEntrance() }
                AppButton(label: "New seed") { model.randomizeSeed() }
            }
            .padding(16)
        }
        .background(model.paperColor)
        .enableInjection()
    }
}

// MARK: - Stage

/// The canvas that renders button + subtext + sparks, mirroring the
/// playground's single-stage render loop.
private struct SketchStageView: View {
    let model: SketchDemoModel

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                model.draw(in: &context, size: size, at: timeline.date)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            model.stageResized(to: newSize)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in model.touchChanged(at: value.location) }
                .onEnded { value in model.touchEnded(at: value.location) }
        )
    }
}

// MARK: - Model

@MainActor
@Observable
final class SketchDemoModel {
    // Content (style itself lives in SketchKit with the tuned defaults).
    var style = SketchStyle()
    var seed: UInt32 = 7
    var label = "hello world!"
    var labelSize: Double = 34
    var buttonSize = CGSize(width: 342, height: 100)

    private(set) var stageSize: CGSize = .zero

    // Realized geometry caches, one entry per boil variant.
    private var normalVariants: [[CachedStroke]] = []
    private var pressedVariants: [[CachedStroke]] = []
    private var schedule: EntranceSchedule?

    // Animation state.
    private var enterStart = Date()
    private var pressed = false
    private var pressStart = Date()
    private var pressCount = 0
    private var counterVariants: [[CachedStroke]] = []
    private var counterStart = Date()
    private var sparks: [Spark] = []

    var inkColor: Color { Color(hex: style.inkHex) }
    var paperColor: Color { Color(hex: style.paperHex) }

    struct CachedStroke {
        let kind: SketchStrokeKind
        let ribbon: RibbonGeometry
        let fullPath: Path
        let centerPath: Path
        let ghostOffset: SketchPoint
    }

    struct Spark {
        let born: Date
        /// One path list per boil variant.
        let variants: [[Path]]
    }

    // MARK: Layout

    private var buttonRect: SketchRect {
        SketchRect(
            x: (stageSize.width - buttonSize.width) / 2,
            y: (stageSize.height - buttonSize.height) / 2 - 14,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    func stageResized(to size: CGSize) {
        guard size != stageSize, size.width > 10, size.height > 10 else { return }
        stageSize = size
        rebuild()
        replayEntrance()
    }

    // MARK: Actions

    func replayEntrance() {
        enterStart = Date()
        pressCount = 0
        counterVariants = []
        sparks = []
    }

    func randomizeSeed() {
        seed = UInt32.random(in: 0..<1_000_000)
        rebuild()
        if pressCount > 0 { rebuildCounter() }
    }

    func touchChanged(at location: CGPoint) {
        if !pressed, hitTest(location) {
            pressed = true
            pressStart = Date()
        }
    }

    func touchEnded(at location: CGPoint) {
        if pressed, hitTest(location) {
            pressCount += 1
            rebuildCounter()
            spawnSparks()
        }
        pressed = false
    }

    private func hitTest(_ location: CGPoint) -> Bool {
        let r = buttonRect
        return location.x >= r.x - 8 && location.x <= r.x + r.width + 8
            && location.y >= r.y - 8 && location.y <= r.y + r.height + 8
    }

    // MARK: Geometry caches

    private func rebuild() {
        normalVariants = (0..<style.variants).map { variant in
            cached(realize(
                buttonSkeleton(
                    in: buttonRect, label: label, labelSize: labelSize,
                    style: style, seed: seed, state: .normal
                ),
                style: style, seed: seed, variant: variant, state: .normal
            ))
        }
        pressedVariants = (0..<style.variants).map { variant in
            cached(realize(
                buttonSkeleton(
                    in: buttonRect, label: label, labelSize: labelSize,
                    style: style, seed: seed, state: .pressed
                ),
                style: style, seed: seed, variant: variant, state: .pressed
            ))
        }
        if let first = normalVariants.first {
            schedule = EntranceSchedule(
                cached: first, penSpeed: style.penSpeed, strokePause: style.strokePause
            )
        }
    }

    private func rebuildCounter() {
        let r = buttonRect
        var layoutRNG = SketchRandom(seed: sketchHash(seed, 4242, UInt32(pressCount)))
        let strokes = HersheyFont.futural.textStrokes(
            "pressed x\(pressCount)",
            size: max(14, labelSize * 0.45),
            centerX: r.x + r.width / 2,
            centerY: r.y + r.height + 38,
            rng: &layoutRNG
        ).map { SkeletonStroke(points: $0, kind: .subtext) }
        counterVariants = (0..<style.variants).map { variant in
            cached(realize(
                strokes, style: style,
                seed: sketchHash(seed &+ 1, UInt32(variant), UInt32(pressCount)),
                variant: variant, state: .normal
            ))
        }
        counterStart = Date()
    }

    private func spawnSparks() {
        let now = Date()
        sparks.removeAll { now.timeIntervalSince($0.born) >= 0.42 }
        let r = buttonRect
        var rng = SketchRandom(seed: sketchHash(seed, 777, UInt32(pressCount)))
        let cx = r.x + r.width + 6 + rng.next() * 10
        let cy = r.y - 6 - rng.next() * 8
        var rays = [SkeletonStroke]()
        let rayCount = 5 + Int(rng.next() * 3)
        for _ in 0..<rayCount {
            let angle = -Double.pi * 0.05 - rng.next() * Double.pi * 0.55
            let r0 = 6 + rng.next() * 5
            let r1 = r0 + 10 + rng.next() * 14
            rays.append(SkeletonStroke(
                points: [
                    SketchPoint(x: cx + cos(angle) * r0, y: cy + sin(angle) * r0),
                    SketchPoint(x: cx + cos(angle) * r1, y: cy + sin(angle) * r1),
                ],
                kind: .accent
            ))
        }
        let variants = (0..<style.variants).map { variant in
            realize(
                rays, style: style,
                seed: sketchHash(seed &+ 2, UInt32(variant), UInt32(pressCount)),
                variant: variant, state: .normal
            ).map { Path(polygon: $0.ribbon.polygon()) }
        }
        sparks.append(Spark(born: Date(), variants: variants))
    }

    private func cached(_ strokes: [RealizedStroke]) -> [CachedStroke] {
        strokes.map { stroke in
            CachedStroke(
                kind: stroke.kind,
                ribbon: stroke.ribbon,
                fullPath: Path(polygon: stroke.ribbon.polygon()),
                centerPath: Path(polyline: stroke.ribbon.center),
                ghostOffset: stroke.ghostOffset
            )
        }
    }

    // MARK: Rendering (mirrors the playground's render loop)

    func draw(in context: inout GraphicsContext, size: CGSize, at date: Date) {
        guard !normalVariants.isEmpty, let schedule else { return }
        let ink = inkColor
        let time = date.timeIntervalSinceReferenceDate
        let variant = Int(time * style.boilFps) % style.variants
        let strokes = pressed ? pressedVariants[variant] : normalVariants[variant]
        let nextVariant = pressed
            ? pressedVariants[(variant + 1) % style.variants]
            : normalVariants[(variant + 1) % style.variants]
        let r = buttonRect

        var stage = context
        if pressed {
            let cx = r.x + r.width / 2
            let cy = r.y + r.height / 2
            stage.translateBy(x: cx, y: cy)
            stage.scaleBy(x: 2 - style.pressSquash, y: style.pressSquash)
            stage.translateBy(x: -cx, y: -cy)
        }

        let elapsed = date.timeIntervalSince(enterStart)
        var hatchBudget = 0.0
        if pressed {
            let hatchTotal = strokes
                .filter { $0.kind == .hatch }
                .reduce(0) { $0 + $1.ribbon.totalLength }
            let reveal = min(1, date.timeIntervalSince(pressStart) / 0.13)
            hatchBudget = hatchTotal * reveal
        }

        // Hatch first (behind the label), then border + label on top.
        for stroke in strokes where stroke.kind == .hatch {
            guard hatchBudget > 0 else { break }
            let take = min(stroke.ribbon.totalLength, hatchBudget)
            hatchBudget -= stroke.ribbon.totalLength
            let path = take >= stroke.ribbon.totalLength
                ? stroke.fullPath
                : Path(polygon: stroke.ribbon.polygon(upTo: stroke.ribbon.index(atLength: take)))
            stage.opacity = 0.45
            stage.fill(path, with: .color(ink))
            stage.opacity = 1
        }

        for (k, stroke) in strokes.enumerated() where stroke.kind != .hatch {
            if k < schedule.entries.count {
                let entry = schedule.entries[k]
                if elapsed < entry.start { continue } // pen hasn't reached this stroke
                if elapsed < entry.end {              // scribbling it right now
                    let length = (elapsed - entry.start) * style.penSpeed
                    let path = Path(
                        polygon: stroke.ribbon.polygon(upTo: stroke.ribbon.index(atLength: length))
                    )
                    stage.fill(path, with: .color(ink))
                    continue
                }
            }
            // Completed: ink, plus the ghost sketch line from the next
            // variant (border only — double lines hurt text legibility).
            stage.fill(stroke.fullPath, with: .color(ink))
            if style.ghost, stroke.kind == .border, k < nextVariant.count {
                var ghost = stage
                ghost.translateBy(x: stroke.ghostOffset.x, y: stroke.ghostOffset.y)
                ghost.stroke(
                    nextVariant[k].centerPath,
                    with: .color(ink.opacity(style.ghostAlpha)),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                )
            }
        }

        // Press-count subtext, written on fast whenever the count changes.
        if !counterVariants.isEmpty {
            var budget = date.timeIntervalSince(counterStart) * style.penSpeed * 2.2
            for stroke in counterVariants[variant] {
                guard budget > 0 else { break }
                let take = min(stroke.ribbon.totalLength, budget)
                budget -= stroke.ribbon.totalLength
                let path = take >= stroke.ribbon.totalLength
                    ? stroke.fullPath
                    : Path(polygon: stroke.ribbon.polygon(upTo: stroke.ribbon.index(atLength: take)))
                context.fill(path, with: .color(ink.opacity(0.75)))
            }
        }

        // Sparks: scribble in fast, fade out. (Expired sparks are skipped
        // here and pruned in spawnSparks — no state mutation during draw.)
        for spark in sparks {
            let age = date.timeIntervalSince(spark.born)
            guard age < 0.42 else { continue }
            let reveal = min(1, age / 0.11)
            let alpha = age < 0.25 ? 0.9 : max(0, 0.9 * (1 - (age - 0.25) / 0.17))
            let paths = spark.variants[variant]
            let shown = max(1, Int(Double(paths.count) * reveal))
            for path in paths.prefix(shown) {
                context.fill(path, with: .color(ink.opacity(alpha)))
            }
        }
    }
}

// MARK: - Bridging helpers

extension EntranceSchedule {
    /// Convenience over the cached representation the demo model stores.
    @MainActor
    init(cached: [SketchDemoModel.CachedStroke], penSpeed: Double, strokePause: Double) {
        let realized = cached.map {
            RealizedStroke(kind: $0.kind, ribbon: $0.ribbon, ghostOffset: $0.ghostOffset)
        }
        self.init(strokes: realized, penSpeed: penSpeed, strokePause: strokePause)
    }
}

// Path/Color bridging for SketchKit geometry lives in SketchSwiftUIBridge.swift
// (shared with HandDrawnTheme).
