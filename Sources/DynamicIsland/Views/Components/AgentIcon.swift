import SwiftUI

struct AgentIcon: View {
    let agentType: AgentType
    var size: CGFloat = 24
    var status: SessionStatus = .active
    var showMascot: Bool = true
    @AppStorage("reduceMotion") private var reduceMotion = false

    private var statusColor: Color {
        switch status {
        case .active, .thinking: .blue
        case .idle: .green
        case .waitingPermission, .waitingAnswer, .waitingPlanReview: .orange
        case .completed: .green
        case .error: .red
        case .compacting: .yellow
        }
    }

    private var shouldPulse: Bool {
        status == .active || status == .thinking || status == .compacting
    }

    var body: some View {
        ZStack {
            if shouldPulse && !reduceMotion {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(statusColor.opacity(0.3))
                    .frame(width: size + 4, height: size + 4)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 0.6 : 0.2)
                    } animation: { _ in .easeInOut(duration: 1.5) }
            }

            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(agentType.color.opacity(0.2))
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.6), lineWidth: 1.5)
                }

            if showMascot && size >= 20 && !reduceMotion {
                AnimatedMascot(agentType: agentType, status: status, size: size)
            } else {
                Image(systemName: agentType.iconSymbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(agentType.color)
            }
        }
    }
}

/// Continuously animated mascot face
private struct AnimatedMascot: View {
    let agentType: AgentType
    let status: SessionStatus
    let size: CGFloat

    @State private var blinkPhase = false
    @State private var lookDir: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { timeline in
            let tick = Int(timeline.date.timeIntervalSince1970 * 6.67) // ~6.67 fps
            let isBlinking = (tick % 30 == 0) || (tick % 30 == 1)
            let lookX: CGFloat = {
                let cycle = tick % 80
                if cycle < 20 { return 0 }
                if cycle < 40 { return 1 }
                if cycle < 50 { return 0 }
                if cycle < 70 { return -1 }
                return 0
            }()

            ZStack {
                HStack(spacing: size * 0.18) {
                    eyeView(s: size, blinking: isBlinking, lookX: lookX)
                    eyeView(s: size, blinking: isBlinking, lookX: lookX)
                }
                .offset(y: -size * 0.06)

                mouthView(s: size, tick: tick)
                    .offset(y: size * 0.18)
            }
        }
    }

    @ViewBuilder
    private func eyeView(s: CGFloat, blinking: Bool, lookX: CGFloat) -> some View {
        let eyeSize = s * 0.16

        switch status {
        case .completed, .idle:
            Capsule()
                .fill(agentType.color)
                .frame(width: eyeSize * 1.2, height: eyeSize * 0.35)
        case .error:
            ZStack {
                Capsule().fill(agentType.color)
                    .frame(width: eyeSize, height: eyeSize * 0.28)
                    .rotationEffect(.degrees(45))
                Capsule().fill(agentType.color)
                    .frame(width: eyeSize, height: eyeSize * 0.28)
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: eyeSize, height: eyeSize)
        case .waitingPermission, .waitingAnswer, .waitingPlanReview:
            Ellipse()
                .fill(agentType.color)
                .frame(width: eyeSize * 1.3, height: blinking ? eyeSize * 0.3 : eyeSize * 1.5)
                .animation(.easeInOut(duration: 0.08), value: blinking)
        default:
            if blinking {
                Capsule()
                    .fill(agentType.color)
                    .frame(width: eyeSize * 1.1, height: eyeSize * 0.25)
            } else {
                Circle()
                    .fill(agentType.color)
                    .frame(width: eyeSize, height: eyeSize)
                    .offset(x: lookX * eyeSize * 0.2,
                            y: status == .thinking || status == .compacting ? -eyeSize * 0.2 : 0)
            }
        }
    }

    @ViewBuilder
    private func mouthView(s: CGFloat, tick: Int) -> some View {
        let mouthW = s * 0.28

        switch status {
        case .completed, .idle:
            MouthShape(smile: true)
                .stroke(agentType.color, lineWidth: s * 0.06)
                .frame(width: mouthW, height: mouthW * 0.5)
        case .error:
            MouthShape(smile: false)
                .stroke(agentType.color, lineWidth: s * 0.06)
                .frame(width: mouthW, height: mouthW * 0.4)
        case .waitingPermission, .waitingAnswer, .waitingPlanReview:
            Circle()
                .stroke(agentType.color, lineWidth: s * 0.05)
                .frame(width: mouthW * 0.45, height: mouthW * 0.45)
        case .thinking, .compacting:
            // Animated dots: thinking "..."
            let dotCount = (tick / 4) % 4
            HStack(spacing: s * 0.03) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(agentType.color.opacity(i < dotCount ? 1.0 : 0.25))
                        .frame(width: s * 0.05, height: s * 0.05)
                }
            }
        default:
            Capsule()
                .fill(agentType.color)
                .frame(width: mouthW * 0.6, height: s * 0.05)
        }
    }
}

private struct MouthShape: Shape {
    let smile: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if smile {
            path.move(to: CGPoint(x: 0, y: rect.midY * 0.3))
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: rect.midY * 0.3),
                control: CGPoint(x: rect.midX, y: rect.height * 1.4)
            )
        } else {
            path.move(to: CGPoint(x: 0, y: rect.height * 0.7))
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: rect.height * 0.7),
                control: CGPoint(x: rect.midX, y: -rect.height * 0.3)
            )
        }
        return path
    }
}
