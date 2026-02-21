import Foundation
import Combine

struct GatewayAttachment: Identifiable {
    enum Kind {
        case image
        case file
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let mimeType: String
    let data: Data

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

struct GatewaySessionSummary: Identifiable {
    let id: String
    let agentId: String
    let title: String
    let status: String
    let detail: String
    let model: String?
    let updatedAt: Date?
}

struct SystemSnapshot {
    let fetchedAt: Date
    let sessions: [GatewaySessionSummary]
    let notes: [String]
}

enum StreamState: Equatable {
    case idle
    case connecting
    case streaming
    case failed(String)
}

@MainActor
class GatewayService: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var streamState: StreamState = .idle
    @Published var latestSystemSnapshot = SystemSnapshot(fetchedAt: .now, sessions: [], notes: ["Not loaded yet"])

    private var baseURL: String = ""
    private var token: String = ""
    private var activeTask: URLSessionDataTask?

    func configure(with settings: SettingsStore) {
        self.baseURL = settings.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = settings.gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        checkConnection()
    }

    func checkConnection() {
        Task {
            guard !baseURL.isEmpty, !token.isEmpty else {
                isConnected = false
                connectionError = "Gateway not configured"
                return
            }
            do {
                _ = try await pingGateway()
                isConnected = true
                connectionError = nil
            } catch {
                isConnected = false
                connectionError = error.localizedDescription
            }
        }
    }

    private func pingGateway() async throws -> Data {
        let endpoints = [
            "/status",
            "/health",
            "/v1/models",
            "/v1/chat/completions"
        ]

        var lastError: Error?
        for endpoint in endpoints {
            do {
                if endpoint == "/v1/chat/completions" {
                    let payload: [String: Any] = [
                        "model": "openclaw:main",
                        "messages": [["role": "user", "content": "ping"]],
                        "max_tokens": 1,
                        "stream": false
                    ]
                    return try await request(path: endpoint, method: "POST", json: payload)
                }
                return try await request(path: endpoint, method: "GET")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(domain: "Gateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot reach gateway"])
    }

    // MARK: - Streaming Chat

    func sendMessage(
        _ text: String,
        agentId: String,
        history: [Message],
        attachments: [GatewayAttachment],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        Task {
            do {
                let req = try buildChatRequest(
                    text: text,
                    agentId: agentId,
                    history: history,
                    attachments: attachments,
                    stream: true
                )
                streamState = .connecting
                startSSE(request: req, onChunk: onChunk, onComplete: onComplete, onError: onError)
            } catch {
                streamState = .failed(error.localizedDescription)
                onError(error.localizedDescription)
            }
        }
    }

    func retryLastAsNonStream(
        text: String,
        agentId: String,
        history: [Message],
        attachments: [GatewayAttachment]
    ) async throws -> String {
        let req = try buildChatRequest(text: text, agentId: agentId, history: history, attachments: attachments, stream: false)
        let data = try await URLSession.shared.data(for: req).0
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? "(No content)"
    }

    func cancelStreaming() {
        activeTask?.cancel()
        activeTask = nil
        streamState = .idle
    }

    // MARK: - System + Controls

    func refreshSystemSnapshot() async {
        var notes: [String] = []
        var sessions: [GatewaySessionSummary] = []

        let probes: [(String, String)] = [
            ("/sessions", "sessions"),
            ("/v1/sessions", "sessions"),
            ("/agents", "agents"),
            ("/v1/agents", "agents")
        ]

        for (path, kind) in probes {
            do {
                let data = try await request(path: path, method: "GET")
                if kind == "sessions" {
                    sessions += decodeSessions(data: data)
                } else {
                    sessions += decodeAgentsAsSessions(data: data)
                }
                notes.append("Loaded \(path)")
            } catch {
                notes.append("\(path): \(error.localizedDescription)")
            }
        }

        if sessions.isEmpty {
            notes.append("No compatible session endpoints found; chat remains available.")
        }

        latestSystemSnapshot = SystemSnapshot(fetchedAt: .now, sessions: dedupe(sessions), notes: notes)
    }

    func resetSession(agentId: String) async -> String {
        await postFirstSuccess(paths: ["/sessions/reset", "/v1/sessions/reset", "/agents/reset"], json: ["agentId": agentId])
    }

    func stopRun(agentId: String) async -> String {
        await postFirstSuccess(paths: ["/sessions/stop", "/v1/sessions/stop", "/agents/stop"], json: ["agentId": agentId])
    }

    func changeModel(agentId: String, model: String) async -> String {
        await postFirstSuccess(paths: ["/agents/model", "/v1/agents/model", "/sessions/model"], json: ["agentId": agentId, "model": model])
    }

    // MARK: - Low level

    private func buildChatRequest(
        text: String,
        agentId: String,
        history: [Message],
        attachments: [GatewayAttachment],
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw NSError(domain: "Gateway", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid gateway URL"])
        }

        let formattedHistory: [[String: Any]] = history.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }

        let contentParts = buildContentParts(text: text, attachments: attachments)
        let userMessage: [String: Any] = ["role": "user", "content": contentParts]

        let body: [String: Any] = [
            "model": "openclaw:\(agentId)",
            "messages": formattedHistory + [userMessage],
            "stream": stream
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300
        return req
    }

    private func buildContentParts(text: String, attachments: [GatewayAttachment]) -> [[String: Any]] {
        var parts: [[String: Any]] = [["type": "text", "text": text]]

        for attachment in attachments {
            switch attachment.kind {
            case .image:
                let b64 = attachment.data.base64EncodedString()
                let dataURL = "data:\(attachment.mimeType);base64,\(b64)"
                parts.append(["type": "image_url", "image_url": ["url": dataURL]])
                parts.append(["type": "text", "text": "[Attached image: \(attachment.name)]"])
            case .file:
                if let fileText = String(data: attachment.data.prefix(12_000), encoding: .utf8), !fileText.isEmpty {
                    parts.append(["type": "text", "text": "[Attached file \(attachment.name)]\n\n\(fileText)"])
                } else {
                    parts.append(["type": "text", "text": "[Attached file \(attachment.name), \(attachment.sizeLabel) — binary preview unavailable]"])
                }
            }
        }

        return parts
    }

    private func startSSE(
        request: URLRequest,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        let delegate = SSEDelegate(
            onState: { state in
                Task { @MainActor in self.streamState = state }
            },
            onChunk: onChunk,
            onComplete: onComplete,
            onError: onError
        )
        let streamSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = streamSession.dataTask(with: request)
        activeTask = task
        task.resume()
    }

    private func request(path: String, method: String, json: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw NSError(domain: "Gateway", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid gateway URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Gateway", code: -3, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Gateway", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(body.prefix(120))"])
        }

        return data
    }

    private func postFirstSuccess(paths: [String], json: [String: Any]) async -> String {
        for path in paths {
            do {
                _ = try await request(path: path, method: "POST", json: json)
                return "Success via \(path)"
            } catch {
                continue
            }
        }
        return "API denied direct action. Use fallback SSH helper in Settings → Recovery."
    }

    private func decodeSessions(data: Data) -> [GatewaySessionSummary] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rows = extractArray(raw)
        return rows.map { row in
            let id = str(row, ["id", "sessionId", "key"]) ?? UUID().uuidString
            let agent = str(row, ["agentId", "agent", "name"]) ?? "unknown"
            let status = str(row, ["status", "state"]) ?? "unknown"
            let detail = str(row, ["task", "doing", "lastMessage", "summary"]) ?? "No detail"
            let model = str(row, ["model", "modelId"])
            let updated = date(row, ["updatedAt", "lastSeen", "timestamp"])
            return GatewaySessionSummary(id: id, agentId: agent, title: "\(agent)", status: status, detail: detail, model: model, updatedAt: updated)
        }
    }

    private func decodeAgentsAsSessions(data: Data) -> [GatewaySessionSummary] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rows = extractArray(raw)
        return rows.map { row in
            let id = str(row, ["id", "agentId", "name"]) ?? UUID().uuidString
            let agent = str(row, ["agentId", "name", "id"]) ?? "unknown"
            let status = str(row, ["status", "state"]) ?? "available"
            let detail = str(row, ["description", "role", "task"]) ?? "Agent listed"
            let model = str(row, ["model", "defaultModel"])
            return GatewaySessionSummary(id: id, agentId: agent, title: agent, status: status, detail: detail, model: model, updatedAt: nil)
        }
    }

    private func dedupe(_ rows: [GatewaySessionSummary]) -> [GatewaySessionSummary] {
        var map: [String: GatewaySessionSummary] = [:]
        for row in rows { map[row.id] = row }
        return map.values.sorted { $0.title < $1.title }
    }

    private func extractArray(_ obj: Any) -> [[String: Any]] {
        if let arr = obj as? [[String: Any]] { return arr }
        if let dict = obj as? [String: Any] {
            for key in ["sessions", "agents", "data", "items", "results"] {
                if let arr = dict[key] as? [[String: Any]] { return arr }
            }
        }
        return []
    }

    private func str(_ row: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = row[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func date(_ row: [String: Any], _ keys: [String]) -> Date? {
        for key in keys {
            if let ts = row[key] as? TimeInterval { return Date(timeIntervalSince1970: ts) }
            if let str = row[key] as? String, let ts = ISO8601DateFormatter().date(from: str) { return ts }
        }
        return nil
    }
}

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private let onState: (StreamState) -> Void
    private let onChunk: (String) -> Void
    private let onComplete: () -> Void
    private let onError: (String) -> Void

    init(
        onState: @escaping (StreamState) -> Void,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onState = onState
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onState(.streaming)
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        while let lineEnd = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineEnd.lowerBound])
            buffer.removeSubrange(buffer.startIndex...lineEnd.upperBound)

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)

            if payload == "[DONE]" {
                DispatchQueue.main.async { self.onState(.idle); self.onComplete() }
                return
            }

            guard
                let data = payload.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let first = choices.first
            else { continue }

            let delta = first["delta"] as? [String: Any]
            if let content = delta?["content"] as? String {
                DispatchQueue.main.async { self.onChunk(content) }
            } else if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                DispatchQueue.main.async { self.onChunk(content) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError, error.code == .cancelled {
            DispatchQueue.main.async { self.onState(.idle) }
            return
        }
        if let error {
            DispatchQueue.main.async {
                self.onState(.failed(error.localizedDescription))
                self.onError(error.localizedDescription)
            }
        } else {
            DispatchQueue.main.async {
                self.onState(.idle)
                self.onComplete()
            }
        }
    }
}
