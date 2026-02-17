import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var gateway: GatewayService
    @StateObject private var convoStore = ConversationStore()
    @State private var showSettings = false

    var body: some View {
        if settings.isConfigured {
            mainTabView
        } else {
            SetupView(showSettings: $showSettings)
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
        }
    }

    private var mainTabView: some View {
        TabView(selection: selectedAgentBinding) {
            ForEach(Agent.all) { agent in
                ChatView(agent: agent)
                    .environmentObject(convoStore)
                    .tabItem {
                        Label(agent.name, systemImage: agent.icon)
                    }
                    .tag(agent.id)
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag("settings")
        }
        .tint(settings.selectedAgent.swiftUIColor)
    }

    private var selectedAgentBinding: Binding<String> {
        Binding(
            get: { settings.selectedAgentId },
            set: { settings.selectedAgentId = $0 }
        )
    }
}

// MARK: - Setup View (first launch)

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
