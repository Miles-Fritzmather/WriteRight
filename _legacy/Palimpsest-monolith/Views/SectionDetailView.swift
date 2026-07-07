import SwiftUI
import UniformTypeIdentifiers

struct SectionDetailView: View {
    let section: Section
    let repository: NotebookRepository

    @State private var pages: [Page] = []
    @State private var showingImporter = false
    @State private var exportURL: IdentifiableURL?
    @State private var isExporting = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(pages) { page in
                    NavigationLink(value: PageDestination(page: page)) {
                        VStack(spacing: 6) {
                            PageThumbnailView(page: page, repository: repository)
                            Text("Page \(page.orderIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(section.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Blank Page", systemImage: "doc.badge.plus", action: addBlankPage)
                    Button("Import PDF…", systemImage: "square.and.arrow.down", action: { showingImporter = true })
                    Button("Export Section as PDF", systemImage: "square.and.arrow.up", action: exportSection)
                        .disabled(isExporting || pages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                importPDF(from: url)
            }
        }
        .sheet(item: $exportURL) { identifiable in
            ShareSheet(activityItems: [identifiable.url])
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        pages = (try? repository.pages(in: section)) ?? []
    }

    private func addBlankPage() {
        _ = try? repository.createPage(in: section, orderIndex: pages.count)
        reload()
    }

    private func importPDF(from url: URL) {
        _ = try? PDFImporter.importPages(from: url, into: section, repository: repository)
        reload()
    }

    private func exportSection() {
        isExporting = true
        let pagesSnapshot = pages
        let repo = repository
        Task {
            let rendered: [(strokes: [Stroke], text: [RecognizedTextLine])] = pagesSnapshot.map { page in
                let strokes = (try? repo.allStrokes(onPage: page.id)) ?? []
                let text = (try? repo.recognizedTextLines(forPage: page.id)) ?? []
                return (strokes, text)
            }
            let data = PDFExporter.exportNotebook(pages: rendered)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(section.title)-\(UUID().uuidString).pdf")
            try? data.write(to: url)
            isExporting = false
            exportURL = IdentifiableURL(url: url)
        }
    }
}
