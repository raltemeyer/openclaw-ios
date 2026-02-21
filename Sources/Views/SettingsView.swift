import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var gateway: GatewayService
    @State private var testingConnection = false
    @State private var connectionResult: ConnectionResult?
    @State private var showToken = false
    @State private var newProfileName = ""

    enum ConnectionResult {
        case success, failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenClaw Instance") {
                    Picker("Active Profile", selection: $settings.activeProfileId) {
                        ForEach(settings.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }

                    HStack {
                        TextField("New profile name", text: $newProfileName)
                        Button("Add") {
                            settings.addProfile(named: newProfileName)
                            newProfileName = ""
                        }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text("Each profile stores its own gateway URL/token and agent tab preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Gateway Profile") {
                    Picker("Profile", selection: $settings.gatewayProfile) {
                        Text("Custom").tag("custom")
                        Text("Local LAN").tag("lan")
                        Text("Tailscale (Recommended)").tag("tailscale")
                    }
                    .onChange(of: settings.gatewayProfile) { _, newValue in
                        settings.applyProfile(newValue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gateway URL").font(.caption).foregroundStyle(.secondary)
                        TextField("http://100.x.y.z:18789", text: $settings.gatewayURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auth Token").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Group {
                                if showToken {
                                    TextField("Gateway token", text: $settings.gatewayToken)
                                } else {
                                    SecureField("Gateway token", text: $settings.gatewayToken)
                                }
                            }
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showToken.toggle() } label: {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Tailscale-first: use your Mac mini Tailscale IP whenever possible. Keep gateway bound to loopback + tailscale only.")
                }

                Section("Agent Management") {
                    ForEach(settings.agentTabOrder, id: \.self) { id in
                        if let agent = Agent.all.first(where: { $0.id == id }) {
                            Toggle(isOn: Binding(
                                get: { settings.isAgentVisible(id) },
                                set: { settings.setAgentVisibility(id, visible: $0) }
                            )) {
                                HStack {
                                    Image(systemName: agent.icon)
                                    Text(agent.name)
                                }
                            }
                        }
                    }

                    if settings.visibleAgentsForReorder.count > 1 {
                        Text("Reorder visible tabs")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(settings.visibleAgentsForReorder) { agent in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                Image(systemName: agent.icon)
                                Text(agent.name)
                            }
                        }
                        .onMove { fromOffsets, toOffset in
                            settings.moveVisibleAgents(fromOffsets: fromOffsets, toOffset: toOffset)
                        }
                    }

                    if !settings.hiddenAgents.isEmpty {
                        Text("Hidden agents can be re-enabled anytime using the toggles above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Connection + Diagnostics") {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if testingConnection { ProgressView().scaleEffect(0.8) } else { Image(systemName: "network") }
                            Text(testingConnection ? "Testing…" : "Test Connection")
                        }
                    }
                    .disabled(testingConnection || !settings.isConfigured)

                    if let result = connectionResult {
                        switch result {
                        case .success:
                            Label("Connected successfully", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }

                    HStack {
                        Circle().fill(gateway.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(gateway.isConnected ? "Gateway reachable" : "Gateway unreachable").foregroundStyle(.secondary)
                    }

                    switch gateway.streamState {
                    case .idle: Text("Stream state: idle").foregroundStyle(.secondary)
                    case .connecting(let attempt): Text("Stream state: connecting (attempt \(attempt))").foregroundStyle(.secondary)
                    case .reconnecting(let delay, let attempt): Text("Stream state: reconnecting in \(delay)s (attempt \(attempt))").foregroundStyle(.secondary)
                    case .streaming: Text("Stream state: active").foregroundStyle(.secondary)
                    case .failed(let err): Text("Stream error: \(err)").foregroundStyle(.red)
                    }
                }

                Section("Recovery (safe helpers)") {
                    Text("No embedded shell. Copy/paste SSH templates into Terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Restart gateway") {
                        Text("ssh ryan@ryans-mac-studio 'openclaw gateway restart'")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }

                    LabeledContent("Status") {
                        Text("ssh ryan@ryans-mac-studio 'openclaw gateway status'")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }

                    LabeledContent("Tail logs") {
                        Text("ssh ryan@ryans-mac-studio 'tail -n 200 ~/.openclaw/logs/gateway.log'")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section("Options") {
                    Toggle("Streaming responses", isOn: $settings.streamingEnabled)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                EditButton()
            }
        }
    }

    private func testConnection() {
        testingConnection = true
        connectionResult = nil
        gateway.checkConnection()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            testingConnection = false
            connectionResult = gateway.isConnected ? .success : .failure("Cannot reach gateway at \(settings.gatewayURL)")
        }
    }
}
