import SwiftUI

enum AgentType: String, CaseIterable, Codable, Identifiable, Sendable {
    case claudeCode = "claude_code"
    case codex = "codex"
    case geminiCli = "gemini_cli"
    case cursor = "cursor"
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
        case .codex: "com.openai.codex"
        case .copilot: "com.microsoft.VSCode"
        default: nil
        }
    }

    var processNames: [String] {
        switch self {
        case .claudeCode: ["claude"]
        case .geminiCli: ["gemini"]
        case .openCode: ["opencode"]
        case .cursor: ["Cursor"]
        case .codex: ["Codex"]
        case .copilot: ["Code"]
        default: []
        }
    }

    var isDesktopApp: Bool {
        switch self {
        case .cursor, .copilot: true
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
        guard let string else { return nil }
        return AgentType(rawValue: string)
            ?? AgentType.allCases.first { $0.displayName.lowercased() == string.lowercased() }
    }

    static func fromBundleId(_ bundleId: String) -> AgentType? {
        allCases.first { $0.bundleId == bundleId }
    }
}
