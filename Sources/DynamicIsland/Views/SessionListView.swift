import SwiftUI

struct SessionListView: View {
    @Environment(SessionManager.self) private var manager
    var onJump: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(manager.visibleSessions) { session in
                    SessionCardView(session: session, onJump: onJump)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

struct SessionCardView: View {
    @Environment(SessionManager.self) private var manager
    let session: AgentSession
    var onJump: (() -> Void)?
    @State private var isHovered = false
    @AppStorage("compactBadgesInExpandedView") private var compactBadges = true
    @AppStorage("displayTimestamp") private var displayTimestamp = true

    var body: some View {
        Button {
            TerminalJumpManager.jump(to: session)
            onJump?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                if !session.prompt.isEmpty && !session.hasPromptTitle {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(session.agentType.color.opacity(0.5))
                            .padding(.top, 2)
                        Text("You: \(session.prompt)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                }

                if !session.agentResponse.isEmpty {
                    Text(session.agentResponse)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }

                if session.currentTool != nil {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                        Text(session.currentTool ?? "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovered ? IslandStyle.cardHover : IslandStyle.cardRest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                .white.opacity(isHovered ? IslandStyle.cardStrokeHover : IslandStyle.cardStrokeRest),
                                lineWidth: 0.5
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            AgentIcon(agentType: session.agentType, size: 24, status: session.status)
            StatusDot(status: session.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if session.hasPromptTitle {
                    Text(session.workspaceName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 5) {
                TagBadge(text: session.agentType.shortName, color: session.agentType.color)

                if displayTimestamp {
                    TagBadge(text: session.formattedDuration, color: .white.opacity(0.3))
                }

                if isHovered {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            manager.dismissSession(session)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 18, height: 18)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var toolActivity: some View {
        VStack(alignment: .leading, spacing: 4) {
            let recentEvents = session.events.suffix(5)
            ForEach(recentEvents) { event in
                HStack(spacing: 6) {
                    Image(systemName: event.isComplete ? "checkmark.square.fill" : "square")
                        .font(.system(size: 9))
                        .foregroundStyle(event.isComplete ? .green.opacity(0.5) : .white.opacity(0.25))

                    Text("\(event.displayName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(event.isComplete ? .white.opacity(0.35) : .white.opacity(0.7))

                    if event.isComplete {
                        Text(event.summary)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.25))
                            .lineLimit(1)
                    }
                }
            }

            if let tool = session.currentTool {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                    Text("Running \(tool)...")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if !session.subagentIds.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.6))
                    Text("\(session.subagentIds.count) subagent\(session.subagentIds.count > 1 ? "s" : "") running")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple.opacity(0.5))
                }
            }
        }
    }

    private func terminalShortName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("iterm") { return "iTerm2" }
        if lower.contains("terminal") { return "Terminal" }
        if lower.contains("ghostty") { return "Ghostty" }
        if lower.contains("warp") { return "Warp" }
        if lower.contains("kitty") { return "Kitty" }
        return name
    }
}

struct StatusDot: View {
    let status: SessionStatus
    @AppStorage("reduceMotion") private var reduceMotion = false

    private var color: Color {
        switch status {
        case .active, .thinking: .blue
        case .idle: .green
        case .waitingPermission, .waitingAnswer, .waitingPlanReview: .orange
        case .completed: .green
        case .error: .red
        case .compacting: .yellow
        }
    }

    private var shouldBounce: Bool {
        switch status {
        case .active, .thinking, .compacting: true
        case .waitingPermission, .waitingAnswer, .waitingPlanReview: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            if shouldBounce && !reduceMotion {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 10, height: 10)
                    .phaseAnimator([false, true]) { content, phase in
                        content.scaleEffect(phase ? 1.8 : 1.0)
                              .opacity(phase ? 0.0 : 0.5)
                    } animation: { _ in .easeOut(duration: 1.2) }
            }

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 3)
                .modifier(BounceModifier(shouldBounce: shouldBounce && !reduceMotion, isWaiting: isWaiting))
        }
        .frame(width: 10, height: 10)
    }

    private var isWaiting: Bool {
        status == .waitingPermission || status == .waitingAnswer || status == .waitingPlanReview
    }
}

private struct BounceModifier: ViewModifier {
    let shouldBounce: Bool
    let isWaiting: Bool

    func body(content: Content) -> some View {
        if isWaiting {
            content.phaseAnimator([false, true]) { view, phase in
                view.offset(y: phase ? -3 : 1)
            } animation: { phase in
                phase ? .easeOut(duration: 0.3) : .easeIn(duration: 0.3).delay(0.15)
            }
        } else if shouldBounce {
            content.phaseAnimator([false, true]) { view, phase in
                view.scaleEffect(phase ? 1.2 : 0.85)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            content
        }
    }
}

struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
