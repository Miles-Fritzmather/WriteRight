import CoreGraphics
import SwiftUI
import UIKit

enum PrototypeToolKind: String, CaseIterable, Identifiable {
    case pen
    case pencil
    case marker
    case highlighter
    case eraser

    var id: Self { self }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .marker: "Marker"
        case .highlighter: "Highlight"
        case .eraser: "Eraser"
        }
    }

    var icon: IconSource {
        switch self {
        case .pen: .systemSymbol("pencil.tip")
        case .pencil: .systemSymbol("pencil")
        case .marker: .systemSymbol("paintbrush.pointed")
        case .highlighter: .systemSymbol("highlighter")
        case .eraser: .systemSymbol("eraser")
        }
    }
}

struct PrototypeInkColor: Hashable, Identifiable {
    let id: String
    let name: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var color: Color {
        Color(red: Double(red), green: Double(green), blue: Double(blue))
    }

    func uiColor(alpha: CGFloat = 1) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static let black = PrototypeInkColor(id: "black", name: "Black", red: 0.11, green: 0.11, blue: 0.12)
    static let blue = PrototypeInkColor(id: "blue", name: "Blue", red: 0.13, green: 0.33, blue: 0.95)
    static let red = PrototypeInkColor(id: "red", name: "Red", red: 0.86, green: 0.18, blue: 0.20)
    static let green = PrototypeInkColor(id: "green", name: "Green", red: 0.08, green: 0.48, blue: 0.26)
    static let purple = PrototypeInkColor(id: "purple", name: "Purple", red: 0.46, green: 0.26, blue: 0.92)

    static let yellow = PrototypeInkColor(id: "yellow", name: "Yellow highlighter", red: 1.00, green: 0.86, blue: 0.18)
    static let mint = PrototypeInkColor(id: "mint", name: "Mint highlighter", red: 0.36, green: 0.92, blue: 0.68)
    static let pink = PrototypeInkColor(id: "pink", name: "Pink highlighter", red: 1.00, green: 0.45, blue: 0.68)
    static let lavender = PrototypeInkColor(id: "lavender", name: "Lavender highlighter", red: 0.65, green: 0.55, blue: 1.00)

    static let inkPalette: [PrototypeInkColor] = [.black, .blue, .red, .green, .purple]
    static let highlighterPalette: [PrototypeInkColor] = [.yellow, .mint, .pink, .lavender]
}

struct PrototypeToolStyle: Equatable {
    let kind: PrototypeToolKind
    let color: PrototypeInkColor
    let width: CGFloat
    let opacity: CGFloat
    let pressureSensitive: Bool
    let blendMode: CGBlendMode

    static let `default` = PrototypeToolStyle(
        kind: .pen,
        color: .black,
        width: 3,
        opacity: 1,
        pressureSensitive: true,
        blendMode: .normal
    )

    static func resolved(
        kind: PrototypeToolKind,
        inkColor: PrototypeInkColor,
        highlighterColor: PrototypeInkColor
    ) -> PrototypeToolStyle {
        switch kind {
        case .pen:
            PrototypeToolStyle(kind: kind, color: inkColor, width: 3, opacity: 1, pressureSensitive: true, blendMode: .normal)
        case .pencil:
            PrototypeToolStyle(kind: kind, color: inkColor, width: 2.25, opacity: 0.72, pressureSensitive: true, blendMode: .normal)
        case .marker:
            PrototypeToolStyle(kind: kind, color: inkColor, width: 5.5, opacity: 0.92, pressureSensitive: true, blendMode: .normal)
        case .highlighter:
            PrototypeToolStyle(kind: kind, color: highlighterColor, width: 18, opacity: 0.36, pressureSensitive: false, blendMode: .multiply)
        case .eraser:
            PrototypeToolStyle(kind: kind, color: inkColor, width: 34, opacity: 1, pressureSensitive: false, blendMode: .clear)
        }
    }
}
