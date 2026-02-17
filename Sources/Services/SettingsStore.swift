import Foundation
import Combine

@MainActor
class SettingsStore: ObservableObject {
    @Published var gatewayURL: String {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: "gatewayURL") }
    }
    @Published var gatewayToken: String {
        didSet {
            // Store token in Keychain in production; UserDefaults for MVP
            UserDefaults.standard.set(gatewayToken, forKey: "gatewayToken")
        }
    }
    @Published var selectedAgentId: String {
        didSet { UserDefaults.standard.set(selectedAgentId, forKey: "selectedAgentId") }
    }
    @Published var streamingEnabled: Bool {
        didSet { UserDefaults.standard.set(streamingEnabled, forKey: "streamingEnabled") }
    }

    init() {
        // Default to Mac mini's local IP — update in Settings if needed
        self.gatewayURL = UserDefaults.standard.string(forKey: "gatewayURL") ?? "http://localhost:18789"
        self.gatewayToken = UserDefaults.standard.string(forKey: "gatewayToken") ?? ""
        self.selectedAgentId = UserDefaults.standard.string(forKey: "selectedAgentId") ?? "main"
        self.streamingEnabled = UserDefaults.standard.bool(forKey: "streamingEnabled") != false
    }

    var selectedAgent: Agent {
        Agent.all.first { $0.id == selectedAgentId } ?? .default
    }

    var isConfigured: Bool {
        !gatewayURL.isEmpty && !gatewayToken.isEmpty
    }
}
