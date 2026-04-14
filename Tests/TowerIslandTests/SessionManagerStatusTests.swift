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
}
