import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!
    let sessionManager = SessionManager()
    let audioEngine = AudioEngine()
    private var socketServer: SocketServer?
    private var notchWindow: NotchWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: [
            "showOnAllSpaces": true,
            "autoCollapseDelay": 3.0,
            "smartSuppression": true,
            "compactBadgesInExpandedView": true,
            "displayTimestamp": true,
            "completedLingerDuration": 120.0,
        ])

        sessionManager.audioEngine = audioEngine
        setupNotchWindow()
        setupMenuBarItem()
        startSocketServer()
        sessionManager.startCleanupTimer()
        ZeroConfigManager.configureAllAgents()

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            ZeroConfigManager.repairHooksIfNeeded()
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.notchWindow?.applySpaceBehavior()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    private static func hasNotch() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        if #available(macOS 14.0, *) {
            return screen.safeAreaInsets.top > 0
        }
        return false
    }

    private func setupNotchWindow() {
        let window = NotchWindow()
        let hostView = FirstMouseHostingView(
            rootView: NotchContentView(onSizeChange: { [weak window] w, h, display in
                window?.resizeToFit(contentWidth: w, contentHeight: h, display: display)
            })
            .environment(sessionManager)
            .environment(audioEngine)
        )
        hostView.frame = window.contentView!.bounds
        hostView.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hostView.sizingOptions = []
        }
        window.contentView?.addSubview(hostView)
        if !Self.hasNotch() {
            let screen = NotchWindow.bestScreen()
            let w: CGFloat = 200
            let h: CGFloat = 48
            let x = screen.frame.origin.x + screen.frame.width - w - 20
            let y = screen.frame.origin.y + screen.frame.height - h
            window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }
        window.orderFrontRegardless()
        notchWindow = window
    }

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Tower Island")
            button.action = #selector(toggleNotch)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Island", action: #selector(showNotch), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Configure Agents...", action: #selector(reconfigure), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func startSocketServer() {
        socketServer = SocketServer(sessionManager: sessionManager)
        socketServer?.start()
    }

    @objc private func toggleNotch() {
        if let w = notchWindow {
            w.isVisible ? w.orderOut(nil) : w.orderFrontRegardless()
        }
    }

    @objc private func showNotch() {
        notchWindow?.orderFrontRegardless()
    }

    @objc private func reconfigure() {
        ZeroConfigManager.configureAllAgents()
    }

    @objc func openPreferences() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Tower Island Settings"
        w.center()
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(
            rootView: PreferencesView()
                .environment(sessionManager)
                .environment(audioEngine)
        )

        settingsWindow = w
        w.level = .statusBar + 2
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(previousPolicy)
            self?.settingsWindow = nil
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
