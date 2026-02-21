import Foundation
import Combine

@MainActor
class SettingsStore: ObservableObject {
    @Published var gatewayURL: String {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: "gatewayURL") }
    }
    @Published var gatewayToken: String {
        didSet {
            KeychainService.saveToken(gatewayToken)
            if !gatewayToken.isEmpty {
                // scrub legacy storage once migrated
                UserDefaults.standard.removeObject(forKey: "gatewayToken")
            }
        }
    }
    @Published var selectedAgentId: String {
        didSet { UserDefaults.standard.set(selectedAgentId, forKey: "selectedAgentId") }
    }
    @Published var streamingEnabled: Bool {
        didSet { UserDefaults.standard.set(streamingEnabled, forKey: "streamingEnabled") }
    }
    @Published var gatewayProfile: String {
        didSet { UserDefaults.standard.set(gatewayProfile, forKey: "gatewayProfile") }
    }

    init() {
        self.gatewayURL = UserDefaults.standard.string(forKey: "gatewayURL") ?? "http://100.64.0.1:18789"

        let keychainToken = KeychainService.loadToken()
        let legacyToken = UserDefaults.standard.string(forKey: "gatewayToken")
        let resolvedToken = (keychainToken?.isEmpty == false) ? keychainToken! : (legacyToken ?? "")
        self.gatewayToken = resolvedToken
        if keychainToken == nil, let legacyToken, !legacyToken.isEmpty {
            KeychainService.saveToken(legacyToken)
            UserDefaults.standard.removeObject(forKey: "gatewayToken")
        }

        self.selectedAgentId = UserDefaults.standard.string(forKey: "selectedAgentId") ?? "main"
        self.streamingEnabled = UserDefaults.standard.object(forKey: "streamingEnabled") as? Bool ?? true
        self.gatewayProfile = UserDefaults.standard.string(forKey: "gatewayProfile") ?? "tailscale"
    }

    var selectedAgent: Agent {
        Agent.all.first { $0.id == selectedAgentId } ?? .default
    }

    var isConfigured: Bool {
        !gatewayURL.isEmpty && !gatewayToken.isEmpty
    }

    func applyProfile(_ profile: String) {
        switch profile {
        case "lan":
            if gatewayURL.isEmpty || gatewayURL.contains("100.") { gatewayURL = "http://192.168.1.10:18789" }
        case "tailscale":
            if gatewayURL.isEmpty || gatewayURL.contains("192.168") { gatewayURL = "http://100.64.0.1:18789" }
        default:
            break
        }
    }
}
