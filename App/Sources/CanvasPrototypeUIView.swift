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
    private var activeSelectionPoints: [CanvasPoint] = []
    private var selectionLassoPoints: [CanvasPoint] = []
    private var selectedStrokeIDs: Set<UUID> = []
    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    private var activeStrokeLayer: CAShapeLayer?
    private var eraserPreviewLayer: CAShapeLayer?
    private var selectionLayer: CAShapeLayer?
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
    private let circleSelectRecognizer = UILongPressGestureRecognizer()

    private enum ActiveInput {
        case drawing
        case erasing
        case selecting
    }

    private enum CanvasAction {
        case add(PrototypeStroke)
        case remove([IndexedStroke])
        case transform(SelectionTransformAction)
    }

    private struct IndexedStroke {
        let stroke: PrototypeStroke
        let index: Int
    }

    private struct SelectionTransformAction {
        let before: [PrototypeStroke]
        let after: [PrototypeStroke]
        let lassoBefore: [CanvasPoint]
        let lassoAfter: [CanvasPoint]
    }

    private struct SelectionTransform {
        let center: CanvasPoint
        let translation: CGVector
        let scale: CGFloat
        let rotation: CGFloat

        func apply(to point: CanvasPoint) -> CanvasPoint {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let scaledX = dx * Double(scale)
            let scaledY = dy * Double(scale)
            let c = Double(cos(rotation))
            let s = Double(sin(rotation))

            return CanvasPoint(
                x: center.x + Double(translation.dx) + c * scaledX - s * scaledY,
                y: center.y + Double(translation.dy) + s * scaledX + c * scaledY
            )
        }
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
        circleSelectRecognizer.addTarget(self, action: #selector(handleCircleSelectPress(_:)))
        circleSelectRecognizer.minimumPressDuration = 0.45
        circleSelectRecognizer.allowableMovement = 18
        circleSelectRecognizer.cancelsTouchesInView = false

        // Navigation is finger-only; pencil touches fall through to the
        // touches* overrides below and always draw.
        let fingerOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in [panRecognizer, pinchRecognizer, rotationRecognizer, undoRecognizer, redoRecognizer] {
            recognizer.allowedTouchTypes = fingerOnly
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        circleSelectRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
        circleSelectRecognizer.delegate = self
        addGestureRecognizer(circleSelectRecognizer)
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
        clearSelection()
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
        activeSelectionPoints = []
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

    func deleteSelectedStrokes() {
        guard !selectedStrokeIDs.isEmpty else { return }
        let removed = indexedStrokes(withIDs: selectedStrokeIDs)
        guard !removed.isEmpty else {
            clearSelection()
            return
        }

        removeIndexedStrokes(removed)
        record(.remove(removed))
        clearSelection()
        noteChanged(force: true)
    }

    func translateSelectionByScreen(dx: CGFloat, dy: CGFloat) {
        guard let center = selectedStrokeCenter else { return }
        let screenCenter = camera.toScreen(center)
        let movedCenter = camera.toCanvas(ScreenPoint(
            x: screenCenter.x + Double(dx),
            y: screenCenter.y + Double(dy)
        ))
        let transform = SelectionTransform(
            center: center,
            translation: CGVector(
                dx: CGFloat(movedCenter.x - center.x),
                dy: CGFloat(movedCenter.y - center.y)
            ),
            scale: 1,
            rotation: 0
        )
        transformSelection(transform, scalesStrokeWidth: false)
    }

    func scaleSelection(by factor: CGFloat) {
        guard factor > 0, let center = selectedStrokeCenter else { return }
        let transform = SelectionTransform(
            center: center,
            translation: .zero,
            scale: factor,
            rotation: 0
        )
        transformSelection(transform, scalesStrokeWidth: true)
    }

    func rotateSelection(by radians: CGFloat) {
        guard let center = selectedStrokeCenter else { return }
        let transform = SelectionTransform(
            center: center,
            translation: .zero,
            scale: 1,
            rotation: radians
        )
        transformSelection(transform, scalesStrokeWidth: false)
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

    @objc private func handleCircleSelectPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        cancelActiveInputForHistoryGesture()

        let location = ScreenPoint(cgPoint: recognizer.location(in: self))
        let canvasPoint = camera.toCanvas(location)
        guard let circleStroke = circleSelectionCandidate(at: canvasPoint) else { return }

        let lassoPoints = circleStroke.stroke.points.map(\.position)
        var hitIDs = strokeIDsHit(by: lassoPoints, includeInterior: true)
        hitIDs.remove(circleStroke.stroke.id)
        guard !hitIDs.isEmpty else { return }

        let removedCircle = IndexedStroke(stroke: circleStroke.stroke, index: circleStroke.index)
        removeIndexedStrokes([removedCircle])
        record(.remove([removedCircle]))
        selectStrokeIDs(hitIDs, lassoPoints: lassoPoints)
        noteChanged(force: true)
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
        if style.kind == .selection {
            activeInput = .selecting
            clearSelection()
            activeSelectionPoints = [firstSample.position]
            updateSelectionLayer(points: activeSelectionPoints, isFinal: false)
        } else if style.kind == .eraser {
            clearSelection()
            activeInput = .erasing
            activeEraserRemovedStrokes = []
            eraserPreviewPoint = firstSample.position
            updateEraserPreview(at: firstSample.position, radius: style.width / 2)
            erase(at: [firstSample], radius: style.width / 2)
        } else {
            clearSelection()
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
        case .selecting:
            appendSelectionPoints(samples.map(\.position))
            predictedPoints = []
            updateSelectionLayer(points: activeSelectionPoints, isFinal: false)
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
        switch activeInput {
        case .drawing:
            finishDrawingStroke()
        case .erasing:
            if !activeEraserRemovedStrokes.isEmpty {
                record(.remove(activeEraserRemovedStrokes))
            }
        case .selecting:
            finishSelection()
        case nil:
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
        activeSelectionPoints = []
        removeEraserPreview()
        noteChanged(force: true)
    }

    private func finishDrawingStroke() {
        guard let stroke = activeStroke, !stroke.points.isEmpty else {
            activeStrokeLayer?.removeFromSuperlayer()
            return
        }

        if handleScribbleDeleteIfNeeded(stroke) {
            activeStrokeLayer?.removeFromSuperlayer()
            return
        }

        commitStroke(stroke, layer: activeStrokeLayer)
    }

    private func commitStroke(_ stroke: PrototypeStroke, layer: CAShapeLayer?) {
        guard !stroke.points.isEmpty else {
            layer?.removeFromSuperlayer()
            return
        }

        var stroke = stroke
        if stroke.style.kind == .selection {
            stroke.style = PrototypeToolStyle.default
        }
        if layer == activeStrokeLayer {
            predictedPoints = []
        }
        if let layer {
            updateStrokeLayer(layer, for: stroke)
            strokes.append(stroke)
            strokeLayers[stroke.id] = layer
        } else {
            addStrokeWithoutHistory(stroke, at: strokes.count)
        }
        record(.add(stroke))
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
        clearSelection()
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

    private func appendSelectionPoints(_ points: [CanvasPoint]) {
        for point in points {
            guard let last = activeSelectionPoints.last else {
                activeSelectionPoints.append(point)
                continue
            }

            if distance(last.cgPoint, to: point.cgPoint) >= max(2 / camera.scale, 0.75) {
                activeSelectionPoints.append(point)
            }
        }
    }

    private func finishSelection() {
        let points = activeSelectionPoints
        guard points.count > 1 else {
            clearSelection()
            return
        }

        let ids = strokeIDsHit(by: points, includeInterior: true)
        selectStrokeIDs(ids, lassoPoints: points)
    }

    private func selectStrokeIDs(_ ids: Set<UUID>, lassoPoints: [CanvasPoint]) {
        selectedStrokeIDs = ids
        selectionLassoPoints = lassoPoints
        updateSelectionLayer(points: lassoPoints, isFinal: true)
        applySelectionHighlight()
    }

    private func clearSelection() {
        selectedStrokeIDs.removeAll()
        selectionLassoPoints.removeAll()
        activeSelectionPoints.removeAll()
        selectionLayer?.removeFromSuperlayer()
        selectionLayer = nil
        applySelectionHighlight()
    }

    private func updateSelectionLayer(points: [CanvasPoint], isFinal: Bool) {
        guard points.count > 1 else { return }
        let layer = selectionLayer ?? makeSelectionLayer()
        selectionLayer = layer
        if layer.superlayer == nil {
            withoutLayerActions {
                canvasLayer.addSublayer(layer)
            }
        }

        let bounds = boundingRect(for: points).insetBy(dx: -12, dy: -12)
        let path = CGMutablePath()
        path.move(to: localPoint(points[0], in: bounds))
        for point in points.dropFirst() {
            path.addLine(to: localPoint(point, in: bounds))
        }
        if isFinal, isClosedShape(points) {
            path.closeSubpath()
        }

        withoutLayerActions {
            layer.frame = bounds
            layer.path = path
            layer.fillColor = isFinal && isClosedShape(points)
                ? UIColor.systemBlue.withAlphaComponent(0.08).cgColor
                : UIColor.clear.cgColor
            layer.lineWidth = max(2 / camera.scale, 0.75)
        }
    }

    private func makeSelectionLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = traitCollection.displayScale
        layer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.lineDashPattern = [8, 5]
        return layer
    }

    private func applySelectionHighlight() {
        for (id, layer) in strokeLayers {
            let isSelected = selectedStrokeIDs.contains(id)
            withoutLayerActions {
                layer.shadowColor = isSelected ? UIColor.systemBlue.cgColor : nil
                layer.shadowOpacity = isSelected ? 0.95 : 0
                layer.shadowRadius = isSelected ? 4 : 0
                layer.shadowOffset = .zero
            }
        }
    }

    private func strokeIDsHit(
        by lassoPoints: [CanvasPoint],
        includeInterior: Bool,
        tolerance overrideTolerance: CGFloat? = nil
    ) -> Set<UUID> {
        guard lassoPoints.count > 1 else { return [] }
        let tolerance = overrideTolerance ?? selectionHitRadius
        let lassoBounds = boundingRect(for: lassoPoints).insetBy(dx: -Double(tolerance), dy: -Double(tolerance))
        let closed = includeInterior && isClosedShape(lassoPoints)

        return Set(strokes.compactMap { stroke in
            guard stroke.renderBounds.intersects(lassoBounds) else { return nil }
            if lassoTouches(stroke, points: lassoPoints, tolerance: tolerance) {
                return stroke.id
            }
            if closed, stroke.points.contains(where: { pointInPolygon($0.position, polygon: lassoPoints) }) {
                return stroke.id
            }
            return nil
        })
    }

    private func lassoTouches(_ stroke: PrototypeStroke, points: [CanvasPoint], tolerance: CGFloat) -> Bool {
        points.contains { point in
            stroke.contains(point, eraserRadius: tolerance)
        }
    }

    private var selectionHitRadius: CGFloat {
        max(8 / camera.scale, 3)
    }

    private var selectedStrokes: [PrototypeStroke] {
        strokes.filter { selectedStrokeIDs.contains($0.id) }
    }

    private var selectedStrokeCenter: CanvasPoint? {
        let points = selectedStrokes.flatMap { stroke in
            stroke.points.map(\.position)
        }
        guard !points.isEmpty else {
            if !selectedStrokeIDs.isEmpty {
                clearSelection()
            }
            return nil
        }

        let bounds = boundingRect(for: points)
        return CanvasPoint(x: bounds.midX, y: bounds.midY)
    }

    private func transformSelection(_ transform: SelectionTransform, scalesStrokeWidth: Bool) {
        cancelActiveInputForHistoryGesture()

        let before = selectedStrokes
        guard !before.isEmpty else {
            clearSelection()
            return
        }

        let lassoBefore = selectionLassoPoints
        let after = before.map { stroke in
            transformed(stroke, by: transform, scalesStrokeWidth: scalesStrokeWidth)
        }
        let lassoAfter = lassoBefore.map(transform.apply)

        applyStrokeVersions(after, lassoPoints: lassoAfter)
        record(.transform(SelectionTransformAction(
            before: before,
            after: after,
            lassoBefore: lassoBefore,
            lassoAfter: lassoAfter
        )))
        noteChanged(force: true)
    }

    private func transformed(
        _ stroke: PrototypeStroke,
        by transform: SelectionTransform,
        scalesStrokeWidth: Bool
    ) -> PrototypeStroke {
        var stroke = stroke
        stroke.points = stroke.points.map { point in
            PrototypePoint(position: transform.apply(to: point.position), force: point.force)
        }
        if scalesStrokeWidth {
            stroke.style = scaledStyle(stroke.style, by: transform.scale)
        }
        return stroke
    }

    private func scaledStyle(_ style: PrototypeToolStyle, by factor: CGFloat) -> PrototypeToolStyle {
        PrototypeToolStyle(
            kind: style.kind,
            color: style.color,
            width: min(max(style.width * factor, 0.5), 160),
            opacity: style.opacity,
            pressureSensitive: style.pressureSensitive,
            blendMode: style.blendMode
        )
    }

    private func applyStrokeVersions(_ versions: [PrototypeStroke], lassoPoints: [CanvasPoint]) {
        guard !versions.isEmpty else { return }
        let versionsByID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
        for index in strokes.indices {
            guard let updatedStroke = versionsByID[strokes[index].id] else { continue }
            strokes[index] = updatedStroke
            updateStrokeLayer(strokeLayers[updatedStroke.id], for: updatedStroke)
        }

        if !selectedStrokeIDs.isDisjoint(with: Set(versionsByID.keys)) {
            selectionLassoPoints = lassoPoints
            if lassoPoints.count > 1 {
                updateSelectionLayer(points: lassoPoints, isFinal: true)
            } else {
                selectionLayer?.removeFromSuperlayer()
                selectionLayer = nil
            }
        }
        applySelectionHighlight()
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

    private func handleScribbleDeleteIfNeeded(_ stroke: PrototypeStroke) -> Bool {
        guard isScribbleDeleteGesture(stroke) else { return false }
        let hitIDs = strokeIDsHit(
            by: stroke.points.map(\.position),
            includeInterior: false,
            tolerance: max(stroke.renderWidth, selectionHitRadius)
        )
        let removed = indexedStrokes(withIDs: hitIDs)
        guard !removed.isEmpty else { return false }

        removeIndexedStrokes(removed)
        record(.remove(removed))
        clearSelection()
        noteChanged(force: true)
        return true
    }

    private func isScribbleDeleteGesture(_ stroke: PrototypeStroke) -> Bool {
        guard [.pen, .pencil, .marker].contains(stroke.style.kind),
              stroke.points.count >= 10
        else { return false }

        let points = stroke.points.map(\.position)
        let box = boundingRect(for: points)
        let diagonal = max(hypot(box.width, box.height), 1)
        guard diagonal >= 18 else { return false }

        let length = pathLength(points)
        let reversals = directionReversalCount(points)
        return length / diagonal >= 3.2 && reversals >= 3
    }

    private func circleSelectionCandidate(at point: CanvasPoint) -> IndexedStroke? {
        let hitRadius = max(14 / camera.scale, 5)
        for (index, stroke) in strokes.enumerated().reversed() {
            guard isCircleSelectionCandidate(stroke),
                  stroke.contains(point, eraserRadius: hitRadius)
            else { continue }
            return IndexedStroke(stroke: stroke, index: index)
        }
        return nil
    }

    private func isCircleSelectionCandidate(_ stroke: PrototypeStroke) -> Bool {
        guard [.pen, .pencil, .marker].contains(stroke.style.kind),
              stroke.points.count >= 12
        else { return false }

        let points = stroke.points.map(\.position)
        guard isClosedShape(points) else { return false }

        let box = boundingRect(for: points)
        let width = max(box.width, 1)
        let height = max(box.height, 1)
        let diagonal = hypot(width, height)
        let aspect = width / height
        guard diagonal >= 35, (0.45...2.2).contains(aspect) else { return false }

        let fillRatio = abs(polygonArea(points)) / max(width * height, 1)
        let lengthRatio = pathLength(points) / max(diagonal, 1)
        return (0.22...0.92).contains(fillRatio) && (1.8...7.5).contains(lengthRatio)
    }

    private func apply(_ action: CanvasAction) {
        switch action {
        case .add(let stroke):
            addStroke(stroke, at: strokes.count)
        case .remove(let indexedStrokes):
            removeStrokes(withIDs: indexedStrokes.map(\.stroke.id))
        case .transform(let transformAction):
            applyStrokeVersions(transformAction.after, lassoPoints: transformAction.lassoAfter)
        }
    }

    private func applyInverse(_ action: CanvasAction) {
        switch action {
        case .add(let stroke):
            removeStrokes(withIDs: [stroke.id])
        case .remove(let indexedStrokes):
            restore(indexedStrokes)
        case .transform(let transformAction):
            applyStrokeVersions(transformAction.before, lassoPoints: transformAction.lassoBefore)
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
        removeIndexedStrokes(indexedStrokes(withIDs: Set(ids)))
    }

    private func indexedStrokes(withIDs ids: Set<UUID>) -> [IndexedStroke] {
        strokes.enumerated().compactMap { index, stroke in
            ids.contains(stroke.id) ? IndexedStroke(stroke: stroke, index: index) : nil
        }
    }

    private func removeIndexedStrokes(_ indexedStrokes: [IndexedStroke]) {
        guard !indexedStrokes.isEmpty else { return }
        let ids = Set(indexedStrokes.map(\.stroke.id))
        strokes.removeAll { ids.contains($0.id) }
        selectedStrokeIDs.subtract(ids)

        for id in ids {
            withoutLayerActions {
                strokeLayers[id]?.removeFromSuperlayer()
            }
            strokeLayers.removeValue(forKey: id)
        }
        applySelectionHighlight()
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
        activeSelectionPoints = []
        if selectedStrokeIDs.isEmpty {
            selectionLayer?.removeFromSuperlayer()
            selectionLayer = nil
        }
        removeEraserPreview()
    }

    private func erase(at samples: [PrototypePoint], radius: CGFloat) {
        guard !samples.isEmpty else { return }
        let previousCount = strokes.count
        let removed = strokes.enumerated().compactMap { index, stroke -> IndexedStroke? in
            let shouldRemove = samples.contains { sample in
                stroke.contains(sample.position, eraserRadius: radius)
            }
            return shouldRemove ? IndexedStroke(stroke: stroke, index: index) : nil
        }
        removeIndexedStrokes(removed)
        activeEraserRemovedStrokes.append(contentsOf: removed)
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

private func localPoint(_ point: CanvasPoint, in bounds: CGRect) -> CGPoint {
    CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
}

private func boundingRect(for points: [CanvasPoint]) -> CGRect {
    guard let first = points.first else { return .null }
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y

    for point in points.dropFirst() {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }

    return CGRect(
        x: minX,
        y: minY,
        width: max(maxX - minX, 1),
        height: max(maxY - minY, 1)
    )
}

private func distance(_ a: CGPoint, to b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

private func pathLength(_ points: [CanvasPoint]) -> CGFloat {
    guard points.count > 1 else { return 0 }
    var length: CGFloat = 0
    for index in 1..<points.count {
        length += distance(points[index - 1].cgPoint, to: points[index].cgPoint)
    }
    return length
}

private func directionReversalCount(_ points: [CanvasPoint]) -> Int {
    guard points.count > 2 else { return 0 }
    let box = boundingRect(for: points)
    let useX = box.width >= box.height
    var lastSign = 0
    var reversals = 0

    for index in 1..<points.count {
        let delta = useX
            ? points[index].x - points[index - 1].x
            : points[index].y - points[index - 1].y
        guard abs(delta) >= 2 else { continue }

        let sign = delta > 0 ? 1 : -1
        if lastSign != 0, sign != lastSign {
            reversals += 1
        }
        lastSign = sign
    }

    return reversals
}

private func isClosedShape(_ points: [CanvasPoint]) -> Bool {
    guard let first = points.first, let last = points.last, points.count >= 8 else { return false }
    let box = boundingRect(for: points)
    let diagonal = hypot(box.width, box.height)
    let threshold = max(8, min(45, diagonal * 0.22))
    return distance(first.cgPoint, to: last.cgPoint) <= threshold
}

private func polygonArea(_ points: [CanvasPoint]) -> CGFloat {
    guard points.count > 2 else { return 0 }
    var area: Double = 0
    for index in points.indices {
        let next = points.index(after: index) == points.endIndex ? points.startIndex : points.index(after: index)
        area += points[index].x * points[next].y - points[next].x * points[index].y
    }
    return CGFloat(area / 2)
}

private func pointInPolygon(_ point: CanvasPoint, polygon: [CanvasPoint]) -> Bool {
    guard polygon.count > 2 else { return false }
    var isInside = false
    var j = polygon.count - 1

    for i in polygon.indices {
        let pi = polygon[i]
        let pj = polygon[j]
        let crosses = (pi.y > point.y) != (pj.y > point.y)
        if crosses {
            let x = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
            if point.x < x {
                isInside.toggle()
            }
        }
        j = i
    }

    return isInside
}
