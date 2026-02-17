import Foundation
import Combine

@MainActor
class GatewayService: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?

    private var baseURL: String = ""
    private var token: String = ""
    private var activeTask: URLSessionDataTask?
    private var session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    func configure(with settings: SettingsStore) {
        self.baseURL = settings.gatewayURL
        self.token = settings.gatewayToken
        checkConnection()
    }

    func checkConnection() {
        guard !baseURL.isEmpty, !token.isEmpty else {
            isConnected = false
            connectionError = "Gateway not configured"
            return
        }

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            connectionError = "Invalid gateway URL"
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10

        let body: [String: Any] = [
            "model": "openclaw",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5,
            "stream": false
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode < 500 {
                    self?.isConnected = true
                    self?.connectionError = nil
                } else {
                    self?.isConnected = false
                    self?.connectionError = error?.localizedDescription ?? "Cannot reach gateway"
                }
            }
        }.resume()
    }

    // MARK: - Streaming Chat

    func sendMessage(
        _ text: String,
        agentId: String,
        history: [Message],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            onError("Invalid gateway URL")
            return
        }

        var messages: [[String: String]] = history.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model": "openclaw:\(agentId)",
            "messages": messages,
            "stream": true
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300

        let delegate = SSEDelegate(onChunk: onChunk, onComplete: onComplete, onError: onError)
        let streamSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = streamSession.dataTask(with: req)
        task.resume()

        // Store so we can cancel
        activeTask = task
    }

    func cancelStreaming() {
        activeTask?.cancel()
        activeTask = nil
    }
}

// MARK: - SSE Delegate

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private let onChunk: (String) -> Void
    private let onComplete: () -> Void
    private let onError: (String) -> Void

    init(
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Process complete lines
        while let lineEnd = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineEnd.lowerBound])
            buffer.removeSubrange(buffer.startIndex...lineEnd.upperBound)

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" {
                DispatchQueue.main.async { self.onComplete() }
                return
            }

            guard
                let data = payload.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let delta = choices.first?["delta"] as? [String: Any],
                let content = delta["content"] as? String
            else { continue }

            DispatchQueue.main.async { self.onChunk(content) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError, error.code == .cancelled { return }
        if let error = error {
            DispatchQueue.main.async { self.onError(error.localizedDescription) }
        } else {
            DispatchQueue.main.async { self.onComplete() }
        }
    }
}
