import SwiftUI

enum AgentType: String, CaseIterable, Codable, Identifiable, Sendable {
    case claudeCode = "claude_code"
    case codex = "codex"
    case geminiCli = "gemini_cli"
    case cursor = "cursor"
    case trae = "trae"
    case openCode = "opencode"
    case droid = "droid"
    case qoder = "qoder"
    case copilot = "copilot"
    case codeBuddy = "code_buddy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCli: "Gemini CLI"
        case .cursor: "Cursor"
        case .trae: "Trae"
        case .openCode: "OpenCode"
        case .droid: "Droid"
        case .qoder: "Qoder"
        case .copilot: "Copilot"
        case .codeBuddy: "CodeBuddy"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .geminiCli: "Gemini"
        case .cursor: "Cursor"
        case .trae: "Trae"
        case .openCode: "OpenCode"
        case .droid: "Droid"
        case .qoder: "Qoder"
        case .copilot: "Copilot"
        case .codeBuddy: "CodeBuddy"
        }
    }

    var color: Color {
        switch self {
        case .claudeCode: Color(red: 0.85, green: 0.45, blue: 0.25)
        case .codex: Color(red: 0.2, green: 0.8, blue: 0.4)
        case .geminiCli: Color(red: 0.3, green: 0.5, blue: 0.95)
        case .cursor: Color(red: 0.6, green: 0.4, blue: 0.9)
        case .trae: Color(red: 0.2, green: 0.7, blue: 0.95)
        case .openCode: Color(red: 0.95, green: 0.7, blue: 0.2)
        case .droid: Color(red: 0.3, green: 0.85, blue: 0.8)
        case .qoder: Color(red: 0.9, green: 0.3, blue: 0.5)
        case .copilot: Color(red: 0.4, green: 0.7, blue: 0.9)
        case .codeBuddy: Color(red: 0.7, green: 0.9, blue: 0.3)
        }
    }

    var iconSymbol: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "terminal"
        case .geminiCli: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .trae: "sparkle.magnifyingglass"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .droid: "cpu"
        case .qoder: "qrcode"
        case .copilot: "airplane"
        case .codeBuddy: "person.2"
        }
    }

    var bundleId: String? {
        switch self {
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .trae: "com.trae.app"
        case .codex: "com.openai.codex"
        case .copilot: "com.microsoft.VSCode"
        default: nil
        }
    }

    var bundleIds: [String] {
        switch self {
        case .cursor:
            [
                "com.todesktop.230313mzl4w4u92", // Cursor
                "com.codeium.windsurf"           // Windsurf
            ]
        case .trae:
            [
                "com.trae.app",                  // Trae
                "cn.trae.app"                    // Trae CN
            ]
        case .codex:
            ["com.openai.codex"]
        case .copilot:
            ["com.microsoft.VSCode"]
        default:
            []
        }
    }

    var processNames: [String] {
        switch self {
        case .claudeCode: ["claude"]
        case .geminiCli: ["gemini"]
        case .openCode: ["opencode"]
        case .cursor: ["Cursor"]
        case .trae: ["Trae", "Trae CN"]
        case .codex: ["Codex"]
        case .copilot: ["Code"]
        default: []
        }
    }

    var isDesktopApp: Bool {
        switch self {
        case .cursor, .trae, .copilot: true
        default: false
        }
    }

    var sendsSessionEnd: Bool {
        switch self {
        case .codex, .openCode: false
        default: true
        }
    }

    static func from(_ string: String?) -> AgentType? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let lower = raw.lowercased()

        if let direct = AgentType(rawValue: lower) {
            return direct
        }

        if let byDisplay = AgentType.allCases.first(where: { $0.displayName.lowercased() == lower }) {
            return byDisplay
        }

        switch lower {
        case "claude", "claude-code", "claudecode":
            return .claudeCode
        case "codex-cli", "codex_cli":
            return .codex
        case "gemini", "gemini-cli", "gemini_cli":
            return .geminiCli
        case "open-code", "open_code":
            return .openCode
        case "code-buddy", "codebuddy":
            return .codeBuddy
        case "trae", "trae cn", "trae-cn", "traecn":
            return .trae
        case "windsurf":
            return .cursor
        default:
            break
        }

        if lower.contains("trae") {
            return .trae
        }
        if lower.contains("cursor") || lower.contains("windsurf") {
            return .cursor
        }
        if lower.contains("codex") {
            return .codex
        }
        if lower.contains("claude") {
            return .claudeCode
        }

        return nil
    }

    static func fromBundleId(_ bundleId: String) -> AgentType? {
        let lower = bundleId.lowercased()
        return allCases.first { $0.bundleIds.contains(where: { $0.lowercased() == lower }) }
    }
}
