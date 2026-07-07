import UIKit

/// Thin wrapper around `UIPencilInteraction` so the double-tap and Pencil Pro
/// squeeze gestures can drive app-level actions (quick tool switch, radial
/// popup) instead of Apple's default "toggle last tool" behavior alone.
final class PencilInputController: NSObject, UIPencilInteractionDelegate {
    var onDoubleTap: (() -> Void)?
    var onSqueeze: ((UIPencilInteraction.Squeeze) -> Void)?

    private var interaction: UIPencilInteraction?

    func install(on view: UIView) {
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        view.addInteraction(interaction)
        self.interaction = interaction
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onDoubleTap?()
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        onSqueeze?(squeeze)
    }
}
