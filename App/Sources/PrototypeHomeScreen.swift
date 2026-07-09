import SketchKit
import SwiftUI
import UIKit

/// Home-screen library prototype (2026-07-08, Miles-approved out-of-spec
/// work): hand-drawn treatment applied through the same Theme surface as the
/// toolbar prototype. Throwaway by design, like all `Prototype*` files.
struct PrototypeHomeScreen: View {
    @State private var library = PrototypeLibraryModel()
    // Shared across the whole stack so the chosen pen tool persists as you move
    // between the root desk and folders.
    @State private var toolModel = PrototypeHomeToolModel()
    @State private var editorRequest: PrototypeEditorRequest?
    @State private var navigationPath: [PrototypeFolder] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            PrototypeNoteGridScreen(
                library: library,
                toolModel: toolModel,
                folder: nil,
                editorRequest: $editorRequest
            ) { folder in
                navigationPath.append(folder)
            }
                .navigationDestination(for: PrototypeFolder.self) { folder in
                    PrototypeNoteGridScreen(
                        library: library,
                        toolModel: toolModel,
                        folder: folder,
                        editorRequest: $editorRequest
                    ) { openedFolder in
                        navigationPath.append(openedFolder)
                    }
                }
        }
        .environment(\.theme, HandDrawnTheme())
        .fullScreenCover(item: $editorRequest, onDismiss: { library.refresh() }) { request in
            PrototypeEditorScreen(request: request) {
                editorRequest = nil
            }
            .environment(\.theme, HandDrawnTheme())
        }
    }
}

/// One folder's worth of the library: folder cards (root only) + note cards.
private struct PrototypeNoteGridScreen: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var library: PrototypeLibraryModel
    @Bindable var toolModel: PrototypeHomeToolModel
    /// nil = library root.
    let folder: PrototypeFolder?
    @Binding var editorRequest: PrototypeEditorRequest?
    let openFolder: (PrototypeFolder) -> Void

    @State private var promptConfig: HandDrawnPromptConfig?
    @State private var chooserConfig: HandDrawnChooserConfig?

    private var notes: [PrototypeNoteSummary] { library.notes(in: folder?.id) }
    private var isRoot: Bool { folder == nil }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if let errorMessage = library.errorMessage {
                    errorBanner(errorMessage)
                }
                if isRoot, !library.folders.isEmpty {
                    sectionHeader("Folders")
                    folderGrid
                    sectionHeader("Notes")
                }
                if notes.isEmpty {
                    emptyState
                } else {
                    noteGrid
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 36)
            .coordinateSpace(name: diegeticCoordinateSpace)
            .overlayPreferenceValue(DiegeticTargetPreferenceKey.self) { targets in
                // Pencil command layer, living *inside* the scroll content so it
                // shares the cards' coordinate space and can reach the scroll
                // view to stop a Pencil stroke from scrolling. Finger falls
                // through (scroll + tap-to-open); `targets` are the card frames.
                DiegeticInputSurface(
                    toolStyle: toolModel.toolStyle,
                    targets: targets,
                    noteTitle: { library.note(withID: $0)?.title ?? "Note" },
                    onGesture: handle
                )
            }
        }
        .background(PrototypeHomePaperBackground().ignoresSafeArea())
        .handDrawnStatusBarOverlay()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { library.refresh() }
        .safeAreaInset(edge: .bottom) {
            PrototypeHomeToolbar(model: toolModel)
        }
        .overlay(alignment: .bottom) { undoRibbon }
        .animation(.snappy(duration: 0.2), value: library.activeUndo?.id)
        .handDrawnPrompt($promptConfig)
        .handDrawnChooser($chooserConfig)
    }

    // MARK: Sections

    private var header: some View {
        AppCardContainer(key: "library.header.\(folder?.id.uuidString ?? "root")") {
            ViewThatFits(in: .horizontal) {
                headerHorizontal
                headerVertical
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var headerHorizontal: some View {
        HStack(alignment: .center, spacing: 14) {
            if !isRoot {
                backButton
            }
            headerCopy
                .frame(maxWidth: .infinity, alignment: .leading)
            headerActions
                .layoutPriority(1)
        }
    }

    private var headerVertical: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if !isRoot {
                    backButton
                }
                headerCopy
            }
            headerActions
        }
    }

    private var backButton: some View {
        AppButton(label: "Back") {
            dismiss()
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerTitle
            Text(headerSubtitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color(hex: "#2b2723").opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            if isRoot {
                AppButton(label: "New Folder") { presentNewFolder() }
            }
            newNoteButton
        }
    }

    @ViewBuilder
    private var headerTitle: some View {
        if let folder {
            Text(folder.name)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color(hex: "#2b2723"))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } else {
            AppText(text: "WriteRight", role: .title)
        }
    }

    private var headerSubtitle: String {
        if isRoot {
            if library.folders.isEmpty {
                return notes.isEmpty
                    ? "Open a fresh page and start writing."
                    : "\(plural(notes.count, "note")) in the library."
            }
            return "\(plural(library.folders.count, "folder")) and \(plural(notes.count, "note"))."
        }
        return notes.isEmpty ? "This folder is ready for a first page." : "\(plural(notes.count, "note")) in this folder."
    }

    private func errorBanner(_ message: String) -> some View {
        AppCardContainer(key: "library.error") {
            HStack(spacing: 10) {
                AppIcon(
                    source: .builtIn(name: "warning", fallbackSymbol: "exclamationmark.triangle"),
                    size: 24
                )
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 22, alignment: .top)]
    }

    private var folderGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(library.folders) { folder in
                PrototypeFolderCard(folder: folder, noteCount: library.noteCount(in: folder))
                    .diegeticTarget(.folder(folder.id))
                    .onTapGesture {
                        openFolder(folder)
                    }
                    .handDrawnLongPressFeedback(key: "folder.\(folder.id.uuidString)") {
                        presentRenameFolder(folder)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Tap to open. Long press to rename. Draw on it with the pen to color it; erase it to delete.")
            }
        }
    }

    private var noteGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 24) {
            ForEach(notes) { note in
                PrototypeNoteCard(note: note)
                    .diegeticTarget(.note(note.id))
                    .onTapGesture {
                        editorRequest = PrototypeEditorRequest(kind: .existing(noteID: note.id))
                    }
                    .handDrawnLongPressFeedback(key: "note.\(note.id.uuidString)") {
                        presentRenameNote(note)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Tap to open. Long press to rename. Lasso and drag it into a folder to move it; erase it to delete.")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        AppText(text: title, role: .heading)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        AppCardContainer(key: "library.empty.\(folder?.id.uuidString ?? "root")") {
            VStack(spacing: 14) {
                AppIcon(source: .builtIn(name: "pen", fallbackSymbol: "scribble.variable"), size: 48)
                    .opacity(0.82)
                AppText(text: isRoot ? "No notes yet" : "This folder is empty", role: .heading)
                Text(isRoot ? "Create a canvas or a legal-pad stack." : "Add a note here when you are ready.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(hex: "#2b2723").opacity(0.68))
                    .multilineTextAlignment(.center)
                newNoteButton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
            .padding(.horizontal, 18)
        }
    }

    private var newNoteButton: some View {
        AppButton(label: "New Note") { presentNewNoteChooser() }
    }

    private func openNewNote(pageType: PrototypePageType) {
        editorRequest = PrototypeEditorRequest(
            kind: .new(folderID: folder?.id, pageType: pageType)
        )
    }

    private func plural(_ count: Int, _ singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    // MARK: Diegetic dispatch

    /// Executes a recognized pen gesture handed up by the input surface.
    private func handle(_ gesture: DiegeticGesture) {
        switch gesture {
        case .deleteNote(let id):
            library.deleteNote(id: id)
        case .deleteFolder(let id):
            library.deleteFolder(id: id)
        case .moveNote(let id, let folderID):
            library.moveNote(id: id, toFolder: folderID)
        case .decorateFolder(let id, let marks):
            library.decorateFolder(id: id, adding: marks)
        }
    }

    /// The hand-drawn undo ribbon shown after a destructive pen gesture
    /// (decision 4) — the safety net that replaces the old delete confirmation.
    @ViewBuilder
    private var undoRibbon: some View {
        if let undo = library.activeUndo {
            AppCardContainer(key: "undo.ribbon") {
                HStack(spacing: 14) {
                    Text(undo.message)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(hex: "#2b2723"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    AppButton(label: "Undo") { library.runActiveUndo() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.bottom, 104)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Prompts & choosers (text entry / creation — no pen gesture yet)

    private func presentNewFolder() {
        promptConfig = HandDrawnPromptConfig(
            title: "New Folder",
            initialText: "",
            confirmLabel: "Create"
        ) { name in
            library.createFolder(named: name)
        }
    }

    private func presentRenameNote(_ note: PrototypeNoteSummary) {
        promptConfig = HandDrawnPromptConfig(
            title: "Rename Note",
            initialText: note.title,
            confirmLabel: "Save"
        ) { newName in
            library.renameNote(note, to: newName)
        }
    }

    private func presentRenameFolder(_ folder: PrototypeFolder) {
        promptConfig = HandDrawnPromptConfig(
            title: "Rename Folder",
            initialText: folder.name,
            confirmLabel: "Save"
        ) { newName in
            library.renameFolder(folder, to: newName)
        }
    }

    private func presentNewNoteChooser() {
        chooserConfig = HandDrawnChooserConfig(
            title: "New Canvas",
            options: PrototypePageType.allCases.map { pageType in
                HandDrawnChooserConfig.Option(
                    label: pageType.title,
                    icon: pageType.iconSource
                ) {
                    openNewNote(pageType: pageType)
                }
            }
        )
    }

}

// MARK: - Cards

private extension View {
    func handDrawnLongPressFeedback(
        key: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(HandDrawnLongPressFeedbackModifier(key: key, action: action))
    }
}

private struct HandDrawnLongPressFeedbackModifier: ViewModifier {
    private static let holdDuration = 0.45

    let key: String
    let action: () -> Void

    @State private var isPressing = false
    @State private var holdProgress: CGFloat = 0

    private var pressScale: CGFloat {
        isPressing ? 0.982 + holdProgress * 0.008 : 1
    }

    private var pressOffset: CGFloat {
        isPressing ? 2 + holdProgress * 1.5 : 0
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressScale)
            .offset(y: pressOffset)
            .overlay {
                HandDrawnLongPressEmphasis(key: key, progress: holdProgress)
                    .opacity(isPressing || holdProgress > 0 ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .zIndex(isPressing ? 1 : 0)
            .animation(.snappy(duration: 0.12), value: isPressing)
            .onLongPressGesture(
                minimumDuration: Self.holdDuration,
                maximumDistance: 18,
                perform: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                },
                onPressingChanged: updatePressing
            )
    }

    private func updatePressing(_ pressing: Bool) {
        if pressing {
            isPressing = true
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                holdProgress = 0
            }
            withAnimation(.linear(duration: Self.holdDuration)) {
                holdProgress = 1
            }
        } else {
            withAnimation(.easeOut(duration: 0.13)) {
                isPressing = false
                holdProgress = 0
            }
        }
    }
}

private struct HandDrawnLongPressEmphasis: View {
    let key: String
    let progress: CGFloat

    private var style: SketchStyle {
        var style = SketchStyle()
        style.inkWidth = 2.2
        style.amplitude = 1.25
        style.jitter = 1.1
        style.cornerRadius = 12
        style.overshoot = 7
        style.hatchSpacing = 7
        style.ghost = false
        style.penSpeed = 3400
        return style
    }

    var body: some View {
        let style = style
        let progress = min(max(Double(progress), 0), 1)
        let ink = Color(hex: style.inkHex)

        SketchElementView(
            seedKey: "card.long-press.\(key)",
            style: style,
            entranceDelay: nil,
            revision: "press-emphasis",
            color: { kind, _ in
                switch kind {
                case .hatch:
                    ink.opacity(0.08 + progress * 0.18)
                case .border:
                    ink.opacity(0.16 + progress * 0.34)
                default:
                    ink.opacity(0.18 + progress * 0.22)
                }
            },
            skeleton: { rect, _ in
                let border = rect.insetBy(7)
                var strokes = borderStrokes(
                    in: border,
                    overshoot: style.overshoot,
                    cornerRadius: style.cornerRadius
                ).map { SkeletonStroke(points: $0, kind: .border) }
                strokes += hatchStrokes(in: border.insetBy(8), spacing: style.hatchSpacing)
                    .map { SkeletonStroke(points: $0, kind: .hatch) }
                return strokes
            }
        )
    }
}

private struct PrototypeFolderCard: View {
    let folder: PrototypeFolder
    let noteCount: Int

    var body: some View {
        AppCardContainer(key: "folder.\(folder.id.uuidString)") {
            VStack(spacing: 8) {
                AppIcon(source: .builtIn(name: "folder", fallbackSymbol: "folder.fill"), size: 58)
                    .frame(maxWidth: .infinity, minHeight: 78)
                Text(folder.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(hex: "#2b2723"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                AppText(text: noteCountText, role: .caption)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
        }
        // Pen marks the user drew on this folder (diegetic recolor), rendered
        // over the whole card and normalized to its bounds.
        .overlay {
            if !folder.decorations.isEmpty {
                DiegeticFolderMarkCanvas(marks: folder.decorations)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }

    private var noteCountText: String {
        noteCount == 1 ? "1 note" : "\(noteCount) notes"
    }
}

/// Draws a folder's diegetic recolor marks, denormalized from the card's
/// bounds. Mirrors the note-thumbnail render path so ink reads consistently.
private struct DiegeticFolderMarkCanvas: View {
    let marks: [DiegeticFolderMark]

    var body: some View {
        Canvas { context, size in
            for mark in marks where mark.points.count > 1 {
                var path = Path()
                let denormalize: (CGPoint) -> CGPoint = { point in
                    CGPoint(x: point.x * size.width, y: point.y * size.height)
                }
                path.move(to: denormalize(mark.points[0]))
                for point in mark.points.dropFirst() {
                    path.addLine(to: denormalize(point))
                }

                var layer = context
                layer.opacity = mark.opacity
                if mark.isHighlighter { layer.blendMode = .multiply }
                layer.stroke(
                    path,
                    with: .color(mark.color.color),
                    style: StrokeStyle(
                        lineWidth: max(mark.width * size.width, 0.6),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }
}

private struct PrototypeNoteCard: View {
    let note: PrototypeNoteSummary

    var body: some View {
        AppCardContainer(key: "note.\(note.id.uuidString)") {
            VStack(alignment: .leading, spacing: 9) {
                PrototypeNoteThumbnailView(
                    pageType: note.pageType,
                    strokes: note.thumbnailStrokes
                )
                    .aspectRatio(note.pageType.thumbnailAspectRatio, contentMode: .fit)
                    .background(Color(hex: "#f7f2e7"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#2b2723").opacity(0.16), lineWidth: 1)
                    }
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: "#2b2723"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(note.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#2b2723").opacity(0.62))
                HStack(spacing: 5) {
                    AppIcon(source: note.pageType.iconSource, size: 14)
                    Text(pageTypeCaption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(hex: "#2b2723").opacity(0.62))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .contentShape(Rectangle())
    }

    private var pageTypeCaption: String {
        guard note.pageType.canvasPageRect != nil else { return note.pageType.title }
        return "\(note.pageType.title) - \(note.pageCount) pages"
    }
}

private extension PrototypePageType {
    var iconSource: IconSource {
        switch self {
        case .infiniteCanvas:
            .builtIn(name: "infinity", fallbackSymbol: "infinity")
        case .legalPaper:
            .builtIn(name: "page", fallbackSymbol: "doc")
        }
    }
}

private struct PrototypeHomePaperBackground: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let ink = Color(hex: "#2b2723")
            context.fill(Path(bounds), with: .color(Color(hex: "#f7f2e7")))

            var ruled = Path()
            var y: CGFloat = 36
            while y < size.height {
                ruled.move(to: CGPoint(x: 0, y: y))
                ruled.addLine(to: CGPoint(x: size.width, y: y))
                y += 34
            }
            context.stroke(ruled, with: .color(ink.opacity(0.045)), lineWidth: 0.8)

            var margin = Path()
            margin.move(to: CGPoint(x: min(size.width * 0.12, 82), y: 0))
            margin.addLine(to: CGPoint(x: min(size.width * 0.12, 82), y: size.height))
            context.stroke(margin, with: .color(Color(red: 0.57, green: 0.18, blue: 0.18).opacity(0.08)), lineWidth: 1)
        }
    }
}

// MARK: - Thumbnail

/// Draws a note's downsampled strokes scaled-to-fit, so cards show real ink.
private struct PrototypeNoteThumbnailView: View {
    let pageType: PrototypePageType
    let strokes: [PrototypeThumbnailStroke]

    var body: some View {
        Canvas { context, size in
            if let pageRect = pageType.canvasPageRect {
                Self.drawPageBackground(pageRect: pageRect, context: &context, size: size)
                Self.drawPageStrokes(
                    strokes,
                    pageRect: pageRect,
                    context: &context,
                    size: size
                )
                return
            }

            Self.drawInfiniteBackground(context: &context, size: size)
            guard let bounds = Self.contentBounds(of: strokes) else { return }

            let inset: CGFloat = 12
            let available = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
            guard available.width > 0, available.height > 0 else { return }

            // Never magnify: small doodles stay small on the page.
            let scale = min(available.width / bounds.width, available.height / bounds.height, 1)
            let offset = CGPoint(
                x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            )
            let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
                .scaledBy(x: scale, y: scale)

            for stroke in strokes {
                let path = Self.path(for: stroke).applying(transform)
                var layer = context
                layer.opacity = stroke.opacity
                if stroke.isHighlighter { layer.blendMode = .multiply }

                if stroke.points.count == 1 {
                    layer.fill(path, with: .color(stroke.color.color))
                } else {
                    layer.stroke(
                        path,
                        with: .color(stroke.color.color),
                        style: StrokeStyle(
                            lineWidth: max(0.6, stroke.width * scale),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
    }

    private static func drawInfiniteBackground(context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(red: 0.99, green: 0.985, blue: 0.97))
        )
        drawGrid(in: CGRect(origin: .zero, size: size), spacing: 22, context: &context)
    }

    private static func drawPageBackground(
        pageRect: CGRect,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let frame = pageFrame(for: pageRect, in: size)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(red: 0.92, green: 0.91, blue: 0.88))
        )
        context.fill(
            Path(frame),
            with: .color(Color(red: 0.99, green: 0.985, blue: 0.97))
        )
        drawGrid(in: frame, spacing: max(frame.width / 8.5, 12), context: &context)
        context.stroke(
            Path(frame),
            with: .color(.primary.opacity(0.18)),
            lineWidth: 1
        )
    }

    private static func drawPageStrokes(
        _ strokes: [PrototypeThumbnailStroke],
        pageRect: CGRect,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let transform = pageTransform(for: pageRect, in: size)
        let clipFrame = pageFrame(for: pageRect, in: size)
        context.clip(to: Path(clipFrame))
        draw(strokes: strokes, transform: transform, context: &context)
    }

    private static func draw(
        strokes: [PrototypeThumbnailStroke],
        transform: CGAffineTransform,
        context: inout GraphicsContext
    ) {
        for stroke in strokes {
            let path = Self.path(for: stroke).applying(transform)
            var layer = context
            layer.opacity = stroke.opacity
            if stroke.isHighlighter { layer.blendMode = .multiply }

            if stroke.points.count == 1 {
                layer.fill(path, with: .color(stroke.color.color))
            } else {
                layer.stroke(
                    path,
                    with: .color(stroke.color.color),
                    style: StrokeStyle(
                        lineWidth: max(0.6, stroke.width * transform.a),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    private static func drawGrid(
        in rect: CGRect,
        spacing: CGFloat,
        context: inout GraphicsContext
    ) {
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(.secondary.opacity(0.22)), lineWidth: 0.7)
    }

    private static func pageFrame(for pageRect: CGRect, in size: CGSize) -> CGRect {
        let scale = min(size.width / pageRect.width, size.height / pageRect.height)
        let pageSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        return CGRect(
            x: (size.width - pageSize.width) / 2,
            y: (size.height - pageSize.height) / 2,
            width: pageSize.width,
            height: pageSize.height
        )
    }

    private static func pageTransform(for pageRect: CGRect, in size: CGSize) -> CGAffineTransform {
        let frame = pageFrame(for: pageRect, in: size)
        let scale = frame.width / pageRect.width
        return CGAffineTransform(
            translationX: frame.minX - pageRect.minX * scale,
            y: frame.minY - pageRect.minY * scale
        )
        .scaledBy(x: scale, y: scale)
    }

    /// Same midpoint smoothing as `PrototypeStroke.layerPath`, in canvas space.
    private static func path(for stroke: PrototypeThumbnailStroke) -> Path {
        var path = Path()
        guard let first = stroke.points.first else { return path }

        if stroke.points.count == 1 {
            let radius = max(stroke.width / 2, 0.5)
            path.addEllipse(in: CGRect(
                x: first.x - radius, y: first.y - radius,
                width: radius * 2, height: radius * 2
            ))
            return path
        }

        path.move(to: first)
        for index in 1..<stroke.points.count {
            let previous = stroke.points[index - 1]
            let current = stroke.points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
        }
        if let last = stroke.points.last {
            path.addLine(to: last)
        }
        return path
    }

    private static func contentBounds(of strokes: [PrototypeThumbnailStroke]) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var padding: CGFloat = 1

        for stroke in strokes {
            padding = max(padding, stroke.width / 2)
            for point in stroke.points {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(maxX - minX + padding * 2, 1),
            height: max(maxY - minY + padding * 2, 1)
        )
    }
}
