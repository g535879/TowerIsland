import SwiftUI

struct ChatHistoryView: View {
    let session: AgentSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(session.chatHistory) { message in
                    chatBubble(message)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 4) {
                if message.role == .user {
                    Spacer()
                }
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .font(.system(size: 8))
                    .foregroundStyle(message.role == .user ? session.agentType.color.opacity(0.6) : .white.opacity(0.4))
                Text(message.role == .user ? "You" : session.agentType.shortName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text(message.timestamp, style: .time)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.2))
                if message.role != .user {
                    Spacer()
                }
            }

            Text(message.content)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(message.role == .user ? 0.8 : 0.6))
                .lineLimit(message.role == .user ? 3 : 10)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(message.role == .user
                              ? session.agentType.color.opacity(0.1)
                              : .white.opacity(0.04))
                )
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
    }
}
