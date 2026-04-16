import SwiftUI

@main
struct TowerIslandApp: App {
    private let testConfiguration = AppTestConfiguration.current()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window is managed by AppDelegate.openPreferences()
        Settings { EmptyView() }
    }
}
