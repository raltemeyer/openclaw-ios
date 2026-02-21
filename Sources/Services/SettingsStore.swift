import Foundation
import Combine

struct GatewayProfileConfig: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var gatewayURL: String
    var networkProfile: String
    var selectedAgentId: String
    var visibleAgentIds: [String]
    var tabOrder: [String]

    static let `default` = GatewayProfileConfig(
        id: "default",
        name: "Default",
        gatewayURL: "http://100.64.0.1:18789",
        networkProfile: "tailscale",
        selectedAgentId: "main",
        visibleAgentIds: Agent.all.map(\.id),
        tabOrder: Agent.all.map(\.id)
    )
}

@MainActor
class SettingsStore: ObservableObject {
    @Published var gatewayURL: String { didSet { persistCurrentProfile() } }
    @Published var gatewayToken: String { didSet { KeychainService.saveToken(gatewayToken, for: activeProfileId) } }
    @Published var selectedAgentId: String { didSet { persistCurrentProfile() } }
    @Published var streamingEnabled: Bool {
        didSet { UserDefaults.standard.set(streamingEnabled, forKey: "streamingEnabled") }
    }
    @Published var gatewayProfile: String { didSet { persistCurrentProfile() } }

    @Published var profiles: [GatewayProfileConfig] { didSet { persistProfiles() } }
    @Published var activeProfileId: String {
        didSet {
            UserDefaults.standard.set(activeProfileId, forKey: "activeProfileId")
            loadActiveProfileIntoPublishedState()
        }
    }

    @Published var visibleAgentIds: [String] { didSet { normalizeAgentPreferencesAndPersist() } }
    @Published var agentTabOrder: [String] { didSet { normalizeAgentPreferencesAndPersist() } }

    private var isApplyingProfile = false

    init() {
        let decodedProfiles = Self.loadProfilesFromDefaults()

        if let decodedProfiles, !decodedProfiles.isEmpty {
            self.profiles = decodedProfiles
        } else {
            // Backward-compatible migration from legacy single-profile keys.
            let legacyURL = UserDefaults.standard.string(forKey: "gatewayURL") ?? GatewayProfileConfig.default.gatewayURL
            let legacySelected = UserDefaults.standard.string(forKey: "selectedAgentId") ?? "main"
            let legacyNetworkProfile = UserDefaults.standard.string(forKey: "gatewayProfile") ?? "tailscale"

            self.profiles = [
                GatewayProfileConfig(
                    id: "default",
                    name: "Default",
                    gatewayURL: legacyURL,
                    networkProfile: legacyNetworkProfile,
                    selectedAgentId: legacySelected,
                    visibleAgentIds: Agent.all.map(\.id),
                    tabOrder: Agent.all.map(\.id)
                )
            ]
        }

        self.streamingEnabled = UserDefaults.standard.object(forKey: "streamingEnabled") as? Bool ?? true

        let storedActive = UserDefaults.standard.string(forKey: "activeProfileId")
        self.activeProfileId = storedActive ?? profiles.first?.id ?? "default"

        let current = profiles.first(where: { $0.id == activeProfileId }) ?? profiles[0]
        self.gatewayURL = current.gatewayURL
        self.gatewayProfile = current.networkProfile
        self.selectedAgentId = current.selectedAgentId
        self.visibleAgentIds = current.visibleAgentIds
        self.agentTabOrder = current.tabOrder

        let scopedToken = KeychainService.loadToken(for: activeProfileId)
        let legacyToken = UserDefaults.standard.string(forKey: "gatewayToken")
        self.gatewayToken = (scopedToken?.isEmpty == false) ? scopedToken! : (legacyToken ?? "")

        if scopedToken == nil, let legacyToken, !legacyToken.isEmpty {
            KeychainService.saveToken(legacyToken, for: activeProfileId)
            UserDefaults.standard.removeObject(forKey: "gatewayToken")
        }

        normalizeAgentPreferencesAndPersist()
        persistProfiles()
    }

    var selectedAgent: Agent {
        orderedVisibleAgents.first(where: { $0.id == selectedAgentId }) ?? orderedVisibleAgents.first ?? .default
    }

    var isConfigured: Bool {
        !gatewayURL.isEmpty && !gatewayToken.isEmpty
    }

    var orderedVisibleAgents: [Agent] {
        let visible = Set(visibleAgentIds)
        let order = normalizedTabOrder()
        return order.compactMap { id in
            guard visible.contains(id) else { return nil }
            return Agent.all.first(where: { $0.id == id })
        }
    }

    var visibleAgentsForReorder: [Agent] {
        orderedVisibleAgents
    }

    var hiddenAgents: [Agent] {
        let visible = Set(visibleAgentIds)
        return normalizedTabOrder().compactMap { id in
            guard !visible.contains(id) else { return nil }
            return Agent.all.first(where: { $0.id == id })
        }
    }

    func isAgentVisible(_ id: String) -> Bool {
        visibleAgentIds.contains(id)
    }

    func setAgentVisibility(_ id: String, visible: Bool) {
        if visible {
            if !visibleAgentIds.contains(id) {
                visibleAgentIds.append(id)
            }
            if !agentTabOrder.contains(id) {
                agentTabOrder.append(id)
            }
        } else {
            if visibleAgentIds.count <= 1, visibleAgentIds.contains(id) {
                return // always keep at least one visible agent
            }
            visibleAgentIds.removeAll { $0 == id }
            if selectedAgentId == id {
                selectedAgentId = orderedVisibleAgents.first?.id ?? Agent.default.id
            }
        }
    }

    func moveVisibleAgents(fromOffsets: IndexSet, toOffset: Int) {
        var visibleOrder = orderedVisibleAgents.map(\.id)
        let moving = fromOffsets.sorted().map { visibleOrder[$0] }
        for index in fromOffsets.sorted(by: >) {
            visibleOrder.remove(at: index)
        }
        var destination = toOffset
        for source in fromOffsets where source < toOffset {
            destination -= 1
        }
        visibleOrder.insert(contentsOf: moving, at: max(0, min(destination, visibleOrder.count)))

        var newGlobalOrder: [String] = []
        let hidden = hiddenAgents.map(\.id)
        let normalized = normalizedTabOrder()

        for id in normalized {
            if hidden.contains(id) {
                newGlobalOrder.append(id)
            } else if let next = visibleOrder.first {
                newGlobalOrder.append(next)
                visibleOrder.removeFirst()
            }
        }

        // In case new IDs were appended and not in normalized yet.
        for remaining in visibleOrder where !newGlobalOrder.contains(remaining) {
            newGlobalOrder.append(remaining)
        }

        agentTabOrder = newGlobalOrder
    }

    func addProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let new = GatewayProfileConfig(
            id: "profile-\(UUID().uuidString)",
            name: trimmed,
            gatewayURL: GatewayProfileConfig.default.gatewayURL,
            networkProfile: "tailscale",
            selectedAgentId: Agent.default.id,
            visibleAgentIds: Agent.all.map(\.id),
            tabOrder: Agent.all.map(\.id)
        )
        profiles.append(new)
        activeProfileId = new.id
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

    // MARK: - Internal persistence

    private func normalizedTabOrder() -> [String] {
        var order = agentTabOrder.filter { id in Agent.all.contains(where: { $0.id == id }) }
        for id in Agent.all.map(\.id) where !order.contains(id) {
            order.append(id)
        }
        return order
    }

    private func normalizeAgentPreferencesAndPersist() {
        if isApplyingProfile { return }

        let knownIds = Set(Agent.all.map(\.id))
        var cleanedVisible = visibleAgentIds.filter { knownIds.contains($0) }
        if cleanedVisible.isEmpty {
            cleanedVisible = [Agent.default.id]
        }

        var cleanedOrder = agentTabOrder.filter { knownIds.contains($0) }
        for id in Agent.all.map(\.id) where !cleanedOrder.contains(id) {
            cleanedOrder.append(id)
        }

        if cleanedVisible != visibleAgentIds {
            visibleAgentIds = cleanedVisible
            return
        }
        if cleanedOrder != agentTabOrder {
            agentTabOrder = cleanedOrder
            return
        }

        if !cleanedVisible.contains(selectedAgentId) {
            selectedAgentId = cleanedVisible.first ?? Agent.default.id
            return
        }

        persistCurrentProfile()
    }

    private func persistCurrentProfile() {
        if isApplyingProfile { return }
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }

        profiles[idx].gatewayURL = gatewayURL
        profiles[idx].networkProfile = gatewayProfile
        profiles[idx].selectedAgentId = selectedAgentId
        profiles[idx].visibleAgentIds = visibleAgentIds
        profiles[idx].tabOrder = agentTabOrder

        // Backward compatibility with older app versions using these keys.
        UserDefaults.standard.set(gatewayURL, forKey: "gatewayURL")
        UserDefaults.standard.set(selectedAgentId, forKey: "selectedAgentId")
        UserDefaults.standard.set(gatewayProfile, forKey: "gatewayProfile")
    }

    private func loadActiveProfileIntoPublishedState() {
        guard let profile = profiles.first(where: { $0.id == activeProfileId }) else { return }
        isApplyingProfile = true
        gatewayURL = profile.gatewayURL
        gatewayProfile = profile.networkProfile
        selectedAgentId = profile.selectedAgentId
        visibleAgentIds = profile.visibleAgentIds
        agentTabOrder = profile.tabOrder
        gatewayToken = KeychainService.loadToken(for: activeProfileId) ?? ""
        isApplyingProfile = false
        normalizeAgentPreferencesAndPersist()
    }

    private func persistProfiles() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profiles) {
            UserDefaults.standard.set(data, forKey: "gatewayProfiles.v2")
        }
    }

    private static func loadProfilesFromDefaults() -> [GatewayProfileConfig]? {
        guard let data = UserDefaults.standard.data(forKey: "gatewayProfiles.v2") else { return nil }
        return try? JSONDecoder().decode([GatewayProfileConfig].self, from: data)
    }
}
