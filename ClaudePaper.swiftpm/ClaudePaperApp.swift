import SwiftUI

@main
struct ClaudePaperApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
        }
    }
}
