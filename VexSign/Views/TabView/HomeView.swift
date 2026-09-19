import SwiftUI
import NimbleViews

/// A stable starting point, including shortcuts to screens whose tabs may be hidden.
struct HomeView: View {
    @State private var isAddingCertificate = false

    private func openTab(_ tab: TabEnum) {
        let preferences = TabBarPreferences.shared

        // Minimal Mode hides everything but Home and Settings; using a Home shortcut
        // to reach a hidden tab means the user wants it back.
        if preferences.isMinimal, !TabBarPreferences.minimalTabs.contains(tab) {
            preferences.setMinimal(false)
        }

        preferences.setHidden(tab, false)
        TabSelectionObserver.shared.selectedTab = tab
    }

    var body: some View {
        NBNavigationView(.localized("Home")) {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityHidden(true)
                        Text("VexSign").font(.title2.bold())
                        Text(.localized("Sign, install, and manage your apps."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }

                Section(.localized("Quick Actions")) {
                    Button {
                        openTab(.library)
                    } label: {
                        Label(.localized("Library"), systemImage: TabEnum.library.icon)
                    }
                    Button {
                        openTab(.sources)
                    } label: {
                        Label(.localized("Sources"), systemImage: TabEnum.sources.icon)
                    }
                    Button {
                        isAddingCertificate = true
                    } label: {
                        Label(.localized("Import Certificate"), systemImage: "plus.rectangle.on.folder")
                    }
                    NavigationLink {
                        CertificatesView()
                    } label: {
                        Label(.localized("Certificates"), systemImage: "checkmark.seal")
                    }
                    NavigationLink {
                        IPAExplorerHomeView()
                    } label: {
                        Label(.localized("IPA Explorer"), systemImage: "folder")
                    }
                }

                Section(.localized("Options")) {
                    NavigationLink {
                        ConfigurationView()
                    } label: {
                        Label(.localized("Signing Options"), systemImage: "signature")
                    }
                    NavigationLink {
                        InstallationView()
                    } label: {
                        Label(.localized("Installation"), systemImage: "arrow.down.app")
                    }
                    Button {
                        openTab(.tweaks)
                    } label: {
                        Label(.localized("Tweaks"), systemImage: TabEnum.tweaks.icon)
                    }
                    Button {
                        openTab(.logs)
                    } label: {
                        Label(.localized("Logs"), systemImage: TabEnum.logs.icon)
                    }
                    NavigationLink {
                        TabBarSettingsView()
                    } label: {
                        Label(.localized("Tab Bar"), systemImage: "squares.below.rectangle")
                    }
                }
            }
            .sheet(isPresented: $isAddingCertificate) {
                CertificatesAddView()
            }
        }
    }
}
