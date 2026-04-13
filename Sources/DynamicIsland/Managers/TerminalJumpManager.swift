import AppKit

enum TerminalApp: String, CaseIterable {
    case iterm2 = "iTerm2"
    case terminal = "Terminal"
    case ghostty = "Ghostty"
    case warp = "Warp"
    case alacritty = "Alacritty"
    case kitty = "Kitty"
    case vscode = "Visual Studio Code"
    case cursor = "Cursor"
    case windsurf = "Windsurf"
    case codex = "Codex"

    var bundleId: String {
        switch self {
        case .iterm2: "com.googlecode.iterm2"
        case .terminal: "com.apple.Terminal"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        case .alacritty: "org.alacritty"
        case .kitty: "net.kovidgoyal.kitty"
        case .vscode: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .windsurf: "com.codeium.windsurf"
        case .codex: "com.openai.codex"
        }
    }

    var aliases: [String] {
        switch self {
        case .iterm2: ["iterm2", "iterm.app", "iterm"]
        case .terminal: ["terminal", "apple_terminal"]
        case .ghostty: ["ghostty"]
        case .warp: ["warp"]
        case .alacritty: ["alacritty"]
        case .kitty: ["kitty"]
        case .vscode: ["visual studio code", "vscode", "code"]
        case .cursor: ["cursor"]
        case .windsurf: ["windsurf"]
        case .codex: ["codex"]
        }
    }

    static func detect(from name: String) -> TerminalApp? {
        let lower = name.lowercased()
        return allCases.first { app in
            app.aliases.contains(where: { lower.contains($0) })
                || lower.contains(app.bundleId.lowercased())
        }
    }

    static func forAgent(_ agentType: AgentType) -> TerminalApp? {
        switch agentType {
        case .cursor: return .cursor
        case .codex: return .codex
        case .copilot: return .vscode
        case .claudeCode, .geminiCli, .openCode, .droid, .qoder, .codeBuddy:
            return nil
        }
    }
}

enum TerminalJumpManager {
    static func jump(to session: AgentSession) {
        let targetApp: TerminalApp? = TerminalApp.forAgent(session.agentType)
            ?? (session.terminal.isEmpty ? nil : TerminalApp.detect(from: session.terminal))

        if let app = targetApp {
            if let tsid = session.termSessionId, !tsid.isEmpty, app == .iterm2 {
                jumpToITermSession(termSessionId: tsid)
                return
            }
            if raiseMatchingWindow(session: session, bundleId: app.bundleId) {
                return
            }
            activateApp(app)
            return
        }

        activateByAgentName(session.agentType)
    }

    private static func jumpToITermSession(termSessionId: String) {
        let matchProp: String
        let matchValue: String

        if termSessionId.hasPrefix("iterm:") {
            matchProp = "unique ID"
            let fullId = String(termSessionId.dropFirst(6))
            if let colonIdx = fullId.firstIndex(of: ":") {
                matchValue = String(fullId[fullId.index(after: colonIdx)...])
            } else {
                matchValue = fullId
            }
        } else if termSessionId.hasPrefix("tty:") {
            matchProp = "tty"
            matchValue = String(termSessionId.dropFirst(4))
        } else {
            matchProp = "unique ID"
            matchValue = termSessionId
        }

        let script = """
        tell application "iTerm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if \(matchProp) of aSession is "\(matchValue)" then
                            select aTab
                            set index of aWindow to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """
        runAppleScript(script)
    }

    private static func raiseMatchingWindow(session: AgentSession, bundleId: String) -> Bool {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return false
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            runningApp.activate()
            return true
        }

        if let targetWid = session.windowNumber {
            for window in windows {
                var pidRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, "_AXWindowNumber" as CFString, &pidRef) == .success,
                   let num = pidRef as? Int, num == targetWid {
                    AXUIElementPerformAction(window, "AXRaise" as CFString)
                    runningApp.activate()
                    return true
                }
            }
        }

        let folderName = (session.workingDirectory as NSString).lastPathComponent
        if !folderName.isEmpty {
            for window in windows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, "AXTitle" as CFString, &titleRef) == .success,
                   let title = titleRef as? String,
                   title.localizedCaseInsensitiveContains(folderName) {
                    AXUIElementPerformAction(window, "AXRaise" as CFString)
                    runningApp.activate()
                    return true
                }
            }
        }

        runningApp.activate()
        return true
    }

    // MARK: - tmux

    private static func jumpToTmuxSession(session: AgentSession, app: TerminalApp) {
        let dir = session.workingDirectory
        guard !dir.isEmpty else { return }

        let script: String
        switch app {
        case .iterm2:
            script = """
            tell application "iTerm2"
                activate
                tell current window
                    repeat with aTab in tabs
                        repeat with aSession in sessions of aTab
                            if name of aSession contains "\(dir)" then
                                select aTab
                                select aSession
                                return
                            end if
                        end repeat
                    end repeat
                end tell
            end tell
            """
        default:
            return
        }
        runAppleScript(script)
    }

    static func captureFrontWindowNumber(for agentType: AgentType, terminal: String) -> Int? {
        let bundleId: String?
        if let app = TerminalApp.forAgent(agentType) {
            bundleId = app.bundleId
        } else if !terminal.isEmpty, let app = TerminalApp.detect(from: terminal) {
            bundleId = app.bundleId
        } else {
            bundleId = nil
        }
        guard let bid = bundleId,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else {
            return nil
        }
        let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == app.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? Int else { continue }
            return wid
        }
        return nil
    }

    // MARK: - Helpers

    private static func activateApp(_ app: TerminalApp) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func activateByAgentName(_ agentType: AgentType) {
        let name = agentType.displayName.lowercased()
        let apps = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: {
            guard let appName = $0.localizedName?.lowercased() else { return false }
            return appName.contains(name) || name.contains(appName)
        }) {
            app.activate()
        }
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
            }
        }
    }
}
