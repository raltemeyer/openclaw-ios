import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var gateway: GatewayService
    @State private var testingConnection = false
    @State private var connectionResult: ConnectionResult?
    @State private var showToken = false

    enum ConnectionResult {
        case success, failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Gateway Section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gateway URL").font(.caption).foregroundStyle(.secondary)
                        TextField("http://192.168.x.x:18789", text: $settings.gatewayURL)
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

                            Button {
                                showToken.toggle()
                            } label: {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Gateway")
                } footer: {
                    Text("Your OpenClaw gateway URL and auth token. For local network access use your Mac's IP. For remote access, use your Tailscale IP.")
                }

                // Connection Test
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if testingConnection {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(testingConnection ? "Testing…" : "Test Connection")
                        }
                    }
                    .disabled(testingConnection || !settings.isConfigured)

                    if let result = connectionResult {
                        switch result {
                        case .success:
                            Label("Connected successfully", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    HStack {
                        Circle()
                            .fill(gateway.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(gateway.isConnected ? "Gateway reachable" : "Gateway unreachable")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Connection")
                }

                // Agents Section
                Section("Agents") {
                    ForEach(Agent.all) { agent in
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(agent.swiftUIColor.gradient)
                                    .frame(width: 32, height: 32)
                                Image(systemName: agent.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name).font(.subheadline.bold())
                                Text(agent.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(agent.id)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(4)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                // Options
                Section("Options") {
                    Toggle("Streaming responses", isOn: $settings.streamingEnabled)
                }

                // Quick Setup
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mac mini (local)")
                            .font(.caption.bold())
                        Text("URL: http://<mac-ip>:18789")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                        Text("Token: found in openclaw.json → gateway.auth.token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        Text("Remote (Tailscale)")
                            .font(.caption.bold())
                        Text("URL: http://<tailscale-ip>:18789")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                } header: {
                    Text("Setup Guide")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func testConnection() {
        testingConnection = true
        connectionResult = nil
        gateway.checkConnection()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            testingConnection = false
            connectionResult = gateway.isConnected ? .success : .failure("Cannot reach gateway at \(settings.gatewayURL)")
        }
    }
}
