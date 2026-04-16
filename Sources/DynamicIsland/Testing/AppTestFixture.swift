import Foundation

struct AppTestFixture: Codable {
    let selectedSessionId: String?
    let sessions: [SessionFixture]
    let update: UpdateFixture?

    struct SessionFixture: Codable {
        let id: String
        let agentType: AgentType
        let terminal: String?
        let workingDirectory: String?
        let prompt: String?
        let status: SessionStatus
        let statusText: String?
        let agentResponse: String?
        let completedAt: Date?
        let pendingPermission: PendingPermissionFixture?
        let pendingQuestion: PendingQuestionFixture?
        let pendingPlanReview: PendingPlanReviewFixture?
    }

    struct PendingPermissionFixture: Codable {
        let requestingAgent: AgentType
        let tool: String
        let description: String
        let filePath: String?
        let diff: String?
    }

    struct PendingQuestionFixture: Codable {
        let requestingAgent: AgentType
        let text: String
        let options: [String]
    }

    struct PendingPlanReviewFixture: Codable {
        let requestingAgent: AgentType
        let markdown: String
    }

    struct UpdateFixture: Codable {
        let state: State
        let release: UpdateManager.ReleaseInfo?
        let version: String?
        let stage: String?
        let message: String?

        enum State: String, Codable {
            case idle
            case checking
            case upToDate
            case updateAvailable
            case installing
            case failed
        }
    }
}
