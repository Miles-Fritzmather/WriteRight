import SwiftUI

struct NotebookListView: View {
    let repository: NotebookRepository

    @State private var path = NavigationPath()
    @State private var notebooks: [Notebook] = []
    @State private var showingSearch = false
    @State private var newNotebookTitle = ""
    @State private var showingNewNotebookPrompt = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(notebooks) { notebook in
                    NavigationLink(value: notebook) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notebook.title).font(.headline)
                            Text(notebook.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Palimpsest")
            .navigationDestination(for: Notebook.self) { notebook in
                NotebookDetailView(notebook: notebook, repository: repository)
            }
            .navigationDestination(for: Section.self) { section in
                SectionDetailView(section: section, repository: repository)
            }
            .navigationDestination(for: PageDestination.self) { destination in
                PageCanvasView(page: destination.page, repository: repository, focusOn: destination.focusCanvasPoint)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewNotebookPrompt = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .alert("New Notebook", isPresented: $showingNewNotebookPrompt) {
                TextField("Title", text: $newNotebookTitle)
                Button("Create", action: createNotebook)
                Button("Cancel", role: .cancel) { newNotebookTitle = "" }
            }
            .sheet(isPresented: $showingSearch) {
                SearchView(repository: repository) { destination in
                    showingSearch = false
                    path.append(destination)
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        notebooks = (try? repository.allNotebooks()) ?? []
    }

    private func createNotebook() {
        defer { newNotebookTitle = "" }
        guard !newNotebookTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        _ = try? repository.createNotebook(title: newNotebookTitle)
        reload()
    }
}
