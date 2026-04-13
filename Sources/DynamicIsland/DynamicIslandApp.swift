import SwiftUI

@main
struct TowerIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window is managed by AppDelegate.openPreferences()
        Settings { EmptyView() }
    }
}
