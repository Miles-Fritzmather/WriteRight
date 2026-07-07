import Inject
import SwiftUI

/// Phase 0 shell: a full-bleed prototype canvas plus a small debug HUD.
/// Plain SwiftUI controls on purpose — the Theme abstraction (SPEC §7)
/// arrives with Phase 1, and this whole screen is throwaway.
struct RootView: View {
    @ObserveInjection var inject
    @State private var model = PrototypeCanvasModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasPrototypeView(
                model: model,
                fingerDrawing: model.fingerDrawing,
                toolStyle: model.currentToolStyle
            )
                .ignoresSafeArea()
            PrototypeHUD(model: model)
                .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            PrototypeToolToolbar(model: model)
        }
        .enableInjection()
    }
}

private struct PrototypeHUD: View {
    @Bindable var model: PrototypeCanvasModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phase 0 — canvas & camera prototype")
                .font(.caption.weight(.semibold))
            Text("Zoom \(Int((model.scale * 100).rounded()))%  ·  Rotation \(Int(model.rotationDegrees.rounded()))°  ·  Strokes \(model.strokeCount)")
                .font(.caption.monospacedDigit())
            Text("Pencil draws · 1–2 fingers pan · pinch zooms · twist rotates")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                AppButton(label: "Reset view") { model.resetCamera() }
                AppButton(label: "Clear ink") { model.clearInk() }
                AppToggle(isOn: $model.fingerDrawing, label: "Finger draws")
            }
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
