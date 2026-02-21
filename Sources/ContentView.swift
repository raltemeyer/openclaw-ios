import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var gateway: GatewayService
    @StateObject private var convoStore = ConversationStore()
    @State private var showSettings = false
    @State private var tabSelection = "main"

    var body: some View {
        if settings.isConfigured {
            mainTabView
        } else {
            SetupView(showSettings: $showSettings)
                .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var mainTabView: some View {
        TabView(selection: $tabSelection) {
            ForEach(Agent.all) { agent in
                ChatView(agent: agent)
                    .environmentObject(convoStore)
                    .tabItem { Label(agent.name, systemImage: agent.icon) }
                    .tag(agent.id)
            }

            SystemView()
                .tabItem { Label("System", systemImage: "server.rack") }
                .tag("system")

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag("settings")
        }
        .tint(settings.selectedAgent.swiftUIColor)
        .onAppear {
            tabSelection = settings.selectedAgentId
        }
        .onChange(of: tabSelection) { _, newValue in
            if Agent.all.contains(where: { $0.id == newValue }) {
                settings.selectedAgentId = newValue
            }
        }
    }
}

struct SystemView: View {
    @EnvironmentObject var gateway: GatewayService
    @State private var selectedSession: GatewaySessionSummary?
    @State private var exportStatus: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last refresh")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(gateway.latestSystemSnapshot.fetchedAt.formatted(date: .omitted, time: .standard))
                                .font(.body.weight(.medium))
                        }
                        Spacer()
                        Button("Refresh") {
                            Task { await gateway.refreshSystemSnapshot() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("Active Sessions / Agents") {
                    if gateway.latestSystemSnapshot.sessions.isEmpty {
                        Text("No sessions found via known endpoints.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(gateway.latestSystemSnapshot.sessions) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(session.title).font(.headline)
                                        Spacer()
                                        Text(session.status).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(session.detail).font(.subheadline)
                                    if let model = session.model {
                                        Text("Model: \(model)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let selectedSession {
                    Section("Quick Controls: \(selectedSession.title)") {
                        Button("Reset Session") {
                            Task { exportStatus = await gateway.resetSession(agentId: selectedSession.agentId) }
                        }
                        Button("Stop Run") {
                            Task { exportStatus = await gateway.stopRun(agentId: selectedSession.agentId) }
                        }
                    }
                }

                Section("Diagnostics notes") {
                    ForEach(gateway.latestSystemSnapshot.notes, id: \.self) { note in
                        Text("• \(note)").font(.caption)
                    }
                }

                Section("Remote Ops") {
                    Button("Copy diagnostics report") {
                        let report = diagnosticsReport()
                        UIPasteboard.general.string = report
                        exportStatus = "Diagnostics report copied"
                    }
                    .buttonStyle(.bordered)

                    Text("Use this report when escalating gateway issues from mobile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let exportStatus {
                        Text(exportStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("System")
            .task {
                if gateway.latestSystemSnapshot.sessions.isEmpty {
                    await gateway.refreshSystemSnapshot()
                }
            }
        }
    }

    private func diagnosticsReport() -> String {
        let sessions = gateway.latestSystemSnapshot.sessions.map { "- \($0.title) [\($0.status)] model=\($0.model ?? "unknown")" }.joined(separator: "\n")
        let notes = gateway.latestSystemSnapshot.notes.map { "- \($0)" }.joined(separator: "\n")

        return """
        OpenClaw iOS Diagnostics
        Timestamp: \(Date().formatted(date: .abbreviated, time: .standard))

        Sessions:
        \(sessions.isEmpty ? "- none" : sessions)

        Notes:
        \(notes.isEmpty ? "- none" : notes)
        """
    }
}

struct SetupView: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "pawprint.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text("OpenClaw")
                    .font(.largeTitle.bold())
                Text("Your AI agent hub")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Connect to your Mac mini gateway", systemImage: "server.rack")
                Label("Chat with Hopper, Henry, Mr. DAG & Scout", systemImage: "person.3")
                Label("Streaming responses with live updates", systemImage: "dot.radiowaves.left.and.right")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button {
                showSettings = true
            } label: {
                Label("Connect Gateway", systemImage: "link")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}
