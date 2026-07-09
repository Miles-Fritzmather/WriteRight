import Inject
import SwiftUI

/// Hand-drawn replacements for the system `.alert` text prompt and the system
/// `Menu`/`confirmationDialog`, so creation/rename/choice flows stay in the
/// ink world instead of dropping to Apple's default chrome + keyboard.

// MARK: - Text prompt

/// One text-entry prompt (rename, new folder…). Presented over a dimmed
/// backdrop with the hand-drawn keyboard docked below — the system keyboard
/// never appears.
struct HandDrawnPromptConfig: Identifiable {
    let id = UUID()
    var title: String
    var initialText: String
    var confirmLabel: String
    var onConfirm: (String) -> Void
}

private struct HandDrawnPromptOverlay: View {
    @ObserveInjection var inject

    let config: HandDrawnPromptConfig
    let onDismiss: () -> Void

    @State private var text = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Card + keyboard cluster, hugging the bottom. It sizes to its
            // content (not the whole screen), so taps in the dim area above
            // still reach the backdrop to dismiss.
            VStack(spacing: 14) {
                AppCardContainer(key: "prompt.\(config.id.uuidString)") {
                    HandDrawnMenuInkSurface(key: "prompt.\(config.id.uuidString)") {
                        VStack(alignment: .leading, spacing: 16) {
                            AppText(text: config.title, role: .heading)
                            HandDrawnTextField(text: text, placeholder: "Name")
                            HStack(spacing: 12) {
                                AppButton(label: "Cancel") { onDismiss() }
                                Spacer(minLength: 0)
                                AppButton(label: config.confirmLabel) { commit() }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: 540)
                .padding(.horizontal, 24)

                HandDrawnKeyboard(text: $text, returnLabel: config.confirmLabel.lowercased()) {
                    commit()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            // Swallow taps on the cluster so only Cancel or the backdrop dismiss.
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .onAppear { text = config.initialText }
    }

    private func commit() {
        config.onConfirm(text.trimmingCharacters(in: .whitespacesAndNewlines))
        onDismiss()
    }
}

// MARK: - Chooser

/// A small list of hand-drawn choices (e.g. the "new canvas" page-type
/// picker) replacing a system `Menu` dropdown.
struct HandDrawnChooserConfig: Identifiable {
    struct Option: Identifiable {
        let id = UUID()
        var label: String
        var icon: IconSource?
        var action: () -> Void
    }

    let id = UUID()
    var title: String
    var options: [Option]
}

private struct HandDrawnChooserOverlay: View {
    @ObserveInjection var inject

    let config: HandDrawnChooserConfig
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            AppCardContainer(key: "chooser.\(config.id.uuidString)") {
                HandDrawnMenuInkSurface(key: "chooser.\(config.id.uuidString)") {
                    VStack(alignment: .leading, spacing: 16) {
                        AppText(text: config.title, role: .heading)
                        ForEach(config.options) { option in
                            HStack(spacing: 12) {
                                if let icon = option.icon {
                                    AppIcon(source: icon, size: 26)
                                }
                                AppButton(label: option.label) {
                                    option.action()
                                    onDismiss()
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
    }
}

// MARK: - Presentation

extension View {
    /// Presents a hand-drawn text prompt when `config` is non-nil.
    func handDrawnPrompt(_ config: Binding<HandDrawnPromptConfig?>) -> some View {
        overlay {
            if let value = config.wrappedValue {
                HandDrawnPromptOverlay(config: value) { config.wrappedValue = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: config.wrappedValue?.id)
    }

    /// Presents a hand-drawn chooser when `config` is non-nil.
    func handDrawnChooser(_ config: Binding<HandDrawnChooserConfig?>) -> some View {
        overlay {
            if let value = config.wrappedValue {
                HandDrawnChooserOverlay(config: value) { config.wrappedValue = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: config.wrappedValue?.id)
    }

}
