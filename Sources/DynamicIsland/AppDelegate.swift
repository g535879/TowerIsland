import AppKit
import Darwin
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!
    /// Set when this process lost the single-instance lock and is about to exit; skip normal startup.
    private static var exitingAsDuplicateInstance = false
    private static var singleInstanceLockFD: Int32 = -1

    let sessionManager = SessionManager()
    let audioEngine = AudioEngine()
    let updateManager = UpdateManager()
    private var socketServer: SocketServer?
    private var notchWindow: NotchWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var checkForUpdatesMenuItem: NSMenuItem?
    private var installUpdateMenuItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !Self.acquireSingleInstanceLock() {
            Self.exitingAsDuplicateInstance = true
            Self.activateOtherInstancesOfThisApp()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.exitingAsDuplicateInstance else { return }
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
        observeUpdateState()
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
            Task { @MainActor [weak self] in
                self?.notchWindow?.applySpaceBehavior()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    private func setupNotchWindow() {
        let window = NotchWindow()
        let hostView = FirstMouseHostingView(
            rootView: NotchContentView(onSizeChange: { [weak window] w, h, display in
                window?.resizeToFit(contentWidth: w, contentHeight: h, display: display)
            })
            .environment(sessionManager)
            .environment(audioEngine)
            .environment(updateManager)
        )
        hostView.frame = window.contentView!.bounds
        hostView.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hostView.sizingOptions = []
        }
        window.contentView?.addSubview(hostView)
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
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        let installUpdateItem = NSMenuItem(
            title: "Install Update...",
            action: #selector(installUpdateFromMenu),
            keyEquivalent: ""
        )
        installUpdateItem.isHidden = true
        menu.addItem(checkForUpdatesItem)
        menu.addItem(installUpdateItem)
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
        checkForUpdatesMenuItem = checkForUpdatesItem
        installUpdateMenuItem = installUpdateItem
        refreshUpdateMenuState()
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

    @objc private func checkForUpdatesFromMenu() {
        Task { @MainActor in
            await updateManager.checkForUpdates()
        }
    }

    @objc private func installUpdateFromMenu() {
        Task { @MainActor in
            await updateManager.installUpdate()
        }
    }

    @objc func openPreferences() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.isFloatingPanel = true
        w.hidesOnDeactivate = false
        w.title = "Tower Island Settings"
        if let screen = notchWindow?.screen ?? NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.origin.x + (sf.width - 680) / 2
            let y = sf.origin.y + (sf.height - 480) / 2
            w.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            w.center()
        }
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(
            rootView: PreferencesView()
                .environment(sessionManager)
                .environment(audioEngine)
                .environment(updateManager)
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
            Task { @MainActor [weak self] in
                NSApp.setActivationPolicy(previousPolicy)
                self?.settingsWindow = nil
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Returns false if another instance is already running (exclusive lock held).
    private static func acquireSingleInstanceLock() -> Bool {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".tower-island")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("instance.lock")
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        singleInstanceLockFD = fd
        return true
    }

    private static func activateOtherInstancesOfThisApp() {
        guard let bid = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in others {
            app.activate(options: [.activateAllWindows])
        }
    }

    private func observeUpdateState() {
        withObservationTracking {
            _ = updateManager.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshUpdateMenuState()
                self?.observeUpdateState()
            }
        }

        withObservationTracking {
            _ = updateManager.latestRelease
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshUpdateMenuState()
                self?.observeUpdateState()
            }
        }
    }

    private func refreshUpdateMenuState() {
        let imageName: String

        switch updateManager.state {
        case .updateAvailable(let version):
            checkForUpdatesMenuItem?.title = "Update Available: \(version)"
            checkForUpdatesMenuItem?.isEnabled = true
            installUpdateMenuItem?.title = "Install \(version)..."
            installUpdateMenuItem?.isHidden = false
            installUpdateMenuItem?.isEnabled = true
            imageName = "arrow.down.circle.fill"
        case .checking:
            checkForUpdatesMenuItem?.title = "Checking for Updates..."
            checkForUpdatesMenuItem?.isEnabled = false
            installUpdateMenuItem?.isHidden = true
            imageName = "arrow.triangle.2.circlepath.circle"
        case .installing(let stage):
            checkForUpdatesMenuItem?.title = "Installing Update (\(stage))..."
            checkForUpdatesMenuItem?.isEnabled = false
            installUpdateMenuItem?.isHidden = true
            imageName = "arrow.down.circle.fill"
        case .upToDate:
            checkForUpdatesMenuItem?.title = "Up to Date"
            checkForUpdatesMenuItem?.isEnabled = true
            installUpdateMenuItem?.isHidden = true
            imageName = "sparkle"
        case .failed:
            checkForUpdatesMenuItem?.title = "Check for Updates..."
            checkForUpdatesMenuItem?.isEnabled = true
            installUpdateMenuItem?.isHidden = updateManager.latestRelease?.dmgURL == nil
            installUpdateMenuItem?.title = "Install Update..."
            installUpdateMenuItem?.isEnabled = updateManager.latestRelease?.dmgURL != nil
            imageName = "exclamationmark.circle"
        case .idle:
            checkForUpdatesMenuItem?.title = "Check for Updates..."
            checkForUpdatesMenuItem?.isEnabled = true
            if let version = updateManager.latestRelease?.normalizedVersion,
               updateManager.latestRelease?.dmgURL != nil,
               UpdateManager.isRemoteVersionNewer(version, than: updateManager.currentVersion) {
                installUpdateMenuItem?.title = "Install \(version)..."
                installUpdateMenuItem?.isHidden = false
                installUpdateMenuItem?.isEnabled = true
                imageName = "arrow.down.circle.fill"
            } else {
                installUpdateMenuItem?.isHidden = true
                imageName = "sparkle"
            }
        }

        statusItem?.button?.image = NSImage(
            systemSymbolName: imageName,
            accessibilityDescription: "Tower Island"
        )
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
