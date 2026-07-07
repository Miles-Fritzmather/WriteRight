import SwiftUI

/// The custom popup that replaces `PKToolPicker` entirely — triggered by
/// Pencil double-tap/squeeze or a toolbar button, anchored at the point
/// where the gesture happened.
struct ToolPopupView: View {
    @ObservedObject var toolbox: ToolboxModel

    private let colors: [StrokeColor] = [.black, .red, .blue, .highlighterYellow]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(InkTool.allCases) { tool in
                    toolButton(tool)
                }
            }
            HStack(spacing: 10) {
                ForEach(colors.indices, id: \.self) { index in
                    colorSwatch(colors[index])
                }
            }
            HStack {
                Text("Width")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(toolbox.currentStyle.width) },
                    set: { toolbox.currentStyle.width = CGFloat($0) }
                ), in: 1...40)
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 12)
        .position(x: toolbox.popupAnchor.x, y: toolbox.popupAnchor.y)
    }

    private func toolButton(_ tool: InkTool) -> some View {
        Button {
            toolbox.select(ToolStyle(
                tool: tool,
                color: toolbox.currentStyle.color,
                width: tool.defaultWidth,
                blendMode: tool.defaultBlendMode
            ))
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 42, height: 42)
                .background(
                    toolbox.currentStyle.tool == tool ? Color.accentColor.opacity(0.2) : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ color: StrokeColor) -> some View {
        Button {
            toolbox.currentStyle.color = color
        } label: {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(.primary.opacity(toolbox.currentStyle.color == color ? 0.6 : 0.1), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}
