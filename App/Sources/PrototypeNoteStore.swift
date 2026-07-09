import CanvasCore
import CoreGraphics
import Foundation

enum PrototypePageType: String, CaseIterable, Codable, Identifiable, Hashable {
    case infiniteCanvas
    case legalPaper

    var id: Self { self }

    var title: String {
        switch self {
        case .infiniteCanvas:
            "Infinite Canvas"
        case .legalPaper:
            "Legal Paper"
        }
    }

    var systemImage: String {
        switch self {
        case .infiniteCanvas:
            "infinity"
        case .legalPaper:
            "doc"
        }
    }

    var canvasPageRect: CGRect? {
        switch self {
        case .infiniteCanvas:
            nil
        case .legalPaper:
            CGRect(origin: .zero, size: pageSize)
        }
    }

    var pageSize: CGSize {
        switch self {
        case .infiniteCanvas:
            .zero
        case .legalPaper:
            CGSize(width: 850, height: 1_400)
        }
    }

    var thumbnailAspectRatio: CGFloat {
        switch self {
        case .infiniteCanvas:
            3 / 4
        case .legalPaper:
            8.5 / 14
        }
    }
}

struct PrototypeCameraSnapshot: Codable {
    var translationX: CGFloat
    var translationY: CGFloat
    var scale: CGFloat
    var rotation: CGFloat

    init(camera: Camera) {
        translationX = camera.translation.dx
        translationY = camera.translation.dy
        scale = camera.scale
        rotation = camera.rotation
    }

    var camera: Camera {
        Camera(
            translation: CGVector(dx: translationX, dy: translationY),
            scale: scale,
            rotation: rotation
        )
    }
}

struct PrototypeNoteDocument: Codable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Home-screen mockup: notes live in at most one folder; nil = library root.
    /// Optional so pre-folder note files keep decoding.
    var folderID: UUID?
    /// Prototype-only page format. Real Page/PageBackground records arrive in
    /// SPEC Phase 4; this keeps today's per-note format choice explicit.
    var pageType: PrototypePageType
    /// Prototype-only bounded-page stack count for legal-paper notes.
    var pageCount: Int
    var camera: PrototypeCameraSnapshot
    var strokes: [PrototypeStroke]

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        folderID: UUID? = nil,
        pageType: PrototypePageType = .infiniteCanvas,
        pageCount: Int = 1,
        camera: PrototypeCameraSnapshot,
        strokes: [PrototypeStroke]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.pageType = pageType
        self.pageCount = max(pageCount, 1)
        self.camera = camera
        self.strokes = strokes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case folderID
        case pageType
        case pageCount
        case camera
        case strokes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        pageType = try container.decodeIfPresent(PrototypePageType.self, forKey: .pageType)
            ?? .infiniteCanvas
        pageCount = max(try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1, 1)
        camera = try container.decode(PrototypeCameraSnapshot.self, forKey: .camera)
        strokes = try container.decode([PrototypeStroke].self, forKey: .strokes)
    }
}

/// One pen-drawn mark left on a folder icon by the diegetic recolor gesture
/// (draw on a folder to give it a custom color — decision 3, 2026-07-09).
/// Geometry is normalized to the folder card's bounds so it survives the card
/// being laid out at any size; see `docs/diegetic-ui/README.md`.
struct DiegeticFolderMark: Codable, Hashable {
    /// Points normalized to the folder card's bounds (0…1), origin top-left.
    var points: [CGPoint]
    var color: PrototypeInkColor
    /// Stroke width as a fraction of the card's width, so it scales with the card.
    var width: CGFloat
    var opacity: CGFloat
    var isHighlighter: Bool
}

struct PrototypeFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    /// Pen marks drawn onto this folder's icon (diegetic recolor). Optional in
    /// storage so pre-decoration `folders.json` files keep decoding.
    var decorations: [DiegeticFolderMark]

    init(id: UUID, name: String, createdAt: Date, decorations: [DiegeticFolderMark] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.decorations = decorations
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, decorations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        decorations = try container.decodeIfPresent([DiegeticFolderMark].self, forKey: .decorations) ?? []
    }
}

/// Downsampled stroke geometry for the home-screen note cards; canvas space.
struct PrototypeThumbnailStroke {
    var points: [CGPoint]
    var color: PrototypeInkColor
    var width: CGFloat
    var opacity: CGFloat
    var isHighlighter: Bool
}

struct PrototypeNoteSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var strokeCount: Int
    var folderID: UUID?
    var pageType: PrototypePageType
    var pageCount: Int
    var thumbnailStrokes: [PrototypeThumbnailStroke]

    // Identity for SwiftUI diffing; thumbnail geometry is derived data and
    // changes exactly when `updatedAt` does.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.updatedAt == rhs.updatedAt
            && lhs.strokeCount == rhs.strokeCount
            && lhs.folderID == rhs.folderID
            && lhs.pageType == rhs.pageType
            && lhs.pageCount == rhs.pageCount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(updatedAt)
        hasher.combine(pageType)
        hasher.combine(pageCount)
    }
}

enum PrototypeNoteStoreError: LocalizedError {
    case documentsDirectoryUnavailable
    case noteNotFound

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            "Documents directory is unavailable."
        case .noteNotFound:
            "The note could not be found."
        }
    }
}

struct PrototypeNoteStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func listNotes() throws -> [PrototypeNoteSummary] {
        let directory = try notesDirectory(createIfNeeded: true)
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.foldersFileName }
            .compactMap { url -> PrototypeNoteSummary? in
                guard let data = try? Data(contentsOf: url),
                      let note = try? decoder.decode(PrototypeNoteDocument.self, from: data)
                else { return nil }

                return PrototypeNoteSummary(
                    id: note.id,
                    title: note.title,
                    updatedAt: note.updatedAt,
                    strokeCount: note.strokes.count,
                    folderID: note.folderID,
                    pageType: note.pageType,
                    pageCount: note.pageCount,
                    thumbnailStrokes: Self.thumbnailStrokes(for: note)
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteNote(id: UUID) throws {
        let directory = try notesDirectory(createIfNeeded: true)
        let url = noteURL(for: id, in: directory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PrototypeNoteStoreError.noteNotFound
        }
        try fileManager.removeItem(at: url)
    }

    func renameNote(id: UUID, to title: String) throws {
        var note = try load(id: id)
        note.title = title
        note.updatedAt = Date()
        try save(note)
    }

    func moveNote(id: UUID, toFolder folderID: UUID?) throws {
        var note = try load(id: id)
        note.folderID = folderID
        try save(note)
    }

    // MARK: Folders

    func listFolders() throws -> [PrototypeFolder] {
        let directory = try notesDirectory(createIfNeeded: true)
        let url = directory.appendingPathComponent(Self.foldersFileName)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try decoder.decode([PrototypeFolder].self, from: data)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func createFolder(named name: String) throws -> PrototypeFolder {
        var folders = try listFolders()
        let folder = PrototypeFolder(id: UUID(), name: name, createdAt: Date())
        folders.append(folder)
        try writeFolders(folders)
        return folder
    }

    func renameFolder(id: UUID, to name: String) throws {
        var folders = try listFolders()
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name
        try writeFolders(folders)
    }

    /// Re-inserts a folder verbatim (id, decorations, createdAt). Used to undo a
    /// delete; note reparenting is handled by the caller.
    func addFolder(_ folder: PrototypeFolder) throws {
        var folders = try listFolders()
        guard !folders.contains(where: { $0.id == folder.id }) else { return }
        folders.append(folder)
        try writeFolders(folders)
    }

    /// Replaces a folder's diegetic recolor marks wholesale (the caller owns
    /// append vs. clear semantics, so undo can restore the exact prior set).
    func setFolderDecorations(id: UUID, to decorations: [DiegeticFolderMark]) throws {
        var folders = try listFolders()
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].decorations = decorations
        try writeFolders(folders)
    }

    /// Deletes the folder; its notes fall back to the library root.
    func deleteFolder(id: UUID) throws {
        var folders = try listFolders()
        folders.removeAll { $0.id == id }
        try writeFolders(folders)

        for summary in try listNotes() where summary.folderID == id {
            try moveNote(id: summary.id, toFolder: nil)
        }
    }

    private func writeFolders(_ folders: [PrototypeFolder]) throws {
        let directory = try notesDirectory(createIfNeeded: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(folders)
        try data.write(to: directory.appendingPathComponent(Self.foldersFileName), options: .atomic)
    }

    private static let foldersFileName = "folders.json"

    /// Caps stroke and point counts so a summary stays cheap to hold and draw.
    private static func thumbnailStrokes(for note: PrototypeNoteDocument) -> [PrototypeThumbnailStroke] {
        let maxStrokes = 160
        let maxPointsPerStroke = 32

        return note.strokes.prefix(maxStrokes).map { stroke in
            var points = stroke.points.map(\.position.cgPoint)
            if points.count > maxPointsPerStroke, let last = points.last {
                let step = max(1, points.count / maxPointsPerStroke)
                points = Swift.stride(from: 0, to: points.count, by: step).map { points[$0] }
                if points.last != last { points.append(last) }
            }
            return PrototypeThumbnailStroke(
                points: points,
                color: stroke.style.color,
                width: stroke.renderWidth,
                opacity: stroke.style.opacity,
                isHighlighter: stroke.style.kind == .highlighter
            )
        }
    }

    func save(_ note: PrototypeNoteDocument) throws {
        let directory = try notesDirectory(createIfNeeded: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(note)
        try data.write(to: noteURL(for: note.id, in: directory), options: .atomic)
    }

    func load(id: UUID) throws -> PrototypeNoteDocument {
        let directory = try notesDirectory(createIfNeeded: true)
        let url = noteURL(for: id, in: directory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PrototypeNoteStoreError.noteNotFound
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try decoder.decode(PrototypeNoteDocument.self, from: data)
    }

    private func notesDirectory(createIfNeeded: Bool) throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw PrototypeNoteStoreError.documentsDirectoryUnavailable
        }

        let directory = documents.appendingPathComponent("WriteRightPrototypeNotes", isDirectory: true)
        if createIfNeeded, !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func noteURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
