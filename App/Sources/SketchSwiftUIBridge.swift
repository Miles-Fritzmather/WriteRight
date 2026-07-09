import SketchKit
import SwiftUI

/// SwiftUI-side bridging for SketchKit geometry — the package stays
/// UI-agnostic (SPEC §11 module discipline); everything that touches
/// `Path`/`Color` lives app-side. Shared by the sketch demo screen and
/// `HandDrawnTheme`.

extension Path {
    init(polygon: [SketchPoint]) {
        self.init()
        guard let first = polygon.first else { return }
        move(to: CGPoint(x: first.x, y: first.y))
        for p in polygon.dropFirst() {
            addLine(to: CGPoint(x: p.x, y: p.y))
        }
        closeSubpath()
    }

    init(polyline: [SketchPoint]) {
        self.init()
        guard let first = polyline.first else { return }
        move(to: CGPoint(x: first.x, y: first.y))
        for p in polyline.dropFirst() {
            addLine(to: CGPoint(x: p.x, y: p.y))
        }
    }
}

extension Color {
    /// Parses "#rrggbb"; falls back to black on malformed input (no crashes
    /// on production paths).
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .black
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Deterministic FNV-1a over UTF-8. Used to derive SketchKit seeds from
/// stable element identities ("tool.pen", "swatch.blue"…). Swift's `Hasher`
/// is deliberately randomized per launch, which would make every control
/// wobble differently on every run — hand-drawn, but not *consistently*
/// hand-drawn.
func sketchSeed(_ key: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in key.utf8 {
        hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return hash
}
