import SwiftUI

/// The home page's pen palette. Same Theme primitives and layout as the
/// editor's `PrototypeToolToolbar`, so the library desk and the canvas feel
/// like one continuous surface — but bound to `PrototypeHomeToolModel` and
/// scoped to the tools that do something on a library page.
struct PrototypeHomeToolbar: View {
    @Bindable var model: PrototypeHomeToolModel

    var body: some View {
        AppToolbarContainer {
            ViewThatFits(in: .horizontal) {
                toolbarContent
                ScrollView(.horizontal, showsIndicators: false) {
                    toolbarContent
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            toolButtons
            AppDivider(height: 42, key: "home-tools-ink")
            palette(title: "Ink", colors: PrototypeInkColor.inkPalette) { color in
                model.selectInkColor(color)
            }
            AppDivider(height: 42, key: "home-ink-highlighter")
            palette(title: "Highlighter", colors: PrototypeInkColor.highlighterPalette) { color in
                model.selectHighlighterColor(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var toolButtons: some View {
        HStack(spacing: 4) {
            ForEach(PrototypeHomeToolModel.homeTools) { tool in
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
            AppLabel(text: title)
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
