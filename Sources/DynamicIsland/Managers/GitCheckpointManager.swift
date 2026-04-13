import Foundation

enum GitCheckpointManager {
    static func createCheckpoint(for session: AgentSession, message: String? = nil) -> GitCheckpoint? {
        let dir = session.workingDirectory
        guard !dir.isEmpty else { return nil }

        let commitMsg = message ?? "checkpoint: \(session.agentType.shortName) @ \(ISO8601DateFormatter().string(from: Date()))"

        let stashResult = runGit(in: dir, args: ["stash", "push", "-m", commitMsg, "--include-untracked"])
        guard stashResult != nil else { return nil }

        let hashResult = runGit(in: dir, args: ["stash", "list", "--format=%H", "-1"])
        let hash = hashResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        return GitCheckpoint(timestamp: Date(), hash: String(hash.prefix(8)), message: commitMsg)
    }

    static func restoreCheckpoint(_ checkpoint: GitCheckpoint, in directory: String) -> Bool {
        let listResult = runGit(in: directory, args: ["stash", "list", "--format=%H %s"])
        guard let list = listResult else { return false }

        let lines = list.split(separator: "\n")
        for (index, line) in lines.enumerated() {
            if line.contains(checkpoint.message) {
                let result = runGit(in: directory, args: ["stash", "pop", "stash@{\(index)}"])
                return result != nil
            }
        }
        return false
    }

    private static func runGit(in directory: String, args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            }
        } catch {}
        return nil
    }
}
