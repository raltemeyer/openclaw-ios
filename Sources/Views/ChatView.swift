import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    let agent: Agent
    @EnvironmentObject var gateway: GatewayService
    @EnvironmentObject var convoStore: ConversationStore

    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @FocusState private var inputFocused: Bool

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingAttachments: [GatewayAttachment] = []
    @State private var showFilePicker = false
    @State private var lastPayload: (text: String, history: [Message], attachments: [GatewayAttachment])?

    private let maxAttachmentCount = 5
    private let maxSingleAttachmentBytes = 10 * 1024 * 1024
    private let maxTotalAttachmentBytes = 20 * 1024 * 1024

    var conversation: Conversation {
        convoStore.conversation(for: agent.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            if !pendingAttachments.isEmpty {
                                attachmentTray
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .onChange(of: conversation.messages.count) { _, _ in scrollToBottom(proxy: proxy) }
                    .onChange(of: conversation.messages.last?.content) { _, _ in scrollToBottom(proxy: proxy) }
                }

                if let info = streamStatusMessage {
                    Label(info, systemImage: "wifi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                if let infoMessage {
                    Label(infoMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 2)
                }

                if let error = errorMessage {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Spacer()
                        Button("Retry") { retryLast() }
                            .font(.caption.bold())
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }

                inputBar
            }
            .navigationTitle(agent.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { connectionStatus }
                ToolbarItem(placement: .navigationBarTrailing) { actionsMenu }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .utf8PlainText, .text, .sourceCode, .json, .xml, .commaSeparatedText, .pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    loadFiles(urls)
                case .failure(let err):
                    errorMessage = "File picker error: \(err.localizedDescription)"
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await loadPhoto(newValue) }
            }
        }
    }

    private var streamStatusMessage: String? {
        switch gateway.streamState {
        case .idle: return nil
        case .connecting(let attempt): return "Connecting stream (attempt \(attempt))"
        case .reconnecting(let delaySeconds, let attempt): return "Reconnecting in \(delaySeconds)s (attempt \(attempt))"
        case .streaming: return "Streaming response"
        case .failed(let msg): return "Stream failed: \(msg)"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Image(systemName: agent.icon).font(.system(size: 48)).foregroundStyle(agent.swiftUIColor.gradient)
            Text("Chat with \(agent.name)").font(.title3.bold())
            Text(agent.description).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 4) {
            Circle().fill(gateway.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(gateway.isConnected ? "Live" : "Offline").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var actionsMenu: some View {
        Menu {
            if isStreaming {
                Button(role: .destructive) {
                    gateway.cancelStreaming(); finalizeStreaming()
                } label: { Label("Stop stream", systemImage: "stop.fill") }
            }
            Button("Reset session") { Task { errorMessage = await gateway.resetSession(agentId: agent.id) } }
            Button("Stop current run") { Task { errorMessage = await gateway.stopRun(agentId: agent.id) } }

            Menu("Set model") {
                ForEach(["openai-codex/gpt-5.3-codex", "anthropic/claude-opus-4-6", "google/gemini-2.5-pro"], id: \.self) { model in
                    Button(model) { Task { errorMessage = await gateway.changeModel(agentId: agent.id, model: model) } }
                }
            }

            Divider()
            Button(role: .destructive) { convoStore.clearConversation(for: agent.id) } label: {
                Label("Clear conversation", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo").font(.title3)
                }
                Button { showFilePicker = true } label: {
                    Image(systemName: "paperclip").font(.title3)
                }

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

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? agent.swiftUIColor : .secondary)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: attachment.kind == .image ? "photo" : "doc")
                        Text("\(attachment.name) • \(attachment.sizeLabel)").lineLimit(1)
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty) && !isStreaming
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        let outgoingText = text.isEmpty ? "[Sent attachments]" : text
        inputText = ""
        errorMessage = nil
        infoMessage = nil
        isStreaming = true
        inputFocused = false

        let attachments = pendingAttachments
        pendingAttachments = []

        let userMsg = Message(role: .user, content: outgoingText + attachmentSummary(attachments), agentId: agent.id)
        convoStore.addMessage(userMsg, to: agent.id)
        let assistantMsg = Message(role: .assistant, content: "", agentId: agent.id, isStreaming: true)
        convoStore.addMessage(assistantMsg, to: agent.id)

        let history = Array(conversation.displayMessages.dropLast(2))
        lastPayload = (outgoingText, history, attachments)

        gateway.sendMessage(
            outgoingText,
            agentId: agent.id,
            history: history,
            attachments: attachments,
            onChunk: { chunk in
                let current = self.conversation.messages.last?.content ?? ""
                self.convoStore.updateLastMessage(in: self.agent.id, content: current + chunk, isStreaming: true)
            },
            onComplete: { finalizeStreaming() },
            onError: { error in
                self.errorMessage = error
                self.convoStore.updateLastMessage(in: self.agent.id, content: "⚠️ \(error)", isStreaming: false)
                self.isStreaming = false
            }
        )
    }

    private func retryLast() {
        guard let payload = lastPayload else { return }
        Task {
            do {
                let result = try await gateway.retryLastAsNonStream(text: payload.text, agentId: agent.id, history: payload.history, attachments: payload.attachments)
                convoStore.updateLastMessage(in: agent.id, content: result, isStreaming: false)
                errorMessage = nil
                isStreaming = false
            } catch {
                errorMessage = "Retry failed: \(error.localizedDescription)"
            }
        }
    }

    private func finalizeStreaming() {
        let content = conversation.messages.last?.content ?? ""
        convoStore.updateLastMessage(in: agent.id, content: content, isStreaming: false)
        isStreaming = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let name = item.itemIdentifier ?? "photo.jpg"
                addAttachment(GatewayAttachment(kind: .image, name: name, mimeType: "image/jpeg", data: data))
            }
        } catch {
            errorMessage = "Photo attach failed: \(error.localizedDescription)"
        }
    }

    private func loadFiles(_ urls: [URL]) {
        for url in urls {
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension
                let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
                let type = UTType(filenameExtension: ext)

                let isAllowed = type?.conforms(to: .text) == true || [.json, .xml, .commaSeparatedText, .pdf].contains(where: { type?.conforms(to: $0) == true })
                guard isAllowed else {
                    errorMessage = "Unsupported file type: \(url.lastPathComponent). Use text, json, csv, xml, or pdf."
                    continue
                }

                addAttachment(GatewayAttachment(kind: .file, name: url.lastPathComponent, mimeType: mime, data: data))
            } catch {
                errorMessage = "Failed to read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func addAttachment(_ attachment: GatewayAttachment) {
        guard pendingAttachments.count < maxAttachmentCount else {
            errorMessage = "Attachment limit reached (\(maxAttachmentCount))."
            return
        }
        guard attachment.data.count <= maxSingleAttachmentBytes else {
            errorMessage = "\(attachment.name) is too large. Limit is 10 MB per file."
            return
        }
        let total = pendingAttachments.reduce(0) { $0 + $1.data.count } + attachment.data.count
        guard total <= maxTotalAttachmentBytes else {
            errorMessage = "Total attachment size exceeds 20 MB."
            return
        }

        pendingAttachments.append(attachment)
        infoMessage = "\(pendingAttachments.count) attachment(s) ready"
    }

    private func attachmentSummary(_ attachments: [GatewayAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        let names = attachments.map(\.name).joined(separator: ", ")
        return "\n\nAttachments: \(names)"
    }
}
