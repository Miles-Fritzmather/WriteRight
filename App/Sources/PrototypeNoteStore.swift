import CanvasCore
import CoreGraphics
import Foundation

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
    var camera: PrototypeCameraSnapshot
    var strokes: [PrototypeStroke]
}

struct PrototypeNoteSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var strokeCount: Int
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
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> PrototypeNoteSummary? in
                guard let data = try? Data(contentsOf: url),
                      let note = try? decoder.decode(PrototypeNoteDocument.self, from: data)
                else { return nil }

                return PrototypeNoteSummary(
                    id: note.id,
                    title: note.title,
                    updatedAt: note.updatedAt,
                    strokeCount: note.strokes.count
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
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
