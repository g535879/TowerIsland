import Foundation

struct ToolEvent: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let tool: String
    let input: String?
    var result: String?
    var linesAdded: Int?
    var linesRemoved: Int?
    var isComplete: Bool

    var displayName: String {
        switch tool.lowercased() {
        case "read", "readfile": "Read"
        case "write", "writefile": "Write"
        case "edit", "editfile", "str_replace": "Edit"
        case "bash", "shell", "terminal": "Bash"
        case "search", "grep", "ripgrep": "Search"
        case "glob", "find": "Find"
        case "ls", "list": "List"
        default: tool.prefix(1).uppercased() + tool.dropFirst()
        }
    }

    var summary: String {
        if let path = input, path.contains("/") {
            let file = (path as NSString).lastPathComponent
            if isComplete {
                if let added = linesAdded, let removed = linesRemoved {
                    return "\(file) (+\(added) -\(removed))"
                }
                if let result, !result.isEmpty {
                    let bytes = result.utf8.count
                    return "\(file) (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
                }
                return "\(file) done"
            }
            return file
        }
        return isComplete ? "Done" : "Running..."
    }

    init(tool: String, input: String? = nil, result: String? = nil,
         linesAdded: Int? = nil, linesRemoved: Int? = nil, isComplete: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.tool = tool
        self.input = input
        self.result = result
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.isComplete = isComplete
    }
}
