import Foundation

enum InjectionLoader {
    /// Debug-only hot reload (SPEC §11).
    /// - Simulator: loads the classic InjectionIII client bundle when that
    ///   app is installed on the Mac.
    /// - Physical device: the linked InjectionNext client package (DEBUG
    ///   builds only) starts itself and connects to the InjectionNext Mac
    ///   app over the local network — nothing to load here.
    /// Both paths are inert when the Mac-side app isn't running.
    static func loadIfAvailable() {
        #if DEBUG && targetEnvironment(simulator)
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
        #endif
    }
}
