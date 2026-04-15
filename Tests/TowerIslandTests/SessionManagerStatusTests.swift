import XCTest
import DIShared
@testable import TowerIsland

@MainActor
final class SessionManagerStatusTests: XCTestCase {
    func testCodexStatusUpdateDoesNotCompleteSessionWithoutSessionEnd() {
        let manager = SessionManager()

        var start = DIMessage(type: .sessionStart, sessionId: "codex-session")
        start.agentType = AgentType.codex.rawValue
        start.prompt = "Fix the bug"
        manager.handleMessage(start)

        guard let session = manager.sessions.first(where: { $0.id == "codex-session" }) else {
            XCTFail("Expected session to be created")
            return
        }

        var doneLikeStatus = DIMessage(type: .statusUpdate, sessionId: "codex-session")
        doneLikeStatus.agentType = AgentType.codex.rawValue
        doneLikeStatus.status = "Done"
        manager.handleMessage(doneLikeStatus)

        XCTAssertEqual(session.status, .active)
        XCTAssertTrue(manager.activeSessions.contains(where: { $0.id == session.id }))

        var followupThinking = DIMessage(type: .progress, sessionId: "codex-session")
        followupThinking.agentType = AgentType.codex.rawValue
        followupThinking.status = "Thinking about additional improvements"
        manager.handleMessage(followupThinking)

        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.statusText, "Thinking about additional improvements")
    }

    func testToolStartClearsPendingPermissionInteraction() {
        let manager = SessionManager()

        var start = DIMessage(type: .sessionStart, sessionId: "claude-perm")
        start.agentType = AgentType.claudeCode.rawValue
        manager.handleMessage(start)

        var permission = DIMessage(type: .permissionRequest, sessionId: "claude-perm")
        permission.agentType = AgentType.claudeCode.rawValue
        permission.tool = "Bash"
        permission.permDescription = "Run shell command"
        manager.handlePermissionRequest(permission, respond: { _ in })

        guard let session = manager.sessions.first(where: { $0.id == "claude-perm" }) else {
            XCTFail("Expected session to be created")
            return
        }
        XCTAssertEqual(session.status, .waitingPermission)
        XCTAssertNotNil(session.pendingPermission)

        var toolStart = DIMessage(type: .toolStart, sessionId: "claude-perm")
        toolStart.agentType = AgentType.claudeCode.rawValue
        toolStart.tool = "Bash"
        manager.handleMessage(toolStart)

        XCTAssertEqual(session.status, .active)
        XCTAssertNil(session.pendingPermission)
        XCTAssertEqual(session.currentTool, "Bash")
    }

    func testToolStartClearsPendingQuestionInteraction() {
        let manager = SessionManager()

        var start = DIMessage(type: .sessionStart, sessionId: "claude-question")
        start.agentType = AgentType.claudeCode.rawValue
        manager.handleMessage(start)

        var question = DIMessage(type: .question, sessionId: "claude-question")
        question.agentType = AgentType.claudeCode.rawValue
        question.questionText = "Continue?"
        question.options = ["yes", "no"]
        manager.handleQuestionRequest(question, respond: { _ in })

        guard let session = manager.sessions.first(where: { $0.id == "claude-question" }) else {
            XCTFail("Expected session to be created")
            return
        }
        XCTAssertEqual(session.status, .waitingAnswer)
        XCTAssertNotNil(session.pendingQuestion)

        var toolStart = DIMessage(type: .toolStart, sessionId: "claude-question")
        toolStart.agentType = AgentType.claudeCode.rawValue
        toolStart.tool = "Read"
        manager.handleMessage(toolStart)

        XCTAssertEqual(session.status, .active)
        XCTAssertNil(session.pendingQuestion)
        XCTAssertEqual(session.currentTool, "Read")
    }
}
