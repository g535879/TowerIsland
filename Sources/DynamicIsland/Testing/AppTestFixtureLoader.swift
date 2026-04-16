import Foundation

@MainActor
enum AppTestFixtureLoader {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func defaultFixturesDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/app", isDirectory: true)
    }

    static func load(
        named fixtureName: String,
        into sessionManager: SessionManager,
        updateManager: UpdateManager,
        fixturesDirectoryURL: URL? = nil
    ) throws -> AppTestFixture {
        try load(
            from: (fixturesDirectoryURL ?? defaultFixturesDirectoryURL())
                .appendingPathComponent("\(fixtureName).json"),
            into: sessionManager,
            updateManager: updateManager
        )
    }

    static func load(
        from fixtureURL: URL,
        into sessionManager: SessionManager,
        updateManager: UpdateManager
    ) throws -> AppTestFixture {
        let fixture = try decoder.decode(AppTestFixture.self, from: Data(contentsOf: fixtureURL))
        apply(fixture, to: sessionManager, updateManager: updateManager)
        return fixture
    }

    @discardableResult
    static func load(
        configuration: AppTestConfiguration,
        into sessionManager: SessionManager,
        updateManager: UpdateManager,
        fixturesDirectoryURL: URL? = nil
    ) throws -> AppTestFixture? {
        if let fixturePath = configuration.fixturePath {
            return try load(
                from: URL(fileURLWithPath: fixturePath),
                into: sessionManager,
                updateManager: updateManager
            )
        }

        guard let fixtureName = configuration.fixtureName else {
            return nil
        }

        return try load(
            named: fixtureName,
            into: sessionManager,
            updateManager: updateManager,
            fixturesDirectoryURL: fixturesDirectoryURL
        )
    }

    static func apply(
        _ fixture: AppTestFixture,
        to sessionManager: SessionManager,
        updateManager: UpdateManager
    ) {
        sessionManager.sessions = fixture.sessions.map(makeSession(from:))
        sessionManager.selectedSessionId = fixture.selectedSessionId ?? sessionManager.sessions.first?.id
        updateManager.applyFixture(fixture.update)
    }

    private static func makeSession(from fixture: AppTestFixture.SessionFixture) -> AgentSession {
        let session = AgentSession(
            id: fixture.id,
            agentType: fixture.agentType,
            terminal: fixture.terminal ?? "",
            workingDirectory: fixture.workingDirectory ?? "",
            prompt: fixture.prompt ?? ""
        )
        session.status = fixture.status
        session.statusText = fixture.statusText ?? ""
        session.agentResponse = fixture.agentResponse ?? ""
        session.completedAt = fixture.completedAt

        if !session.prompt.isEmpty {
            session.chatHistory.append(ChatMessage(timestamp: Date(), role: .user, content: session.prompt))
        }

        if let pendingPermission = fixture.pendingPermission {
            session.pendingPermission = PendingPermission(
                requestingAgent: pendingPermission.requestingAgent,
                tool: pendingPermission.tool,
                description: pendingPermission.description,
                diff: pendingPermission.diff,
                filePath: pendingPermission.filePath,
                respond: { _ in }
            )
        }

        if let pendingQuestion = fixture.pendingQuestion {
            session.pendingQuestion = PendingQuestion(
                requestingAgent: pendingQuestion.requestingAgent,
                text: pendingQuestion.text,
                options: pendingQuestion.options,
                respond: { _ in },
                cancel: nil
            )
        }

        if let pendingPlanReview = fixture.pendingPlanReview {
            session.pendingPlanReview = PendingPlanReview(
                requestingAgent: pendingPlanReview.requestingAgent,
                markdown: pendingPlanReview.markdown,
                respond: { _, _ in }
            )
        }

        return session
    }
}
