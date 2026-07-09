import SwiftUI
import UIKit

/// The transparent pen layer that sits over a diegetic screen's card grid.
/// It renders live ink but takes **no touches itself** — Apple Pencil input is
/// captured by a `DiegeticPencilRecognizer` installed on the enclosing scroll
/// view (routed by `allowedTouchTypes`, which is reliable where hit-testing the
/// touch type was not). Finger touches never reach the recognizer, so scroll
/// and tap-to-open stay fully native (decision 1, 2026-07-09). Strokes are
/// live-rendered as transient ink, then classified into a `DiegeticGesture` on
/// lift. See the design doc at `docs/diegetic-ui/README.md`.
struct DiegeticInputSurface: UIViewRepresentable {
    var toolStyle: PrototypeToolStyle
    var targets: [DiegeticTargetFrame]
    var noteTitle: (UUID) -> String
    var onGesture: (DiegeticGesture) -> Void

    func makeUIView(context: Context) -> DiegeticInputUIView {
        let view = DiegeticInputUIView()
        push(to: view)
        return view
    }

    func updateUIView(_ view: DiegeticInputUIView, context: Context) {
        push(to: view)
    }

    private func push(to view: DiegeticInputUIView) {
        view.toolStyle = toolStyle
        view.targets = targets
        view.noteTitle = noteTitle
        view.onGesture = onGesture
    }
}

final class DiegeticInputUIView: UIView {

    var toolStyle: PrototypeToolStyle = .default
    var targets: [DiegeticTargetFrame] = [] {
        didSet {
            // Selection highlights are pinned to note frames; keep them current
            // as notes appear/disappear (they scroll for free — see the doc).
            if !selectedNoteIDs.isEmpty { redrawSelection() }
        }
    }
    var noteTitle: (UUID) -> String = { _ in "Note" }
    var onGesture: ((DiegeticGesture) -> Void)?

    private enum Mode {
        case draw
        case erase
        case lasso
        case grabNote(UUID)
        case dragSelection
    }

    private var mode: Mode?
    private var activeTouch: UITouch?
    private var points: [CGPoint] = []
    private var inkLayer: CAShapeLayer?
    private var chipLayer: CALayer?
    private var hoverLayer: CAShapeLayer?
    private var hoveredFolder: UUID?
    private var selectedNoteIDs: Set<UUID> = []
    private var selectionLayers: [UUID: CAShapeLayer] = [:]
    private weak var hostScrollView: UIScrollView?
    private weak var pencilRecognizer: DiegeticPencilRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        // Input arrives through a Pencil-only gesture recognizer installed on the
        // enclosing scroll view (see didMoveToWindow) — NOT through this view's own
        // touch handling. Hit-test-based Pencil detection proved unreliable on
        // device (`event.allTouches` didn't carry the Pencil at hit-test time, so
        // the touch fell through as a tap). The surface stays transparent to
        // touches; finger interactions (scroll, tap-to-open) reach the cards
        // natively and untouched.
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Scroll-view coexistence + Pencil recognizer

    /// The tool touch types the diegetic layer draws with: the Apple Pencil,
    /// plus `.direct` (finger/trackpad) in the Simulator, which has no Pencil so
    /// would otherwise be untestable.
    private static var toolTouchTypes: [NSNumber] {
        var types: [NSNumber] = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        #if targetEnvironment(simulator)
        types.append(NSNumber(value: UITouch.TouchType.direct.rawValue))
        #endif
        return types
    }

    // The surface lives inside the page's scroll view. Pencil input is captured
    // by a recognizer we install on that scroll view (routed by touch type, which
    // is reliable — unlike inspecting `event.allTouches` in hitTest). The scroll
    // view's own pan is limited to finger touches so a Pencil never scrolls.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            hostScrollView?.isScrollEnabled = true
            return
        }
        let scrollView = enclosingScrollView()
        hostScrollView = scrollView
        scrollView?.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        installPencilRecognizer(on: scrollView)
    }

    private func installPencilRecognizer(on scrollView: UIScrollView?) {
        guard let scrollView else { return }
        if let recognizer = pencilRecognizer, recognizer.view === scrollView { return }
        pencilRecognizer?.view?.removeGestureRecognizer(pencilRecognizer!)

        let recognizer = DiegeticPencilRecognizer()
        recognizer.surface = self
        recognizer.allowedTouchTypes = Self.toolTouchTypes
        recognizer.cancelsTouchesInView = true
        scrollView.addGestureRecognizer(recognizer)
        pencilRecognizer = recognizer
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }

    // MARK: Stroke handling (driven by DiegeticPencilRecognizer)

    func beginStroke(_ touch: UITouch, event: UIEvent?) {
        guard mode == nil else { return }
        activeTouch = touch
        // Freeze scrolling for the length of the stroke so nothing hijacks it.
        hostScrollView?.isScrollEnabled = false
        let location = touch.preciseLocation(in: self)
        points = [location]

        switch toolStyle.kind {
        case .eraser:
            mode = .erase
            beginInkLayer(color: Self.eraseColor, width: max(toolStyle.width * 0.4, 10), dashed: false)
            updateInkPath()
        case .selection:
            if case .note(let id)? = DiegeticClassifier.target(at: location, in: targets) {
                if selectedNoteIDs.contains(id) {
                    // Drag the whole current selection.
                    mode = .dragSelection
                    beginChip(title: selectionChipTitle, at: location)
                } else {
                    // Grab this single note (and drop any prior selection).
                    clearSelection()
                    mode = .grabNote(id)
                    beginChip(title: noteTitle(id), at: location)
                }
                updateHover(at: location)
            } else {
                // Lasso across empty desk → select what it encloses on lift.
                mode = .lasso
                beginInkLayer(color: Self.selectionColor, width: 2, dashed: true)
                updateInkPath()
            }
        case .pen, .pencil, .marker, .highlighter:
            mode = .draw
            beginInkLayer(
                color: toolStyle.color.uiColor(alpha: toolStyle.opacity),
                width: toolStyle.width,
                dashed: false
            )
            updateInkPath()
        }
    }

    func moveStroke(event: UIEvent?) {
        guard let activeTouch, let mode else { return }
        let coalesced = event?.coalescedTouches(for: activeTouch) ?? [activeTouch]
        points.append(contentsOf: coalesced.map { $0.preciseLocation(in: self) })
        let location = activeTouch.preciseLocation(in: self)

        switch mode {
        case .draw, .erase, .lasso:
            updateInkPath()
        case .grabNote, .dragSelection:
            moveChip(to: location)
            updateHover(at: location)
        }
    }

    func endStroke() {
        guard let activeTouch, let mode else {
            resetState()
            return
        }
        let location = activeTouch.preciseLocation(in: self)

        switch mode {
        case .draw:
            let primary = DiegeticClassifier.primaryTarget(for: points, in: targets)
            if case .folder(let id)? = primary,
               let frame = folderFrame(id),
               let mark = DiegeticClassifier.folderMark(
                   polyline: points,
                   in: frame,
                   color: toolStyle.color,
                   strokeWidth: toolStyle.width,
                   opacity: toolStyle.opacity,
                   isHighlighter: toolStyle.kind == .highlighter
               ) {
                // Drawing on a folder always colors it (never deletes) so a
                // scribble-fill can't nuke it.
                onGesture?(.decorateFolder(id, marks: [mark]))
            } else if DiegeticClassifier.isScribble(points), case .note(let id)? = primary {
                // Scribble over a note → delete (the canvas's scribble-to-erase).
                onGesture?(.deleteNote(id))
            } else if DiegeticClassifier.isClosedLoop(points) {
                // Circle around notes → select them (the canvas's circle-select).
                // Only when it actually encloses notes, so an idle doodle-loop
                // doesn't wipe an existing selection.
                let ids = DiegeticClassifier.selectedNotes(by: points, in: targets)
                if !ids.isEmpty { applySelection(Set(ids)) }
            }
            // Anything else is a transient doodle — it fades. (Persistence seam:
            // decision 2 — see design doc.)
            fadeAndClearInk()
        case .erase:
            switch DiegeticClassifier.primaryTarget(for: points, in: targets) {
            case .note(let id)?: onGesture?(.deleteNote(id))
            case .folder(let id)?: onGesture?(.deleteFolder(id))
            case nil: break
            }
            fadeAndClearInk()
        case .lasso:
            // Select whatever the loop enclosed / crossed (empty set deselects).
            applySelection(Set(DiegeticClassifier.selectedNotes(by: points, in: targets)))
            fadeAndClearInk()
        case .grabNote(let id):
            let folderID = DiegeticClassifier.folder(at: location, in: targets)
            // Dropped back onto its own card → the user picked it up and put it
            // back; don't treat that as "move to root". Any real destination
            // (a folder) or a drop clearly off the source still moves it.
            let overSource = targets.first { $0.id == .note(id) }?.frame.contains(location) ?? false
            if folderID != nil || !overSource {
                onGesture?(.moveNote(id, toFolder: folderID))
            }
            clearChip()
            clearHover()
        case .dragSelection:
            // Drop the whole selection: onto a folder → move in; onto the desk →
            // move to root (the model no-ops any note that didn't actually move).
            let folderID = DiegeticClassifier.folder(at: location, in: targets)
            for id in selectedNoteIDs {
                onGesture?(.moveNote(id, toFolder: folderID))
            }
            clearSelection()
            clearChip()
            clearHover()
        }

        resetState()
    }

    private func resetState() {
        mode = nil
        activeTouch = nil
        points = []
        hoveredFolder = nil
        hostScrollView?.isScrollEnabled = true
    }

    // MARK: Live ink

    private func beginInkLayer(color: UIColor, width: CGFloat, dashed: Bool) {
        let ink = CAShapeLayer()
        ink.contentsScale = traitCollection.displayScale
        ink.fillColor = nil
        ink.strokeColor = color.cgColor
        ink.lineWidth = width
        ink.lineCap = .round
        ink.lineJoin = .round
        if dashed { ink.lineDashPattern = [8, 5] }
        layer.addSublayer(ink)
        inkLayer = ink
    }

    private func updateInkPath() {
        guard let inkLayer, let first = points.first else { return }
        let path = CGMutablePath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        withoutImplicitAnimation { inkLayer.path = path }
    }

    private func fadeAndClearInk() {
        guard let layer = inkLayer else { return }
        inkLayer = nil
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.opacity
        fade.toValue = 0
        fade.duration = 0.3
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            layer.removeFromSuperlayer()
        }
    }

    // MARK: Grab-and-drop chip

    private func beginChip(title: String, at point: CGPoint) {
        let chip = CALayer()
        chip.bounds = CGRect(x: 0, y: 0, width: 156, height: 46)
        chip.position = point
        chip.backgroundColor = Self.paperColor.withAlphaComponent(0.97).cgColor
        chip.cornerRadius = 11
        chip.borderColor = Self.inkColor.withAlphaComponent(0.7).cgColor
        chip.borderWidth = 1.5
        chip.shadowColor = UIColor.black.cgColor
        chip.shadowOpacity = 0.22
        chip.shadowRadius = 10
        chip.shadowOffset = CGSize(width: 0, height: 5)

        let label = CATextLayer()
        label.string = title
        label.fontSize = 15
        label.alignmentMode = .center
        label.truncationMode = .end
        label.isWrapped = false
        label.foregroundColor = Self.inkColor.cgColor
        label.contentsScale = traitCollection.displayScale
        label.frame = chip.bounds.insetBy(dx: 12, dy: 13)
        chip.addSublayer(label)

        layer.addSublayer(chip)
        chipLayer = chip

        // Small "lift" as it's picked up.
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.85
        pop.toValue = 1
        pop.duration = 0.14
        chip.add(pop, forKey: "pop")
    }

    private func moveChip(to point: CGPoint) {
        withoutImplicitAnimation { chipLayer?.position = point }
    }

    private func clearChip() {
        guard let chip = chipLayer else { return }
        chipLayer = nil
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.2
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        chip.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            chip.removeFromSuperlayer()
        }
    }

    // MARK: Folder drop hover

    private func updateHover(at point: CGPoint) {
        let folderID = DiegeticClassifier.folder(at: point, in: targets)
        guard folderID != hoveredFolder else { return }
        hoveredFolder = folderID
        guard let folderID, let frame = folderFrame(folderID) else {
            clearHover()
            return
        }

        let highlight = hoverLayer ?? makeHoverLayer()
        hoverLayer = highlight
        if highlight.superlayer == nil {
            layer.insertSublayer(highlight, at: 0)
        }
        withoutImplicitAnimation {
            highlight.frame = frame.insetBy(dx: -4, dy: -4)
            highlight.path = CGPath(
                roundedRect: CGRect(origin: .zero, size: highlight.bounds.size),
                cornerWidth: 16,
                cornerHeight: 16,
                transform: nil
            )
        }
    }

    private func makeHoverLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = traitCollection.displayScale
        layer.fillColor = Self.selectionColor.withAlphaComponent(0.12).cgColor
        layer.strokeColor = Self.selectionColor.withAlphaComponent(0.9).cgColor
        layer.lineWidth = 2.5
        layer.lineDashPattern = [7, 5]
        return layer
    }

    private func clearHover() {
        hoverLayer?.removeFromSuperlayer()
        hoverLayer = nil
    }

    // MARK: Selection

    private var selectionChipTitle: String {
        if selectedNoteIDs.count == 1, let id = selectedNoteIDs.first {
            return noteTitle(id)
        }
        return "\(selectedNoteIDs.count) notes"
    }

    private func applySelection(_ ids: Set<UUID>) {
        selectedNoteIDs = ids
        redrawSelection()
    }

    private func clearSelection() {
        selectedNoteIDs.removeAll()
        redrawSelection()
    }

    /// Reconciles the persistent highlight layers with `selectedNoteIDs`. The
    /// layers sit in the surface's own (content-space) layer, so they scroll
    /// with the cards for free.
    private func redrawSelection() {
        for (id, layer) in selectionLayers where !selectedNoteIDs.contains(id) {
            layer.removeFromSuperlayer()
            selectionLayers[id] = nil
        }
        for id in selectedNoteIDs {
            guard let frame = noteFrame(id) else {
                // Offscreen (the grid is lazy) or gone — drop the layer but keep
                // the selection, so it re-highlights when scrolled back.
                selectionLayers[id]?.removeFromSuperlayer()
                selectionLayers[id] = nil
                continue
            }
            let highlight = selectionLayers[id] ?? makeSelectionLayer()
            selectionLayers[id] = highlight
            if highlight.superlayer == nil {
                layer.insertSublayer(highlight, at: 0)
            }
            withoutImplicitAnimation {
                highlight.frame = frame.insetBy(dx: -3, dy: -3)
                highlight.path = CGPath(
                    roundedRect: CGRect(origin: .zero, size: highlight.bounds.size),
                    cornerWidth: 16,
                    cornerHeight: 16,
                    transform: nil
                )
            }
        }
    }

    private func makeSelectionLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = traitCollection.displayScale
        layer.fillColor = Self.selectionColor.withAlphaComponent(0.1).cgColor
        layer.strokeColor = Self.selectionColor.cgColor
        layer.lineWidth = 2.5
        layer.lineDashPattern = [8, 5]
        return layer
    }

    private func noteFrame(_ id: UUID) -> CGRect? {
        targets.first { $0.id == .note(id) }?.frame
    }

    // MARK: Helpers

    private func folderFrame(_ id: UUID) -> CGRect? {
        targets.first { $0.id == .folder(id) }?.frame
    }

    private func withoutImplicitAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    // Palette matches the hand-drawn theme (#f7f2e7 paper, #2b2723 ink).
    private static let paperColor = UIColor(red: 0.969, green: 0.949, blue: 0.906, alpha: 1)
    private static let inkColor = UIColor(red: 0.169, green: 0.153, blue: 0.137, alpha: 1)
    private static let eraseColor = UIColor(red: 0.169, green: 0.153, blue: 0.137, alpha: 0.28)
    private static let selectionColor = UIColor(red: 0.13, green: 0.33, blue: 0.85, alpha: 1)
}

/// A continuous recognizer, installed on the page's scroll view, that routes
/// tool touches (Apple Pencil — plus finger in the Simulator, via
/// `allowedTouchTypes`) to the diegetic surface. Living on the scroll view means
/// it receives touches that hit any descendant card, and UIKit's touch-type
/// routing is reliable where hit-test inspection was not. It begins on
/// touch-down so `cancelsTouchesInView` suppresses the underlying card's tap for
/// the length of a Pencil stroke; finger touches are never routed here, so
/// scroll and tap-to-open stay fully native.
final class DiegeticPencilRecognizer: UIGestureRecognizer {
    weak var surface: DiegeticInputUIView?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        state = .began
        surface?.beginStroke(touch, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .changed
        surface?.moveStroke(event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        surface?.endStroke()
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        surface?.endStroke()
        state = .cancelled
    }
}
