import CoreGraphics
import Foundation
import GRDB

/// The hub described in the architecture doc: every read and write for
/// notebooks, sections, pages, strokes, and recognized text goes through
/// here. PencilKit, the tiled renderer, search, and export all treat this as
/// the single source of truth — none of them own persistence themselves.
final class NotebookRepository: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Notebooks / Sections / Pages

    func createNotebook(title: String) throws -> Notebook {
        let notebook = Notebook(title: title)
        try dbQueue.write { db in
            try NotebookRow(notebook).insert(db)
        }
        return notebook
    }

    func allNotebooks() throws -> [Notebook] {
        try dbQueue.read { db in
            try NotebookRow.order(Column("createdAt").desc).fetchAll(db).map(\.asNotebook)
        }
    }

    func createSection(title: String, in notebook: Notebook, orderIndex: Int) throws -> Section {
        let section = Section(notebookID: notebook.id, title: title, orderIndex: orderIndex)
        try dbQueue.write { db in try SectionRow(section).insert(db) }
        return section
    }

    func sections(in notebook: Notebook) throws -> [Section] {
        try dbQueue.read { db in
            try SectionRow
                .filter(Column("notebookID") == notebook.id.uuidString)
                .order(Column("orderIndex"))
                .fetchAll(db)
                .map(\.asSection)
        }
    }

    func createPage(in section: Section, orderIndex: Int, background: PageBackground = .blank) throws -> Page {
        let page = Page(sectionID: section.id, background: background, orderIndex: orderIndex)
        try dbQueue.write { db in try PageRow(page).insert(db) }
        return page
    }

    func page(withID id: UUID) throws -> Page? {
        try dbQueue.read { db in
            try PageRow.filter(Column("id") == id.uuidString).fetchOne(db)?.asPage
        }
    }

    func pages(in section: Section) throws -> [Page] {
        try dbQueue.read { db in
            try PageRow
                .filter(Column("sectionID") == section.id.uuidString)
                .order(Column("orderIndex"))
                .fetchAll(db)
                .map(\.asPage)
        }
    }

    // MARK: - Strokes

    func allStrokes(onPage pageID: UUID) throws -> [Stroke] {
        try dbQueue.read { db in
            try StrokeRow
                .filter(Column("pageID") == pageID.uuidString)
                .fetchAll(db)
                .map(\.asStroke)
        }
    }

    /// R-tree-backed spatial query: every stroke whose bounding box
    /// intersects `rect`. Used for jump-to-search-hit and, as pages grow
    /// past what's comfortable to hold in memory, viewport-scoped loading.
    func strokes(onPage pageID: UUID, intersecting rect: CGRect) throws -> [Stroke] {
        try dbQueue.read { db in
            try StrokeRow.fetchAll(db, sql: """
                SELECT stroke.* FROM stroke
                JOIN stroke_rtree ON stroke.rowid = stroke_rtree.id
                WHERE stroke.pageID = ?
                  AND stroke_rtree.minX <= ? AND stroke_rtree.maxX >= ?
                  AND stroke_rtree.minY <= ? AND stroke_rtree.maxY >= ?
                """, arguments: [pageID.uuidString, rect.maxX, rect.minX, rect.maxY, rect.minY])
                .map(\.asStroke)
        }
    }

    @discardableResult
    func insertStroke(_ stroke: Stroke) throws -> Stroke {
        try dbQueue.write { db in
            var row = try StrokeRow(stroke)
            try row.insert(db)
            guard let rowID = row.rowid else { return }
            try db.execute(sql: """
                INSERT INTO stroke_rtree(id, minX, maxX, minY, maxY) VALUES (?, ?, ?, ?, ?)
                """, arguments: [rowID, stroke.boundingBox.minX, stroke.boundingBox.maxX, stroke.boundingBox.minY, stroke.boundingBox.maxY])
        }
        return stroke
    }

    func deleteStrokes(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                if let rowID = try Int64.fetchOne(db, sql: "SELECT rowid FROM stroke WHERE id = ?", arguments: [id.uuidString]) {
                    try db.execute(sql: "DELETE FROM stroke_rtree WHERE id = ?", arguments: [rowID])
                }
                try db.execute(sql: "DELETE FROM stroke WHERE id = ?", arguments: [id.uuidString])
            }
        }
    }

    // MARK: - Recognized text (Vision OCR results, feeds FTS5 search)

    func recognizedTextLines(forPage pageID: UUID) throws -> [RecognizedTextLine] {
        try dbQueue.read { db in
            try RecognizedTextLineRow
                .filter(Column("pageID") == pageID.uuidString)
                .fetchAll(db)
                .map(\.asLine)
        }
    }

    func replaceRecognizedText(_ lines: [RecognizedTextLine], forPage pageID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM recognizedTextLine WHERE pageID = ?", arguments: [pageID.uuidString])
            for line in lines {
                try RecognizedTextLineRow(line).insert(db)
            }
        }
    }

    struct SearchHit {
        let line: RecognizedTextLine
    }

    func searchText(_ query: String) throws -> [SearchHit] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let ftsQuery = query
            .split(separator: " ")
            .map { "\($0)*" }
            .joined(separator: " ")
        return try dbQueue.read { db in
            try RecognizedTextLineRow.fetchAll(db, sql: """
                SELECT recognizedTextLine.* FROM recognizedTextLine
                JOIN recognizedText_fts ON recognizedTextLine.rowid = recognizedText_fts.rowid
                WHERE recognizedText_fts MATCH ?
                ORDER BY rank
                """, arguments: [ftsQuery])
                .map { SearchHit(line: $0.asLine) }
        }
    }
}

// MARK: - GRDB row types
//
// Kept separate from the domain models in `Models/` so that layer stays free
// of persistence-framework concerns. IDs are stored as `TEXT` (UUID strings)
// explicitly rather than relying on a default UUID<->SQLite mapping.

private struct NotebookRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notebook"
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(_ n: Notebook) {
        id = n.id.uuidString
        title = n.title
        createdAt = n.createdAt
        updatedAt = n.updatedAt
    }

    var asNotebook: Notebook {
        Notebook(id: UUID(uuidString: id)!, title: title, createdAt: createdAt, updatedAt: updatedAt)
    }
}

private struct SectionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "section"
    var id: String
    var notebookID: String
    var title: String
    var orderIndex: Int
    var createdAt: Date

    init(_ s: Section) {
        id = s.id.uuidString
        notebookID = s.notebookID.uuidString
        title = s.title
        orderIndex = s.orderIndex
        createdAt = s.createdAt
    }

    var asSection: Section {
        Section(id: UUID(uuidString: id)!, notebookID: UUID(uuidString: notebookID)!, title: title, orderIndex: orderIndex, createdAt: createdAt)
    }
}

private struct PageRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "page"
    var id: String
    var sectionID: String
    var backgroundData: Data
    var objectIDsData: Data
    var orderIndex: Int
    var createdAt: Date

    init(_ p: Page) {
        id = p.id.uuidString
        sectionID = p.sectionID.uuidString
        backgroundData = try! JSONEncoder().encode(p.background)
        objectIDsData = try! JSONEncoder().encode(p.objectIDs)
        orderIndex = p.orderIndex
        createdAt = p.createdAt
    }

    var asPage: Page {
        let background = (try? JSONDecoder().decode(PageBackground.self, from: backgroundData)) ?? .blank
        let objectIDs = (try? JSONDecoder().decode([UUID].self, from: objectIDsData)) ?? []
        return Page(id: UUID(uuidString: id)!, sectionID: UUID(uuidString: sectionID)!, background: background, objectIDs: objectIDs, orderIndex: orderIndex, createdAt: createdAt)
    }
}

private struct StrokeRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "stroke"
    var rowid: Int64?
    var id: String
    var pageID: String
    var pointsData: Data
    var styleData: Data
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var createdAt: Date

    init(_ stroke: Stroke) throws {
        rowid = nil
        id = stroke.id.uuidString
        pageID = stroke.pageID.uuidString
        pointsData = try JSONEncoder().encode(stroke.points)
        styleData = try JSONEncoder().encode(stroke.style)
        minX = stroke.boundingBox.minX
        minY = stroke.boundingBox.minY
        maxX = stroke.boundingBox.maxX
        maxY = stroke.boundingBox.maxY
        createdAt = stroke.createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowid = inserted.rowID
    }

    var asStroke: Stroke {
        let points = (try? JSONDecoder().decode([SamplePoint].self, from: pointsData)) ?? []
        let style = (try? JSONDecoder().decode(ToolStyle.self, from: styleData)) ?? .default(for: .pen)
        var stroke = Stroke(id: UUID(uuidString: id)!, pageID: UUID(uuidString: pageID)!, points: points, style: style, createdAt: createdAt)
        stroke.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return stroke
    }
}

private struct RecognizedTextLineRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recognizedTextLine"
    var rowid: Int64?
    var id: String
    var pageID: String
    var text: String
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var recognizedAt: Date

    init(_ line: RecognizedTextLine) {
        rowid = nil
        id = line.id.uuidString
        pageID = line.pageID.uuidString
        text = line.text
        minX = line.boundingBox.minX
        minY = line.boundingBox.minY
        maxX = line.boundingBox.maxX
        maxY = line.boundingBox.maxY
        recognizedAt = line.recognizedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowid = inserted.rowID
    }

    var asLine: RecognizedTextLine {
        RecognizedTextLine(
            id: UUID(uuidString: id)!,
            pageID: UUID(uuidString: pageID)!,
            text: text,
            boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            recognizedAt: recognizedAt
        )
    }
}
