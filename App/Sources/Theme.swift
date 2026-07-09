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
    /// Chrome around a toolbar's content (background, border, elevation).
    @MainActor
    func toolbarContainer(_ content: AnyView) -> AnyView
    /// Arced chrome for floating quick-access tool palettes.
    @MainActor
    func arcToolbarContainer(_ content: AnyView) -> AnyView
    /// Small inline caption, e.g. palette group titles.
    @MainActor
    func label(_ text: String) -> AnyView
    /// Vertical separator. `key` is a stable identity so themes with
    /// per-element randomness (hand-drawn wobble) can vary per instance.
    @MainActor
    func divider(height: CGFloat, key: String) -> AnyView
    /// Display text that should share the active theme's type treatment.
    @MainActor
    func text(_ text: String, role: AppTextRole) -> AnyView
    /// Reusable card/surface chrome. Callers own layout and padding inside.
    @MainActor
    func cardContainer(_ content: AnyView, key: String) -> AnyView
}

enum IconSource: Hashable, Sendable {
    case systemSymbol(String)
    /// Bundled hand-drawn stroke asset (SPEC §7). Themes without a stroke
    /// renderer fall back to the SF Symbol.
    case builtIn(name: String, fallbackSymbol: String)
}

struct AppMenuAction: Identifiable {
    let id: String
    let title: String
    let action: () -> Void
}

enum AppTextRole: Equatable, Sendable {
    case title
    case heading
    case caption

    var systemFont: Font {
        switch self {
        case .title:
            .largeTitle.weight(.semibold)
        case .heading:
            .title3.weight(.semibold)
        case .caption:
            .caption.weight(.semibold)
        }
    }
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
        let symbolName = switch source {
        case .systemSymbol(let name): name
        case .builtIn(_, let fallbackSymbol): fallbackSymbol
        }
        return AnyView(
            Image(systemName: symbolName)
                .font(.system(size: size, weight: .medium))
                .frame(width: size, height: size)
        )
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

    func toolbarContainer(_ content: AnyView) -> AnyView {
        AnyView(
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        )
    }

    func arcToolbarContainer(_ content: AnyView) -> AnyView {
        AnyView(
            content
                .background(.regularMaterial, in: AppArcToolbarShape())
                .overlay {
                    AppArcToolbarShape()
                        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                }
        )
    }

    func label(_ text: String) -> AnyView {
        AnyView(
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        )
    }

    func divider(height: CGFloat, key: String) -> AnyView {
        AnyView(
            Divider()
                .frame(height: height)
        )
    }

    func text(_ text: String, role: AppTextRole) -> AnyView {
        AnyView(
            Text(text)
                .font(role.systemFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        )
    }

    func cardContainer(_ content: AnyView, key: String) -> AnyView {
        AnyView(
            content
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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

struct AppToolbarContainer<Content: View>: View {
    @Environment(\.theme) private var theme

    @ViewBuilder let content: () -> Content

    var body: some View {
        theme.toolbarContainer(AnyView(content()))
    }
}

struct AppArcToolbarContainer<Content: View>: View {
    @Environment(\.theme) private var theme

    @ViewBuilder let content: () -> Content

    var body: some View {
        theme.arcToolbarContainer(AnyView(content()))
    }
}

struct AppLabel: View {
    @Environment(\.theme) private var theme

    let text: String

    var body: some View {
        theme.label(text)
    }
}

struct AppText: View {
    @Environment(\.theme) private var theme

    let text: String
    let role: AppTextRole

    var body: some View {
        theme.text(text, role: role)
    }
}

struct AppDivider: View {
    @Environment(\.theme) private var theme

    let height: CGFloat
    let key: String

    var body: some View {
        theme.divider(height: height, key: key)
    }
}

struct AppCardContainer<Content: View>: View {
    @Environment(\.theme) private var theme

    let key: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        theme.cardContainer(AnyView(content()), key: key)
    }
}

private struct AppArcToolbarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + 2
        let right = rect.maxX - 2
        let topSide = rect.minY + rect.height * 0.32
        let topPeak = rect.minY + 5
        let bottomSide = rect.maxY - rect.height * 0.22
        let bottomBelly = rect.maxY - 3
        let midX = rect.midX

        path.move(to: CGPoint(x: left, y: topSide))
        path.addQuadCurve(
            to: CGPoint(x: right, y: topSide),
            control: CGPoint(x: midX, y: topPeak)
        )
        path.addLine(to: CGPoint(x: right, y: bottomSide))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottomSide),
            control: CGPoint(x: midX, y: bottomBelly)
        )
        path.closeSubpath()
        return path
    }
}
