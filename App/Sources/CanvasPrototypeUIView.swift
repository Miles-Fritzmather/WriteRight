import CanvasCore
import Model
import UIKit

/// Phase 0 prototype canvas (SPEC §8 — throwaway by design).
///
/// Captures Apple Pencil input into canvas space at the moment each sample
/// arrives (SPEC §5) and redraws everything through the camera transform
/// with plain Core Graphics. Deliberately unoptimized: PencilKit live ink
/// arrives in Phase 1, tiled rendering in Phase 3. What this screen proves
/// is the coordinate discipline — ink drawn while panned/zoomed/rotated
/// must land exactly where the pencil touches.
final class CanvasPrototypeUIView: UIView {

    // MARK: State

    private(set) var camera = Camera() {
        didSet {
            setNeedsDisplay()
            noteChanged()
        }
    }

    private var strokes: [PrototypeStroke] = []
    private var activeStroke: PrototypeStroke?
    private var activeTouch: UITouch?
    private var predictedPoints: [PrototypePoint] = []

    /// Lets a finger (or the simulator's mouse) draw. While enabled,
    /// panning needs two fingers so drawing and panning don't fight.
    var fingerDrawingEnabled = false {
        didSet { panRecognizer.minimumNumberOfTouches = fingerDrawingEnabled ? 2 : 1 }
    }

    var onChange: ((Camera, Int) -> Void)?

    private let minScale: CGFloat = 0.05
    private let maxScale: CGFloat = 64

    private let panRecognizer = UIPanGestureRecognizer()
    private let pinchRecognizer = UIPinchGestureRecognizer()
    private let rotationRecognizer = UIRotationGestureRecognizer()

    // MARK: Setup

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1)
        contentMode = .redraw

        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 2
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        rotationRecognizer.addTarget(self, action: #selector(handleRotation(_:)))

        // Navigation is finger-only; pencil touches fall through to the
        // touches* overrides below and always draw.
        let fingerOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in [panRecognizer, pinchRecognizer, rotationRecognizer] {
            recognizer.allowedTouchTypes = fingerOnly
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Camera

    private var hasSetInitialCamera = false

    override func layoutSubviews() {
        super.layoutSubviews()
        // Start with the canvas origin centered so the grid axes are visible.
        if !hasSetInitialCamera, bounds.width > 0 {
            hasSetInitialCamera = true
            camera = defaultCamera
        }
    }

    private var defaultCamera: Camera {
        Camera(translation: CGVector(dx: bounds.midX, dy: bounds.midY))
    }

    func resetCamera() { camera = defaultCamera }

    func clearInk() {
        strokes.removeAll()
        activeStroke = nil
        activeTouch = nil
        predictedPoints = []
        setNeedsDisplay()
        noteChanged()
    }

    private func noteChanged() {
        onChange?(camera, strokes.count)
    }

    // MARK: Finger gestures → camera

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed else { return }
        let d = recognizer.translation(in: self)
        camera.panBy(dx: d.x, dy: d.y)
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .changed else { return }
        let pivot = ScreenPoint(cgPoint: recognizer.location(in: self))
        let target = min(max(camera.scale * recognizer.scale, minScale), maxScale)
        let factor = target / camera.scale
        if factor != 1 {
            camera.zoomBy(factor, about: pivot)
        }
        recognizer.scale = 1
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        guard recognizer.state == .changed else { return }
        camera.rotateBy(recognizer.rotation, about: ScreenPoint(cgPoint: recognizer.location(in: self)))
        recognizer.rotation = 0
    }

    // MARK: Pencil input → canvas-space strokes

    private func isDrawingTouch(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (fingerDrawingEnabled && touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first(where: isDrawingTouch) else { return }
        activeTouch = touch
        activeStroke = PrototypeStroke(points: [sample(touch)], baseWidth: 3)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), activeStroke != nil else { return }
        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        activeStroke?.points.append(contentsOf: coalesced.map(sample))
        predictedPoints = (event?.predictedTouches(for: touch) ?? []).map(sample)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Commit what was drawn — a cancel usually means a system gesture
        // took the touch, and losing ink feels worse than keeping it.
        finishStroke(touches)
    }

    private func finishStroke(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if let stroke = activeStroke, !stroke.points.isEmpty {
            strokes.append(stroke)
        }
        activeStroke = nil
        activeTouch = nil
        predictedPoints = []
        setNeedsDisplay()
        noteChanged()
    }

    /// SPEC §5: every sample is converted to canvas space at capture time,
    /// through whatever the camera is at that instant.
    private func sample(_ touch: UITouch) -> PrototypePoint {
        let screen = ScreenPoint(cgPoint: touch.preciseLocation(in: self))
        return PrototypePoint(position: camera.toCanvas(screen), force: touch.force)
    }

    // MARK: Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.concatenate(camera.transform)
        drawGrid(ctx)
        for stroke in strokes {
            draw(stroke, in: ctx)
        }
        if var live = activeStroke {
            // Predicted samples render as part of the live stroke and are
            // replaced by real ones on the next event.
            live.points.append(contentsOf: predictedPoints)
            draw(live, in: ctx)
        }
        ctx.restoreGState()
    }

    private let inkColor = UIColor(white: 0.13, alpha: 1)

    private func draw(_ stroke: PrototypeStroke, in ctx: CGContext) {
        ctx.setStrokeColor(inkColor.cgColor)
        ctx.setFillColor(inkColor.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let points = stroke.points
        guard points.count > 1 else {
            if let p = points.first {
                let r = stroke.width(for: p.force) / 2
                ctx.fillEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            }
            return
        }
        // Per-segment widths so pressure reads; round caps hide the joins.
        for i in 1..<points.count {
            ctx.setLineWidth(stroke.width(for: points[i].force))
            ctx.move(to: points[i - 1].position.cgPoint)
            ctx.addLine(to: points[i].position.cgPoint)
            ctx.strokePath()
        }
    }

    /// A canvas-space reference grid plus origin axes, so camera motion is
    /// legible even before any ink exists.
    private func drawGrid(_ ctx: CGContext) {
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ].map { camera.toCanvas(ScreenPoint(cgPoint: $0)) }
        guard let minX = corners.map(\.x).min(),
              let maxX = corners.map(\.x).max(),
              let minY = corners.map(\.y).min(),
              let maxY = corners.map(\.y).max()
        else { return }

        // Keep on-screen grid spacing between ~24pt and ~240pt at any zoom.
        var spacing: CGFloat = 100
        while spacing * camera.scale < 24 { spacing *= 10 }
        while spacing * camera.scale > 240 { spacing /= 10 }

        let hairline = 1 / camera.scale
        ctx.setLineWidth(hairline)
        ctx.setStrokeColor(UIColor(white: 0.5, alpha: 0.25).cgColor)

        var x = (minX / spacing).rounded(.down) * spacing
        while x <= maxX {
            ctx.move(to: CGPoint(x: x, y: minY))
            ctx.addLine(to: CGPoint(x: x, y: maxY))
            x += spacing
        }
        var y = (minY / spacing).rounded(.down) * spacing
        while y <= maxY {
            ctx.move(to: CGPoint(x: minX, y: y))
            ctx.addLine(to: CGPoint(x: maxX, y: y))
            y += spacing
        }
        ctx.strokePath()

        // Origin axes and marker (clipped away when offscreen).
        ctx.setLineWidth(2 * hairline)
        ctx.setStrokeColor(UIColor(white: 0.35, alpha: 0.5).cgColor)
        ctx.move(to: CGPoint(x: minX, y: 0))
        ctx.addLine(to: CGPoint(x: maxX, y: 0))
        ctx.move(to: CGPoint(x: 0, y: minY))
        ctx.addLine(to: CGPoint(x: 0, y: maxY))
        ctx.strokePath()

        let r = 4 * hairline
        ctx.setFillColor(UIColor.systemRed.withAlphaComponent(0.6).cgColor)
        ctx.fillEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    }
}

extension CanvasPrototypeUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Pan + pinch + rotate blend into one continuous two-finger
        // navigation gesture.
        true
    }
}
