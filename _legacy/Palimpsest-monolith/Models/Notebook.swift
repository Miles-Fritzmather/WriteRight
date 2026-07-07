import Foundation

struct Section: Identifiable, Codable, Hashable {
    let id: UUID
    var notebookID: UUID
    var title: String
    var orderIndex: Int
    var createdAt: Date

    init(id: UUID = UUID(), notebookID: UUID, title: String, orderIndex: Int, createdAt: Date = Date()) {
        self.id = id
        self.notebookID = notebookID
        self.title = title
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }
}

struct Notebook: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
