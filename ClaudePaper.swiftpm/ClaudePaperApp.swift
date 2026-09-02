import SwiftUI

@main
struct ClaudePaperApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = SessionStore()
    @StateObject private var library = SymbolLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(library)
        }
    }
}
