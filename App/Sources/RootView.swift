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
            CanvasPrototypeView(model: model, fingerDrawing: model.fingerDrawing)
                .ignoresSafeArea()
            PrototypeHUD(model: model)
                .padding(12)
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
            Text("Pencil draws · 1–2 fingers pan · pinch zooms · twist rotates · 🔥")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Reset view") { model.resetCamera() }
                Button("Clear ink", role: .destructive) { model.clearInk() }
                Toggle("Finger draws", isOn: $model.fingerDrawing)
                    .toggleStyle(.button)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
