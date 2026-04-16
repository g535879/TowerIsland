import AppKit
import Foundation
import DIShared

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

    var bundleIds: [String] {
        switch self {
        case .iterm2: ["com.googlecode.iterm2"]
        case .terminal: ["com.apple.Terminal"]
        case .ghostty: ["com.mitchellh.ghostty"]
        case .warp: ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .alacritty: ["org.alacritty"]
        case .kitty: ["net.kovidgoyal.kitty"]
        case .vscode: ["com.microsoft.VSCode"]
        case .cursor: ["com.todesktop.230313mzl4w4u92"]
        case .windsurf: ["com.codeium.windsurf"]
        case .codex: ["com.openai.codex"]
        }
    }

    var bundleId: String {
        bundleIds[0]
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

        if lower.contains("warp") { return .warp }
        if lower.contains("iterm") { return .iterm2 }
        if lower.contains("ghostty") { return .ghostty }
        if lower.contains("alacritty") { return .alacritty }
        if lower.contains("kitty") { return .kitty }
        if lower.contains("apple_terminal") || lower == "terminal" || lower.contains("com.apple.terminal") {
            return .terminal
        }

        return allCases.first { app in
            app.aliases.contains(where: { lower.contains($0) })
                || app.bundleIds.contains(where: { lower.contains($0.lowercased()) })
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
    static func jump(to session: AgentSession) -> Bool {
        let detectedApp: TerminalApp? = session.terminal.isEmpty ? nil : TerminalApp.detect(from: session.terminal)
        let agentPreferredApp = TerminalApp.forAgent(session.agentType)

        let targetApp: TerminalApp?
        if session.agentType == .cursor {
            let termSessionId = session.termSessionId ?? ""
            let isCursorIDE = detectedApp == .cursor
                || (detectedApp == .terminal && termSessionId.isEmpty)
            targetApp = isCursorIDE ? .cursor : (detectedApp ?? agentPreferredApp)
        } else {
            targetApp = detectedApp ?? agentPreferredApp
        }

        if let app = targetApp {
            if let tsid = session.termSessionId, !tsid.isEmpty, app == .iterm2 {
                jumpToITermSession(termSessionId: tsid)
                return true
            }
            if app == .terminal, jumpToTerminalWindow(session: session) {
                return true
            }
            if raiseMatchingWindow(session: session, app: app) {
                return true
            }
            activateApp(app)
            return app != .warp
        }

        activateByAgentName(session.agentType)
        return true
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

    private static func jumpToTerminalWindow(session: AgentSession) -> Bool {
        let folderName = (session.workingDirectory as NSString).lastPathComponent
        let escapedFolder = folderName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let hasWindowId = session.windowNumber != nil
        guard hasWindowId || !folderName.isEmpty else { return false }

        let commands: [String] = {
            if let wid = session.windowNumber {
                return [
                    "repeat with w in windows",
                    "if id of w is \(wid) then",
                    "set index of w to 1",
                    "activate",
                    "return true",
                    "end if",
                    "end repeat"
                ]
            }
            return [
                "repeat with w in windows",
                "repeat with t in tabs of w",
                "set tn to custom title of t",
                "if tn is missing value then set tn to \"\"",
                "set tname to (tn as text)",
                "if tname contains \"\(escapedFolder)\" then",
                "set selected tab of w to t",
                "set index of w to 1",
                "activate",
                "return true",
                "end if",
                "end repeat",
                "end repeat"
            ]
        }()

        let script = """
        tell application \"Terminal\"
            \(commands.joined(separator: "\n            "))
            return false
        end tell
        """

        return runAppleScriptBool(script)
    }

    private static func raiseMatchingWindow(session: AgentSession, app: TerminalApp) -> Bool {
        let runningApps = app.bundleIds
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard let runningApp = runningApps.first else {
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
            if let matchedWindow = matchAXWindowByWindowNumber(windows: windows, windowNumber: targetWid)
                ?? matchAXWindowByWindowTitle(windows: windows, title: windowTitle(for: targetWid)) {
                AXUIElementPerformAction(matchedWindow, "AXRaise" as CFString)
                runningApp.activate()
                return true
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
        let targetApp: TerminalApp?
        if let app = TerminalApp.forAgent(agentType) {
            targetApp = app
        } else if !terminal.isEmpty, let app = TerminalApp.detect(from: terminal) {
            targetApp = app
        } else {
            targetApp = nil
        }

        guard let targetApp else { return nil }
        let runningApps = targetApp.bundleIds
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard let app = runningApps.first else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let focusedWindowRef {
            let focusedWindow = unsafeBitCast(focusedWindowRef, to: AXUIElement.self)
            var numberRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedWindow, "_AXWindowNumber" as CFString, &numberRef) == .success,
               let windowNumber = numberRef as? Int {
                return windowNumber
            }
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

    private static func matchAXWindowByWindowNumber(windows: [AXUIElement], windowNumber: Int) -> AXUIElement? {
        for window in windows {
            var numberRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "_AXWindowNumber" as CFString, &numberRef) == .success,
               let num = numberRef as? Int,
               num == windowNumber {
                return window
            }
        }
        return nil
    }

    private static func matchAXWindowByWindowTitle(windows: [AXUIElement], title: String?) -> AXUIElement? {
        guard let title, !title.isEmpty else { return nil }
        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXTitle" as CFString, &titleRef) == .success,
               let axTitle = titleRef as? String,
               (axTitle == title || axTitle.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains(axTitle)) {
                return window
            }
        }
        return nil
    }

    private static func windowTitle(for windowNumber: Int) -> String? {
        let options = CGWindowListOption([.optionAll])
        guard let list = CGWindowListCopyWindowInfo(options, CGWindowID(windowNumber)) as? [[String: Any]],
              let info = list.first else {
            return nil
        }
        return info[kCGWindowName as String] as? String
    }

    private static func activateApp(_ app: TerminalApp) {
        let runningApps = app.bundleIds
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        if let running = runningApps.first {
            running.activate(options: [.activateAllWindows])
            return
        }

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

    private static func runAppleScriptBool(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil { return false }
        return output.booleanValue
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runAppleScriptBool(source)
        }
    }
}
