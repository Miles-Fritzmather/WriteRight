import CanvasCore
import CoreGraphics
import Foundation
import Observation
import UIKit

/// Bridges the prototype canvas UIView to the SwiftUI HUD.
@MainActor
@Observable
final class PrototypeCanvasModel {
    var scale: CGFloat = 1
    var rotationDegrees: Double = 0
    var strokeCount = 0
    var fingerDrawing = false
    var selectedTool: PrototypeToolKind = .pen
    var selectedInkColor: PrototypeInkColor = .black
    var selectedHighlighterColor: PrototypeInkColor = .yellow
    var noteSummaries: [PrototypeNoteSummary] = []
    var currentNoteTitle: String
    var storageMessage: String?

    weak var canvasView: CanvasPrototypeUIView?

    private let noteStore = PrototypeNoteStore()
    private var currentNoteID: UUID
    private var currentNoteCreatedAt: Date

    init() {
        let now = Date()
        currentNoteID = UUID()
        currentNoteCreatedAt = now
        currentNoteTitle = Self.defaultTitle(for: now)
        refreshNotes()
    }

    func resetCamera() { canvasView?.resetCamera() }
    func clearInk() { canvasView?.clearInk() }

    var currentToolStyle: PrototypeToolStyle {
        PrototypeToolStyle.resolved(
            kind: selectedTool,
            inkColor: selectedInkColor,
            highlighterColor: selectedHighlighterColor
        )
    }

    func selectTool(_ tool: PrototypeToolKind) {
        selectedTool = tool
    }

    func selectInkColor(_ color: PrototypeInkColor) {
        selectedInkColor = color
        if selectedTool == .highlighter || selectedTool == .eraser {
            selectedTool = .pen
        }
    }

    func selectHighlighterColor(_ color: PrototypeInkColor) {
        selectedHighlighterColor = color
        if selectedTool != .highlighter {
            selectedTool = .highlighter
        }
    }

    func newNote() {
        let now = Date()
        currentNoteID = UUID()
        currentNoteCreatedAt = now
        currentNoteTitle = Self.defaultTitle(for: now)
        canvasView?.startBlankNote()
        storageMessage = "New note ready"
    }

    func saveNote() {
        guard let canvasView else {
            storageMessage = "Canvas is not ready"
            return
        }

        do {
            let note = canvasView.makeNoteDocument(
                id: currentNoteID,
                title: currentNoteTitle,
                createdAt: currentNoteCreatedAt
            )
            try noteStore.save(note)
            currentNoteCreatedAt = note.createdAt
            currentNoteTitle = note.title
            refreshNotes()
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
            canvasView.loadNote(note)
            refreshNotes()
            storageMessage = "Loaded \(note.title)"
        } catch {
            storageMessage = "Load failed: \(error.localizedDescription)"
        }
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
    func apply(camera: Camera, strokeCount: Int) {
        if camera.scale != scale { scale = camera.scale }

        var degrees = camera.rotation * 180 / .pi
        degrees.formTruncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        if degrees != rotationDegrees { rotationDegrees = degrees }

        if strokeCount != self.strokeCount { self.strokeCount = strokeCount }
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Note \(formatter.string(from: date))"
    }
}
