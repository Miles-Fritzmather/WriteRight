import Foundation
import Observation

/// A single-level "undo the last diegetic action" affordance surfaced as the
/// hand-drawn undo ribbon (decision 4, 2026-07-09: destructive pen gestures
/// commit immediately, with undo as the safety net instead of a modal).
@MainActor
struct DiegeticUndo: Identifiable {
    let id = UUID()
    var message: String
    var perform: () -> Void
}

/// Home-screen mockup state: folders + note summaries, with pass-through
/// CRUD to `PrototypeNoteStore`. Throwaway by design, like the rest of the
/// `Prototype*` files.
@MainActor
@Observable
final class PrototypeLibraryModel {
    private(set) var folders: [PrototypeFolder] = []
    private(set) var notes: [PrototypeNoteSummary] = []
    var errorMessage: String?
    /// The most recent undoable action, shown as the undo ribbon while non-nil.
    private(set) var activeUndo: DiegeticUndo?

    private let store = PrototypeNoteStore()

    init() {
        refresh()
    }

    func refresh() {
        do {
            folders = try store.listFolders()
            notes = try store.listNotes()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load library: \(error.localizedDescription)"
        }
    }

    func notes(in folderID: UUID?) -> [PrototypeNoteSummary] {
        notes.filter { $0.folderID == folderID }
    }

    func noteCount(in folder: PrototypeFolder) -> Int {
        notes(in: folder.id).count
    }

    func folder(withID id: UUID?) -> PrototypeFolder? {
        folders.first { $0.id == id }
    }

    func note(withID id: UUID) -> PrototypeNoteSummary? {
        notes.first { $0.id == id }
    }

    // MARK: Note actions

    func deleteNote(_ note: PrototypeNoteSummary) {
        // Capture the full document first so the undo can re-materialize it.
        let document = try? store.load(id: note.id)
        do {
            try store.deleteNote(id: note.id)
            refresh()
            if let document {
                registerUndo("Erased \(note.title)") { [self] in
                    try? store.save(document)
                    refresh()
                }
            }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func renameNote(_ note: PrototypeNoteSummary, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform("Rename failed") { try store.renameNote(id: note.id, to: trimmed) }
    }

    func moveNote(_ note: PrototypeNoteSummary, toFolder folderID: UUID?) {
        // A no-op drop (dropping a root note back on the root desk) shouldn't
        // churn disk or clobber the undo ribbon.
        guard note.folderID != folderID else { return }
        let previous = note.folderID
        do {
            try store.moveNote(id: note.id, toFolder: folderID)
            refresh()
            let destination = folder(withID: folderID)?.name ?? "the library"
            registerUndo("Moved \(note.title) to \(destination)") { [self] in
                try? store.moveNote(id: note.id, toFolder: previous)
                refresh()
            }
        } catch {
            errorMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    // MARK: Folder actions

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform("New folder failed") { _ = try store.createFolder(named: trimmed) }
    }

    func renameFolder(_ folder: PrototypeFolder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform("Rename failed") { try store.renameFolder(id: folder.id, to: trimmed) }
    }

    func deleteFolder(_ folder: PrototypeFolder) {
        // Its notes fall back to the library root on delete; remember them so
        // undo can reparent them.
        let childIDs = notes(in: folder.id).map(\.id)
        do {
            try store.deleteFolder(id: folder.id)
            refresh()
            registerUndo("Erased \(folder.name)") { [self] in
                try? store.addFolder(folder)
                for id in childIDs {
                    try? store.moveNote(id: id, toFolder: folder.id)
                }
                refresh()
            }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    /// Appends pen marks to a folder icon (the diegetic recolor gesture).
    func decorateFolder(_ folder: PrototypeFolder, adding marks: [DiegeticFolderMark]) {
        guard !marks.isEmpty else { return }
        let previous = folder.decorations
        do {
            try store.setFolderDecorations(id: folder.id, to: previous + marks)
            refresh()
            registerUndo("Colored \(folder.name)") { [self] in
                try? store.setFolderDecorations(id: folder.id, to: previous)
                refresh()
            }
        } catch {
            errorMessage = "Recolor failed: \(error.localizedDescription)"
        }
    }

    // MARK: ID-based dispatch (from the pen surface, which only carries IDs)

    func deleteNote(id: UUID) {
        guard let note = note(withID: id) else { return }
        deleteNote(note)
    }

    func deleteFolder(id: UUID) {
        guard let folder = folder(withID: id) else { return }
        deleteFolder(folder)
    }

    func moveNote(id: UUID, toFolder folderID: UUID?) {
        guard let note = note(withID: id) else { return }
        moveNote(note, toFolder: folderID)
    }

    func decorateFolder(id: UUID, adding marks: [DiegeticFolderMark]) {
        guard let folder = folder(withID: id) else { return }
        decorateFolder(folder, adding: marks)
    }

    // MARK: Undo plumbing

    func runActiveUndo() {
        activeUndo?.perform()
        activeUndo = nil
    }

    func dismissUndo() {
        activeUndo = nil
    }

    private func registerUndo(_ message: String, _ undo: @escaping () -> Void) {
        let action = DiegeticUndo(message: message, perform: undo)
        activeUndo = action
        let id = action.id
        // Auto-retire the ribbon so a stale "undo" can't reach back much later.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if self?.activeUndo?.id == id {
                self?.activeUndo = nil
            }
        }
    }

    private func perform(_ failureLabel: String, _ work: () throws -> Void) {
        do {
            try work()
            refresh()
        } catch {
            errorMessage = "\(failureLabel): \(error.localizedDescription)"
        }
    }
}
