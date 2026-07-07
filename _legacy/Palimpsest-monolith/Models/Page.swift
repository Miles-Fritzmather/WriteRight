import CoreGraphics
import Foundation

enum PageBackground: Codable, Hashable {
    case blank
    case ruled(lineSpacing: CGFloat)
    case grid(cellSize: CGFloat)
    case importedPDF(assetPath: String, pageIndex: Int)

    private enum Kind: String, Codable { case blank, ruled, grid, importedPDF }
    private enum CodingKeys: String, CodingKey { case kind, lineSpacing, cellSize, assetPath, pageIndex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .blank: self = .blank
        case .ruled: self = .ruled(lineSpacing: try c.decode(CGFloat.self, forKey: .lineSpacing))
        case .grid: self = .grid(cellSize: try c.decode(CGFloat.self, forKey: .cellSize))
        case .importedPDF:
            self = .importedPDF(
                assetPath: try c.decode(String.self, forKey: .assetPath),
                pageIndex: try c.decode(Int.self, forKey: .pageIndex)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .blank:
            try c.encode(Kind.blank, forKey: .kind)
        case .ruled(let spacing):
            try c.encode(Kind.ruled, forKey: .kind)
            try c.encode(spacing, forKey: .lineSpacing)
        case .grid(let cellSize):
            try c.encode(Kind.grid, forKey: .kind)
            try c.encode(cellSize, forKey: .cellSize)
        case .importedPDF(let path, let index):
            try c.encode(Kind.importedPDF, forKey: .kind)
            try c.encode(path, forKey: .assetPath)
            try c.encode(index, forKey: .pageIndex)
        }
    }
}

struct Page: Identifiable, Codable, Hashable {
    let id: UUID
    var sectionID: UUID
    var background: PageBackground
    var objectIDs: [UUID]
    var orderIndex: Int
    var createdAt: Date

    init(id: UUID = UUID(), sectionID: UUID, background: PageBackground = .blank, objectIDs: [UUID] = [], orderIndex: Int, createdAt: Date = Date()) {
        self.id = id
        self.sectionID = sectionID
        self.background = background
        self.objectIDs = objectIDs
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }
}

/// A recognized line of handwriting, with its canvas-space bounding box so a
/// search hit can pan the camera straight to it.
struct RecognizedTextLine: Identifiable, Codable, Equatable {
    let id: UUID
    var pageID: UUID
    var text: String
    var boundingBox: CGRect
    var recognizedAt: Date

    init(id: UUID = UUID(), pageID: UUID, text: String, boundingBox: CGRect, recognizedAt: Date = Date()) {
        self.id = id
        self.pageID = pageID
        self.text = text
        self.boundingBox = boundingBox
        self.recognizedAt = recognizedAt
    }
}
