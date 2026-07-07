import SwiftUI

struct PrototypeToolToolbar: View {
    @Bindable var model: PrototypeCanvasModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent
            ScrollView(.horizontal, showsIndicators: false) {
                toolbarContent
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            toolButtons
            Divider()
                .frame(height: 42)
            palette(title: "Ink", colors: PrototypeInkColor.inkPalette) { color in
                model.selectInkColor(color)
            }
            Divider()
                .frame(height: 42)
            palette(title: "Highlighter", colors: PrototypeInkColor.highlighterPalette) { color in
                model.selectHighlighterColor(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolButtons: some View {
        HStack(spacing: 4) {
            ForEach(PrototypeToolKind.allCases) { tool in
                AppIconButton(
                    source: tool.icon,
                    title: tool.title,
                    isSelected: model.selectedTool == tool
                ) {
                    model.selectTool(tool)
                }
            }
        }
    }

    private func palette(
        title: String,
        colors: [PrototypeInkColor],
        action: @escaping (PrototypeInkColor) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            ForEach(colors) { color in
                AppColorSwatch(
                    color: color.color,
                    title: color.name,
                    isSelected: isSelected(color)
                ) {
                    action(color)
                }
            }
        }
    }

    private func isSelected(_ color: PrototypeInkColor) -> Bool {
        if PrototypeInkColor.highlighterPalette.contains(color) {
            model.selectedHighlighterColor == color
        } else {
            model.selectedInkColor == color
        }
    }
}
