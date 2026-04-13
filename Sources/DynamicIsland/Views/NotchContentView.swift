import SwiftUI

enum IslandState: Equatable {
    case collapsed
    case expanded
    case permission(String)
    case question(String)
    case planReview(String)
}

struct NotchContentView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(AudioEngine.self) private var audio
    @State private var state: IslandState = .collapsed
    @State private var isHovering = false
    @State private var expandedByHover = false
    @State private var expandedAt: Date = .distantPast
    @State private var showContent = false
    @State private var jumpMouseLocation: CGPoint?
    @State private var hoverTimer: Timer?
    @State private var lastCollapseAt: Date = .distantPast
    @State private var expandPending = false
    @AppStorage("autoCollapseDelay") private var autoCollapseDelay = 3.0
    @AppStorage("smartSuppression") private var smartSuppression = true
    @AppStorage("autoHideWhenNoActiveSessions") private var autoHideWhenNoActiveSessions = false
    var onSizeChange: ((CGFloat, CGFloat, Bool) -> Void)?

    private var isExpanded: Bool { state != .collapsed }

    private var contentWidth: CGFloat {
        isExpanded ? expandedWidth : pillWidth
    }

    private var contentHeight: CGFloat {
        isExpanded ? expandedHeight + 8 : 48
    }

    private var expandedWidth: CGFloat {
        switch state {
        case .collapsed: return 0
        case .expanded: return 420
        case .permission, .question: return 440
        case .planReview: return 500
        }
    }

    private var expandedHeight: CGFloat {
        switch state {
        case .collapsed: return 0
        case .expanded:
            let count = manager.visibleSessions.count
            return min(CGFloat(count) * 120 + 50, 480)
        case .permission(let id):
            let perm = manager.sessions.first(where: { $0.id == id })?.pendingPermission
            var h: CGFloat = 42 + 1 + 30
            let hasDesc = perm != nil && !perm!.description.isEmpty
            let hasPath = perm?.filePath.map { !$0.isEmpty } ?? false
            let hasDiff = perm?.diff.map { !$0.isEmpty } ?? false
            h += hasDesc ? 52 : (hasPath ? 52 : 0)
            if hasDesc && hasPath { h += 22 }
            if hasDiff { h += 130 }
            h += 52
            return min(h, 480)
        case .question(let id):
            let optionCount = manager.sessions.first(where: { $0.id == id })?.pendingQuestion?.options.count ?? 0
            let baseHeight: CGFloat = 120
            let optionHeight: CGFloat = CGFloat(max(optionCount, 2)) * 42
            return min(baseHeight + optionHeight, 480)
        case .planReview: return 480
        }
    }

    private var shapeWidth: CGFloat {
        isExpanded ? expandedWidth : pillWidth
    }

    private var shapeHeight: CGFloat {
        isExpanded ? expandedHeight : 36
    }

    private static let expandSpring = Animation.spring(response: 0.4, dampingFraction: 0.82)
    private static let collapseSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    private static let contentFade = Animation.easeInOut(duration: 0.2)

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: isExpanded ? 22 : 18, style: .continuous)
                .fill(.black)
                .shadow(color: .white.opacity(isExpanded ? 0.06 : 0), radius: 20, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: isExpanded ? 22 : 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .frame(width: shapeWidth, height: shapeHeight)

            expandedContent
                .frame(width: expandedWidth > 0 ? expandedWidth : 420)
                .opacity(showContent ? 1 : 0)
                .allowsHitTesting(showContent)

            CollapsedPillView(isHovering: isHovering) {
                expand(to: .expanded)
            }
            .frame(width: pillWidth, height: 36)
            .opacity(showContent ? 0 : 1)
            .allowsHitTesting(!showContent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onChange(of: manager.visibleSessions.count) { oldCount, newCount in
            withAnimation(.easeInOut(duration: 0.2)) { reportSize() }
            if autoHideWhenNoActiveSessions {
                if newCount == 0 && oldCount > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if manager.visibleSessions.isEmpty {
                            NSApp.windows.first(where: { $0 is NotchWindow })?.orderOut(nil)
                        }
                    }
                } else if newCount > 0 && oldCount == 0 {
                    NSApp.windows.first(where: { $0 is NotchWindow })?.orderFrontRegardless()
                }
            }
        }
        .onAppear {
            reportSize()
            startHoverPolling()
        }
        .onChange(of: manager.hasInteraction) { _, hasInteraction in
            if hasInteraction {
                autoExpandForInteraction()
            } else if case .permission = state {
                collapse()
            } else if case .question = state {
                collapse()
            } else if case .planReview = state {
                collapse()
            }
        }
    }

    private func expand(to newState: IslandState) {
        guard !expandPending else { return }
        expandPending = true
        let target = targetSize(for: newState)
        onSizeChange?(target.width, target.height, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(Self.expandSpring) {
                self.isHovering = false
                self.state = newState
            }
            withAnimation(Self.contentFade.delay(0.12)) {
                self.showContent = true
            }
            self.expandPending = false
        }
    }

    private func collapse() {
        lastCollapseAt = Date()
        withAnimation(Self.contentFade) {
            showContent = false
        }
        withAnimation(Self.collapseSpring) {
            state = .collapsed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            reportSize()
        }
    }

    private func reportSize() {
        onSizeChange?(contentWidth, contentHeight, true)
    }

    private func targetSize(for state: IslandState) -> (width: CGFloat, height: CGFloat) {
        let w: CGFloat
        let h: CGFloat
        switch state {
        case .collapsed:
            w = 140; h = 48
        case .expanded:
            let count = manager.visibleSessions.count
            w = 420; h = min(CGFloat(count) * 120 + 50, 480) + 8
        case .permission:
            w = 440; h = expandedHeight + 8
        case .question(let id):
            let optionCount = manager.sessions.first(where: { $0.id == id })?.pendingQuestion?.options.count ?? 4
            let contentH: CGFloat = 120 + CGFloat(max(optionCount, 2)) * 42
            w = 440; h = min(contentH, 480) + 8
        case .planReview:
            w = 500; h = 480 + 8
        }
        return (w, h)
    }

    private var pillWidth: CGFloat {
        let count = manager.visibleSessions.count
        if isHovering && count > 0 { return min(CGFloat(count) * 90 + 80, 400) }
        if count == 0 { return 140 }
        return CGFloat(count) * 40 + 60
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            expandedHeader

            switch state {
            case .expanded:
                SessionListView(onJump: {
                    expandedByHover = false
                    jumpMouseLocation = NSEvent.mouseLocation
                    collapse()
                })

            case .permission(let id):
                if let session = manager.sessions.first(where: { $0.id == id }) {
                    PermissionApprovalView(session: session) {
                        collapseAfterDelay()
                    }
                }

            case .question(let id):
                if let session = manager.sessions.first(where: { $0.id == id }) {
                    QuestionAnswerView(session: session) {
                        collapseAfterDelay()
                    }
                }

            case .planReview(let id):
                if let session = manager.sessions.first(where: { $0.id == id }) {
                    PlanReviewView(session: session) {
                        collapseAfterDelay()
                    }
                }

            case .collapsed:
                EmptyView()
            }
        }
        .padding(.bottom, 8)
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    audio.isMuted.toggle()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(audio.isMuted ? .white.opacity(0.25) : .white.opacity(0.72))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(manager.activeSessions.count) active")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))

            Button {
                expandedByHover = false
                collapse()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func openSettingsWindow() {
        AppDelegate.shared?.openPreferences()
    }

    private func isAgentTerminalFocused() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let terminalBundleIds = [
            "com.googlecode.iterm2", "com.apple.Terminal",
            "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty",
            "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"
        ]
        return terminalBundleIds.contains(frontApp.bundleIdentifier ?? "")
    }

    private func autoExpandForInteraction() {
        guard let session = manager.activeSessions.first(where: {
            $0.status == .waitingPermission || $0.status == .waitingAnswer || $0.status == .waitingPlanReview
        }) else { return }

        switch session.status {
        case .waitingPermission: expand(to: .permission(session.id))
        case .waitingAnswer: expand(to: .question(session.id))
        case .waitingPlanReview: expand(to: .planReview(session.id))
        default: break
        }
    }

    private func startHoverPolling() {
        stopHoverPolling()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                pollMousePosition()
            }
        }
    }

    private func stopHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func pollMousePosition() {
        guard let window = NSApp.windows.first(where: { $0 is NotchWindow }) as? NotchWindow else { return }
        guard !window.isDragging else { return }

        let mouse = NSEvent.mouseLocation
        var hitFrame = window.frame
        hitFrame.size.height += 2
        let inside = hitFrame.contains(mouse)

        if inside && !isExpanded {
            guard Date().timeIntervalSince(lastCollapseAt) > 0.5 else { return }
            if let savedPos = jumpMouseLocation {
                let dx = mouse.x - savedPos.x
                let dy = mouse.y - savedPos.y
                if dx * dx + dy * dy < 9 { return }
                jumpMouseLocation = nil
            }
            if !manager.visibleSessions.isEmpty {
                if smartSuppression && isAgentTerminalFocused() { return }
                expandedByHover = true
                expandedAt = Date()
                expand(to: .expanded)
            } else if !isHovering {
                withAnimation(.easeInOut(duration: 0.2)) { isHovering = true }
            }
        } else if !inside && isHovering && !isExpanded {
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = false }
        } else if !inside && expandedByHover && state == .expanded {
            if Date().timeIntervalSince(expandedAt) > 0.5 {
                collapse()
                expandedByHover = false
            }
        }
    }

    private func collapseAfterDelay() {
        guard autoCollapseDelay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + autoCollapseDelay) {
            if !manager.hasInteraction {
                expandedByHover = false
                collapse()
            }
        }
    }
}
