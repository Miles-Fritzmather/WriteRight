import CoreGraphics
import Model

/// Throwaway Phase 0 stroke. The real `Stroke` model (SPEC §6) with tools,
/// undo, and persistence arrives in Phase 1.
struct PrototypePoint {
    /// Canvas space, always — converted at capture time (SPEC §5).
    var position: CanvasPoint
    /// Raw `UITouch.force`; 0 for finger/mouse input.
    var force: CGFloat
}

struct PrototypeStroke {
    var points: [PrototypePoint]
    var baseWidth: CGFloat

    /// Cheap pressure curve, just good enough to judge how drawing feels.
    /// Phase 1 replaces it with real tool styles.
    func width(for force: CGFloat) -> CGFloat {
        guard force > 0 else { return baseWidth }
        return baseWidth * min(max(0.35 + 0.65 * force, 0.25), 2.5)
    }
}
