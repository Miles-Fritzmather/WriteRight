import Inject
import SwiftUI

/// App root: the home-screen library mockup, which presents the prototype
/// canvas editor full screen (`PrototypeEditorScreen`).
struct RootView: View {
    @ObserveInjection var inject

    var body: some View {
        PrototypeHomeScreen()
            .enableInjection()
    }
}
