import SwiftUI

@main
struct WriteRightApp: App {
    init() {
        InjectionLoader.loadIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
