import SwiftUI

@main
struct PalimpsestApp: App {
    private let repository = NotebookRepository()

    var body: some Scene {
        WindowGroup {
            NotebookListView(repository: repository)
        }
    }
}
