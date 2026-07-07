import SwiftUI

/// Full-text search over recognized handwriting (FTS5-backed). Tapping a
/// result opens its page with the camera centered on that exact line.
struct SearchView: View {
    let repository: NotebookRepository
    let onSelect: (PageDestination) -> Void

    @State private var query = ""
    @State private var results: [NotebookRepository.SearchHit] = []

    var body: some View {
        NavigationStack {
            List(results, id: \.line.id) { hit in
                Button {
                    select(hit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.line.text)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        Text(hit.line.recognizedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "Search your handwriting" : "No results",
                        systemImage: "magnifyingglass"
                    )
                }
            }
            .searchable(text: $query, prompt: "Search handwriting")
            .onChange(of: query) { _, newValue in
                results = (try? repository.searchText(newValue)) ?? []
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func select(_ hit: NotebookRepository.SearchHit) {
        guard let page = try? repository.page(withID: hit.line.pageID) else { return }
        let focus = CGPoint(x: hit.line.boundingBox.midX, y: hit.line.boundingBox.midY)
        onSelect(PageDestination(page: page, focusCanvasPoint: focus))
    }
}
