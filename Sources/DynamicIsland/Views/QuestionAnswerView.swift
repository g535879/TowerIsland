import SwiftUI

struct QuestionAnswerView: View {
    let session: AgentSession
    let onComplete: () -> Void
    @Environment(SessionManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))

            if let q = session.pendingQuestion {
                questionContent(q)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.green.opacity(0.6))
                    Text("Question was handled externally")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { onComplete() }
            }
        }
    }

    private var displayAgent: AgentType {
        session.pendingQuestion?.requestingAgent ?? session.agentType
    }

    private var header: some View {
        HStack(spacing: 8) {
            AgentIcon(agentType: displayAgent, size: 20)
            Text(displayAgent.shortName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("Question")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func questionContent(_ q: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 16))
                Text(q.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        manager.answerQuestion(session: session, answer: option)
                        onComplete()
                    } label: {
                        HStack {
                            Text("⌘\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(width: 24)
                            Text(option)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
