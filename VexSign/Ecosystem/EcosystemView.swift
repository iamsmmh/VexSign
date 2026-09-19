import SwiftUI

struct EcosystemView: View {
    @AppStorage("VexSign.ecosystem.repositoryAutoRefresh") private var autoRefresh = false
    var body: some View {
        List {
            Section("Publish & Discover") {
                NavigationLink(destination: RepositoryBuilderView()) { Label("Repository Builder", systemImage: "shippingbox") }
                NavigationLink(destination: DiscoveryView()) { Label("Discovery", systemImage: "sparkles") }
            }
            Section("Repository Sync") {
                Toggle("Automatic Six-Hour Refresh", isOn: $autoRefresh)
                    .onChange(of: autoRefresh) { _ in EcosystemMaintenance.schedule() }
                Text("Refreshes at startup and during available background time. iOS controls the actual schedule. Game Mode pauses network work.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Signing Tools") {
                NavigationLink(destination: CertificateDashboardView()) { Label("Certificate Health", systemImage: "checkmark.shield") }
                NavigationLink(destination: OTAView()) { Label("OTA Distribution", systemImage: "qrcode") }
                NavigationLink(destination: CloneWizardView()) { Label("Clone Wizard", systemImage: "square.on.square") }
                NavigationLink(destination: AnalyticsView()) { Label("Analytics", systemImage: "chart.bar") }
            }
        }.navigationTitle("Ecosystem")
    }
}
