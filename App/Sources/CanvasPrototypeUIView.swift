import CanvasCore
import Model
import QuartzCore
import SketchKit
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
            updateBrushPreviewLayer()
            noteChanged()
        }
    }

    private var strokes: [PrototypeStroke] = []
    private var activeStroke: PrototypeStroke?
    private var activeTouch: UITouch?
    private var activeInput: ActiveInput?
    private var activePageIndex: Int?
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
    private var brushPreviewLayer: CAShapeLayer?
    private var brushPreviewScreenPoint: CGPoint?
    private var undoStack: [CanvasAction] = []
    private var redoStack: [CanvasAction] = []
    private var selectionTransformSession: SelectionTransformSession?
    private var activeSelectionGestureRecognizers = Set<ObjectIdentifier>()
    private var activeSelectionDragScreenPoint: ScreenPoint?
    private var rotationSnapDisplayLink: CADisplayLink?
    private var rotationSnapStartTime: CFTimeInterval = 0
    private var rotationSnapStartCamera = Camera()
    private var rotationSnapDelta: CGFloat = 0
    private var rotationSnapPivot = ScreenPoint(x: 0, y: 0)
    private let rotationSnapDisplayLinkTarget = RotationSnapDisplayLinkTarget()
    private let pencilInteraction = UIPencilInteraction()
    private let hoverRecognizer = UIHoverGestureRecognizer()

    private let canvasLayer = CALayer()
    private let hudUpdateInterval: CFTimeInterval = 1.0 / 15.0
    private var lastHUDUpdateTime: CFTimeInterval = 0

    var toolStyle: PrototypeToolStyle = .default {
        didSet { updateBrushPreviewLayer() }
    }

    var pageType: PrototypePageType = .infiniteCanvas {
        didSet {
            guard oldValue != pageType else { return }
            pageCount = pageType.canvasPageRect == nil ? 1 : max(pageCount, 1)
            updateBackgroundColor()
            setNeedsDisplay()
        }
    }

    var pageCount: Int = 1 {
        didSet {
            pageCount = max(pageCount, 1)
            guard oldValue != pageCount else { return }
            setNeedsDisplay()
            onPageCountChange?(pageCount)
        }
    }

    var onChange: ((Camera, Int, Int) -> Void)?
    var onPageCountChange: ((Int) -> Void)?
    var onPencilQuickAccess: ((CGPoint?) -> Void)?

    private let minScale: CGFloat = 0.05
    private let maxScale: CGFloat = 64
    private let rotationSnapDuration: CFTimeInterval = 0.24
    private let pageGap: CGFloat = 120

    private let panRecognizer = UIPanGestureRecognizer()
    private let pinchRecognizer = UIPinchGestureRecognizer()
    private let rotationRecognizer = UIRotationGestureRecognizer()
    private let snapRotationRecognizer = UITapGestureRecognizer()
    private let undoRecognizer = UITapGestureRecognizer()
    private let redoRecognizer = UITapGestureRecognizer()
    private let circleSelectRecognizer = UILongPressGestureRecognizer()

    private enum ActiveInput {
        case drawing
        case erasing
        case selecting
        case movingSelection
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

    private struct SelectionTransformSession {
        let before: [PrototypeStroke]
        let lassoBefore: [CanvasPoint]
        var changed = false
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
        rotationSnapDisplayLinkTarget.view = self
        pencilInteraction.delegate = self
        isMultipleTouchEnabled = true
        isOpaque = true
        updateBackgroundColor()
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
        hoverRecognizer.addTarget(self, action: #selector(handleHover(_:)))
        snapRotationRecognizer.addTarget(self, action: #selector(handleSnapRotationTap(_:)))
        snapRotationRecognizer.numberOfTouchesRequired = 1
        snapRotationRecognizer.numberOfTapsRequired = 2
        snapRotationRecognizer.cancelsTouchesInView = false
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
        // touches* overrides below and always draw or move selected ink.
        let fingerOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in [
            panRecognizer,
            pinchRecognizer,
            rotationRecognizer,
            snapRotationRecognizer,
            undoRecognizer,
            redoRecognizer,
        ] {
            recognizer.allowedTouchTypes = fingerOnly
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        hoverRecognizer.delegate = self
        addGestureRecognizer(hoverRecognizer)
        circleSelectRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
        circleSelectRecognizer.delegate = self
        addGestureRecognizer(circleSelectRecognizer)
        addInteraction(pencilInteraction)
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
            setCamera(defaultCamera, pivot: nil)
        } else {
            updateCanvasLayerTransform()
        }
    }

    private var defaultCamera: Camera {
        defaultCamera(for: pageType, focusPageIndex: 0)
    }

    private func defaultCamera(
        for pageType: PrototypePageType,
        focusPageIndex: Int
    ) -> Camera {
        guard let pageRect = pageRect(at: focusPageIndex, pageType: pageType),
              bounds.width > 0,
              bounds.height > 0
        else {
            return Camera(translation: CGVector(dx: bounds.midX, dy: bounds.midY))
        }

        let margin: CGFloat = 56
        let bottomToolbarClearance: CGFloat = 132
        let availableWidth = max(bounds.width - margin * 2, 1)
        let availableHeight = max(bounds.height - margin * 2 - bottomToolbarClearance, 1)
        let scale = min(
            availableWidth / pageRect.width,
            availableHeight / pageRect.height,
            1
        )
        let visibleCenter = CGPoint(
            x: bounds.midX,
            y: (bounds.height - bottomToolbarClearance) / 2
        )

        return Camera(
            translation: CGVector(
                dx: visibleCenter.x - pageRect.midX * scale,
                dy: visibleCenter.y - pageRect.midY * scale
            ),
            scale: scale,
            rotation: 0
        )
    }

    private func setCamera(_ nextCamera: Camera, pivot: ScreenPoint?) {
        camera = constrainedCamera(nextCamera, pivot: pivot)
    }

    private func constrainedCamera(_ candidate: Camera, pivot: ScreenPoint?) -> Camera {
        guard pageType.canvasPageRect != nil,
              bounds.width > 0,
              bounds.height > 0
        else { return candidate }

        var constrained = candidate
        let scrollLocked = isPageScrollLocked(scale: constrained.scale)
        let limit: CGFloat = scrollLocked ? 0 : rotationLimit(for: constrained)
        let normalizedRotation = normalizedAngle(constrained.rotation)
        let clampedRotation = min(max(normalizedRotation, -limit), limit)
        let rotationDelta = shortestAngleDelta(from: normalizedRotation, to: clampedRotation)

        if abs(rotationDelta) > 0.0001 {
            constrained.rotateBy(rotationDelta, about: pivot ?? screenCenter)
        }
        constrained.rotation = clampedRotation
        if scrollLocked {
            constrained.translation.dx = centeredPageTranslationX(scale: constrained.scale)
        }
        return constrained
    }

    private func isPageScrollLocked(scale: CGFloat) -> Bool {
        guard pageType.canvasPageRect != nil,
              bounds.width > 0,
              bounds.height > 0
        else { return false }

        let pageSize = pageType.pageSize
        guard pageSize.width > 0, pageSize.height > 0 else { return false }
        let pageFillScale = max(bounds.width / pageSize.width, bounds.height / pageSize.height)
        return scale <= pageFillScale * 1.02
    }

    private func centeredPageTranslationX(scale: CGFloat) -> CGFloat {
        let pageWidth = pageType.pageSize.width
        return bounds.midX - (pageWidth * scale / 2)
    }

    private func rotationLimit(for candidate: Camera) -> CGFloat {
        if viewportFitsInsideSinglePage(using: candidate) {
            return .pi
        }

        let pageSize = pageType.pageSize
        guard pageSize.width > 0, pageSize.height > 0 else { return .pi }

        let fullPageScale = min(
            max((bounds.width - 112) / pageSize.width, 0),
            max((bounds.height - 180) / pageSize.height, 0)
        )
        let pageOnlyScale = max(bounds.width / pageSize.width, bounds.height / pageSize.height)
        let denominator = max(pageOnlyScale - fullPageScale, 0.001)
        let progress = min(max((candidate.scale - fullPageScale) / denominator, 0), 1)
        return (progress * progress) * (.pi / 4)
    }

    private func viewportFitsInsideSinglePage(using camera: Camera) -> Bool {
        guard pageType.canvasPageRect != nil else { return false }
        let corners = screenCorners.map { camera.toCanvas(ScreenPoint(cgPoint: $0)).cgPoint }
        guard !corners.isEmpty else { return false }

        return (0..<pageCount).contains { index in
            guard let pageRect = pageRect(at: index) else { return false }
            return corners.allSatisfy { pageRect.contains($0) }
        }
    }

    private var screenCenter: ScreenPoint {
        ScreenPoint(x: bounds.midX, y: bounds.midY)
    }

    private var screenCorners: [CGPoint] {
        [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
    }

    private var pageStackBounds: CGRect? {
        guard pageType.canvasPageRect != nil, pageCount > 0 else { return nil }
        let size = pageType.pageSize
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: CGFloat(pageCount) * size.height + CGFloat(max(pageCount - 1, 0)) * pageGap
        )
    }

    private func pageRect(at index: Int, pageType: PrototypePageType? = nil) -> CGRect? {
        pageRect(at: index, pageType: pageType ?? self.pageType)
    }

    private func pageRect(at index: Int, pageType: PrototypePageType) -> CGRect? {
        guard index >= 0, pageType.canvasPageRect != nil else { return nil }
        let size = pageType.pageSize
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(
            x: 0,
            y: CGFloat(index) * (size.height + pageGap),
            width: size.width,
            height: size.height
        )
    }

    private func visiblePageIndices(intersecting visibleRect: CGRect) -> ClosedRange<Int>? {
        guard pageType.canvasPageRect != nil, pageCount > 0 else { return nil }
        let size = pageType.pageSize
        guard size.width > 0, size.height > 0 else { return nil }

        let stride = size.height + pageGap
        let first = max(0, Int(floor((visibleRect.minY - size.height) / stride)))
        let last = min(pageCount - 1, Int(floor(visibleRect.maxY / stride)))
        guard first <= last else { return nil }
        return first...last
    }

    func makeNoteDocument(id: UUID, title: String, createdAt: Date) -> PrototypeNoteDocument {
        finishSelectionTransformSession()
        cancelActiveInputForHistoryGesture()
        let now = Date()
        return PrototypeNoteDocument(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: now,
            pageType: pageType,
            pageCount: pageCount,
            camera: PrototypeCameraSnapshot(camera: camera),
            strokes: strokes
        )
    }

    func loadNote(_ note: PrototypeNoteDocument) {
        pageType = note.pageType
        pageCount = note.pageType.canvasPageRect == nil ? 1 : note.pageCount
        replaceCanvas(strokes: note.strokes, camera: note.camera.camera)
    }

    func startBlankNote(pageType: PrototypePageType) {
        self.pageType = pageType
        pageCount = pageType.canvasPageRect == nil ? 1 : 1
        replaceCanvas(strokes: [], camera: defaultCamera(for: pageType, focusPageIndex: 0))
    }

    func appendPageAndFocus() {
        guard pageType.canvasPageRect != nil else { return }
        pageCount += 1
        let pageIndex = pageCount - 1
        setCamera(defaultCamera(for: pageType, focusPageIndex: pageIndex), pivot: nil)
        noteChanged(force: true)
    }

    func deleteSelectedStrokes() {
        finishSelectionTransformSession()
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

    private func noteChanged(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastHUDUpdateTime >= hudUpdateInterval else { return }
        lastHUDUpdateTime = now
        onChange?(camera, strokes.count, selectedStrokeIDs.count)
    }

    // MARK: Finger gestures → camera or selected ink

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            cancelRotationSnapAnimation()
            if hasSelection {
                beginSelectionTransformGesture(recognizer)
            }
        case .changed:
            let d = recognizer.translation(in: self)
            if isSelectionTransformGesture(recognizer) {
                translateSelectionByScreen(dx: d.x, dy: d.y)
            } else {
                var nextCamera = camera
                nextCamera.panBy(dx: d.x, dy: d.y)
                setCamera(nextCamera, pivot: nil)
            }
            recognizer.setTranslation(.zero, in: self)
        case .ended, .cancelled, .failed:
            endSelectionTransformGesture(recognizer)
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            cancelRotationSnapAnimation()
            if hasSelection {
                beginSelectionTransformGesture(recognizer)
            }
        case .changed:
            let pivot = ScreenPoint(cgPoint: recognizer.location(in: self))
            if isSelectionTransformGesture(recognizer) {
                scaleSelection(by: recognizer.scale, about: pivot)
            } else {
                let target = min(max(camera.scale * recognizer.scale, minScale), maxScale)
                let factor = target / camera.scale
                if factor != 1 {
                    var nextCamera = camera
                    nextCamera.zoomBy(factor, about: pivot)
                    setCamera(nextCamera, pivot: pivot)
                }
            }
            recognizer.scale = 1
        case .ended, .cancelled, .failed:
            endSelectionTransformGesture(recognizer)
        default:
            break
        }
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            cancelRotationSnapAnimation()
            if hasSelection {
                beginSelectionTransformGesture(recognizer)
            }
        case .changed:
            let pivot = ScreenPoint(cgPoint: recognizer.location(in: self))
            if isSelectionTransformGesture(recognizer) {
                rotateSelection(by: recognizer.rotation, about: pivot)
            } else {
                var nextCamera = camera
                nextCamera.rotateBy(recognizer.rotation, about: pivot)
                setCamera(nextCamera, pivot: pivot)
            }
            recognizer.rotation = 0
        case .ended, .cancelled, .failed:
            endSelectionTransformGesture(recognizer)
        default:
            break
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            brushPreviewScreenPoint = recognizer.location(in: self)
            updateBrushPreviewLayer()
        case .ended, .cancelled, .failed:
            removeBrushPreview()
        default:
            break
        }
    }

    @objc private func handleSnapRotationTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized else { return }
        snapCameraRotationToNearestRightAngle()
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

    private var hasSelection: Bool {
        !selectedStrokeIDs.isEmpty
    }

    private func beginSelectionTransformGesture(_ recognizer: UIGestureRecognizer) {
        guard beginSelectionTransformSession() else { return }
        activeSelectionGestureRecognizers.insert(ObjectIdentifier(recognizer))
    }

    private func isSelectionTransformGesture(_ recognizer: UIGestureRecognizer) -> Bool {
        activeSelectionGestureRecognizers.contains(ObjectIdentifier(recognizer))
    }

    private func endSelectionTransformGesture(_ recognizer: UIGestureRecognizer) {
        let key = ObjectIdentifier(recognizer)
        guard activeSelectionGestureRecognizers.remove(key) != nil else { return }
        if activeSelectionGestureRecognizers.isEmpty {
            finishSelectionTransformSession()
        }
    }

    @discardableResult
    private func beginSelectionTransformSession() -> Bool {
        if selectionTransformSession != nil {
            return true
        }

        if activeInput != .movingSelection {
            cancelActiveInputForHistoryGesture()
        }

        let before = selectedStrokes
        guard !before.isEmpty else {
            clearSelection()
            noteChanged(force: true)
            return false
        }

        selectionTransformSession = SelectionTransformSession(
            before: before,
            lassoBefore: selectionLassoPoints
        )
        return true
    }

    private func finishSelectionTransformSession() {
        guard let session = selectionTransformSession else { return }
        let after = selectedStrokes
        let lassoAfter = selectionLassoPoints

        if session.changed, !after.isEmpty {
            record(.transform(SelectionTransformAction(
                before: session.before,
                after: after,
                lassoBefore: session.lassoBefore,
                lassoAfter: lassoAfter
            )))
        }

        selectionTransformSession = nil
        noteChanged(force: true)
    }

    private func translateSelectionByScreen(dx: CGFloat, dy: CGFloat) {
        guard abs(dx) > .ulpOfOne || abs(dy) > .ulpOfOne,
              let center = selectedStrokeCenter
        else { return }

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
        applySelectionTransform(transform, scalesStrokeWidth: false)
    }

    private func scaleSelection(by factor: CGFloat, about pivot: ScreenPoint) {
        guard factor > 0, abs(factor - 1) > .ulpOfOne else { return }
        let transform = SelectionTransform(
            center: camera.toCanvas(pivot),
            translation: .zero,
            scale: factor,
            rotation: 0
        )
        applySelectionTransform(transform, scalesStrokeWidth: true)
    }

    private func rotateSelection(by radians: CGFloat, about pivot: ScreenPoint) {
        guard abs(radians) > .ulpOfOne else { return }
        let transform = SelectionTransform(
            center: camera.toCanvas(pivot),
            translation: .zero,
            scale: 1,
            rotation: radians
        )
        applySelectionTransform(transform, scalesStrokeWidth: false)
    }

    private func applySelectionTransform(_ transform: SelectionTransform, scalesStrokeWidth: Bool) {
        guard beginSelectionTransformSession() else { return }

        let before = selectedStrokes
        guard !before.isEmpty else {
            clearSelection()
            noteChanged(force: true)
            return
        }

        let lassoBefore = selectionLassoPoints
        let after = before.map { stroke in
            transformed(stroke, by: transform, scalesStrokeWidth: scalesStrokeWidth)
        }
        let lassoAfter = lassoBefore.map(transform.apply)
        guard strokesAreInsideWritablePages(after), lassoIsInsideWritablePages(lassoAfter) else { return }

        applyStrokeVersions(after, lassoPoints: lassoAfter)
        selectionTransformSession?.changed = true
        noteChanged()
    }

    private func selectionDragHit(at point: CanvasPoint) -> Bool {
        guard hasSelection else { return false }
        if let bounds = selectedStrokeBounds?.insetBy(dx: -Double(selectionHitRadius), dy: -Double(selectionHitRadius)),
           bounds.contains(point.cgPoint) {
            return true
        }

        return isClosedShape(selectionLassoPoints)
            && pointInPolygon(point, polygon: selectionLassoPoints)
    }

    private func snapCameraRotationToNearestRightAngle() {
        cancelActiveInputForHistoryGesture()
        cancelRotationSnapAnimation()

        let quarterTurn = CGFloat.pi / 2
        let target = (camera.rotation / quarterTurn).rounded() * quarterTurn
        let delta = shortestAngleDelta(from: camera.rotation, to: target)
        guard abs(delta) > 0.001 else { return }

        rotationSnapStartCamera = camera
        rotationSnapDelta = delta
        rotationSnapPivot = ScreenPoint(x: bounds.midX, y: bounds.midY)
        rotationSnapStartTime = CACurrentMediaTime()

        let displayLink = CADisplayLink(
            target: rotationSnapDisplayLinkTarget,
            selector: #selector(RotationSnapDisplayLinkTarget.step(_:))
        )
        rotationSnapDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    fileprivate func stepRotationSnap(_ displayLink: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - rotationSnapStartTime
        let progress = min(max(elapsed / rotationSnapDuration, 0), 1)
        let eased = easeInOut(progress)

        var nextCamera = rotationSnapStartCamera
        nextCamera.rotateBy(rotationSnapDelta * eased, about: rotationSnapPivot)
        setCamera(nextCamera, pivot: rotationSnapPivot)

        if progress >= 1 {
            cancelRotationSnapAnimation()
            noteChanged(force: true)
        }
    }

    private func cancelRotationSnapAnimation() {
        rotationSnapDisplayLink?.invalidate()
        rotationSnapDisplayLink = nil
    }

    private func updateBrushPreviewLayer() {
        guard let point = brushPreviewScreenPoint,
              shouldShowBrushPreview
        else {
            removeBrushPreview()
            return
        }
        let canvasPoint = camera.toCanvas(ScreenPoint(cgPoint: point))
        guard inputPageIndex(containing: canvasPoint) != nil else {
            removeBrushPreview()
            return
        }

        let previewLayer = brushPreviewLayer ?? makeBrushPreviewLayer()
        brushPreviewLayer = previewLayer
        if previewLayer.superlayer == nil {
            layer.addSublayer(previewLayer)
        }

        let screenWidth = max(toolStyle.width * camera.scale, 6)
        let radius = min(max(screenWidth / 2, 3), 96)
        let frame = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: .zero, size: frame.size))

        let color = previewColor
        withoutLayerActions {
            previewLayer.frame = frame
            previewLayer.path = path
            previewLayer.lineWidth = toolStyle.kind == .eraser ? 1.4 : 1.2
            previewLayer.strokeColor = color.withAlphaComponent(0.72).cgColor
            previewLayer.fillColor = color.withAlphaComponent(toolStyle.kind == .eraser ? 0.05 : 0.12).cgColor
            previewLayer.opacity = Float(0.55 + 0.35 * (1 - hoverRecognizer.zOffset))
        }
    }

    private var shouldShowBrushPreview: Bool {
        switch toolStyle.kind {
        case .pen, .pencil, .marker, .highlighter, .eraser:
            true
        case .selection:
            false
        }
    }

    private var previewColor: UIColor {
        if toolStyle.kind == .eraser {
            return UIColor.label
        }
        return toolStyle.color.uiColor(alpha: 1)
    }

    private func makeBrushPreviewLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = traitCollection.displayScale
        layer.lineDashPattern = [5, 4]
        return layer
    }

    private func removeBrushPreview() {
        brushPreviewScreenPoint = nil
        brushPreviewLayer?.removeFromSuperlayer()
        brushPreviewLayer = nil
    }

    // MARK: Pencil input → canvas-space strokes

    private func isDrawingTouch(_ touch: UITouch) -> Bool {
        touch.type == .pencil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first(where: isDrawingTouch) else { return }
        cancelRotationSnapAnimation()
        removeBrushPreview()
        activeTouch = touch
        let style = toolStyle
        activeToolStyle = style

        let firstSample = sample(touch)
        guard let pageIndex = inputPageIndex(containing: firstSample.position) else {
            activeTouch = nil
            activeToolStyle = nil
            return
        }
        activePageIndex = pageIndex

        if selectionDragHit(at: firstSample.position) {
            guard beginSelectionTransformSession() else {
                activeTouch = nil
                activePageIndex = nil
                activeToolStyle = nil
                return
            }
            activeInput = .movingSelection
            activeSelectionDragScreenPoint = ScreenPoint(cgPoint: touch.preciseLocation(in: self))
        } else if style.kind == .selection {
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
        let samples = samplesInActivePage(coalesced.map(sample))

        switch activeInput {
        case .drawing:
            guard !samples.isEmpty else {
                finishDrawingStroke()
                clearActiveInputAfterForcedFinish()
                return
            }
            activeStroke?.append(samples)
            predictedPoints = samplesInActivePage((event?.predictedTouches(for: touch) ?? []).map(sample))
            updateActiveStrokeLayer()
        case .erasing:
            predictedPoints = []
            guard !samples.isEmpty else {
                eraserPreviewPoint = nil
                removeEraserPreview()
                return
            }
            eraserPreviewPoint = samples.last?.position
            if let point = eraserPreviewPoint {
                updateEraserPreview(at: point, radius: (activeToolStyle ?? toolStyle).width / 2)
            }
            erase(at: samples, radius: (activeToolStyle ?? toolStyle).width / 2)
        case .selecting:
            guard !samples.isEmpty else { return }
            appendSelectionPoints(samples.map(\.position))
            predictedPoints = []
            updateSelectionLayer(points: activeSelectionPoints, isFinal: false)
        case .movingSelection:
            predictedPoints = []
            let current = ScreenPoint(cgPoint: touch.preciseLocation(in: self))
            if let previous = activeSelectionDragScreenPoint {
                translateSelectionByScreen(
                    dx: CGFloat(current.x - previous.x),
                    dy: CGFloat(current.y - previous.y)
                )
            }
            activeSelectionDragScreenPoint = current
        }
    }

    private func clearActiveInputAfterForcedFinish() {
        activeStroke = nil
        activeTouch = nil
        activeInput = nil
        activePageIndex = nil
        activeToolStyle = nil
        activeStrokeLayer = nil
        predictedPoints = []
        eraserPreviewPoint = nil
        activeSelectionDragScreenPoint = nil
        noteChanged(force: true)
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
        case .movingSelection:
            finishSelectionTransformSession()
        case nil:
            activeStrokeLayer?.removeFromSuperlayer()
        }

        activeStroke = nil
        activeTouch = nil
        activeInput = nil
        activePageIndex = nil
        activeToolStyle = nil
        activeStrokeLayer = nil
        predictedPoints = []
        eraserPreviewPoint = nil
        activeEraserRemovedStrokes = []
        activeSelectionPoints = []
        activeSelectionDragScreenPoint = nil
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
        guard strokesAreInsideWritablePages([stroke]) else {
            layer?.removeFromSuperlayer()
            return
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

    private func inputPageIndex(containing point: CanvasPoint) -> Int? {
        guard pageType.canvasPageRect != nil else { return 0 }
        return pageIndex(containing: point)
    }

    private func pageIndex(containing point: CanvasPoint) -> Int? {
        guard pageType.canvasPageRect != nil, pageCount > 0 else { return nil }
        let size = pageType.pageSize
        guard size.width > 0, size.height > 0 else { return nil }

        let p = point.cgPoint
        guard p.x >= 0, p.x <= size.width, p.y >= 0 else { return nil }
        let stride = size.height + pageGap
        let index = Int(floor(p.y / stride))
        guard index >= 0, index < pageCount else { return nil }

        let pageMinY = CGFloat(index) * stride
        let pageRect = CGRect(x: 0, y: pageMinY, width: size.width, height: size.height)
        return pageRect.contains(p) ? index : nil
    }

    private func samplesInActivePage(_ samples: [PrototypePoint]) -> [PrototypePoint] {
        guard pageType.canvasPageRect != nil else { return samples }
        guard let activePageIndex,
              let pageRect = pageRect(at: activePageIndex)
        else { return [] }

        return samples.filter { pageRect.contains($0.position.cgPoint) }
    }

    private func strokesAreInsideWritablePages(_ strokes: [PrototypeStroke]) -> Bool {
        guard pageType.canvasPageRect != nil else { return true }
        return strokes.allSatisfy { stroke in
            stroke.points.allSatisfy { inputPageIndex(containing: $0.position) != nil }
        }
    }

    private func lassoIsInsideWritablePages(_ points: [CanvasPoint]) -> Bool {
        guard pageType.canvasPageRect != nil else { return true }
        return points.allSatisfy { inputPageIndex(containing: $0) != nil }
    }

    // MARK: Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.concatenate(camera.transform)
        switch pageType {
        case .infiniteCanvas:
            drawInfiniteCanvasBackground(ctx)
        case .legalPaper:
            drawLegalPaperBackground(ctx)
        }
        ctx.restoreGState()
    }

    // Palette matches the hand-drawn theme's SketchStyle hex defaults
    // (#f7f2e7 paper, #2b2723 ink) — duplicated as components because this
    // view draws through CoreGraphics/UIKit, not SwiftUI.
    private var paperColor: UIColor {
        UIColor(red: 0.969, green: 0.949, blue: 0.906, alpha: 1) // #f7f2e7
    }

    private var deskColor: UIColor {
        UIColor(red: 0.902, green: 0.875, blue: 0.812, alpha: 1) // darker warm beige
    }

    private var gridInkColor: UIColor {
        UIColor(red: 0.169, green: 0.153, blue: 0.137, alpha: 1) // #2b2723
    }

    private var fleckBeige: UIColor {
        UIColor(red: 0.851, green: 0.804, blue: 0.694, alpha: 1) // darker beige speck
    }

    private var fleckGray: UIColor {
        UIColor(red: 0.545, green: 0.522, blue: 0.475, alpha: 1) // warm gray speck
    }

    private func updateBackgroundColor() {
        backgroundColor = pageType.canvasPageRect == nil ? paperColor : deskColor
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
        activeSelectionGestureRecognizers.removeAll()
        selectionTransformSession = nil
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
            guard strokesAreInsideWritablePages([stroke]) else { continue }
            addStrokeWithoutHistory(stroke, at: strokes.count)
        }
        setCamera(newCamera, pivot: nil)
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

    private var selectedStrokeBounds: CGRect? {
        let points = selectedStrokes.flatMap { stroke in
            stroke.points.map(\.position)
        }
        guard !points.isEmpty else { return nil }
        return boundingRect(for: points)
    }

    private var selectedStrokeCenter: CanvasPoint? {
        guard let bounds = selectedStrokeBounds else {
            if !selectedStrokeIDs.isEmpty {
                clearSelection()
            }
            return nil
        }

        return CanvasPoint(x: bounds.midX, y: bounds.midY)
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
        } else if activeInput == .movingSelection {
            finishSelectionTransformSession()
        }

        activeStroke = nil
        activeTouch = nil
        activeInput = nil
        activePageIndex = nil
        activeToolStyle = nil
        activeStrokeLayer = nil
        predictedPoints = []
        eraserPreviewPoint = nil
        activeEraserRemovedStrokes = []
        activeSelectionPoints = []
        activeSelectionDragScreenPoint = nil
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

    private func drawInfiniteCanvasBackground(_ ctx: CGContext) {
        guard let visibleRect = visibleCanvasBounds() else { return }
        // Bare textured paper — no grid or axes. Camera motion stays legible
        // because the flecks are anchored in canvas space and move with it.
        drawPaperFlecks(ctx, in: visibleRect)
    }

    // MARK: Paper texture

    /// Flecks are anchored in canvas space — glued to the plane, so they
    /// pan/zoom/rotate with the ink — and continue seamlessly forever:
    /// each canvas-space cell derives its own RNG stream from its integer
    /// cell coordinates (`sketchHash`, same determinism scheme as the
    /// hand-drawn theme), so any region of the infinite plane regenerates
    /// the exact same specks on every visit. Nothing is stored, nothing
    /// tiles, nothing repeats.
    ///
    /// A fleck's size is fixed in canvas space, so one tier only reads as
    /// "paper specks" near its home zoom. Two adjacent ×10 tiers are blended
    /// by the fractional zoom octave (the same decade laddering `drawGrid`
    /// uses for spacing), keeping on-screen texture density roughly constant
    /// across the full 0.05×–64× zoom range.
    private enum PaperFleck {
        static let cellSize: CGFloat = 256          // canvas pt at tier 0
        static let flecksPerCell = 9
        static let radiusFraction: CGFloat = 0.0055 // ≈ 1.4pt specks in a tier's home zoom
        static let minScreenRadius: CGFloat = 0.5   // below this a tier is sub-pixel mist; skip
        static let maxCellsPerTier = 600            // defensive cap for huge/external displays
        static let seedSalt: UInt32 = 0x5041_5045   // "PAPE"
    }

    private func drawPaperFlecks(_ ctx: CGContext, in visibleRect: CGRect) {
        // Continuous zoom octave: 0 at 1×, +1 at 0.1×, −1 at 10×.
        let level = -log10(Double(max(camera.scale, 0.0001)))
        let lower = level.rounded(.down)
        let frac = CGFloat(level - lower)
        drawFleckTier(ctx, in: visibleRect, tierExponent: Int(lower), weight: 1 - frac)
        drawFleckTier(ctx, in: visibleRect, tierExponent: Int(lower) + 1, weight: frac)
    }

    private func drawFleckTier(
        _ ctx: CGContext,
        in visibleRect: CGRect,
        tierExponent: Int,
        weight: CGFloat
    ) {
        guard weight > 0.02 else { return }
        let cellSize = PaperFleck.cellSize * pow(10, CGFloat(tierExponent))
        let baseRadius = cellSize * PaperFleck.radiusFraction
        guard baseRadius * camera.scale >= PaperFleck.minScreenRadius else { return }

        // A fleck's center lives in its own cell, but its body can spill past
        // the cell edge, so pad the scan by the largest possible fleck extent.
        // Without this, specks near a cell boundary just outside the viewport
        // pop in as you pan. Costs an extra cell only when the viewport edge
        // happens to fall within a few points of a boundary.
        let maxHalfExtent = baseRadius * 1.5 * 2.8 / 2
        let scanRect = visibleRect.insetBy(dx: -maxHalfExtent, dy: -maxHalfExtent)

        let minCellX = Int(floor(scanRect.minX / cellSize))
        let maxCellX = Int(floor(scanRect.maxX / cellSize))
        let minCellY = Int(floor(scanRect.minY / cellSize))
        let maxCellY = Int(floor(scanRect.maxY / cellSize))
        guard (maxCellX - minCellX + 1) * (maxCellY - minCellY + 1) <= PaperFleck.maxCellsPerTier
        else { return }

        let beigePath = CGMutablePath()
        let grayPath = CGMutablePath()
        let tierSalt = PaperFleck.seedSalt ^ UInt32(bitPattern: Int32(truncatingIfNeeded: tierExponent))

        for cellY in minCellY...maxCellY {
            for cellX in minCellX...maxCellX {
                var rng = SketchRandom(seed: sketchHash(
                    UInt32(truncatingIfNeeded: cellX),
                    UInt32(truncatingIfNeeded: cellY),
                    tierSalt
                ))
                let originX = CGFloat(cellX) * cellSize
                let originY = CGFloat(cellY) * cellSize
                for _ in 0..<PaperFleck.flecksPerCell {
                    // Fixed draw order per fleck keeps the stream stable:
                    // x, y, size, width, height, angle, tone.
                    let x = originX + CGFloat(rng.next()) * cellSize
                    let y = originY + CGFloat(rng.next()) * cellSize
                    let radius = baseRadius * CGFloat(0.55 + rng.next() * 0.95)
                    let width = radius * CGFloat(1.5 + rng.next() * 1.3)
                    let height = radius * CGFloat(0.75 + rng.next() * 0.55)
                    // Slight random elongation + rotation reads as paper
                    // fiber rather than polka dots.
                    let transform = CGAffineTransform(translationX: x, y: y)
                        .rotated(by: CGFloat(rng.next()) * .pi)
                    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                    if rng.next() < 0.62 {
                        beigePath.addEllipse(in: rect, transform: transform)
                    } else {
                        grayPath.addEllipse(in: rect, transform: transform)
                    }
                }
            }
        }

        ctx.setFillColor(fleckBeige.withAlphaComponent(0.55 * weight).cgColor)
        ctx.addPath(beigePath)
        ctx.fillPath()
        ctx.setFillColor(fleckGray.withAlphaComponent(0.32 * weight).cgColor)
        ctx.addPath(grayPath)
        ctx.fillPath()
    }

    private func drawLegalPaperBackground(_ ctx: CGContext) {
        guard let stackBounds = pageStackBounds else { return }

        let hairline = 1 / camera.scale
        let visibleRect = visibleCanvasBounds() ?? stackBounds
        let scrollLocked = isPageScrollLocked(scale: camera.scale)
        let shouldDrawShadow = !scrollLocked
        let shouldDrawTexture = !scrollLocked

        guard let pageIndices = visiblePageIndices(intersecting: visibleRect) else { return }
        for pageIndex in pageIndices {
            guard let pageRect = pageRect(at: pageIndex),
                  pageRect.intersects(visibleRect)
            else { continue }

            if shouldDrawShadow {
                ctx.saveGState()
                ctx.setShadow(
                    offset: CGSize(width: 0, height: 12 * hairline),
                    blur: 24 * hairline,
                    color: UIColor.black.withAlphaComponent(0.16).cgColor
                )
                ctx.setFillColor(paperColor.cgColor)
                ctx.fill(pageRect)
                ctx.restoreGState()
            } else {
                ctx.setFillColor(paperColor.cgColor)
                ctx.fill(pageRect)
            }

            ctx.saveGState()
            ctx.addRect(pageRect)
            ctx.clip()
            let pageVisibleRect = visibleRect.intersection(pageRect)
            if !pageVisibleRect.isNull, !pageVisibleRect.isEmpty {
                if shouldDrawTexture {
                    drawPaperFlecks(ctx, in: pageVisibleRect)
                }
                drawGrid(ctx, in: pageVisibleRect)
            }
            ctx.restoreGState()

            ctx.setLineWidth(hairline)
            ctx.setStrokeColor(gridInkColor.withAlphaComponent(0.3).cgColor)
            ctx.stroke(pageRect)
        }
    }

    private func visibleCanvasBounds() -> CGRect? {
        let corners = screenCorners.map { camera.toCanvas(ScreenPoint(cgPoint: $0)) }
        guard let minX = corners.map(\.x).min(),
              let maxX = corners.map(\.x).max(),
              let minY = corners.map(\.y).min(),
              let maxY = corners.map(\.y).max()
        else { return nil }

        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
    }

    /// A canvas-space reference grid for the ruled `legalPaper` page type.
    /// The infinite canvas draws no grid (bare textured paper).
    private func drawGrid(_ ctx: CGContext, in visibleRect: CGRect) {
        let minX = visibleRect.minX
        let maxX = visibleRect.maxX
        let minY = visibleRect.minY
        let maxY = visibleRect.maxY

        // Keep on-screen grid spacing between ~24pt and ~240pt at any zoom.
        var spacing: CGFloat = 100
        while spacing * camera.scale < 24 { spacing *= 10 }
        while spacing * camera.scale > 240 { spacing /= 10 }

        let hairline = 1 / camera.scale
        ctx.setLineWidth(hairline)
        ctx.setStrokeColor(gridInkColor.withAlphaComponent(0.12).cgColor)

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
    }
}

private final class RotationSnapDisplayLinkTarget: NSObject {
    weak var view: CanvasPrototypeUIView?

    @MainActor @objc func step(_ displayLink: CADisplayLink) {
        guard let view else {
            displayLink.invalidate()
            return
        }

        view.stepRotationSnap(displayLink)
    }
}

extension CanvasPrototypeUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Pan + pinch + rotate blend into one continuous two-finger gesture,
        // targeting either the camera or the current selection.
        true
    }
}

extension CanvasPrototypeUIView: UIPencilInteractionDelegate {
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        cancelActiveInputForHistoryGesture()
        onPencilQuickAccess?(quickAccessAnchor(from: tap.hoverPose))
    }

    func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        guard squeeze.phase == .ended else { return }
        cancelActiveInputForHistoryGesture()
        onPencilQuickAccess?(quickAccessAnchor(from: squeeze.hoverPose))
    }

    private func quickAccessAnchor(from pose: UIPencilHoverPose?) -> CGPoint? {
        pose?.location ?? brushPreviewScreenPoint
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

private func shortestAngleDelta(from start: CGFloat, to end: CGFloat) -> CGFloat {
    var delta = end - start
    while delta > .pi { delta -= 2 * .pi }
    while delta <= -.pi { delta += 2 * .pi }
    return delta
}

private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
    var normalized = angle
    while normalized > .pi { normalized -= 2 * .pi }
    while normalized <= -.pi { normalized += 2 * .pi }
    return normalized
}

private func easeInOut(_ t: CFTimeInterval) -> CGFloat {
    let clamped = min(max(t, 0), 1)
    return CGFloat(clamped * clamped * (3 - 2 * clamped))
}
