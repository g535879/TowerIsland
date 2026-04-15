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
    @State private var islandObscuredByNotch = false
    @State private var state: IslandState = .collapsed
    @State private var isHovering = false
    @State private var expandedByHover = false
    @State private var expandedAt: Date = .distantPast
    @State private var showContent = false
    @State private var jumpMouseLocation: CGPoint?
    @State private var hoverTimer: Timer?
    @State private var lastCollapseAt: Date = .distantPast
    @State private var expandPending = false
    @State private var collapseAnimating = false
    @State private var collapseGeneration = 0
    /// Last known expanded `shapeHeight` (black panel), used to interpolate notch corner radii with `shapeHeight` during spring (avoids boolean snap).
    @State private var cachedExpandedShapeHeight: CGFloat = 220
    @AppStorage("autoCollapseDelay") private var autoCollapseDelay = 3.0
    @AppStorage("smartSuppression") private var smartSuppression = true
    @AppStorage("autoHideWhenNoActiveSessions") private var autoHideWhenNoActiveSessions = false
    var onSizeChange: ((CGFloat, CGFloat, Bool) -> Void)?

    private var isExpanded: Bool { state != .collapsed }

    private var contentWidth: CGFloat {
        isExpanded ? expandedWidth : pillWidth
    }

    private var collapsedShapeHeight: CGFloat { 32 }
    private var collapsedOuterHeight: CGFloat { collapsedShapeHeight }

    private var contentHeight: CGFloat {
        isExpanded ? expandedHeight + 8 : collapsedOuterHeight
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
            let listH = min(CGFloat(count) * 80 + 30, 480)
            return Self.expandedPanelHeaderHeight + listH + (Self.expandedPanelBottomInset - 8)
        case .permission(let id):
            return permissionExpandedTotalHeight(sessionId: id)
        case .question(let id):
            let optionCount = manager.sessions.first(where: { $0.id == id })?.pendingQuestion?.options.count ?? 0
            let baseHeight: CGFloat = 120
            let optionHeight: CGFloat = CGFloat(max(optionCount, 2)) * 42
            return min(baseHeight + optionHeight, 480)
        case .planReview: return 480
        }
    }

    /// Permission card body only (matches `PermissionApprovalView` layout estimate).
    private func permissionCardInnerHeight(sessionId: String) -> CGFloat {
        let perm = manager.sessions.first(where: { $0.id == sessionId })?.pendingPermission
        var h: CGFloat = 42 + 1 + 30
        let hasDesc = perm != nil && !perm!.description.isEmpty
        let hasPath = perm?.filePath.map { !$0.isEmpty } ?? false
        let hasDiff = perm?.diff.map { !$0.isEmpty } ?? false
        h += hasDesc ? 52 : (hasPath ? 52 : 0)
        if hasDesc && hasPath { h += 22 }
        if hasDiff { h += 130 }
        h += 52
        return min(h, 480)
    }

    /// Full expanded height for permission mode: island toolbar + card + bottom inset (same as session list layout).
    private func permissionExpandedTotalHeight(sessionId: String) -> CGFloat {
        let inner = permissionCardInnerHeight(sessionId: sessionId)
        return inner + Self.expandedPanelHeaderHeight + Self.expandedPanelBottomInset
    }

    private var shapeWidth: CGFloat {
        isExpanded ? expandedWidth : pillWidth
    }

    private var shapeHeight: CGFloat {
        isExpanded ? expandedHeight : collapsedShapeHeight
    }

    private var pillFillColor: Color { IslandStyle.surface }

    private var pillStrokeOpacity: CGFloat { IslandStyle.strokeOpacity }

    /// 0 = collapsed strip (flat top), 1 = full expanded card — follows `shapeHeight` during spring so corners don’t snap before size.
    private var notchShapeOpenProgress: CGFloat {
        NotchShapeGeometry.openProgress(
            shapeHeight: shapeHeight,
            cachedExpandedShapeHeight: cachedExpandedShapeHeight
        )
    }

    private var notchTopCornerRadius: CGFloat {
        NotchShapeGeometry.topCornerRadius(state: state)
    }

    private var notchBottomCornerRadius: CGFloat {
        NotchShapeGeometry.bottomCornerRadius(openProgress: notchShapeOpenProgress)
    }

    private static let expandSpring = Animation.spring(response: 0.4, dampingFraction: 0.82)
    private static let collapseSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    private static let contentFade = Animation.easeInOut(duration: 0.2)

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: notchTopCornerRadius,
                bottomLeadingRadius: notchBottomCornerRadius,
                bottomTrailingRadius: notchBottomCornerRadius,
                topTrailingRadius: notchTopCornerRadius,
                style: .continuous
            )
            .fill(pillFillColor)
            .shadow(
                color: .white.opacity(0.04 + 0.02 * notchShapeOpenProgress),
                radius: 10 + 10 * notchShapeOpenProgress,
                y: 3 + notchShapeOpenProgress
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: notchTopCornerRadius,
                    bottomLeadingRadius: notchBottomCornerRadius,
                    bottomTrailingRadius: notchBottomCornerRadius,
                    topTrailingRadius: notchTopCornerRadius,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(pillStrokeOpacity), lineWidth: 0.5)
            }
            .frame(width: shapeWidth, height: shapeHeight)

            expandedContent
                .frame(width: expandedWidth > 0 ? expandedWidth : 420,
                       height: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(showContent ? 1 : 0)
                .allowsHitTesting(showContent)
                .zIndex(1)

            CollapsedPillView(obscuredByNotch: islandObscuredByNotch) {
                expand(to: .expanded)
            }
            .frame(width: shapeWidth, height: collapsedShapeHeight)
            .opacity(showContent ? 0 : 1)
            .allowsHitTesting(!showContent)
            .zIndex(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onChange(of: expandedHeight) { _, _ in
            if case .expanded = state {
                cachedExpandedShapeHeight = max(collapsedShapeHeight + 1, expandedHeight)
            }
        }
        .onChange(of: manager.activeSessions.count) { _, _ in
            reportSize()
        }
        .onChange(of: manager.visibleSessions.count) { oldCount, newCount in
            reportSize()
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
            if let w = NSApp.windows.first(where: { $0 is NotchWindow }) as? NotchWindow {
                islandObscuredByNotch = w.isObscuredByPhysicalNotch()
            }
            reportSize()
            startHoverPolling()
        }
        .onChange(of: manager.hasInteraction) { _, hasInteraction in
            if hasInteraction {
                if collapseAnimating {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        guard manager.hasInteraction else { return }
                        autoExpandForInteraction()
                    }
                } else {
                    autoExpandForInteraction()
                }
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
        collapseGeneration += 1
        collapseAnimating = false
        expandPending = true
        let target = targetSize(for: newState)
        if case .expanded = newState {
            let count = manager.visibleSessions.count
            let listH = min(CGFloat(count) * 80 + 30, 480)
            cachedExpandedShapeHeight = Self.expandedPanelHeaderHeight + listH + (Self.expandedPanelBottomInset - 8)
        }
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
        collapseGeneration += 1
        let generation = collapseGeneration
        lastCollapseAt = Date()
        collapseAnimating = true
        withAnimation(Self.collapseSpring) {
            showContent = false
            state = .collapsed
        }
        // Defer NSWindow frame sync to the next main runloop turn so we are not inside SwiftUI's
        // animation/layout commit (reduces AppKit exceptions in _reallySetFrame: during collapse).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard generation == self.collapseGeneration, self.state == .collapsed else { return }
            let w = self.pillWidth
            let h = self.collapsedOuterHeight
            DispatchQueue.main.async {
                guard generation == self.collapseGeneration, self.state == .collapsed else { return }
                if let window = NSApp.windows.first(where: { $0 is NotchWindow }) as? NotchWindow {
                    window.resizeToFitCollapse(contentWidth: w, contentHeight: h)
                }
                self.collapseAnimating = false
            }
        }
    }

    private func reportSize() {
        guard !collapseAnimating else { return }
        onSizeChange?(contentWidth, contentHeight, true)
    }

    private func targetSize(for state: IslandState) -> (width: CGFloat, height: CGFloat) {
        let w: CGFloat
        let h: CGFloat
        switch state {
        case .collapsed:
            w = pillWidth
            h = collapsedOuterHeight
        case .expanded:
            let count = manager.visibleSessions.count
            let listH = min(CGFloat(count) * 80 + 30, 480)
            w = 420
            h = Self.expandedPanelHeaderHeight + listH + Self.expandedPanelBottomInset
        case .permission(let id):
            // Must not use `expandedHeight` here: `expand(to:)` runs before `state` updates, so
            // `expandedHeight` would still reflect `.collapsed` (0) and resize the window to ~8pt tall.
            w = 440
            h = permissionExpandedTotalHeight(sessionId: id) + 8
        case .question(let id):
            let optionCount = manager.sessions.first(where: { $0.id == id })?.pendingQuestion?.options.count ?? 4
            let contentH: CGFloat = 120 + CGFloat(max(optionCount, 2)) * 42
            w = 440; h = min(contentH, 480) + 8
        case .planReview:
            w = 500; h = 480 + 8
        }
        return (w, h)
    }

    /// Toolbar row in `expandedHeader` (~10+10 vertical padding + ~28 controls).
    private static let expandedPanelHeaderHeight: CGFloat = 48
    /// Space between session list / cards and the bottom rounded edge of the expanded panel.
    private static let expandedPanelBottomInset: CGFloat = 16
    /// Spans slightly past the camera housing; kept compact (competitor-style bar).
    private static let collapsedPillWidthNotched: CGFloat = 276
    /// Bottom-only rounding when docked under the notch (top edge flush with screen).
    private var pillWidth: CGFloat {
        if islandObscuredByNotch {
            return Self.collapsedPillWidthNotched
        }
        let n = manager.visibleSessions.count
        if n == 0 { return 180 }
        let icon: CGFloat = 22
        let gap: CGFloat = 8
        let horizontalPadding: CGFloat = 40
        let w = horizontalPadding + CGFloat(n) * icon + CGFloat(max(0, n - 1)) * gap
        return min(max(w, 160), 420)
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
                    .id(session.pendingQuestion?.id)
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
        .padding(.bottom, Self.expandedPanelBottomInset)
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

        if !window.isVisible && (manager.hasInteraction || !manager.visibleSessions.isEmpty) {
            window.orderFrontRegardless()
        }

        let obscured = window.isObscuredByPhysicalNotch()
        if obscured != islandObscuredByNotch {
            islandObscuredByNotch = obscured
            reportSize()
        }

        let mouse = NSEvent.mouseLocation
        var hitFrame = window.frame
        hitFrame.size.height += 2
        let inside = hitFrame.contains(mouse)

        if inside && !isExpanded {
            guard Date().timeIntervalSince(lastCollapseAt) > 1.2 else { return }
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
        } else if ExpandedAutoCollapsePolicy.shouldCollapseOnMouseExit(
            isPointerInside: inside,
            state: state,
            expandedByHover: expandedByHover,
            visibleSessionCount: manager.visibleSessions.count,
            elapsedSinceExpand: Date().timeIntervalSince(expandedAt)
        ) {
            collapse()
            expandedByHover = false
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
