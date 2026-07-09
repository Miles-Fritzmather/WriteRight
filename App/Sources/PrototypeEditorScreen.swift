import SwiftUI

/// What the home screen wants the editor to open.
struct PrototypeEditorRequest: Identifiable {
    enum Kind {
        case new(folderID: UUID?, pageType: PrototypePageType)
        case existing(noteID: UUID)
    }

    let id = UUID()
    let kind: Kind
}

/// The Phase 0/1 canvas editor, lifted out of `RootView` so the home-screen
/// mockup can present it full screen: prototype canvas + themed toolbar.
struct PrototypeEditorScreen: View {
    @State private var model: PrototypeCanvasModel
    @State private var isClosing = false
    private let onClose: () -> Void

    init(request: PrototypeEditorRequest, onClose: @escaping () -> Void) {
        _model = State(initialValue: PrototypeCanvasModel(request: request))
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasPrototypeView(
                model: model,
                toolStyle: model.currentToolStyle
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            AppButton(label: "Done") {
                closeEditor()
            }
            .padding(.top, 46)
            .padding(.trailing, 12)
        }
        .overlay(alignment: .topLeading) {
            if model.currentPageType.canvasPageRect != nil {
                pageControls
                    .padding(.top, 46)
                    .padding(.leading, 20)
            }
        }
        .overlay {
            GeometryReader { proxy in
                if model.isPencilQuickToolbarPresented {
                    PrototypePencilQuickToolbar(model: model)
                        .environment(\.theme, HandDrawnTheme())
                        .position(quickToolbarPosition(in: proxy.size))
                        .transition(.scale(scale: 0.86, anchor: .center).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            // Hand-drawn treatment scoped to the tool menu per SPEC §7's
            // "where it delights first" guidance (approved early, 2026-07-08).
            PrototypeToolToolbar(model: model)
                .environment(\.theme, HandDrawnTheme())
        }
        .handDrawnStatusBarOverlay()
        .animation(.snappy(duration: 0.18), value: model.isPencilQuickToolbarPresented)
    }

    private func closeEditor() {
        guard !isClosing else { return }
        isClosing = true
        model.saveIfNeeded(refreshAfterSave: false)
        onClose()
    }

    private var pageControls: some View {
        AppCardContainer(key: "editor.page-controls") {
            HStack(spacing: 10) {
                AppButton(label: "Add Page") {
                    model.addPage()
                }
                AppDivider(height: 28, key: "editor-page-count")
                AppText(text: pageCountText, role: .caption)
                    .frame(minWidth: 54, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var pageCountText: String {
        model.currentPageCount == 1 ? "1 Page" : "\(model.currentPageCount) Pages"
    }

    private func quickToolbarPosition(in size: CGSize) -> CGPoint {
        let toolbarSize = PrototypePencilQuickToolbar.popupSize
        let margin: CGFloat = 18
        let bottomToolbarClearance: CGFloat = 142
        let anchor = model.pencilQuickToolbarAnchor ?? CGPoint(
            x: size.width / 2,
            y: size.height - bottomToolbarClearance - toolbarSize.height / 2
        )

        let aboveY = anchor.y - toolbarSize.height * 0.72
        let belowY = anchor.y + toolbarSize.height * 0.72
        let preferredY = aboveY - toolbarSize.height / 2 > margin
            ? aboveY
            : belowY

        return CGPoint(
            x: clamp(
                anchor.x,
                min: toolbarSize.width / 2 + margin,
                max: size.width - toolbarSize.width / 2 - margin
            ),
            y: clamp(
                preferredY,
                min: toolbarSize.height / 2 + margin,
                max: size.height - toolbarSize.height / 2 - bottomToolbarClearance
            )
        )
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), Swift.max(minimum, maximum))
    }
}
