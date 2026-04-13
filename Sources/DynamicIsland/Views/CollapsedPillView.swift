import SwiftUI

struct CollapsedPillView: View {
    @Environment(SessionManager.self) private var manager
    let isHovering: Bool
    let onTap: () -> Void

    private var visible: [AgentSession] { manager.visibleSessions }

    var body: some View {
        HStack(spacing: 8) {
            if visible.isEmpty {
                idleContent
            } else if isHovering {
                hoveredContent
            } else {
                compactContent
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var idleContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green.opacity(0.6))
                .frame(width: 6, height: 6)
            Text("Ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            ForEach(Array(visible.prefix(4))) { session in
                PillBadge(session: session, compact: true)
            }
            if visible.count > 4 {
                Text("+\(visible.count - 4)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let interacting = visible.first(where: { $0.status == .waitingPermission }) {
                Spacer()
                interactionBadge(for: interacting)
            }
        }
    }

    private var hoveredContent: some View {
        HStack(spacing: 8) {
            ForEach(Array(visible.prefix(4))) { session in
                HStack(spacing: 4) {
                    AgentIcon(agentType: session.agentType, size: 14, status: session.status)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.agentType.shortName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(idleOrDone(session) ? (session.statusText.isEmpty ? "Done" : String(session.statusText.prefix(40))) : session.lastActivity)
                            .font(.system(size: 8))
                            .foregroundStyle(idleOrDone(session) ? .green.opacity(0.6) : .white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(idleOrDone(session)
                    ? .green.opacity(0.08)
                    : session.agentType.color.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }

    private func idleOrDone(_ session: AgentSession) -> Bool {
        session.status == .idle || session.status == .completed
    }

    private func interactionBadge(for session: AgentSession) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
            Text("Action")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.orange.opacity(0.2))
        .clipShape(Capsule())
    }
}
