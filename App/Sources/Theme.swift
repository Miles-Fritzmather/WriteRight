import SwiftUI

protocol Theme: Sendable {
    @MainActor
    func button(_ label: String, action: @escaping () -> Void) -> AnyView
    @MainActor
    func menu(_ label: String, actions: [AppMenuAction]) -> AnyView
    @MainActor
    func icon(_ source: IconSource, size: CGFloat) -> AnyView
    @MainActor
    func iconButton(
        _ source: IconSource,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> AnyView
    @MainActor
    func colorSwatch(
        _ color: Color,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> AnyView
    @MainActor
    func toggle(_ isOn: Binding<Bool>, label: String) -> AnyView
}

enum IconSource: Hashable, Sendable {
    case systemSymbol(String)
}

struct AppMenuAction: Identifiable {
    let id: String
    let title: String
    let action: () -> Void
}

struct SystemTheme: Theme {
    func button(_ label: String, action: @escaping () -> Void) -> AnyView {
        AnyView(
            Button(label, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        )
    }

    func menu(_ label: String, actions: [AppMenuAction]) -> AnyView {
        AnyView(
            Menu(label) {
                if actions.isEmpty {
                    Text("No saved notes")
                } else {
                    ForEach(actions) { action in
                        Button(action.title, action: action.action)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        )
    }

    func icon(_ source: IconSource, size: CGFloat) -> AnyView {
        switch source {
        case .systemSymbol(let name):
            AnyView(
                Image(systemName: name)
                    .font(.system(size: size, weight: .medium))
                    .frame(width: size, height: size)
            )
        }
    }

    func iconButton(
        _ source: IconSource,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            Button(action: action) {
                VStack(spacing: 3) {
                    icon(source, size: 18)
                    Text(title)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 58, height: 46)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isSelected ? "Selected" : "")
        )
    }

    func colorSwatch(
        _ color: Color,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            Button(action: action) {
                Circle()
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    }
                    .overlay {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                            .padding(-4)
                    }
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isSelected ? "Selected" : "")
        )
    }

    func toggle(_ isOn: Binding<Bool>, label: String) -> AnyView {
        AnyView(
            Toggle(label, isOn: isOn)
                .toggleStyle(.button)
                .controlSize(.small)
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: any Theme = SystemTheme()
}

extension EnvironmentValues {
    var theme: any Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

struct AppButton: View {
    @Environment(\.theme) private var theme

    let label: String
    let action: () -> Void

    var body: some View {
        theme.button(label, action: action)
    }
}

struct AppMenuButton: View {
    @Environment(\.theme) private var theme

    let label: String
    let actions: [AppMenuAction]

    var body: some View {
        theme.menu(label, actions: actions)
    }
}

struct AppIcon: View {
    @Environment(\.theme) private var theme

    let source: IconSource
    let size: CGFloat

    var body: some View {
        theme.icon(source, size: size)
    }
}

struct AppIconButton: View {
    @Environment(\.theme) private var theme

    let source: IconSource
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        theme.iconButton(source, title: title, isSelected: isSelected, action: action)
    }
}

struct AppColorSwatch: View {
    @Environment(\.theme) private var theme

    let color: Color
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        theme.colorSwatch(color, title: title, isSelected: isSelected, action: action)
    }
}

struct AppToggle: View {
    @Environment(\.theme) private var theme

    @Binding var isOn: Bool
    let label: String

    var body: some View {
        theme.toggle($isOn, label: label)
    }
}
