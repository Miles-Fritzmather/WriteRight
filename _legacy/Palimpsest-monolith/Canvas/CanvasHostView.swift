import Combine
import PencilKit
import UIKit

/// Orchestrates the hybrid-ink canvas: PencilKit captures the live stroke
/// (for Apple's predictive low-latency rendering), and once a stroke is
/// finished it is converted to a `Stroke`, handed to `PageEditorModel`, and
/// rendered from then on by `TiledCanvasView`. Finger touches pan/pinch/
/// rotate the camera; only the Pencil draws.
///
/// Geometry: `canvasContentContainer` and `pkCanvasView` both use `bounds`
/// centered on local (0, 0), with `center == .zero`. That makes a plain
/// `view.transform = camera.transform` behave exactly like
/// `canvasPoint.applying(camera.transform)` — no anchor-point tricks needed.
/// `pkCanvasView`'s own bounds coordinate system is therefore canvas space
/// directly, so `PKStrokePoint.location` needs no further conversion.
final class CanvasHostView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let camera = CanvasCamera()

    var editorModel: PageEditorModel! {
        didSet {
            tiledCanvasView.strokeProvider = { [weak self] rect in
                self?.editorModel.strokes(intersecting: rect) ?? []
            }
            tiledCanvasView.resetCache()
        }
    }

    var toolbox: ToolboxModel! {
        didSet { bindToolbox() }
    }

    let pencilInput = PencilInputController()

    /// Large-but-bounded stand-in for an unbounded plane — see the
    /// architecture note on why a literally infinite `PKCanvasView` isn't
    /// practical (CALayer/texture size ceilings). Comfortably larger than
    /// any real page of handwritten notes.
    private let contentExtent: CGFloat = 20_000

    private let tiledCanvasView = TiledCanvasView()
    private let canvasContentContainer = UIView()
    private let pkCanvasView = PKCanvasView()
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownTouchLocation: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .systemBackground
        clipsToBounds = true

        addSubview(tiledCanvasView)
        tiledCanvasView.camera = camera

        let canvasBounds = CGRect(x: -contentExtent / 2, y: -contentExtent / 2, width: contentExtent, height: contentExtent)
        canvasContentContainer.bounds = canvasBounds
        canvasContentContainer.center = .zero
        addSubview(canvasContentContainer)

        pkCanvasView.bounds = canvasBounds
        pkCanvasView.center = .zero
        pkCanvasView.backgroundColor = .clear
        pkCanvasView.isOpaque = false
        pkCanvasView.drawingPolicy = .pencilOnly
        pkCanvasView.isScrollEnabled = false
        pkCanvasView.delegate = self
        canvasContentContainer.addSubview(pkCanvasView)

        pencilInput.install(on: self)
        pencilInput.onDoubleTap = { [weak self] in self?.toolbox.quickToggleTool() }
        pencilInput.onSqueeze = { [weak self] squeeze in
            guard squeeze.phase == .ended, let self else { return }
            self.toolbox.presentPopup(at: self.lastKnownTouchLocation)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        configureForFingerOnly(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        configureForFingerOnly(pinch)

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        configureForFingerOnly(rotation)

        let eraser = UIPanGestureRecognizer(target: self, action: #selector(handleEraserPan(_:)))
        eraser.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        eraser.maximumNumberOfTouches = 1
        addGestureRecognizer(eraser)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
    }

    private func configureForFingerOnly(_ gr: UIGestureRecognizer) {
        gr.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        gr.delegate = self
        addGestureRecognizer(gr)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tiledCanvasView.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        if camera.transform.isIdentity {
            camera.resetToIdentity(centeredIn: bounds.size)
            applyCameraToContentContainer()
        }
        if let focusPoint = initialFocusCanvasPoint {
            camera.center(on: focusPoint, in: bounds.size)
            applyCameraToContentContainer()
            tiledCanvasView.setNeedsDisplay()
            initialFocusCanvasPoint = nil
        }
    }

    private func bindToolbox() {
        cancellables.removeAll()
        toolbox.$currentStyle
            .sink { [weak self] style in
                guard let self else { return }
                self.pkCanvasView.isUserInteractionEnabled = style.tool != .eraser
                if style.tool != .eraser {
                    self.pkCanvasView.tool = self.pkInkingTool(for: style)
                }
            }
            .store(in: &cancellables)
    }

    private func pkInkingTool(for style: ToolStyle) -> PKInkingTool {
        let inkType: PKInkingTool.InkType
        switch style.tool {
        case .pen: inkType = .pen
        case .marker: inkType = .marker
        case .pencil: inkType = .pencil
        case .eraser: inkType = .pen // unreachable; interaction is disabled for eraser
        }
        let color = UIColor(red: style.color.red, green: style.color.green, blue: style.color.blue, alpha: style.color.alpha)
        return PKInkingTool(inkType, color: color, width: style.width)
    }

    private func applyCameraToContentContainer() {
        canvasContentContainer.transform = camera.transform
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: - Camera gestures (finger only)

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        lastKnownTouchLocation = gr.location(in: self)
        let translation = gr.translation(in: self)
        gr.setTranslation(.zero, in: self)
        camera.applyIncrementalPan(CGVector(dx: translation.x, dy: translation.y))
        applyCameraToContentContainer()
        tiledCanvasView.setNeedsDisplay()
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        let anchor = gr.location(in: self)
        lastKnownTouchLocation = anchor
        camera.applyIncrementalScale(gr.scale, anchor: anchor)
        gr.scale = 1
        applyCameraToContentContainer()
        tiledCanvasView.setNeedsDisplay()
    }

    @objc private func handleRotation(_ gr: UIRotationGestureRecognizer) {
        let anchor = gr.location(in: self)
        lastKnownTouchLocation = anchor
        camera.applyIncrementalRotation(gr.rotation, anchor: anchor)
        gr.rotation = 0
        applyCameraToContentContainer()
        tiledCanvasView.setNeedsDisplay()
    }

    @objc private func handleHover(_ gr: UIHoverGestureRecognizer) {
        switch gr.state {
        case .began, .changed:
            let location = gr.location(in: self)
            lastKnownTouchLocation = location
            onHover?(location)
        default:
            onHover?(nil)
        }
    }

    var onHover: ((CGPoint?) -> Void)?

    /// Set once, right after creation, to jump straight to a search hit
    /// instead of the default centered-on-origin starting view. Applied on
    /// the next layout pass since bounds aren't known yet at creation time.
    var initialFocusCanvasPoint: CGPoint?

    // MARK: - Eraser (Pencil-only; hit-tests our own data model, not PencilKit's)

    @objc private func handleEraserPan(_ gr: UIPanGestureRecognizer) {
        guard toolbox.currentStyle.tool == .eraser, gr.state == .began || gr.state == .changed else { return }
        let canvasPoint = camera.canvasPoint(fromScreen: gr.location(in: self))
        let ids = editorModel.strokeIDs(near: canvasPoint, radius: max(toolbox.currentStyle.width, 12))
        guard !ids.isEmpty else { return }
        let boxes = editorModel.boundingBoxes(for: ids)
        editorModel.erase(strokeIDs: ids)
        tiledCanvasView.invalidate(canvasRects: boxes)
    }

    // MARK: - PKCanvasViewDelegate (live stroke -> committed Stroke)

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let newStroke = canvasView.drawing.strokes.last else { return }
        let stroke = Stroke.from(pkStroke: newStroke, pageID: editorModel.page.id, style: toolbox.currentStyle, convertingFrom: canvasView, to: canvasContentContainer)
        editorModel.commit(stroke)
        tiledCanvasView.invalidate(canvasRects: [stroke.boundingBox])
        // PencilKit's copy has been absorbed into the tile cache — clear it
        // so the ink isn't drawn twice.
        canvasView.drawing = PKDrawing()
    }
}

private extension Stroke {
    /// `PKCanvasView` is a `UIScrollView` subclass, which manages `bounds.origin`
    /// as its content offset — it does not honor an arbitrary negative origin
    /// the way a plain `UIView` does, so its local coordinate system is *not*
    /// guaranteed to equal canvas space directly despite matching bounds size.
    /// Converting through the view hierarchy (rather than assuming coordinate
    /// equality) is what actually makes this robust.
    static func from(pkStroke: PKStroke, pageID: UUID, style: ToolStyle, convertingFrom sourceView: UIView, to targetView: UIView) -> Stroke {
        var points: [SamplePoint] = []
        points.reserveCapacity(pkStroke.path.count)
        for point in pkStroke.path {
            let canvasLocation = sourceView.convert(point.location, to: targetView)
            points.append(SamplePoint(
                x: canvasLocation.x,
                y: canvasLocation.y,
                pressure: Float(point.force),
                altitude: Float(point.altitude),
                azimuth: Float(point.azimuth),
                timestamp: point.timeOffset
            ))
        }
        return Stroke(pageID: pageID, points: points, style: style)
    }
}
