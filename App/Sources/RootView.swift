import Inject
import SwiftUI

/// Phase 0 shell: a full-bleed prototype canvas plus a small debug HUD.
/// The HUD now uses the Phase 1 Theme wrappers even though the canvas
/// remains prototype code.
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
        let loadActions = model.noteSummaries.map { summary in
            AppMenuAction(
                id: summary.id.uuidString,
                title: "\(summary.title) · \(summary.strokeCount) strokes"
            ) {
                model.loadNote(summary)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Phase 0 — canvas & camera prototype")
                .font(.caption.weight(.semibold))
            Text("Zoom \(Int((model.scale * 100).rounded()))%  ·  Rotation \(Int(model.rotationDegrees.rounded()))°  ·  Strokes \(model.strokeCount)")
                .font(.caption.monospacedDigit())
            Text(model.currentNoteTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Pencil draws · 1–2 fingers pan · pinch zooms · twist rotates")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                AppButton(label: "Reset view") { model.resetCamera() }
                AppButton(label: "Clear ink") { model.clearInk() }
                AppToggle(isOn: $model.fingerDrawing, label: "Finger draws")
            }
            .font(.caption)
            HStack(spacing: 10) {
                AppButton(label: "New note") { model.newNote() }
                AppButton(label: "Save") { model.saveNote() }
                AppMenuButton(label: "Load", actions: loadActions)
                AppButton(label: "Delete selected") { model.deleteSelection() }
            }
            .font(.caption)
            HStack(spacing: 8) {
                AppButton(label: "L") { model.translateSelection(dx: -28, dy: 0) }
                AppButton(label: "R") { model.translateSelection(dx: 28, dy: 0) }
                AppButton(label: "U") { model.translateSelection(dx: 0, dy: -28) }
                AppButton(label: "D") { model.translateSelection(dx: 0, dy: 28) }
            }
            .font(.caption)
            HStack(spacing: 8) {
                AppButton(label: "Scale -") { model.scaleSelection(by: 0.88) }
                AppButton(label: "Scale +") { model.scaleSelection(by: 1.14) }
                AppButton(label: "Rot -") { model.rotateSelection(by: -12) }
                AppButton(label: "Rot +") { model.rotateSelection(by: 12) }
            }
            .font(.caption)
            if let storageMessage = model.storageMessage {
                Text(storageMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
