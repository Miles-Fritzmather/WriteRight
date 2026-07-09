import CanvasCore
import CoreGraphics
import Foundation
import Observation
import UIKit

/// Bridges the prototype canvas UIView to the SwiftUI editor chrome.
@MainActor
@Observable
final class PrototypeCanvasModel {
    var scale: CGFloat = 1
    var rotationDegrees: Double = 0
    var strokeCount = 0
    var selectedStrokeCount = 0
    var selectedTool: PrototypeToolKind = .pen
    var selectedInkColor: PrototypeInkColor = .black
    var selectedHighlighterColor: PrototypeInkColor = .yellow
    var isPencilQuickToolbarPresented = false
    var pencilQuickToolbarAnchor: CGPoint?
    var noteSummaries: [PrototypeNoteSummary] = []
    var currentNoteTitle: String
    var currentPageType: PrototypePageType
    var currentPageCount: Int = 1
    var storageMessage: String?

    weak var canvasView: CanvasPrototypeUIView?

    private let noteStore = PrototypeNoteStore()
    private var currentNoteID: UUID
    private var currentNoteCreatedAt: Date
    private var currentFolderID: UUID?
    /// A note requested before the canvas UIView exists (home-screen open);
    /// applied in `attach(_:)`.
    private var pendingNote: PrototypeNoteDocument?

    init(
        request: PrototypeEditorRequest = PrototypeEditorRequest(
            kind: .new(folderID: nil, pageType: .infiniteCanvas)
        )
    ) {
        let now = Date()
        currentNoteID = UUID()
        currentNoteCreatedAt = now
        currentNoteTitle = Self.defaultTitle(for: now)
        currentPageType = .infiniteCanvas

        switch request.kind {
        case .new(let folderID, let pageType):
            currentFolderID = folderID
            currentPageType = pageType
            currentPageCount = 1
        case .existing(let noteID):
            do {
                let note = try noteStore.load(id: noteID)
                currentNoteID = note.id
                currentNoteCreatedAt = note.createdAt
                currentNoteTitle = note.title
                currentFolderID = note.folderID
                currentPageType = note.pageType
                currentPageCount = note.pageCount
                pendingNote = note
            } catch {
                storageMessage = "Load failed: \(error.localizedDescription)"
            }
        }
        refreshNotes()
    }

    /// Called from `makeUIView`; applies a note that was requested before the
    /// canvas existed.
    func attach(_ view: CanvasPrototypeUIView) {
        canvasView = view
        view.pageType = currentPageType
        view.pageCount = currentPageCount
        view.onPageCountChange = { [weak self] pageCount in
            self?.currentPageCount = pageCount
        }
        if let pendingNote {
            view.loadNote(pendingNote)
            self.pendingNote = nil
        }
    }

    func deleteSelection() { canvasView?.deleteSelectedStrokes() }

    func togglePencilQuickToolbar(at anchor: CGPoint?) {
        if isPencilQuickToolbarPresented {
            closePencilQuickToolbar()
        } else {
            pencilQuickToolbarAnchor = anchor
            isPencilQuickToolbarPresented = true
        }
    }

    func closePencilQuickToolbar() {
        isPencilQuickToolbarPresented = false
        pencilQuickToolbarAnchor = nil
    }

    var currentToolStyle: PrototypeToolStyle {
        PrototypeToolStyle.resolved(
            kind: selectedTool,
            inkColor: selectedInkColor,
            highlighterColor: selectedHighlighterColor
        )
    }

    func selectTool(_ tool: PrototypeToolKind) {
        selectedTool = tool
        closePencilQuickToolbar()
    }

    func selectInkColor(_ color: PrototypeInkColor) {
        selectedInkColor = color
        if selectedTool == .highlighter || selectedTool == .eraser || selectedTool == .selection {
            selectedTool = .pen
        }
    }

    func selectHighlighterColor(_ color: PrototypeInkColor) {
        selectedHighlighterColor = color
        if selectedTool != .highlighter {
            selectedTool = .highlighter
        }
    }

    func newNote(pageType: PrototypePageType = .infiniteCanvas) {
        let now = Date()
        currentNoteID = UUID()
        currentNoteCreatedAt = now
        currentNoteTitle = Self.defaultTitle(for: now)
        currentPageType = pageType
        currentPageCount = 1
        canvasView?.startBlankNote(pageType: pageType)
        storageMessage = "New note ready"
    }

    func addPage() {
        guard currentPageType.canvasPageRect != nil else { return }
        canvasView?.appendPageAndFocus()
        currentPageCount = canvasView?.pageCount ?? currentPageCount + 1
        storageMessage = "Added page \(currentPageCount)"
    }

    func saveNote(refreshAfterSave: Bool = true) {
        guard let canvasView else {
            storageMessage = "Canvas is not ready"
            return
        }

        do {
            var note = canvasView.makeNoteDocument(
                id: currentNoteID,
                title: currentNoteTitle,
                createdAt: currentNoteCreatedAt
            )
            note.folderID = currentFolderID
            try noteStore.save(note)
            currentNoteCreatedAt = note.createdAt
            currentNoteTitle = note.title
            currentPageType = note.pageType
            currentPageCount = note.pageCount
            if refreshAfterSave {
                refreshNotes()
            }
            storageMessage = "Saved \(note.title)"
        } catch {
            storageMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func loadNote(_ summary: PrototypeNoteSummary) {
        guard let canvasView else {
            storageMessage = "Canvas is not ready"
            return
        }

        do {
            let note = try noteStore.load(id: summary.id)
            currentNoteID = note.id
            currentNoteCreatedAt = note.createdAt
            currentNoteTitle = note.title
            currentFolderID = note.folderID
            currentPageType = note.pageType
            currentPageCount = note.pageCount
            canvasView.loadNote(note)
            refreshNotes()
            storageMessage = "Loaded \(note.title)"
        } catch {
            storageMessage = "Load failed: \(error.localizedDescription)"
        }
    }

    /// Close-time save: skip only a brand-new note with no ink, so backing
    /// out of an empty canvas doesn't litter the library.
    func saveIfNeeded(refreshAfterSave: Bool = true) {
        let existsOnDisk = noteSummaries.contains { $0.id == currentNoteID }
        guard strokeCount > 0 || currentPageCount > 1 || existsOnDisk else { return }
        saveNote(refreshAfterSave: refreshAfterSave)
    }

    func refreshNotes() {
        do {
            noteSummaries = try noteStore.listNotes()
        } catch {
            noteSummaries = []
            storageMessage = "Could not list notes: \(error.localizedDescription)"
        }
    }

    /// Called at up to 120 Hz during gestures; writes only on real change
    /// so SwiftUI isn't invalidated needlessly.
    func apply(camera: Camera, strokeCount: Int, selectedStrokeCount: Int) {
        if camera.scale != scale { scale = camera.scale }

        var degrees = camera.rotation * 180 / .pi
        degrees.formTruncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        if degrees != rotationDegrees { rotationDegrees = degrees }

        if strokeCount != self.strokeCount { self.strokeCount = strokeCount }
        if selectedStrokeCount != self.selectedStrokeCount {
            self.selectedStrokeCount = selectedStrokeCount
        }
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Note \(formatter.string(from: date))"
    }
}
