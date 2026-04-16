import Foundation

public struct AppDiagnosticsSnapshot: Codable, Equatable {
    public let islandState: String
    public let selectedSessionId: String?
    public let pendingInteraction: String?
    public let visibleSessions: [SessionSnapshot]
    public let visibleAccessibilityIdentifiers: [String]
    public let update: UpdateSnapshot

    public struct SessionSnapshot: Codable, Equatable {
        public let id: String
        public let agentType: String
        public let status: String
        public let workingDirectory: String
        public let prompt: String
        public let pendingInteraction: String?
    }

    public struct UpdateSnapshot: Codable, Equatable {
        public let state: String
        public let version: String?
        public let dmgURL: String?
    }

    @MainActor
    static func make(
        sessionManager: SessionManager,
        updateManager: UpdateManager,
        islandState: String,
        preferencesVisible: Bool = false
    ) -> Self {
        let prioritizedSession = sessionManager.prioritizedInteractionSession ?? sessionManager.selectedSession

        return Self(
            islandState: islandState,
            selectedSessionId: sessionManager.selectedSessionId,
            pendingInteraction: prioritizedSession.flatMap(pendingInteraction(for:)),
            visibleSessions: sessionManager.visibleSessions.map { session in
                SessionSnapshot(
                    id: session.id,
                    agentType: session.agentType.rawValue,
                    status: session.status.rawValue,
                    workingDirectory: session.workingDirectory,
                    prompt: session.prompt,
                    pendingInteraction: pendingInteraction(for: session)
                )
            },
            visibleAccessibilityIdentifiers: visibleAccessibilityIdentifiers(
                sessionManager: sessionManager,
                updateManager: updateManager,
                islandState: islandState,
                preferencesVisible: preferencesVisible
            ),
            update: UpdateSnapshot(
                state: updateStateName(updateManager.state),
                version: updateVersion(updateManager),
                dmgURL: updateManager.latestRelease?.dmgURL?.absoluteString
            )
        )
    }

    @MainActor
    private static func visibleAccessibilityIdentifiers(
        sessionManager: SessionManager,
        updateManager: UpdateManager,
        islandState: String,
        preferencesVisible: Bool
    ) -> [String] {
        var identifiers: [String] = []

        if islandState == "collapsed" {
            identifiers.append(TestAccessibility.collapsedPill)
        } else {
            identifiers.append(TestAccessibility.islandRoot)
        }

        if let session = sessionManager.prioritizedInteractionSession ?? sessionManager.selectedSession {
            switch pendingInteraction(for: session) {
            case "permission":
                identifiers.append(TestAccessibility.permissionPanel)
                identifiers.append(TestAccessibility.permissionDenyButton)
                identifiers.append(TestAccessibility.permissionApproveButton)
            case "question":
                identifiers.append(TestAccessibility.questionPanel)
                identifiers.append(contentsOf: session.pendingQuestion?.options.indices.map(TestAccessibility.questionOption(index:)) ?? [])
            case "planReview":
                identifiers.append(TestAccessibility.planPanel)
                identifiers.append(TestAccessibility.planRejectButton)
                identifiers.append(TestAccessibility.planApproveButton)
            default:
                break
            }
        }

        if preferencesVisible {
            identifiers.append(TestAccessibility.preferencesRoot)
            identifiers.append(TestAccessibility.updateStatusLabel)
            identifiers.append(TestAccessibility.updateCheckButton)
            if updateManager.latestRelease?.dmgURL != nil {
                identifiers.append(TestAccessibility.updateInstallButton)
            }
        }

        return identifiers
    }

    private static func pendingInteraction(for session: AgentSession) -> String? {
        switch session.status {
        case .waitingPermission:
            return "permission"
        case .waitingAnswer:
            return "question"
        case .waitingPlanReview:
            return "planReview"
        default:
            return nil
        }
    }

    private static func updateStateName(_ state: UpdateManager.State) -> String {
        switch state {
        case .idle:
            return "idle"
        case .checking:
            return "checking"
        case .upToDate:
            return "upToDate"
        case .updateAvailable:
            return "updateAvailable"
        case .installing:
            return "installing"
        case .failed:
            return "failed"
        }
    }

    @MainActor
    private static func updateVersion(_ updateManager: UpdateManager) -> String? {
        switch updateManager.state {
        case .updateAvailable(let version):
            return version
        case .installing:
            return updateManager.latestRelease?.normalizedVersion
        default:
            return updateManager.latestRelease?.normalizedVersion
        }
    }
}

extension IslandState {
    var diagnosticsValue: String {
        switch self {
        case .collapsed:
            return "collapsed"
        case .expanded:
            return "expanded"
        case .permission:
            return "permission"
        case .question:
            return "question"
        case .planReview:
            return "planReview"
        }
    }
}
