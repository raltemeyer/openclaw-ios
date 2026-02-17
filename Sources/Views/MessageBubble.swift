import SwiftUI

struct MessageBubble: View {
    let message: Message
    let agent: Agent

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
                bubbleContent
            } else {
                agentAvatar
                bubbleContent
                Spacer(minLength: 60)
            }
        }
    }

    private var agentAvatar: some View {
        ZStack {
            Circle()
                .fill(agent.swiftUIColor.gradient)
                .frame(width: 28, height: 28)
            Image(systemName: agent.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                if message.content.isEmpty && message.isStreaming {
                    typingIndicator
                } else {
                    textContent
                }
            }

            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var textContent: some View {
        Text(message.content)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? agent.swiftUIColor : Color(.secondarySystemBackground))
            .foregroundStyle(isUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if message.isStreaming {
                    streamingCursor
                }
            }
            .textSelection(.enabled)
    }

    private var streamingCursor: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(agent.swiftUIColor)
            .frame(width: 2, height: 14)
            .padding(6)
            .blinking()
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(1.0)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: true
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Blinking modifier

struct BlinkingModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

extension View {
    func blinking() -> some View {
        modifier(BlinkingModifier())
    }
}
