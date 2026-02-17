import SwiftUI

@main
struct OpenClawApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var gatewayService = GatewayService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(gatewayService)
                .onAppear {
                    gatewayService.configure(with: settingsStore)
                }
                .onChange(of: settingsStore.gatewayURL) { _, _ in
                    gatewayService.configure(with: settingsStore)
                }
                .onChange(of: settingsStore.gatewayToken) { _, _ in
                    gatewayService.configure(with: settingsStore)
                }
        }
    }
}
