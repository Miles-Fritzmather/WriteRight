import CanvasCore
import Model
import QuartzCore
import UIKit

/// Phase 0 prototype canvas (SPEC §8 — throwaway by design).
///
/// Captures Apple Pencil input into canvas space at the moment each sample
/// arrives (SPEC §5). Strokes render as cached vector layers under a parent
/// canvas transform, so camera gestures move the environment without
/// re-stroking every point. PencilKit live ink arrives in Phase 1, tiled
/// rendering in Phase 3.
final class CanvasPrototypeUIView: UIView {

    // MARK: State

    private(set) var camera = Camera() {
        didSet {
            updateCanvasLayerTransform()
            setNeedsDisplay()
            noteChanged()
        }
    }

    private var strokes: [PrototypeStroke] = []
    private var activeStroke: PrototypeStroke?
    private var activeTouch: UITouch?
    private var activeInput: ActiveInput?
    private var activeToolStyle: PrototypeToolStyle?
    private var predictedPoints: [PrototypePoint] = []
    private var eraserPreviewPoint: CanvasPoint?
    private var activeEraserRemovedStrokes: [IndexedStroke] = []
    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    private var activeStrokeLayer: CAShapeLayer?
    private var eraserPreviewLayer: CAShapeLayer?
    private var undoStack: [CanvasAction] = []
    private var redoStack: [CanvasAction] = []

    private let canvasLayer = CALayer()
    private let hudUpdateInterval: CFTimeInterval = 1.0 / 15.0
    private var lastHUDUpdateTime: CFTimeInterval = 0

    /// Lets a finger (or the simulator's mouse) draw. While enabled,
    /// panning needs two fingers so drawing and panning don't fight.
    var fingerDrawingEnabled = false {
        didSet { panRecognizer.minimumNumberOfTouches = fingerDrawingEnabled ? 2 : 1 }
    }

    var toolStyle: PrototypeToolStyle = .default

    var onChange: ((Camera, Int) -> Void)?

    private let minScale: CGFloat = 0.05
    private let maxScale: CGFloat = 64

    private let panRecognizer = UIPanGestureRecognizer()
    private let pinchRecognizer = UIPinchGestureRecognizer()
    private let rotationRecognizer = UIRotationGestureRecognizer()
    private let undoRecognizer = UITapGestureRecognizer()
    private let redoRecognizer = UITapGestureRecognizer()

    private enum ActiveInput {
        case drawing
        case erasing
    }

    private enum CanvasAction {
        case add(PrototypeStroke)
        case remove([IndexedStroke])
    }

    private struct IndexedStroke {
        let stroke: PrototypeStroke
        let index: Int
    }

    // MARK: Setup

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1)
        contentMode = .redraw
        layer.addSublayer(canvasLayer)
        canvasLayer.anchorPoint = .zero
        canvasLayer.position = .zero
        canvasLayer.masksToBounds = false
        canvasLayer.contentsScale = traitCollection.displayScale

        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 2
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        rotationRecognizer.addTarget(self, action: #selector(handleRotation(_:)))
        undoRecognizer.addTarget(self, action: #selector(handleUndoTap(_:)))
        undoRecognizer.numberOfTouchesRequired = 2
        undoRecognizer.numberOfTapsRequired = 2
        undoRecognizer.cancelsTouchesInView = false
        redoRecognizer.addTarget(self, action: #selector(handleRedoTap(_:)))
        redoRecognizer.numberOfTouchesRequired = 3
        redoRecognizer.numberOfTapsRequired = 2
        redoRecognizer.cancelsTouchesInView = false

        // Navigation is finger-only; pencil touches fall through to the
        // touches* overrides below and always draw.
        let fingerOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in [panRecognizer, pinchRecognizer, rotationRecognizer, undoRecognizer, redoRecognizer] {
            recognizer.allowedTouchTypes = fingerOnly
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        undoRecognizer.require(toFail: redoRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Camera

    private var hasSetInitialCamera = false

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCanvasLayer()
        // Start with the canvas origin centered so the grid axes are visible.
        if !hasSetInitialCamera, bounds.width > 0 {
            hasSetInitialCamera = true
            camera = defaultCamera
        } else {
            updateCanvasLayerTransform()
        }
    }

    private var defaultCamera: Camera {
        Camera(translation: CGVector(dx: bounds.midX, dy: bounds.midY))
    }

    func resetCamera() {
        camera = defaultCamera
        noteChanged(force: true)
    }

    func clearInk() {
        strokes.removeAll()
        for layer in strokeLayers.values {
            layer.removeFromSuperlayer()
        }
        strokeLayers.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        activeStrokeLayer?.removeFromSuperlayer()
        activeStrokeLayer = nil
        removeEraserPreview()
        activeStroke = nil
        activeTouch = nil
        activeInput = nil
        activeToolStyle = nil
        predictedPoints = []
        eraserPreviewPoint = nil
        activeEraserRemovedStrokes = []
        setNeedsDisplay()
        noteChanged(force: true)
    }

    func makeNoteDocument(id: UUID, title: String, createdAt: Date) -> PrototypeNoteDocument {
        cancelActiveInputForHistoryGesture()
        let now = Date()
        return PrototypeNoteDocument(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: now,
            camera: PrototypeCameraSnapshot(camera: camera),
            strokes: strokes
        )
    }

    func loadNote(_ note: PrototypeNoteDocument) {
        replaceCanvas(strokes: note.strokes, camera: note.camera.camera)
    }

    func startBlankNote() {
        replaceCanvas(strokes: [], camera: defaultCamera)
    }

    private func noteChanged(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastHUDUpdateTime >= hudUpdateInterval else { return }
        lastHUDUpdateTime = now
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

    @objc private func handleUndoTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized else { return }
        undo()
    }

    @objc private func handleRedoTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized else { return }
        redo()
    }

    // MARK: Pencil input → canvas-space strokes

    private func isDrawingTouch(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (fingerDrawingEnabled && touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first(where: isDrawingTouch) else { return }
        activeTouch = touch
        let style = toolStyle
        activeToolStyle = style

        let firstSample = sample(touch)
        if style.kind == .eraser {
            activeInput = .erasing
            activeEraserRemovedStrokes = []
            eraserPreviewPoint = firstSample.position
            updateEraserPreview(at: firstSample.position, radius: style.width / 2)
            erase(at: [firstSample], radius: style.width / 2)
        } else {
            activeInput = .drawing
            activeStroke = PrototypeStroke(points: [firstSample], style: style)
            if let activeStroke {
                let layer = makeStrokeLayer(for: activeStroke)
                activeStrokeLayer = layer
                withoutLayerActions {
                    canvasLayer.addSublayer(layer)
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let activeInput else { return }
        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        let samples = coalesced.map(sample)

        switch activeInput {
        case .drawing:
            activeStroke?.append(samples)
            predictedPoints = (event?.predictedTouches(for: touch) ?? []).map(sample)
            updateActiveStrokeLayer()
        case .erasing:
            predictedPoints = []
            eraserPreviewPoint = samples.last?.position
            if let point = eraserPreviewPoint {
                updateEraserPreview(at: point, radius: (activeToolStyle ?? toolStyle).width / 2)
            }
            erase(at: samples, radius: (activeToolStyle ?? toolStyle).width / 2)
        }
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
        if activeInput == .drawing, let stroke = activeStroke, !stroke.points.isEmpty {
            predictedPoints = []
            updateStrokeLayer(activeStrokeLayer, for: stroke)
            strokes.append(stroke)
            if let activeStrokeLayer {
                strokeLayers[stroke.id] = activeStrokeLayer
            }
            record(.add(stroke))
        } else if activeInput == .erasing, !activeEraserRemovedStrokes.isEmpty {
            record(.remove(activeEraserRemovedStrokes))
        } else {
            activeStrokeLayer?.removeFromSuperlayer()
        }
        activeStroke = nil
        activeTouch = nil
        activeInput = nil
        activeToolStyle = nil
        activeStrokeLayer = nil
        predictedPoints = []
        eraserPreviewPoint = nil
        activeEraserRemovedStrokes = []
        removeEraserPreview()
        noteChanged(force: true)
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
        ctx.restoreGState()
    }

    private func layoutCanvasLayer() {
        withoutLayerActions {
            canvasLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            canvasLayer.position = .zero
        }
    }

    private func updateCanvasLayerTransform() {
        withoutLayerActions {
            canvasLayer.setAffineTransform(camera.transform)
        }
    }

    private func makeStrokeLayer(for stroke: PrototypeStroke) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = traitCollection.displayScale
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.masksToBounds = false
        updateStrokeLayer(layer, for: stroke)
        return layer
    }

    private func replaceCanvas(strokes newStrokes: [PrototypeStroke], camera newCamera: Camera) {
        cancelActiveInputForHistoryGesture()
        for layer in strokeLayers.values {
            layer.removeFromSuperlayer()
        }
        strokeLayers.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        activeStrokeLayer?.removeFromSuperlayer()
        activeStrokeLayer = nil
        removeEraserPreview()

        strokes = []
        for stroke in newStrokes {
            addStrokeWithoutHistory(stroke, at: strokes.count)
        }
        camera = newCamera
        noteChanged(force: true)
    }

    private func addStrokeWithoutHistory(_ stroke: PrototypeStroke, at index: Int) {
        let insertionIndex = min(max(index, 0), strokes.count)
        strokes.insert(stroke, at: insertionIndex)
        let strokeLayer = makeStrokeLayer(for: stroke)
        strokeLayers[stroke.id] = strokeLayer
        withoutLayerActions {
            insertLayer(strokeLayer, forStrokeAt: insertionIndex)
        }
    }

    private func updateActiveStrokeLayer() {
        guard let activeStroke else { return }
        updateStrokeLayer(activeStrokeLayer, for: activeStroke, include: predictedPoints)
    }

    private func updateStrokeLayer(
        _ layer: CAShapeLayer?,
        for stroke: PrototypeStroke,
        include predictedPoints: [PrototypePoint] = []
    ) {
        guard let layer else { return }
        let renderBounds = stroke.renderBounds(include: predictedPoints)
        guard !renderBounds.isNull else { return }

        let color = stroke.style.color.uiColor(alpha: 1)
        withoutLayerActions {
            layer.frame = renderBounds
            layer.path = stroke.layerPath(include: predictedPoints)
            layer.opacity = Float(stroke.style.opacity)
            layer.lineWidth = stroke.renderWidth

            if stroke.points.count + predictedPoints.count == 1 {
                layer.fillColor = color.cgColor
                layer.strokeColor = nil
            } else {
                layer.fillColor = nil
                layer.strokeColor = color.cgColor
            }
        }
    }

    private func updateEraserPreview(at point: CanvasPoint, radius: CGFloat) {
        let previewLayer = eraserPreviewLayer ?? makeEraserPreviewLayer()
        eraserPreviewLayer = previewLayer
        if previewLayer.superlayer == nil {
            withoutLayerActions {
                canvasLayer.addSublayer(previewLayer)
            }
        }

        let frame = CGRect(
            x: point.x - Double(radius),
            y: point.y - Double(radius),
            width: Double(radius * 2),
            height: Double(radius * 2)
        )
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: .zero, size: frame.size))

        withoutLayerActions {
            previewLayer.frame = frame
            previewLayer.path = path
        }
    }

    private func makeEraserPreviewLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = traitCollection.displayScale
        layer.fillColor = UIColor.label.withAlphaComponent(0.06).cgColor
        layer.strokeColor = UIColor.label.withAlphaComponent(0.45).cgColor
        layer.lineWidth = 1
        return layer
    }

    private func removeEraserPreview() {
        eraserPreviewLayer?.removeFromSuperlayer()
        eraserPreviewLayer = nil
    }

    private func withoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private func record(_ action: CanvasAction) {
        undoStack.append(action)
        redoStack.removeAll()
    }

    private func undo() {
        cancelActiveInputForHistoryGesture()
        guard let action = undoStack.popLast() else { return }
        applyInverse(action)
        redoStack.append(action)
        noteChanged(force: true)
    }

    private func redo() {
        cancelActiveInputForHistoryGesture()
        guard let action = redoStack.popLast() else { return }
        apply(action)
        undoStack.append(action)
        noteChanged(force: true)
    }

    private func apply(_ action: CanvasAction) {
        switch action {
        case .add(let stroke):
            addStroke(stroke, at: strokes.count)
        case .remove(let indexedStrokes):
            removeStrokes(withIDs: indexedStrokes.map(\.stroke.id))
        }
    }

    private func applyInverse(_ action: CanvasAction) {
        switch action {
        case .add(let stroke):
            removeStrokes(withIDs: [stroke.id])
        case .remove(let indexedStrokes):
            restore(indexedStrokes)
        }
    }

    private func addStroke(_ stroke: PrototypeStroke, at index: Int) {
        let insertionIndex = min(max(index, 0), strokes.count)
        strokes.insert(stroke, at: insertionIndex)
        let strokeLayer = makeStrokeLayer(for: stroke)
        strokeLayers[stroke.id] = strokeLayer
        withoutLayerActions {
            insertLayer(strokeLayer, forStrokeAt: insertionIndex)
        }
    }

    private func restore(_ indexedStrokes: [IndexedStroke]) {
        for indexedStroke in indexedStrokes.sorted(by: { $0.index < $1.index }) {
            addStroke(indexedStroke.stroke, at: indexedStroke.index)
        }
    }

    private func removeStrokes(withIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let ids = Set(ids)
        strokes.removeAll { ids.contains($0.id) }
        for id in ids {
            withoutLayerActions {
                strokeLayers[id]?.removeFromSuperlayer()
            }
            strokeLayers.removeValue(forKey: id)
        }
    }

    private func insertLayer(_ layer: CALayer, forStrokeAt index: Int) {
        if index >= canvasLayer.sublayers?.count ?? 0 {
            canvasLayer.addSublayer(layer)
            return
        }

        let followingLayer = strokes.dropFirst(index + 1)
            .lazy
            .compactMap { [self] in strokeLayers[$0.id] }
            .first

        if let followingLayer {
            canvasLayer.insertSublayer(layer, below: followingLayer)
        } else {
            canvasLayer.addSublayer(layer)
        }
    }

    private func cancelActiveInputForHistoryGesture() {
        guard activeInput != nil else { return }

        if activeInput == .drawing {
            withoutLayerActions {
                activeStrokeLayer?.removeFromSuperlayer()
            }
        } else if activeInput == .erasing, !activeEraserRemovedStrokes.isEmpty {
            restore(activeEraserRemovedStrokes)
        }

        activeStroke = nil
        activeTouch = nil
        activeInput = nil
        activeToolStyle = nil
        activeStrokeLayer = nil
        predictedPoints = []
        eraserPreviewPoint = nil
        activeEraserRemovedStrokes = []
        removeEraserPreview()
    }

    private func erase(at samples: [PrototypePoint], radius: CGFloat) {
        guard !samples.isEmpty else { return }
        let previousCount = strokes.count
        var removed: [IndexedStroke] = []
        strokes = strokes.enumerated().compactMap { index, stroke in
            let shouldRemove = samples.contains { sample in
                stroke.contains(sample.position, eraserRadius: radius)
            }
            if shouldRemove {
                removed.append(IndexedStroke(stroke: stroke, index: index))
                return nil
            }
            return stroke
        }
        activeEraserRemovedStrokes.append(contentsOf: removed)
        for indexedStroke in removed {
            withoutLayerActions {
                strokeLayers[indexedStroke.stroke.id]?.removeFromSuperlayer()
            }
            strokeLayers.removeValue(forKey: indexedStroke.stroke.id)
        }
        if strokes.count != previousCount {
            noteChanged(force: true)
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
