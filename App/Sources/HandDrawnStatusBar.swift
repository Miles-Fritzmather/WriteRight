import Foundation
import Inject
import Network
import SketchKit
import SwiftUI
import UIKit

/// A hand-drawn replacement for the iOS system status bar. The real status
/// bar can't be restyled, so the app hides it (see project.yml
/// `UIStatusBarHidden`) and draws this instead: clock + date + connectivity +
/// battery. This strip stays deliberately non-animated so the readouts never
/// disappear while the hand-drawn chrome around it refreshes.
///
/// Honesty notes: the clock and battery level/charging state are real
/// (`UIDevice` battery monitoring). Wi-Fi signal *strength* has no public
/// API, so the Wi-Fi mark is binary — full arcs when the device is online,
/// slashed when it isn't (via `NWPathMonitor`). On the Simulator battery
/// reads as unavailable, so it shows full.
struct HandDrawnStatusBar: View {
    @ObserveInjection var inject
    @State private var network = NetworkMonitor()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let now = context.date
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    StatusInk(key: "time", text: Self.timeString(now), size: 14)
                    StatusInk(key: "date", text: Self.dateString(now), size: 12)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 10) {
                    StatusWifi(online: network.online)
                    StatusInk(key: "batteryPct", text: Self.batteryPercentString(), size: 12)
                    StatusBattery(level: Self.batteryLevel(), isCharging: Self.isCharging())
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 30)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            network.start()
        }
    }

    // MARK: Readouts

    private static func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Simulator returns a negative level (no battery); treat that as full.
    private static func batteryLevel() -> Double {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 1 : Double(level)
    }

    private static func isCharging() -> Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private static func batteryPercentString() -> String {
        "\(Int((batteryLevel() * 100).rounded()))%"
    }
}

extension View {
    func handDrawnStatusBarOverlay(topPadding: CGFloat = 8) -> some View {
        overlay(alignment: .top) {
            HandDrawnStatusBar()
                .padding(.top, topPadding)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Connectivity

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var online = true
    private let monitor = NWPathMonitor()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.online = satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "writeright.statusbar.network", qos: .utility))
    }
}

// MARK: - Static ink renderer

private struct StaticStatusSketchElement: View {
    let seedKey: String
    let style: SketchStyle
    let color: (SketchStrokeKind, SketchState) -> Color
    let skeleton: (SketchRect, SketchState) -> [SkeletonStroke]

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            let rect = SketchRect(x: 0, y: 0, width: size.width, height: size.height)
            let state = SketchState.normal
            let strokes = realize(
                skeleton(rect, state),
                style: style,
                seed: sketchSeed(seedKey),
                variant: 0,
                state: state
            )
            for stroke in strokes {
                context.fill(
                    Path(polygon: stroke.ribbon.polygon()),
                    with: .color(color(stroke.kind, state))
                )
            }
        }
    }
}

// MARK: - Ink text

/// Small run of status text. It uses the same Hershey/SketchKit stroke pipeline
/// as theme text, but draws statically so the status strip cannot briefly blank.
private struct StatusInk: View {
    let key: String
    let text: String
    var size: Double

    private var ink: Color { Color(hex: "#2b2723") }

    var body: some View {
        let seed = sketchHash(sketchSeed("status.\(key)"), 555, 0)
        let measured = hersheyTextSize(text, size: size, seed: seed)
        return StaticStatusSketchElement(
            seedKey: "status.\(key)",
            style: statusInkStyle,
            color: { _, _ in ink },
            skeleton: { rect, _ in
                hersheyTextSkeleton(
                    text,
                    size: size,
                    center: SketchPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2),
                    seed: seed,
                    kind: .label
                )
            }
        )
        .frame(width: max(measured.width + 6, 8), height: size + 10)
        .accessibilityLabel(text)
    }
}

// MARK: - Battery

private struct StatusBattery: View {
    let level: Double
    let isCharging: Bool

    private var ink: Color { Color(hex: "#2b2723") }

    var body: some View {
        StaticStatusSketchElement(
            seedKey: "status.battery",
            style: statusInkStyle,
            color: { kind, _ in
                kind == .hatch ? ink.opacity(0.85) : ink
            },
            skeleton: { rect, _ in batterySkeleton(in: rect, level: level, isCharging: isCharging) }
        )
        .frame(width: 34, height: 18)
        .accessibilityLabel("Battery \(Int((level * 100).rounded())) percent\(isCharging ? ", charging" : "")")
    }
}

private func batterySkeleton(in rect: SketchRect, level: Double, isCharging: Bool) -> [SkeletonStroke] {
    let body = SketchRect(x: rect.x, y: rect.y + 2, width: rect.width - 5, height: rect.height - 4)
    var strokes = borderStrokes(in: body, overshoot: 3, cornerRadius: 2.5)
        .map { SkeletonStroke(points: $0, kind: .border) }

    // Positive terminal nub on the right.
    let nubX = body.x + body.width + 1.5
    strokes.append(SkeletonStroke(points: [
        SketchPoint(x: nubX, y: rect.y + rect.height * 0.34),
        SketchPoint(x: nubX, y: rect.y + rect.height * 0.66),
    ], kind: .label))

    // Charge fill: vertical strokes across an inner rect scaled to the level.
    // (SketchKit's `hatchStrokes` insets 7pt internally — too big for a
    // battery this small — so the fill is drawn by hand here.)
    let inner = body.insetBy(2.4)
    let clamped = min(max(level, 0), 1)
    if clamped > 0.02 {
        let fillWidth = max(inner.width * clamped, 1)
        var x = inner.x + 0.6
        while x <= inner.x + fillWidth {
            strokes.append(SkeletonStroke(points: [
                SketchPoint(x: x, y: inner.y),
                SketchPoint(x: x, y: inner.y + inner.height),
            ], kind: .hatch))
            x += 2.2
        }
    }

    if isCharging {
        let cx = rect.x + rect.width / 2
        strokes.append(SkeletonStroke(points: [
            SketchPoint(x: cx + 2, y: rect.y + 3),
            SketchPoint(x: cx - 3, y: rect.y + rect.height / 2 + 0.5),
            SketchPoint(x: cx + 1.5, y: rect.y + rect.height / 2 + 0.5),
            SketchPoint(x: cx - 3, y: rect.y + rect.height - 3),
        ], kind: .accent))
    }
    return strokes
}

// MARK: - Wi-Fi

private struct StatusWifi: View {
    let online: Bool

    private var ink: Color { Color(hex: "#2b2723") }

    var body: some View {
        StaticStatusSketchElement(
            seedKey: "status.wifi",
            style: statusInkStyle,
            color: { kind, _ in
                kind == .accent ? ink : ink.opacity(online ? 1 : 0.4)
            },
            skeleton: { rect, _ in wifiSkeleton(in: rect, online: online) }
        )
        .frame(width: 24, height: 18)
        .accessibilityLabel(online ? "Online" : "Offline")
    }
}

private func wifiSkeleton(in rect: SketchRect, online: Bool) -> [SkeletonStroke] {
    let cx = rect.x + rect.width / 2
    let cy = rect.y + rect.height - 2
    var strokes = [SkeletonStroke]()
    for (index, radius) in [rect.width * 0.46, rect.width * 0.31, rect.width * 0.16].enumerated() {
        // Wide arc bulging up (y grows downward → sweep the top half,
        // symmetric about straight-up at 1.5π), narrowing slightly inward.
        let half = 0.30 - Double(index) * 0.02
        strokes.append(SkeletonStroke(
            points: arcPoints(cx: cx, cy: cy, radius: radius, from: .pi * (1.5 - half), to: .pi * (1.5 + half), steps: 12),
            kind: .label
        ))
    }
    // Base dot.
    strokes.append(SkeletonStroke(
        points: arcPoints(cx: cx, cy: cy, radius: 0.9, from: 0, to: 2 * .pi, steps: 8),
        kind: .label
    ))
    if !online {
        strokes.append(SkeletonStroke(points: [
            SketchPoint(x: rect.x + 1, y: rect.y + 1),
            SketchPoint(x: rect.x + rect.width - 1, y: rect.y + rect.height - 1),
        ], kind: .accent))
    }
    return strokes
}

private func arcPoints(cx: Double, cy: Double, radius: Double, from: Double, to: Double, steps: Int) -> [SketchPoint] {
    (0...max(steps, 1)).map { index in
        let t = from + (to - from) * Double(index) / Double(max(steps, 1))
        return SketchPoint(x: cx + radius * cos(t), y: cy + radius * sin(t))
    }
}

// MARK: - Shared style

/// Thin, static ink for the status strip — no boil (a jittering clock reads as
/// broken, not charming) and no ghost pass (too heavy at this size).
private let statusInkStyle: SketchStyle = {
    var s = SketchStyle()
    s.variants = 1
    s.inkWidth = 1.7
    s.amplitude = 0.9
    s.jitter = 0.7
    s.taper = 5
    s.spacing = 3.5
    s.ghost = false
    s.penSpeed = 3200
    return s
}()
