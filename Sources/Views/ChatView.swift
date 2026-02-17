import SwiftUI

struct ChatView: View {
    let agent: Agent
    @EnvironmentObject var gateway: GatewayService
    @EnvironmentObject var convoStore: ConversationStore
    @EnvironmentObject var settings: SettingsStore

    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var conversation: Conversation {
        convoStore.conversation(for: agent.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if conversation.displayMessages.isEmpty {
                                emptyState
                            } else {
                                ForEach(conversation.displayMessages) { message in
                                    MessageBubble(message: message, agent: agent)
                                        .id(message.id)
                                }
                            }

                            // Scroll anchor
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: conversation.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: conversation.messages.last?.content) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                // Input bar
                inputBar
            }
            .navigationTitle(agent.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    connectionStatus
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isStreaming {
                        Button("Stop") {
                            gateway.cancelStreaming()
                            finalizeStreaming()
                        }
                        .foregroundStyle(.red)
                    } else {
                        Menu {
                            Button(role: .destructive) {
                                convoStore.clearConversation(for: agent.id)
                            } label: {
                                Label("Clear conversation", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Image(systemName: agent.icon)
                .font(.system(size: 48))
                .foregroundStyle(agent.swiftUIColor.gradient)
            Text("Chat with \(agent.name)")
                .font(.title3.bold())
            Text(agent.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(gateway.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(gateway.isConnected ? "Live" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(agent.name)…", text: $inputText, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)
                .onSubmit { sendMessage() }
                .submitLabel(.send)
                .disabled(isStreaming)

            Button {
                sendMessage()
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? agent.swiftUIColor : .secondary)
            }
            .disabled(!canSend && !isStreaming)
            .animation(.easeInOut(duration: 0.15), value: isStreaming)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        errorMessage = nil
        isStreaming = true
        inputFocused = false

        // Add user message
        let userMsg = Message(role: .user, content: text, agentId: agent.id)
        convoStore.addMessage(userMsg, to: agent.id)

        // Placeholder for streaming response
        let assistantMsg = Message(role: .assistant, content: "", agentId: agent.id, isStreaming: true)
        convoStore.addMessage(assistantMsg, to: agent.id)

        let history = conversation.displayMessages.dropLast(2) // exclude user msg + placeholder
        gateway.sendMessage(
            text,
            agentId: agent.id,
            history: Array(history),
            onChunk: { chunk in
                let current = self.conversation.messages.last?.content ?? ""
                self.convoStore.updateLastMessage(in: self.agent.id, content: current + chunk, isStreaming: true)
            },
            onComplete: {
                self.finalizeStreaming()
            },
            onError: { error in
                self.errorMessage = error
                self.convoStore.updateLastMessage(in: self.agent.id, content: "⚠️ \(error)", isStreaming: false)
                self.isStreaming = false
            }
        )
    }

    private func finalizeStreaming() {
        let content = conversation.messages.last?.content ?? ""
        convoStore.updateLastMessage(in: agent.id, content: content, isStreaming: false)
        isStreaming = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
