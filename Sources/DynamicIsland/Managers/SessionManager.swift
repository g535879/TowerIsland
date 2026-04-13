import Foundation
import Observation
import AppKit
import DIShared


@Observable
@MainActor
final class SessionManager {
    var sessions: [AgentSession] = []
    var selectedSessionId: String?
    var audioEngine: AudioEngine?
    /// Incremented to force SwiftUI to re-evaluate `visibleSessions` after linger expires.
    var visibleSessionsVersion: Int = 0
    private var cleanupTimer: Timer?
    private var workspaceObserver: Any?

    static let idleTimeout: TimeInterval = 120

    var completedLingerDuration: TimeInterval {
        let val = UserDefaults.standard.double(forKey: "completedLingerDuration")
        if val < 0 { return .infinity }
        return val > 0 ? val : 120
    }

    var activeSessions: [AgentSession] {
        sessions.filter { $0.status != .completed }
    }

    /// Active sessions + recently completed sessions that should still be visible in the pill.
    var visibleSessions: [AgentSession] {
        _ = visibleSessionsVersion
        let now = Date()
        return sessions.filter { session in
            if session.status != .completed { return true }
            guard let completedAt = session.completedAt else { return false }
            return now.timeIntervalSince(completedAt) < completedLingerDuration
        }
    }

    func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleSessions()
                self?.checkProcessesAlive()
            }
        }
        observeAppTermination()
    }

    // MARK: - Desktop App Termination

    private func observeAppTermination() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier else { return }
            Task { @MainActor in
                self?.handleAppTerminated(bundleId: bundleId)
            }
        }
    }

    private func handleAppTerminated(bundleId: String) {
        guard let agentType = AgentType.fromBundleId(bundleId) else { return }
        for session in activeSessions where session.agentType == agentType {
            markCompleted(session)
        }
        if let selectedSessionId, sessions.first(where: { $0.id == selectedSessionId })?.status == .completed {
            self.selectedSessionId = activeSessions.first?.id
        }
    }

    // MARK: - CLI Process Checking

    private func checkProcessesAlive() {
        let checks: [(AgentType, [String])] = activeSessions
            .filter { !$0.agentType.isDesktopApp && !$0.agentType.processNames.isEmpty }
            .reduce(into: [(AgentType, [String])]()) { result, session in
                if !result.contains(where: { $0.0 == session.agentType }) {
                    result.append((session.agentType, session.agentType.processNames))
                }
            }

        guard !checks.isEmpty else { return }

        Task.detached { [weak self] in
            var deadAgents: [AgentType] = []
            for (agentType, names) in checks {
                if let self, !self.isAnyProcessRunning(names: names) {
                    deadAgents.append(agentType)
                }
            }
            guard !deadAgents.isEmpty else { return }
            await MainActor.run {
                guard let self else { return }
                for agentType in deadAgents {
                    for session in self.activeSessions where session.agentType == agentType {
                        self.markCompleted(session)
                    }
                }
                if let sid = self.selectedSessionId,
                   self.sessions.first(where: { $0.id == sid })?.status == .completed {
                    self.selectedSessionId = self.activeSessions.first?.id
                }
            }
        }
    }

    private nonisolated func isAnyProcessRunning(names: [String]) -> Bool {
        for name in names {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-x", name]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 { return true }
            } catch {}
        }
        return false
    }

    private func cleanupStaleSessions() {
        let now = Date()
        for session in activeSessions {
            if (session.status == .active || session.status == .idle),
               now.timeIntervalSince(session.lastActivityTime) > Self.idleTimeout {
                markCompleted(session)
            }
        }
        if let selectedSessionId, sessions.first(where: { $0.id == selectedSessionId })?.status == .completed {
            self.selectedSessionId = activeSessions.first?.id
        }
    }

    var selectedSession: AgentSession? {
        guard let id = selectedSessionId else { return activeSessions.first }
        return sessions.first { $0.id == id }
    }

    var hasInteraction: Bool {
        activeSessions.contains {
            $0.status == .waitingPermission || $0.status == .waitingAnswer || $0.status == .waitingPlanReview
        }
    }

    func handleMessage(_ message: DIMessage) {
        switch message.type {
        case .sessionStart:
            startSession(message)
        case .sessionEnd:
            endSession(message)
        case .toolStart:
            handleToolStart(message)
        case .toolComplete:
            handleToolComplete(message)
        case .statusUpdate, .progress:
            handleStatus(message)
        case .subagentStart:
            handleSubagentStart(message)
        case .subagentEnd:
            handleSubagentEnd(message)
        case .contextCompact:
            handleContextCompact(message)
        default:
            break
        }
    }

    func handlePermissionRequest(_ message: DIMessage, respond: @escaping @Sendable (Bool) -> Void) {
        let realAgent = AgentType.from(message.agentType) ?? .claudeCode
        let session = findOrCreateSessionForInteraction(message)
        session.status = .waitingPermission
        session.pendingPermission = PendingPermission(
            requestingAgent: realAgent,
            tool: message.tool ?? "unknown",
            description: message.permDescription ?? "",
            diff: message.diff,
            filePath: message.filePath,
            respond: respond
        )
        selectedSessionId = session.id
        audioEngine?.play(.permissionRequest)
    }

    func handleQuestionRequest(_ message: DIMessage, respond: @escaping @Sendable (String) -> Void) {
        let realAgent = AgentType.from(message.agentType) ?? .claudeCode
        let session = findOrCreateSessionForInteraction(message)
        session.status = .waitingAnswer
        session.pendingQuestion = PendingQuestion(
            requestingAgent: realAgent,
            text: message.questionText ?? "",
            options: message.options ?? [],
            respond: respond
        )
        selectedSessionId = session.id
        audioEngine?.play(.question)
    }

    func handlePlanReview(_ message: DIMessage, respond: @escaping @Sendable (Bool, String?) -> Void) {
        let realAgent = AgentType.from(message.agentType) ?? .claudeCode
        let session = findOrCreateSessionForInteraction(message)
        session.status = .waitingPlanReview
        session.pendingPlanReview = PendingPlanReview(
            requestingAgent: realAgent,
            markdown: message.planMarkdown ?? "",
            respond: respond
        )
        selectedSessionId = session.id
        audioEngine?.play(.planReview)
    }

    func approvePermission(session: AgentSession) {
        session.pendingPermission?.respond(true)
        session.pendingPermission = nil
        session.status = .active
        audioEngine?.play(.approved)
    }

    func denyPermission(session: AgentSession) {
        session.pendingPermission?.respond(false)
        session.pendingPermission = nil
        session.status = .active
        audioEngine?.play(.denied)
    }

    func answerQuestion(session: AgentSession, answer: String) {
        session.pendingQuestion?.respond(answer)
        session.pendingQuestion = nil
        session.status = .active
        audioEngine?.play(.answered)
    }

    func respondToPlan(session: AgentSession, approved: Bool, feedback: String?) {
        session.pendingPlanReview?.respond(approved, feedback)
        session.pendingPlanReview = nil
        session.status = .active
        audioEngine?.play(approved ? .approved : .denied)
    }

    func dismissSession(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        if selectedSessionId == session.id {
            selectedSessionId = activeSessions.first?.id
        }
    }

    // MARK: - Private

    private func startSession(_ message: DIMessage) {
        let agentType = AgentType.from(message.agentType) ?? .claudeCode

        if let existing = sessions.first(where: { $0.id == message.sessionId }) {
            existing.lastActivityTime = Date()
            existing.status = .active
            existing.statusText = ""
            clearStaleInteraction(existing)
            if let t = message.terminal, !t.isEmpty { existing.terminal = t }
            if let w = message.workingDir, !w.isEmpty { existing.workingDirectory = w }
            if let p = message.prompt, !p.isEmpty {
                existing.prompt = p
                existing.chatHistory.append(ChatMessage(timestamp: Date(), role: .user, content: p))
                audioEngine?.play(.sessionStart)
            }
            if let ts = message.termSessionId, !ts.isEmpty { existing.termSessionId = ts }
            if existing.windowNumber == nil {
                existing.windowNumber = TerminalJumpManager.captureFrontWindowNumber(
                    for: existing.agentType, terminal: existing.terminal)
            }
            updateTokenUsage(session: existing, message: message)
            selectedSessionId = existing.id
            return
        }

        let session = AgentSession(
            id: message.sessionId,
            agentType: agentType,
            terminal: message.terminal ?? "",
            workingDirectory: message.workingDir ?? "",
            prompt: message.prompt ?? ""
        )
        session.termSessionId = message.termSessionId
        session.windowNumber = TerminalJumpManager.captureFrontWindowNumber(
            for: agentType, terminal: session.terminal)
        sessions.append(session)
        if !session.prompt.isEmpty {
            session.chatHistory.append(ChatMessage(timestamp: Date(), role: .user, content: session.prompt))
        }
        updateTokenUsage(session: session, message: message)
        selectedSessionId = session.id
        audioEngine?.play(.sessionStart)
    }

    private func endSession(_ message: DIMessage) {
        let agentType = AgentType.from(message.agentType) ?? .claudeCode

        guard let session = sessions.first(where: { $0.id == message.sessionId }) else { return }
        let alreadyCompleted = session.status == .completed
        updateTokenUsage(session: session, message: message)

        if let responseText = message.status, !responseText.isEmpty {
            session.agentResponse = responseText
            session.statusText = responseText
        }

        if !session.agentResponse.isEmpty {
            if let lastIdx = session.chatHistory.lastIndex(where: { $0.role == .assistant }) {
                session.chatHistory[lastIdx] = ChatMessage(
                    timestamp: Date(), role: .assistant, content: session.agentResponse
                )
            } else {
                session.chatHistory.append(
                    ChatMessage(timestamp: Date(), role: .assistant, content: session.agentResponse)
                )
            }
        }

        if !agentType.processNames.isEmpty {
            session.status = .idle
            session.currentTool = nil
            if session.statusText.isEmpty {
                session.statusText = "Done"
            }
            session.lastActivityTime = Date()
        } else {
            markCompleted(session)
        }
        if !alreadyCompleted {
            audioEngine?.play(.sessionEnd)
        }

        if session.status == .completed, selectedSessionId == session.id {
            selectedSessionId = activeSessions.first?.id
        }
    }

    private func markCompleted(_ session: AgentSession) {
        session.status = .completed
        session.currentTool = nil
        session.completedAt = Date()
        scheduleLingerCleanup()
    }

    private func scheduleLingerCleanup() {
        let linger = completedLingerDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + linger + 0.1) { [weak self] in
            guard let self else { return }
            self.visibleSessionsVersion += 1
            self.cleanupLingeredSessions()
        }
    }

    private func cleanupLingeredSessions() {
        let now = Date()
        sessions.removeAll { session in
            guard session.status == .completed, let completedAt = session.completedAt else { return false }
            return now.timeIntervalSince(completedAt) > completedLingerDuration + 5
        }
    }

    private func handleToolStart(_ message: DIMessage) {
        let session = findOrCreateSession(message)
        let event = ToolEvent(tool: message.tool ?? "unknown", input: message.toolInput)
        session.events.append(event)
        session.currentTool = message.tool
        audioEngine?.play(.toolStart)
    }

    private func handleToolComplete(_ message: DIMessage) {
        let session = findOrCreateSession(message)
        if let idx = session.events.lastIndex(where: { $0.tool == (message.tool ?? "") && !$0.isComplete }) {
            session.events[idx].result = message.toolResult
            session.events[idx].linesAdded = message.linesAdded
            session.events[idx].linesRemoved = message.linesRemoved
            session.events[idx].isComplete = true
        }
        session.currentTool = nil
        updateTokenUsage(session: session, message: message)
    }

    private func handleStatus(_ message: DIMessage) {
        let session = findOrCreateSession(message, reactivate: false)
        let text = message.status ?? ""
        session.statusText = text
        if !text.isEmpty {
            session.agentResponse = text
            if let lastIdx = session.chatHistory.lastIndex(where: { $0.role == .assistant }) {
                session.chatHistory[lastIdx] = ChatMessage(
                    timestamp: Date(), role: .assistant, content: text
                )
            } else {
                session.chatHistory.append(
                    ChatMessage(timestamp: Date(), role: .assistant, content: text)
                )
            }
        }

        let lower = text.lowercased()
        if lower.contains("compact") || lower.contains("context window") {
            audioEngine?.play(.contextCompacting)
        } else if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") {
            session.status = .error
            audioEngine?.play(.error)
        } else if !text.isEmpty && !session.agentType.sendsSessionEnd && !text.hasPrefix("{") {
            if session.status != .completed && session.status != .idle {
                markCompleted(session)
                audioEngine?.play(.sessionEnd)
            }
        }
        updateTokenUsage(session: session, message: message)
    }

    private func handleSubagentStart(_ message: DIMessage) {
        let parentId = message.parentSessionId ?? message.sessionId
        let matchAgent: (AgentSession) -> Bool = { session in
            guard let agent = message.agentType else { return false }
            return session.agentType.rawValue == agent
        }
        guard let parent = sessions.first(where: { $0.id == parentId && $0.status != .completed })
                ?? activeSessions.first(where: matchAgent) else { return }
        let subId = message.subagentId ?? UUID().uuidString
        if !parent.subagentIds.contains(subId) {
            parent.subagentIds.append(subId)
        }
        parent.lastActivityTime = Date()
        let event = ToolEvent(tool: "Subagent", input: message.prompt)
        parent.events.append(event)
    }

    private func handleSubagentEnd(_ message: DIMessage) {
        let parentId = message.parentSessionId ?? message.sessionId
        let matchAgent: (AgentSession) -> Bool = { session in
            guard let agent = message.agentType else { return false }
            return session.agentType.rawValue == agent
        }
        guard let parent = sessions.first(where: { $0.id == parentId && $0.status != .completed })
                ?? activeSessions.first(where: matchAgent) else { return }
        if let subId = message.subagentId {
            parent.subagentIds.removeAll { $0 == subId }
        }
        parent.lastActivityTime = Date()
        updateTokenUsage(session: parent, message: message)
        if let idx = parent.events.lastIndex(where: { $0.tool == "Subagent" && !$0.isComplete }) {
            parent.events[idx].isComplete = true
            parent.events[idx].result = "Completed"
        }
    }

    private func handleContextCompact(_ message: DIMessage) {
        let session = findOrCreateSession(message)
        session.status = .compacting
        session.statusText = message.status ?? "Context compacting..."
        audioEngine?.play(.contextCompacting)
        updateTokenUsage(session: session, message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if session.status == .compacting {
                session.status = .active
            }
        }
    }

    /// If the agent sent new activity while we were still showing a pending interaction,
    /// the interaction was handled externally (e.g. user responded in the terminal).
    private func clearStaleInteraction(_ session: AgentSession) {
        switch session.status {
        case .waitingPermission:
            session.pendingPermission = nil
            session.status = .active
        case .waitingAnswer:
            session.pendingQuestion = nil
            session.status = .active
        case .waitingPlanReview:
            session.pendingPlanReview = nil
            session.status = .active
        default:
            break
        }
    }

    private func updateTokenUsage(session: AgentSession, message: DIMessage) {
        if let t = message.tokensIn { session.tokenUsage.inputTokens += t }
        if let t = message.tokensOut { session.tokenUsage.outputTokens += t }
        if let t = message.totalTokens { session.tokenUsage.totalTokens = t }
        if let c = message.costUSD { session.tokenUsage.estimatedCostUSD += c }
        if let m = message.model, !m.isEmpty { session.tokenUsage.model = m }
    }

    /// For interactive requests (permission/question/plan), skip parentSession folding
    /// so the requesting agent keeps its own session and doesn't collide with Cursor activity.
    private func findOrCreateSessionForInteraction(_ message: DIMessage) -> AgentSession {
        let agentType = AgentType.from(message.agentType) ?? .claudeCode

        if let existing = sessions.first(where: { $0.id == message.sessionId && $0.status != .completed }) {
            existing.lastActivityTime = Date()
            return existing
        }
        if let sameAgent = activeSessions.first(where: { $0.agentType == agentType }) {
            sameAgent.lastActivityTime = Date()
            return sameAgent
        }
        if let completed = sessions.first(where: { $0.id == message.sessionId }) {
            completed.lastActivityTime = Date()
            completed.status = .active
            return completed
        }
        let session = AgentSession(
            id: message.sessionId,
            agentType: agentType,
            terminal: message.terminal ?? "",
            workingDirectory: message.workingDir ?? "",
            prompt: message.prompt ?? ""
        )
        sessions.append(session)
        return session
    }

    private func findOrCreateSession(_ message: DIMessage, reactivate: Bool = true) -> AgentSession {
        let agentType = AgentType.from(message.agentType) ?? .claudeCode

        if let existing = sessions.first(where: { $0.id == message.sessionId && $0.status != .completed }) {
            existing.lastActivityTime = Date()
            return existing
        }

        if let completed = sessions.first(where: { $0.id == message.sessionId }) {
            completed.lastActivityTime = Date()
            if reactivate { completed.status = .active }
            return completed
        }

        let session = AgentSession(
            id: message.sessionId,
            agentType: agentType,
            terminal: message.terminal ?? "",
            workingDirectory: message.workingDir ?? "",
            prompt: message.prompt ?? ""
        )
        sessions.append(session)
        return session
    }
}
