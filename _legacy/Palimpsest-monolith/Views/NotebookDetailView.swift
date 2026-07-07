import SwiftUI

struct NotebookDetailView: View {
    let notebook: Notebook
    let repository: NotebookRepository

    @State private var sections: [Section] = []
    @State private var newSectionTitle = ""
    @State private var showingNewSectionPrompt = false

    var body: some View {
        List {
            ForEach(sections) { section in
                NavigationLink(value: section) {
                    Text(section.title).font(.headline)
                }
            }
        }
        .navigationTitle(notebook.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewSectionPrompt = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Section", isPresented: $showingNewSectionPrompt) {
            TextField("Title", text: $newSectionTitle)
            Button("Create", action: createSection)
            Button("Cancel", role: .cancel) { newSectionTitle = "" }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        sections = (try? repository.sections(in: notebook)) ?? []
    }

    private func createSection() {
        defer { newSectionTitle = "" }
        guard !newSectionTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        _ = try? repository.createSection(title: newSectionTitle, in: notebook, orderIndex: sections.count)
        reload()
    }
}
