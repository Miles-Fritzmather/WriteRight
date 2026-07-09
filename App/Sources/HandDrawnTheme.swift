import Foundation
import Inject
import SketchKit
import SwiftUI

/// The hand-drawn theme (SPEC §7, pulled forward from Phase 8 for the
/// toolbar with Miles's approval, 2026-07-08). Every primitive renders
/// through SketchKit's wobble → boil → ink-ribbon pipeline with the tuned
/// `SketchStyle` defaults — the same styling as the sketch demo button.
///
/// Feature code is untouched by design: this is the theme swap §7 exists for.
struct HandDrawnTheme: Theme {
    var style = SketchStyle()

    private var ink: Color { Color(hex: style.inkHex) }
    private var paper: Color { Color(hex: style.paperHex) }

    /// Demo parameters are tuned for a 342×100 hero button; controls are a
    /// quarter that size, so ink width and wobble scale down with them.
    private var controlStyle: SketchStyle {
        var s = style
        s.inkWidth = 2.3
        s.amplitude = 1.5
        s.jitter = 1.3
        s.taper = 7
        s.spacing = 4
        s.cornerRadius = 9
        s.overshoot = 6
        s.hatchSpacing = 6.5
        s.ghostOffset = 1.5
        return s
    }

    /// Toolbar chrome: heavier ink, faster pen so the long border swoop
    /// doesn't hold up the entrance.
    private var chromeStyle: SketchStyle {
        var s = style
        s.inkWidth = 2.9
        s.cornerRadius = 12
        s.penSpeed = 2800
        return s
    }

    /// Free-standing text: ghost pass off (double lines hurt legibility).
    private var textStyle: SketchStyle {
        var s = controlStyle
        s.ghost = false
        return s
    }

    /// Grid cards need more breathing room than toolbar controls, but less
    /// visual weight than the floating tool chrome.
    private var cardStyle: SketchStyle {
        var s = style
        s.inkWidth = 2.4
        s.amplitude = 1.7
        s.jitter = 1.35
        s.cornerRadius = 12
        s.overshoot = 7
        s.ghostOffset = 1.4
        s.penSpeed = 3200
        return s
    }

    /// Launch stagger so the toolbar writes itself on as a wave rather than
    /// all at once — deterministic per element, like everything else here.
    private static func entranceDelay(_ seedKey: String) -> Double {
        Double(sketchSeed(seedKey) % 400) / 1000
    }

    private func pointSize(for role: AppTextRole) -> Double {
        switch role {
        case .title:
            22
        case .heading:
            13
        case .caption:
            8.2
        }
    }

    // MARK: Theme conformance

    func button(_ label: String, action: @escaping () -> Void) -> AnyView {
        let s = controlStyle
        let seedKey = "button.\(label)"
        let seed = sketchSeed(seedKey)
        let labelSize = 10.5
        // Must match the rng seed `buttonSkeleton` uses for its label so the
        // measured width and the rendered strokes agree.
        let measured = hersheyTextSize(label, size: labelSize, seed: sketchHash(seed, 999, 0))
        let width = max(54, measured.width + 28)
        let inkColor = ink

        return AnyView(
            Button(action: action) { Color.clear }
                .buttonStyle(SketchPressStyle { pressed in
                    AnyView(
                        SketchElementView(
                            seedKey: seedKey,
                            style: s,
                            pressed: pressed,
                            pressable: true,
                            entranceDelay: Self.entranceDelay(seedKey),
                            color: { kind, _ in
                                kind == .hatch ? inkColor.opacity(0.4) : inkColor
                            },
                            skeleton: { rect, state in
                                buttonSkeleton(
                                    in: rect.insetBy(3.5),
                                    label: label,
                                    labelSize: labelSize,
                                    style: s,
                                    seed: seed,
                                    state: state
                                )
                            }
                        )
                        .frame(width: width, height: 30)
                    )
                })
                .accessibilityLabel(label)
        )
    }

    func menu(_ label: String, actions: [AppMenuAction]) -> AnyView {
        let s = controlStyle
        let seedKey = "menu.\(label)"
        let seed = sketchSeed(seedKey)
        let labelSize = 10.5
        let measured = hersheyTextSize(label, size: labelSize, seed: sketchHash(seed, 999, 0))
        let inkColor = ink

        return AnyView(
            Menu {
                if actions.isEmpty {
                    Text("No saved notes")
                } else {
                    ForEach(actions) { action in
                        Button(action.title, action: action.action)
                    }
                }
            } label: {
                SketchElementView(
                    seedKey: seedKey,
                    style: s,
                    entranceDelay: Self.entranceDelay(seedKey),
                    color: { _, _ in inkColor },
                    skeleton: { rect, state in
                        buttonSkeleton(
                            in: rect.insetBy(3.5),
                            label: label,
                            labelSize: labelSize,
                            style: s,
                            seed: seed,
                            state: state
                        )
                    }
                )
                .frame(width: max(54, measured.width + 28), height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        )
    }

    func icon(_ source: IconSource, size: CGFloat) -> AnyView {
        switch source {
        case .builtIn(let name, _) where SketchIconLibrary.exists(name: name):
            let s = textStyle
            let inkColor = ink
            let seedKey = "icon.\(name)"
            return AnyView(
                SketchElementView(
                    seedKey: seedKey,
                    style: s,
                    entranceDelay: Self.entranceDelay(seedKey),
                    color: { _, _ in inkColor },
                    skeleton: { rect, _ in
                        SketchIconLibrary.skeleton(name: name, in: rect) ?? []
                    }
                )
                .frame(width: size, height: size)
            )
        case .systemSymbol(let name), .builtIn(_, let name):
            return AnyView(
                Image(systemName: name)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(width: size, height: size)
            )
        }
    }

    func iconButton(
        _ source: IconSource,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> AnyView {
        let s = controlStyle
        let seedKey = "tool.\(title)"
        let seed = sketchSeed(seedKey)
        let inkColor = ink
        let iconName: String? = switch source {
        case .builtIn(let name, _) where SketchIconLibrary.exists(name: name): name
        default: nil
        }
        // Shrink long titles ("Highlight") to fit inside the border.
        var fittedTitleSize = 6.8
        let measuredTitle = hersheyTextSize(title, size: fittedTitleSize, seed: sketchHash(seed, 555, 0))
        if measuredTitle.width > 44 {
            fittedTitleSize *= 44 / measuredTitle.width
        }
        let titleSize = fittedTitleSize

        return AnyView(
            Button(action: action) { Color.clear }
                .buttonStyle(SketchPressStyle { pressed in
                    AnyView(
                        SketchElementView(
                            seedKey: seedKey,
                            style: s,
                            pressed: pressed,
                            pressable: true,
                            entranceDelay: Self.entranceDelay(seedKey),
                            revision: isSelected ? "selected" : "normal",
                            color: { kind, state in
                                switch kind {
                                case .hatch:
                                    state == .pressed
                                        ? inkColor.opacity(0.38)
                                        : inkColor.opacity(0.14)
                                case .border:
                                    inkColor.opacity(isSelected ? 1 : 0.55)
                                default:
                                    inkColor.opacity(isSelected ? 1 : 0.72)
                                }
                            },
                            skeleton: { rect, state in
                                let border = rect.insetBy(3.5)
                                var strokes = borderStrokes(
                                    in: border,
                                    overshoot: s.overshoot,
                                    cornerRadius: s.cornerRadius
                                ).map { SkeletonStroke(points: $0, kind: .border) }
                                if let iconName {
                                    let iconBox = SketchRect(
                                        x: rect.x + (rect.width - 20) / 2,
                                        y: border.y + 3,
                                        width: 20,
                                        height: 20
                                    )
                                    strokes += SketchIconLibrary.skeleton(name: iconName, in: iconBox) ?? []
                                }
                                strokes += hersheyTextSkeleton(
                                    title,
                                    size: titleSize,
                                    center: SketchPoint(
                                        x: rect.x + rect.width / 2,
                                        y: border.y + border.height - 7.5
                                    ),
                                    seed: sketchHash(seed, 555, 0),
                                    kind: .subtext
                                )
                                if state == .pressed || isSelected {
                                    strokes += hatchStrokes(in: border, spacing: s.hatchSpacing)
                                        .map { SkeletonStroke(points: $0, kind: .hatch) }
                                }
                                return strokes
                            }
                        )
                        .frame(width: 58, height: 46)
                    )
                })
                .accessibilityLabel(title)
                .accessibilityValue(isSelected ? "Selected" : "")
        )
    }

    func colorSwatch(
        _ color: Color,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> AnyView {
        var s = controlStyle
        s.inkWidth = 2.1
        s.taper = 5
        let swatchStyle = s
        let seedKey = "swatch.\(title)"
        let inkColor = ink

        return AnyView(
            Button(action: action) { Color.clear }
                .buttonStyle(SketchPressStyle { pressed in
                    AnyView(
                        SketchElementView(
                            seedKey: seedKey,
                            style: swatchStyle,
                            pressed: pressed,
                            pressable: true,
                            entranceDelay: Self.entranceDelay(seedKey),
                            revision: isSelected ? "selected" : "normal",
                            color: { kind, _ in
                                switch kind {
                                case .border: color
                                case .hatch: color.opacity(0.85)
                                case .accent: inkColor
                                default: inkColor
                                }
                            },
                            skeleton: { rect, _ in
                                let cx = rect.x + rect.width / 2
                                let cy = rect.y + rect.height / 2
                                // Crayon ring + scribble fill; selection adds
                                // an ink lasso around the whole swatch.
                                var strokes = [
                                    SkeletonStroke(
                                        points: ringPoints(cx: cx, cy: cy, radius: 10.5, seedKey: seedKey),
                                        kind: .border
                                    ),
                                    SkeletonStroke(
                                        points: spiralPoints(cx: cx, cy: cy, outer: 8.2, inner: 1.4, turns: 2.7),
                                        kind: .hatch
                                    ),
                                ]
                                if isSelected {
                                    strokes.append(SkeletonStroke(
                                        points: ringPoints(cx: cx, cy: cy, radius: 15, seedKey: seedKey + ".ring"),
                                        kind: .accent
                                    ))
                                }
                                return strokes
                            }
                        )
                        .frame(width: 38, height: 38)
                    )
                })
                .accessibilityLabel(title)
                .accessibilityValue(isSelected ? "Selected" : "")
        )
    }

    func toggle(_ isOn: Binding<Bool>, label: String) -> AnyView {
        let s = controlStyle
        let seedKey = "toggle.\(label)"
        let seed = sketchSeed(seedKey)
        let labelSize = 10.5
        let measured = hersheyTextSize(label, size: labelSize, seed: sketchHash(seed, 555, 0))
        let boxSide = 13.0
        let width = measured.width + boxSide + 36
        let inkColor = ink

        return AnyView(
            Button { isOn.wrappedValue.toggle() } label: { Color.clear }
                .buttonStyle(SketchPressStyle { pressed in
                    AnyView(
                        SketchElementView(
                            seedKey: seedKey,
                            style: s,
                            pressed: pressed,
                            pressable: true,
                            entranceDelay: Self.entranceDelay(seedKey),
                            revision: isOn.wrappedValue ? "on" : "off",
                            color: { kind, _ in
                                kind == .hatch ? inkColor.opacity(0.38) : inkColor
                            },
                            skeleton: { rect, state in
                                let border = rect.insetBy(3.5)
                                var strokes = borderStrokes(
                                    in: border, overshoot: s.overshoot, cornerRadius: s.cornerRadius
                                ).map { SkeletonStroke(points: $0, kind: .border) }
                                let box = SketchRect(
                                    x: border.x + 7,
                                    y: rect.y + (rect.height - boxSide) / 2,
                                    width: boxSide,
                                    height: boxSide
                                )
                                // Sharp sketchbook box (cornerRadius < 1 →
                                // four overshooting side strokes).
                                strokes += borderStrokes(in: box, overshoot: 2.2, cornerRadius: 0)
                                    .map { SkeletonStroke(points: $0, kind: .label) }
                                if isOn.wrappedValue {
                                    strokes.append(SkeletonStroke(
                                        points: [
                                            SketchPoint(x: box.x + 2.4, y: box.y + 7),
                                            SketchPoint(x: box.x + 5.6, y: box.y + 10.6),
                                            SketchPoint(x: box.x + 12.6, y: box.y + 1.2),
                                        ],
                                        kind: .accent
                                    ))
                                }
                                strokes += hersheyTextSkeleton(
                                    label,
                                    size: labelSize,
                                    center: SketchPoint(
                                        x: box.x + boxSide + 8 + measured.width / 2,
                                        y: rect.y + rect.height / 2
                                    ),
                                    seed: sketchHash(seed, 555, 0),
                                    kind: .label
                                )
                                if state == .pressed {
                                    strokes += hatchStrokes(in: border, spacing: s.hatchSpacing)
                                        .map { SkeletonStroke(points: $0, kind: .hatch) }
                                }
                                return strokes
                            }
                        )
                        .frame(width: width, height: 30)
                    )
                })
                .accessibilityLabel(label)
                .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        )
    }

    func toolbarContainer(_ content: AnyView) -> AnyView {
        let s = chromeStyle
        let inkColor = ink
        let paperColor = paper
        return AnyView(
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    SketchElementView(
                        seedKey: "toolbar.container",
                        style: s,
                        entranceDelay: 0,
                        paperFill: paperColor,
                        color: { _, _ in inkColor },
                        skeleton: { rect, _ in
                            borderStrokes(
                                in: rect.insetBy(6),
                                overshoot: s.overshoot,
                                cornerRadius: s.cornerRadius
                            ).map { SkeletonStroke(points: $0, kind: .border) }
                        }
                    )
                    .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                )
        )
    }

    func arcToolbarContainer(_ content: AnyView) -> AnyView {
        let s = chromeStyle
        let inkColor = ink
        let paperColor = paper
        return AnyView(
            content
                .background(
                    SketchElementView(
                        seedKey: "toolbar.arc.container",
                        style: s,
                        entranceDelay: 0,
                        paperFill: paperColor,
                        color: { _, _ in inkColor },
                        skeleton: { rect, _ in
                            [SkeletonStroke(
                                points: arcToolbarBorder(in: rect.insetBy(6)),
                                kind: .border
                            )]
                        }
                    )
                    .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                )
        )
    }

    func label(_ text: String) -> AnyView {
        let s = textStyle
        let seedKey = "label.\(text)"
        let seed = sketchSeed(seedKey)
        let size = 9.0
        let measured = hersheyTextSize(text, size: size, seed: sketchHash(seed, 555, 0))
        let inkColor = ink
        return AnyView(
            SketchElementView(
                seedKey: seedKey,
                style: s,
                entranceDelay: Self.entranceDelay(seedKey),
                color: { _, _ in inkColor.opacity(0.72) },
                skeleton: { rect, _ in
                    hersheyTextSkeleton(
                        text,
                        size: size,
                        center: SketchPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2),
                        seed: sketchHash(seed, 555, 0),
                        kind: .subtext
                    )
                }
            )
            .frame(width: measured.width + 8, height: max(16, measured.height + 8))
            .accessibilityLabel(text)
        )
    }

    func divider(height: CGFloat, key: String) -> AnyView {
        let s = textStyle
        let seedKey = "divider.\(key)"
        let inkColor = ink
        return AnyView(
            SketchElementView(
                seedKey: seedKey,
                style: s,
                entranceDelay: Self.entranceDelay(seedKey),
                color: { _, _ in inkColor.opacity(0.45) },
                skeleton: { rect, _ in
                    [SkeletonStroke(
                        points: [
                            SketchPoint(x: rect.x + rect.width / 2 + 1, y: rect.y + 3),
                            SketchPoint(x: rect.x + rect.width / 2 - 1, y: rect.y + rect.height - 3),
                        ],
                        kind: .accent
                    )]
                }
            )
            .frame(width: 9, height: height)
        )
    }

    func text(_ text: String, role: AppTextRole) -> AnyView {
        var s = textStyle
        switch role {
        case .title:
            s.inkWidth = 2.8
            s.amplitude = 1.2
            s.penSpeed = 3400
        case .heading:
            s.inkWidth = 2.2
            s.amplitude = 1.0
        case .caption:
            s.inkWidth = 1.6
            s.amplitude = 0.7
        }
        let seedKey = "text.\(role.seedName).\(text)"
        let seed = sketchSeed(seedKey)
        let size = pointSize(for: role)
        let measured = hersheyTextSize(text, size: size, seed: sketchHash(seed, 555, 0))
        let inkColor = ink.opacity(role == .caption ? 0.72 : 0.95)

        return AnyView(
            SketchElementView(
                seedKey: seedKey,
                style: s,
                entranceDelay: Self.entranceDelay(seedKey),
                color: { _, _ in inkColor },
                skeleton: { rect, _ in
                    hersheyTextSkeleton(
                        text,
                        size: size,
                        center: SketchPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2),
                        seed: sketchHash(seed, 555, 0),
                        kind: .label
                    )
                }
            )
            .frame(width: measured.width + 10, height: max(measured.height + 10, size + 8))
            .accessibilityLabel(text)
        )
    }

    func cardContainer(_ content: AnyView, key: String) -> AnyView {
        let s = cardStyle
        let seedKey = "card.\(key)"
        let inkColor = ink
        let paperColor = paper

        return AnyView(
            content
                .background(
                    SketchElementView(
                        seedKey: seedKey,
                        style: s,
                        entranceDelay: Self.entranceDelay(seedKey),
                        paperFill: paperColor,
                        color: { _, _ in inkColor },
                        skeleton: { rect, _ in
                            borderStrokes(
                                in: rect.insetBy(6),
                                overshoot: s.overshoot,
                                cornerRadius: s.cornerRadius
                            ).map { SkeletonStroke(points: $0, kind: .border) }
                        }
                    )
                    .shadow(color: .black.opacity(0.09), radius: 4, y: 2)
                )
        )
    }
}

private extension AppTextRole {
    var seedName: String {
        switch self {
        case .title:
            "title"
        case .heading:
            "heading"
        case .caption:
            "caption"
        }
    }
}

// MARK: - Press plumbing

/// Renders a hand-drawn control in place of the system button chrome,
/// feeding `isPressed` through so the element can squash + hatch like the
/// demo button. Internal so hand-drawn components outside the theme (the
/// keyboard, popups) can reuse the same press behavior.
struct SketchPressStyle: ButtonStyle {
    let content: (Bool) -> AnyView

    func makeBody(configuration: Configuration) -> some View {
        content(configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - The boiling element renderer

/// One hand-drawn element: realizes its skeleton through SketchKit once per
/// size/revision, caches every boil variant as prebuilt `Path`s, then just
/// re-composites on a timeline — full frame rate only while something is
/// animating (entrance, press), `boilFps` otherwise.
struct SketchElementView: View {
    @ObserveInjection var inject

    let seedKey: String
    let style: SketchStyle
    var pressed: Bool = false
    /// Realize the pressed-state variants too (buttons); off for static
    /// chrome so it isn't computed twice.
    var pressable: Bool = false
    /// Seconds after appear before the write-on starts; nil = no entrance.
    var entranceDelay: Double? = nil
    /// Fills the first border stroke's centerline loop — the paper itself
    /// boils along with the ink.
    var paperFill: Color? = nil
    /// Skeleton-content fingerprint; bump it (e.g. "selected"/"normal") to
    /// re-realize geometry without replaying the entrance.
    var revision: String = ""
    let color: (SketchStrokeKind, SketchState) -> Color
    let skeleton: (SketchRect, SketchState) -> [SkeletonStroke]

    @State private var cache: RealizedCache?
    @State private var appearedAt: Date?
    @State private var pressStartedAt = Date.distantPast
    @State private var fastUntil: Date?

    private struct RealizedCache {
        var size: CGSize
        var normal: [[SketchCachedStroke]]
        var pressedVariants: [[SketchCachedStroke]]
        var schedule: EntranceSchedule?
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumFrameInterval)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, at: timeline.date)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            rebuild(for: newSize)
        }
        .onChange(of: revision) {
            if let size = cache?.size {
                rebuild(for: size, force: true)
            }
        }
        .onChange(of: pressed) { _, isDown in
            if isDown { pressStartedAt = Date() }
            holdFastFrames(0.45)
        }
        .task(id: fastUntil) {
            // When the fast window lapses, drop back to boil cadence.
            guard let until = fastUntil else { return }
            let remaining = until.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            if !Task.isCancelled { fastUntil = nil }
        }
        .enableInjection()
    }

    private var minimumFrameInterval: Double {
        if let fastUntil, fastUntil.timeIntervalSinceNow > 0 { return 1.0 / 120.0 }
        return 1.0 / max(style.boilFps, 0.1)
    }

    private func holdFastFrames(_ seconds: Double) {
        let candidate = Date().addingTimeInterval(seconds)
        if fastUntil.map({ candidate > $0 }) ?? true {
            fastUntil = candidate
        }
    }

    private func rebuild(for size: CGSize, force: Bool = false) {
        guard size.width > 4, size.height > 4 else { return }
        if !force, let cache, cache.size == size { return }

        let rect = SketchRect(x: 0, y: 0, width: size.width, height: size.height)
        let seed = sketchSeed(seedKey)

        let normalRealized = (0..<style.variants).map { variant in
            realize(skeleton(rect, .normal), style: style, seed: seed, variant: variant, state: .normal)
        }
        let normal = normalRealized.map { $0.map(SketchCachedStroke.init) }
        let pressedVariants: [[SketchCachedStroke]] = pressable
            ? (0..<style.variants).map { variant in
                realize(skeleton(rect, .pressed), style: style, seed: seed, variant: variant, state: .pressed)
                    .map(SketchCachedStroke.init)
            }
            : normal

        var schedule: EntranceSchedule?
        if entranceDelay != nil, let first = normalRealized.first {
            schedule = EntranceSchedule(
                strokes: first, penSpeed: style.penSpeed, strokePause: style.strokePause
            )
        }
        cache = RealizedCache(
            size: size, normal: normal, pressedVariants: pressedVariants, schedule: schedule
        )

        if appearedAt == nil {
            appearedAt = Date()
            if let entranceDelay, let schedule {
                holdFastFrames(entranceDelay + schedule.totalDuration + 0.2)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, at date: Date) {
        guard let cache, !cache.normal.isEmpty else { return }
        let variantCount = cache.normal.count
        // Per-element phase offset so the whole toolbar doesn't flip its
        // boil variant on the same clock tick.
        let phase = Double(sketchSeed(seedKey) % 997) / 997 / max(style.boilFps, 0.1)
        let time = date.timeIntervalSinceReferenceDate + phase
        let variant = Int(time * style.boilFps) % variantCount
        let strokes = pressed ? cache.pressedVariants[variant] : cache.normal[variant]
        let next = (pressed ? cache.pressedVariants : cache.normal)[(variant + 1) % variantCount]
        let state: SketchState = pressed ? .pressed : .normal

        var stage = context
        if pressed {
            let cx = size.width / 2
            let cy = size.height / 2
            stage.translateBy(x: cx, y: cy)
            stage.scaleBy(x: 2 - style.pressSquash, y: style.pressSquash)
            stage.translateBy(x: -cx, y: -cy)
        }

        if let paperFill, let border = strokes.first(where: { $0.kind == .border }) {
            stage.fill(border.centerLoop, with: .color(paperFill))
        }

        let elapsed: Double
        if let entranceDelay, let appearedAt {
            elapsed = date.timeIntervalSince(appearedAt) - entranceDelay
        } else {
            elapsed = .infinity
        }
        let entranceComplete = elapsed >= (cache.schedule?.totalDuration ?? -1)

        // Hatch first (behind border/label), press-revealed like the demo;
        // held back until the element has finished writing itself on.
        if entranceComplete || pressed {
            var hatchBudget = Double.infinity
            if pressed {
                let total = strokes
                    .filter { $0.kind == .hatch }
                    .reduce(0) { $0 + $1.ribbon.totalLength }
                hatchBudget = total * min(1, date.timeIntervalSince(pressStartedAt) / 0.13)
            }
            for stroke in strokes where stroke.kind == .hatch {
                guard hatchBudget > 0 else { break }
                let take = min(stroke.ribbon.totalLength, hatchBudget)
                hatchBudget -= stroke.ribbon.totalLength
                let path = take >= stroke.ribbon.totalLength
                    ? stroke.fullPath
                    : Path(polygon: stroke.ribbon.polygon(upTo: stroke.ribbon.index(atLength: take)))
                stage.fill(path, with: .color(color(.hatch, state)))
            }
        }

        var scheduleIndex = 0
        for (k, stroke) in strokes.enumerated() where stroke.kind != .hatch {
            defer { scheduleIndex += 1 }
            if let schedule = cache.schedule, scheduleIndex < schedule.entries.count {
                let entry = schedule.entries[scheduleIndex]
                if elapsed < entry.start { continue } // pen hasn't reached this stroke
                if elapsed < entry.end {              // scribbling it right now
                    let length = (elapsed - entry.start) * style.penSpeed
                    let path = Path(
                        polygon: stroke.ribbon.polygon(upTo: stroke.ribbon.index(atLength: length))
                    )
                    stage.fill(path, with: .color(color(stroke.kind, state)))
                    continue
                }
            }
            stage.fill(stroke.fullPath, with: .color(color(stroke.kind, state)))
            if style.ghost, stroke.kind == .border, k < next.count {
                var ghost = stage
                ghost.translateBy(x: stroke.ghostOffset.x, y: stroke.ghostOffset.y)
                ghost.stroke(
                    next[k].centerPath,
                    with: .color(color(.border, state).opacity(style.ghostAlpha)),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                )
            }
        }
    }
}

/// A realized stroke with its `Path`s prebuilt — everything the per-frame
/// composite needs without touching geometry again.
struct SketchCachedStroke {
    let kind: SketchStrokeKind
    let ribbon: RibbonGeometry
    let fullPath: Path
    let centerPath: Path
    let centerLoop: Path
    let ghostOffset: SketchPoint

    init(_ stroke: RealizedStroke) {
        kind = stroke.kind
        ribbon = stroke.ribbon
        fullPath = Path(polygon: stroke.ribbon.polygon())
        centerPath = Path(polyline: stroke.ribbon.center)
        centerLoop = Path(polygon: stroke.ribbon.center)
        ghostOffset = stroke.ghostOffset
    }
}

// MARK: - Skeleton helpers

extension SketchRect {
    func insetBy(_ inset: Double) -> SketchRect {
        SketchRect(
            x: x + inset, y: y + inset,
            width: max(width - 2 * inset, 1), height: max(height - 2 * inset, 1)
        )
    }
}

private func arcToolbarBorder(in rect: SketchRect) -> [SketchPoint] {
    let left = rect.x
    let right = rect.x + rect.width
    let topSide = rect.y + rect.height * 0.32
    let topPeak = rect.y + 2
    let bottomSide = rect.y + rect.height * 0.78
    let bottomBelly = rect.y + rect.height - 2
    let midX = rect.x + rect.width / 2

    return quadraticPoints(
        from: SketchPoint(x: left, y: topSide),
        control: SketchPoint(x: midX, y: topPeak),
        to: SketchPoint(x: right, y: topSide),
        steps: 18
    )
    + [
        SketchPoint(x: right, y: bottomSide),
    ]
    + quadraticPoints(
        from: SketchPoint(x: right, y: bottomSide),
        control: SketchPoint(x: midX, y: bottomBelly),
        to: SketchPoint(x: left, y: bottomSide),
        steps: 18
    )
    + [
        SketchPoint(x: left, y: topSide),
    ]
}

private func quadraticPoints(
    from start: SketchPoint,
    control: SketchPoint,
    to end: SketchPoint,
    steps: Int
) -> [SketchPoint] {
    (0...max(steps, 1)).map { index in
        let t = Double(index) / Double(max(steps, 1))
        let inv = 1 - t
        return SketchPoint(
            x: inv * inv * start.x + 2 * inv * t * control.x + t * t * end.x,
            y: inv * inv * start.y + 2 * inv * t * control.y + t * t * end.y
        )
    }
}

/// Hershey text as skeleton strokes. Callers measuring for layout must use
/// the same `seed` so the jittered letter spacing matches what renders.
func hersheyTextSkeleton(
    _ text: String,
    size: Double,
    center: SketchPoint,
    seed: UInt32,
    kind: SketchStrokeKind
) -> [SkeletonStroke] {
    var rng = SketchRandom(seed: seed)
    return HersheyFont.futural.textStrokes(
        text, size: size, centerX: center.x, centerY: center.y, rng: &rng
    ).map { SkeletonStroke(points: $0, kind: kind) }
}

/// Bounding box of laid-out Hershey text (deterministic per seed).
func hersheyTextSize(_ text: String, size: Double, seed: UInt32) -> CGSize {
    var rng = SketchRandom(seed: seed)
    let strokes = HersheyFont.futural.textStrokes(
        text, size: size, centerX: 0, centerY: 0, rng: &rng
    )
    var minX = Double.infinity, maxX = -Double.infinity
    var minY = Double.infinity, maxY = -Double.infinity
    for stroke in strokes {
        for p in stroke {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
    }
    guard minX < maxX else { return CGSize(width: size * 0.6, height: size) }
    return CGSize(width: maxX - minX, height: maxY - minY)
}

/// Circle as a single pen loop: starts near the top, sweeps all the way
/// around, and overlaps its own start like the border swoop. The seed key
/// nudges the start angle so stacked rings don't share a seam.
func ringPoints(cx: Double, cy: Double, radius: Double, seedKey: String) -> [SketchPoint] {
    let startDegrees = -80.0 + Double(sketchSeed(seedKey) % 60) - 30
    let sweep = 385.0
    let step = 14.0
    var pts = [SketchPoint]()
    var d = 0.0
    while d <= sweep {
        let a = (startDegrees + d) * .pi / 180
        pts.append(SketchPoint(x: cx + radius * cos(a), y: cy + radius * sin(a)))
        d += step
    }
    return pts
}

/// Inward scribble spiral — the "colored in with a crayon" fill.
func spiralPoints(cx: Double, cy: Double, outer: Double, inner: Double, turns: Double) -> [SketchPoint] {
    let steps = max(8, Int(turns * 24))
    var pts = [SketchPoint]()
    pts.reserveCapacity(steps + 1)
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let a = t * turns * 2 * .pi
        let r = outer + (inner - outer) * t
        pts.append(SketchPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
    }
    return pts
}
