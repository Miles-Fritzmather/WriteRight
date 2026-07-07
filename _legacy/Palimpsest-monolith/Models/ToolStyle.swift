import CoreGraphics
import Foundation

enum InkTool: String, Codable, CaseIterable, Identifiable {
    case pen
    case marker
    case pencil
    case eraser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .pencil: return "Pencil"
        case .eraser: return "Eraser"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pen: return 2.5
        case .marker: return 14
        case .pencil: return 3.5
        case .eraser: return 20
        }
    }

    var defaultBlendMode: StrokeBlendMode {
        self == .marker ? .multiply : .normal
    }
}

enum StrokeBlendMode: String, Codable {
    case normal
    case multiply
}

/// Color stored as sRGB components so it round-trips through SQLite / JSON
/// without depending on `UIColor`'s dynamic (light/dark) resolution.
struct StrokeColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = StrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let red = StrokeColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
    static let blue = StrokeColor(red: 0.1, green: 0.35, blue: 0.9, alpha: 1)
    static let highlighterYellow = StrokeColor(red: 1.0, green: 0.92, blue: 0.2, alpha: 0.55)
}

struct ToolStyle: Codable, Equatable {
    var tool: InkTool
    var color: StrokeColor
    var width: CGFloat
    var blendMode: StrokeBlendMode

    static func `default`(for tool: InkTool) -> ToolStyle {
        ToolStyle(tool: tool, color: .black, width: tool.defaultWidth, blendMode: tool.defaultBlendMode)
    }
}
