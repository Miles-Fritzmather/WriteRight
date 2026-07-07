import Foundation
import GRDB

/// Owns the single SQLite connection for the app: a WAL-mode `DatabaseQueue`
/// with an R-tree spatial index over stroke bounding boxes and an FTS5 index
/// over recognized handwriting text. This is the durability backbone behind
/// the data-model/store layer described in the architecture doc.
/// `DatabaseQueue` serializes all access internally, so sharing one instance
/// across threads is exactly its documented, intended usage.
final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    init(path: String? = nil) {
        let resolvedPath: String
        if let path {
            resolvedPath = path
        } else {
            let directory = try! FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            resolvedPath = directory.appendingPathComponent("Palimpsest.sqlite").path
        }

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbQueue = try! DatabaseQueue(path: resolvedPath, configuration: configuration)
        try! Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_core_schema") { db in
            try db.create(table: "notebook") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "section") { t in
                t.column("id", .text).primaryKey()
                t.column("notebookID", .text).notNull().indexed().references("notebook", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("orderIndex", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "page") { t in
                t.column("id", .text).primaryKey()
                t.column("sectionID", .text).notNull().indexed().references("section", onDelete: .cascade)
                t.column("backgroundData", .blob).notNull()
                t.column("objectIDsData", .blob).notNull()
                t.column("orderIndex", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "stroke") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("id", .text).notNull().unique()
                t.column("pageID", .text).notNull().indexed().references("page", onDelete: .cascade)
                t.column("pointsData", .blob).notNull()
                t.column("styleData", .blob).notNull()
                t.column("minX", .double).notNull()
                t.column("minY", .double).notNull()
                t.column("maxX", .double).notNull()
                t.column("maxY", .double).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // R-tree spatial index over stroke bounding boxes, keyed by the
            // same rowid as the `stroke` table — this is what makes viewport
            // and eraser-region queries fast regardless of page size.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE stroke_rtree USING rtree(
                    id, minX, maxX, minY, maxY
                )
                """)

            try db.create(table: "recognizedTextLine") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("id", .text).notNull().unique()
                t.column("pageID", .text).notNull().indexed().references("page", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("minX", .double).notNull()
                t.column("minY", .double).notNull()
                t.column("maxX", .double).notNull()
                t.column("maxY", .double).notNull()
                t.column("recognizedAt", .datetime).notNull()
            }

            // FTS5 full-text index over recognized handwriting, kept in sync
            // with `recognizedTextLine` via triggers (external-content table).
            try db.execute(sql: """
                CREATE VIRTUAL TABLE recognizedText_fts USING fts5(
                    text, content='recognizedTextLine', content_rowid='rowid'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER recognizedTextLine_ai AFTER INSERT ON recognizedTextLine BEGIN
                    INSERT INTO recognizedText_fts(rowid, text) VALUES (new.rowid, new.text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER recognizedTextLine_ad AFTER DELETE ON recognizedTextLine BEGIN
                    INSERT INTO recognizedText_fts(recognizedText_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER recognizedTextLine_au AFTER UPDATE ON recognizedTextLine BEGIN
                    INSERT INTO recognizedText_fts(recognizedText_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
                    INSERT INTO recognizedText_fts(rowid, text) VALUES (new.rowid, new.text);
                END
                """)
        }

        return migrator
    }
}
