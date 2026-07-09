import Foundation
import Inject
import SketchKit
import SwiftUI

/// A fully hand-drawn on-screen keyboard. It never touches UIKit's keyboard —
/// text fields in the hand-drawn world (`HandDrawnTextField`) are display-only
/// and this view mutates the bound string directly, so the system keyboard is
/// never summoned. Each key renders through the same SketchKit pipeline as the
/// rest of the theme (`SketchElementView`), but with `variants = 1` so the
/// dense key grid stays calm and readable rather than boiling.
struct HandDrawnKeyboard: View {
    @Binding var text: String
    /// Label drawn on the primary return key (e.g. "save", "create"); the key
    /// commits the prompt.
    var returnLabel: String
    var onReturn: () -> Void

    @State private var shifted = true          // start capitalized, like iOS
    @State private var showSymbols = false

    private let rowSpacing: CGFloat = 8
    private let keySpacing: CGFloat = 6
    private let keyHeight: CGFloat = 42

    private var letterRows: [[Character]] {
        [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")]
    }

    private var symbolRows: [[Character]] {
        [Array("1234567890"), Array("-/:;()$&@\""), Array(".,?!'")]
    }

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - keySpacing * 9) / 10
            VStack(spacing: rowSpacing) {
                topRows(unit: unit)
                bottomRow(unit: unit, totalWidth: geo.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: keyHeight * 4 + rowSpacing * 3)
    }

    @ViewBuilder
    private func topRows(unit: CGFloat) -> some View {
        let rows = showSymbols ? symbolRows : letterRows
        // Row 0 — ten keys, full width.
        keyRow(rows[0], unit: unit)
        // Row 1 — nine keys, inset half a key each side so it centers.
        keyRow(rows[1], unit: unit)
            .padding(.horizontal, (unit + keySpacing) / 2)
        // Row 2 — shift, seven keys, delete.
        HStack(spacing: keySpacing) {
            HandDrawnKeyButton(
                id: showSymbols ? "more-symbols" : "shift",
                glyph: showSymbols ? .text("#+=") : .shift,
                emphasized: shifted && !showSymbols,
                width: unit * 1.5,
                height: keyHeight
            ) { shifted.toggle() }
            ForEach(Array(rows[2]), id: \.self) { character in
                letterKey(character, unit: unit)
            }
            HandDrawnKeyButton(
                id: "delete",
                glyph: .delete,
                emphasized: false,
                width: unit * 1.5,
                height: keyHeight
            ) { deleteBackward() }
        }
    }

    private func bottomRow(unit: CGFloat, totalWidth: CGFloat) -> some View {
        let sideWidth = unit * 1.7
        let spaceWidth = totalWidth - sideWidth * 2 - keySpacing * 2
        return HStack(spacing: keySpacing) {
            HandDrawnKeyButton(
                id: "plane-toggle",
                glyph: .text(showSymbols ? "ABC" : "123"),
                emphasized: false,
                width: sideWidth,
                height: keyHeight
            ) { showSymbols.toggle() }
            HandDrawnKeyButton(
                id: "space",
                glyph: .space,
                emphasized: false,
                width: max(spaceWidth, unit),
                height: keyHeight
            ) { insert(" ") }
            HandDrawnKeyButton(
                id: "return",
                glyph: .text(returnLabel),
                emphasized: true,
                width: sideWidth,
                height: keyHeight
            ) { onReturn() }
        }
    }

    private func keyRow(_ characters: [Character], unit: CGFloat) -> some View {
        HStack(spacing: keySpacing) {
            ForEach(Array(characters), id: \.self) { character in
                letterKey(character, unit: unit)
            }
        }
    }

    private func letterKey(_ character: Character, unit: CGFloat) -> some View {
        let display = shifted && !showSymbols
            ? String(character).uppercased()
            : String(character)
        return HandDrawnKeyButton(
            id: "char-\(character)",
            glyph: .text(display),
            emphasized: false,
            width: unit,
            height: keyHeight
        ) { insert(display) }
    }

    // MARK: Editing

    private func insert(_ string: String) {
        text += string
        if shifted, !showSymbols { shifted = false } // one-shot shift, like iOS
    }

    private func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }
}

// MARK: - Key

private enum KeyGlyph {
    case text(String)
    case shift
    case delete
    case space
}

private struct HandDrawnKeyButton: View {
    let id: String
    fileprivate let glyph: KeyGlyph
    let emphasized: Bool
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    private var ink: Color { Color(hex: "#2b2723") }

    var body: some View {
        Button(action: action) { Color.clear }
            .buttonStyle(SketchPressStyle { pressed in
                AnyView(
                    SketchElementView(
                        seedKey: "key.\(id)",
                        style: HandDrawnKeyboardStyle.key,
                        pressed: pressed,
                        pressable: true,
                        entranceDelay: Double(sketchSeed("key.\(id)") % 220) / 1000,
                        paperFill: Color(hex: "#f7f2e7"),
                        revision: emphasized ? "on" : "off",
                        color: { kind, state in
                            switch kind {
                            case .hatch:
                                state == .pressed ? ink.opacity(0.34) : ink.opacity(0.16)
                            default:
                                ink
                            }
                        },
                        skeleton: { rect, state in
                            let border = rect.insetBy(3)
                            var strokes = borderStrokes(
                                in: border,
                                overshoot: HandDrawnKeyboardStyle.key.overshoot,
                                cornerRadius: HandDrawnKeyboardStyle.key.cornerRadius
                            ).map { SkeletonStroke(points: $0, kind: .border) }
                            strokes += glyphStrokes(glyph, in: border, seedKey: "key.\(id)")
                            if state == .pressed || emphasized {
                                strokes += hatchStrokes(in: border, spacing: HandDrawnKeyboardStyle.key.hatchSpacing)
                                    .map { SkeletonStroke(points: $0, kind: .hatch) }
                            }
                            return strokes
                        }
                    )
                    .frame(width: width, height: height)
                )
            })
            .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        switch glyph {
        case .text(let string): string
        case .shift: "Shift"
        case .delete: "Delete"
        case .space: "Space"
        }
    }
}

enum HandDrawnKeyboardStyle {
    /// Static (no boil) so a grid of ~30 keys stays a calm reading surface;
    /// keeps press squash + hatch and a quick write-on entrance.
    static let key: SketchStyle = {
        var s = SketchStyle()
        s.variants = 1
        s.inkWidth = 2.0
        s.amplitude = 1.15
        s.jitter = 1.0
        s.taper = 6
        s.spacing = 4
        s.cornerRadius = 7
        s.overshoot = 5
        s.hatchSpacing = 6
        s.ghostOffset = 1.2
        s.penSpeed = 3000
        return s
    }()
}

// MARK: - Key glyphs

/// A key's centered pictogram/label, authored directly in the key's inner
/// rect (not the 24-box `SketchIconLibrary` uses — keys need tighter fitting).
private func glyphStrokes(_ glyph: KeyGlyph, in rect: SketchRect, seedKey: String) -> [SkeletonStroke] {
    switch glyph {
    case .text(let string):
        var size = min(rect.height * 0.42, 17)
        let measured = hersheyTextSize(string, size: size, seed: sketchHash(sketchSeed(seedKey), 555, 0))
        let maxWidth = rect.width - 8
        if measured.width > maxWidth, measured.width > 0 {
            size *= maxWidth / measured.width
        }
        return hersheyTextSkeleton(
            string,
            size: size,
            center: SketchPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2),
            seed: sketchHash(sketchSeed(seedKey), 555, 0),
            kind: .label
        )
    case .shift:
        return [SkeletonStroke(points: shiftArrow(in: glyphBox(in: rect, side: 17)), kind: .label)]
    case .delete:
        return deleteGlyph(in: glyphBox(in: rect, side: 19))
    case .space:
        return [SkeletonStroke(points: spaceBar(in: glyphBox(in: rect, side: min(rect.width - 22, 78))), kind: .label)]
    }
}

/// A centered box `side` tall, used to place special-key glyphs.
private func glyphBox(in rect: SketchRect, side: Double) -> SketchRect {
    let w = min(side, rect.width - 6)
    let h = min(17, rect.height - 12)
    return SketchRect(
        x: rect.x + (rect.width - w) / 2,
        y: rect.y + (rect.height - h) / 2,
        width: w,
        height: h
    )
}

private func shiftArrow(in r: SketchRect) -> [SketchPoint] {
    let midX = r.x + r.width / 2
    let stem = r.width * 0.2
    let shoulderY = r.y + r.height * 0.52
    return [
        SketchPoint(x: midX, y: r.y),
        SketchPoint(x: r.x + r.width, y: shoulderY),
        SketchPoint(x: midX + stem, y: shoulderY),
        SketchPoint(x: midX + stem, y: r.y + r.height),
        SketchPoint(x: midX - stem, y: r.y + r.height),
        SketchPoint(x: midX - stem, y: shoulderY),
        SketchPoint(x: r.x, y: shoulderY),
        SketchPoint(x: midX, y: r.y),
    ]
}

private func deleteGlyph(in r: SketchRect) -> [SkeletonStroke] {
    let tip = r.width * 0.28
    let midY = r.y + r.height / 2
    let outline = [
        SketchPoint(x: r.x, y: midY),
        SketchPoint(x: r.x + tip, y: r.y),
        SketchPoint(x: r.x + r.width, y: r.y),
        SketchPoint(x: r.x + r.width, y: r.y + r.height),
        SketchPoint(x: r.x + tip, y: r.y + r.height),
        SketchPoint(x: r.x, y: midY),
    ]
    let crossX0 = r.x + tip + (r.width - tip) * 0.22
    let crossX1 = r.x + r.width - (r.width - tip) * 0.18
    let inset = r.height * 0.24
    return [
        SkeletonStroke(points: outline, kind: .label),
        SkeletonStroke(points: [
            SketchPoint(x: crossX0, y: r.y + inset),
            SketchPoint(x: crossX1, y: r.y + r.height - inset),
        ], kind: .label),
        SkeletonStroke(points: [
            SketchPoint(x: crossX1, y: r.y + inset),
            SketchPoint(x: crossX0, y: r.y + r.height - inset),
        ], kind: .label),
    ]
}

private func spaceBar(in r: SketchRect) -> [SketchPoint] {
    // A shallow bracket ⎵ centered on the key.
    let top = r.y + r.height * 0.35
    let bottom = r.y + r.height * 0.72
    return [
        SketchPoint(x: r.x, y: top),
        SketchPoint(x: r.x, y: bottom),
        SketchPoint(x: r.x + r.width, y: bottom),
        SketchPoint(x: r.x + r.width, y: top),
    ]
}

// MARK: - Hand-drawn text field (display-only; no system keyboard)

/// Renders the current text as hand-drawn Hershey ink with a blinking caret.
/// Purely a display surface — editing happens via `HandDrawnKeyboard`, so no
/// `UITextField`/system keyboard is ever involved.
struct HandDrawnTextField: View {
    @ObserveInjection var inject

    let text: String
    var placeholder: String = ""

    private let height: CGFloat = 44
    private let textSize: Double = 17
    private let leftPad: Double = 14
    private let seed: UInt32 = 0x46_49_45_4C  // "FIEL"

    @State private var size: CGSize = .zero
    @State private var glyphPaths: [Path] = []
    @State private var isPlaceholder = false
    @State private var caretX: CGFloat = 0

    private var ink: Color { Color(hex: "#2b2723") }
    private var paper: Color { Color(hex: "#f7f2e7") }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.55)) { timeline in
            Canvas { context, canvasSize in
                // Field surface: a soft inset panel so the caret has a home.
                let panel = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 1.5, dy: 1.5)
                context.fill(
                    Path(roundedRect: panel, cornerRadius: 8),
                    with: .color(paper.opacity(0.6))
                )

                for path in glyphPaths {
                    context.fill(path, with: .color(isPlaceholder ? ink.opacity(0.34) : ink))
                }

                // Blinking caret sits after the text (or at the left when empty).
                let blinkOn = Int(timeline.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
                if blinkOn {
                    let cy = canvasSize.height / 2
                    let half = textSize * 0.62
                    var caret = Path()
                    caret.move(to: CGPoint(x: caretX, y: cy - half))
                    caret.addLine(to: CGPoint(x: caretX, y: cy + half))
                    context.stroke(caret, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            if newSize != size {
                size = newSize
                rebuild()
            }
        }
        .onChange(of: text) { rebuild() }
        .enableInjection()
    }

    private func rebuild() {
        guard size.height > 0 else { return }
        let showPlaceholder = text.isEmpty && !placeholder.isEmpty
        isPlaceholder = showPlaceholder
        let shown = showPlaceholder ? placeholder : text

        guard !shown.isEmpty else {
            glyphPaths = []
            caretX = CGFloat(leftPad)
            return
        }

        let measured = hersheyTextSize(shown, size: textSize, seed: seed)
        let centerX = leftPad + measured.width / 2
        let centerY = Double(size.height) / 2
        let skeleton = hersheyTextSkeleton(
            shown,
            size: textSize,
            center: SketchPoint(x: centerX, y: centerY),
            seed: seed,
            kind: .label
        )
        // Single realize (no boil) — text you're reading should hold still.
        let realized = realize(skeleton, style: HandDrawnKeyboardStyle.key, seed: seed, variant: 0, state: .normal)
        glyphPaths = realized.map { Path(polygon: $0.ribbon.polygon()) }
        caretX = showPlaceholder ? CGFloat(leftPad) : CGFloat(leftPad + measured.width + 4)
    }
}
