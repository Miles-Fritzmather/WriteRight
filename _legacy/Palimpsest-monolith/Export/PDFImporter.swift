import Foundation
import PDFKit

/// Imports a PDF's pages as annotatable page backgrounds. The source file is
/// copied into app storage so the import survives the caller's URL access
/// scope ending (share sheet / file picker URLs are often transient).
enum PDFImporter {
    enum ImportError: Error {
        case invalidPDF
    }

    static func importPages(from sourceURL: URL, into section: Section, repository: NotebookRepository) throws -> [Page] {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: sourceURL) else { throw ImportError.invalidPDF }

        let importsDirectory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)

        let destination = importsDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let startIndex = try repository.pages(in: section).count
        var createdPages: [Page] = []
        for index in 0..<document.pageCount {
            let page = try repository.createPage(
                in: section,
                orderIndex: startIndex + index,
                background: .importedPDF(assetPath: destination.path, pageIndex: index)
            )
            createdPages.append(page)
        }
        return createdPages
    }
}
