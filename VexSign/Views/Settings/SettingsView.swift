//
//  SettingsView.swift
//  VexSign — Smartly Categorized & Organized Settings
//  Incorporating best features from FlareStore, LiveContainer, Feather, FeatherPlus,
//  Ksign, KoSign, RyukSign, MySignReincarnated, SideStore, and AppNest.
//

import SwiftUI
import NimbleViews
import UIKit
import Darwin
import IDeviceSwift

struct SettingsView: View {
    @AppStorage("vexsign.selectedCert") private var _storedSelectedCert: Int = 0
    @AppStorage(GameMode.enabledKey) private var _gameMode: Bool = false
    @State private var _currentIcon: String? = UIApplication.shared.alternateIconName
    @ObservedObject private var _selfUpdate = SelfUpdateManager.shared
    @ObservedObject private var _updateChecker = AppUpdateChecker.shared
    @ObservedObject private var _lockManager = AppLockManager.shared

    @FetchRequest(
        entity: CertificatePair.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .snappy
    ) private var _certificates: FetchedResults<CertificatePair>

    private var selectedCertificate: CertificatePair? {
        guard _storedSelectedCert >= 0, _storedSelectedCert < _certificates.count else { return nil }
        return _certificates[_storedSelectedCert]
    }

    private let _githubUrl = "https://github.com/iamsmmh/VexSign"
    private let _donationsUrl = "https://github.com/iamsmmh/VexSign"

    var body: some View {
        NBNavigationView(.localized("Settings")) {
            Form {
                #if !NIGHTLY && !DEBUG
                SettingsDonationCellView(site: _donationsUrl)
                #endif

                _aboutSection

                // MARK: 1. Personalization & Interface
                NBSection(.localized("Personalization"), systemName: "paintbrush.fill") {
                    NavigationLink(destination: AppearanceView()) {
                        Label(.localized("Appearance"), systemImage: "paintbrush.fill")
                    }
                    NavigationLink(destination: AppIconView(currentIcon: $_currentIcon)) {
                        Label(.localized("App Icon"), systemImage: "app.badge.fill")
                    }
                    NavigationLink(destination: TabBarSettingsView()) {
                        Label(.localized("Tab Bar"), systemImage: "squares.below.rectangle")
                    }
                    NavigationLink(destination: NotificationsSettingsView()) {
                        Label(.localized("Notifications & Dynamic Island"), systemImage: "bell.badge.fill")
                    }
                } footer: {
                    Text(.localized("Customize themes, accent tints, home screen icon, the fixed tab shell, and Live Activities."))
                }

                // MARK: 2. App Store, Downloads & Updates (FlareStore / SideStore / Ksign)
                NBSection(.localized("App Store & Updates"), systemName: "bag.fill") {
                    NavigationLink(destination: RefreshAndDownloadsSettingsView()) {
                        Label(.localized("Refresh & Background Sync"), systemImage: "arrow.clockwise.icloud.fill")
                    }
                    NavigationLink(destination: DownloadsSettingsView()) {
                        Label(.localized("Download Manager"), systemImage: "arrow.down.circle.fill")
                    }
                    NavigationLink(destination: UpdateMatchingSettingsView()) {
                        HStack {
                            Label(.localized("Update Matching"), systemImage: "slider.horizontal.3")
                            if _updateChecker.updateCount > 0 {
                                Spacer()
                                Text("\(_updateChecker.updateCount)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.userTint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    NavigationLink(destination: FavoritesAndAutoUpdatesSettingsView()) {
                        Label(.localized("Favorites & Auto Updates"), systemImage: "star.circle.fill")
                    }
                    NavigationLink(destination: UpdatesSettingsView()) {
                        HStack {
                            Label(.localized("App Updates"), systemImage: "sparkles")
                            if _selfUpdate.available != nil {
                                Spacer()
                                Circle().fill(Color.userTint).frame(width: 8, height: 8)
                            }
                        }
                    }
                    NavigationLink(destination: AutomationView()) {
                        Label(.localized("Background Automation"), systemImage: "bolt.badge.clock.fill")
                    }
                } footer: {
                    Text(.localized("Background repository refreshing, download network settings, update matching rules, and automated signing."))
                }

                // MARK: 3. Security, Privacy & LiveContainer Vault
                NBSection(.localized("Security & Privacy"), systemName: "lock.shield.fill") {
                    NavigationLink(destination: AppLockSettingsView()) {
                        HStack {
                            Label(.localized("Master App Lock"), systemImage: "lock.iphone")
                            Spacer()
                            Text(AppLockManager.isEnabled ? .localized("On") : .localized("Off"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(destination: SpecificAppLockSettingsView()) {
                        HStack {
                            Label(.localized("Specific App Lock"), systemImage: "lock.fill")
                            if !_lockManager.lockedAppUUIDs.isEmpty {
                                Spacer()
                                Text("\(_lockManager.lockedAppUUIDs.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.userTint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    NavigationLink(destination: HiddenAppsSettingsView()) {
                        HStack {
                            Label(.localized("Hidden Apps Vault"), systemImage: "eye.slash.fill")
                            if !_lockManager.hiddenAppUUIDs.isEmpty {
                                Spacer()
                                Text("\(_lockManager.hiddenAppUUIDs.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.purple, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    NavigationLink(destination: AntiRevokeSettingsView()) {
                        Label(.localized("Anti-Revoke & DNS Shield"), systemImage: "shield.checkered")
                    }
                    NavigationLink(destination: CertificateExpirySettingsView()) {
                        Label(.localized("Expiry Reminders"), systemImage: "bell.badge.fill")
                    }
                } footer: {
                    Text(.localized("Features from LiveContainer, AppNest, and FlareStore. Lock specific apps with Face ID, conceal hidden applications, and block Apple revocation endpoints."))
                }

                // MARK: 4. Signing & Tweaks Engine (Feather / FeatherPlus / MySign)
                NBSection(.localized("Signing & Patches"), systemName: "signature") {
                    if let cert = selectedCertificate {
                        CertificatesCellView(cert: cert)
                    } else {
                        Text(.localized("No Certificate Configured"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(destination: CertificatesView()) {
                        Label(.localized("Certificates Manager"), systemImage: "checkmark.seal.fill")
                    }
                    NavigationLink(destination: ConfigurationView()) {
                        Label(.localized("Signing Options"), systemImage: "signature")
                    }
                    NavigationLink(destination: AdvancedSigningSettingsView()) {
                        Label(.localized("Advanced Signing & Patches"), systemImage: "cpu.fill")
                    }
                    NavigationLink(destination: SigningProfilesView()) {
                        Label(.localized("Signing Profiles"), systemImage: "person.crop.rectangle.stack.fill")
                    }
                    NavigationLink {
                        TweakLibraryList().navigationTitle(.localized("Tweaks"))
                    } label: {
                        Label(.localized("Tweaks & Dylibs"), systemImage: "wrench.and.screwdriver.fill")
                    }
                    NavigationLink(destination: FilesCompressionView()) {
                        Label(.localized("Compression & Packaging"), systemImage: "archivebox.fill")
                    }
                    NavigationLink(destination: InstallationView()) {
                        Label(.localized("Installation Engine"), systemImage: "arrow.down.app.fill")
                    }
                } footer: {
                    Text(.localized("Configure entitlements, PPQ protection, FlareStore iOS 26/27 build SDK spoofing, dylib injection, and local loopback installation."))
                }

                // MARK: 5. LiveContainer, JIT & Services (LiveContainer / SideStore / FlareStore)
                NBSection(.localized("LiveContainer, JIT & Tools"), systemName: "bolt.badge.automatic.fill") {
                    NavigationLink(destination: GuidesView()) {
                        Label(.localized("Guides"), systemImage: "book.fill")
                    }
                    NavigationLink(destination: JITSettingsView()) {
                        Label(.localized("JIT & On-Device Pairing"), systemImage: "bolt.badge.automatic.fill")
                    }
                    NavigationLink(destination: LocationSimulatorSettingsView()) {
                        Label(.localized("Location Simulator"), systemImage: "location.fill")
                    }
                    NavigationLink(destination: WebManagerView()) {
                        Label(.localized("Web Manager & File Server"), systemImage: "externaldrive.badge.wifi")
                    }
                    NavigationLink(destination: IPAExplorerHomeView()) {
                        Label(.localized("IPA Explorer"), systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(destination: EcosystemView()) {
                        Label("Ecosystem", systemImage: "square.stack.3d.up.fill")
                    }
                    NavigationLink(destination: CloudSigningView()) {
                        Label(.localized("Cloud Signing"), systemImage: "cloud.fill")
                    }
                    NavigationLink(destination: GameModeView()) {
                        HStack {
                            Label(.localized("Game Mode"), systemImage: "gamecontroller.fill")
                            Spacer()
                            Text(_gameMode ? .localized("On") : .localized("Off"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(.localized("JIT attachment for emulators, FlareStore location simulator, browser drag-and-drop file upload, bundle inspection, and ecosystem synchronization."))
                }

                // MARK: 6. Storage & Maintenance
                _directories()

                NBSection(.localized("Storage & Maintenance"), systemName: "internaldrive.fill") {
                    NavigationLink(destination: StorageView()) {
                        Label(.localized("Storage Breakdown"), systemImage: "internaldrive.fill")
                    }
                    NavigationLink(destination: CleanupView()) {
                        Label(.localized("Auto Cleanup & Cache"), systemImage: "sparkles")
                    }
                    NavigationLink(destination: BackupView()) {
                        Label(.localized("Backup, Transfer & Migration"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink(destination: IPSWBrowserView()) {
                        Label(.localized("IPSW & Firmware Catalog"), systemImage: "opticaldisc.fill")
                    }
                    NavigationLink(destination: DeviceDiagnosticsView()) {
                        Label(.localized("System Diagnostics"), systemImage: "info.circle.fill")
                    }
                    NavigationLink(destination: LogsHistoryView()) {
                        Label(.localized("Activity Logs"), systemImage: "text.alignleft")
                    }
                    NavigationLink(destination: ResetView()) {
                        Label(.localized("Reset VexSign"), systemImage: "trash.fill")
                    }
                } footer: {
                    Text(.localized("Inspect storage footprint, wipe cached downloads, create full backup archives, browse firmware files, and export diagnostic logs."))
                }
            }
        }
    }
}

// MARK: - Subviews

private extension SettingsView {
    var _aboutSection: some View {
        Section {
            NavigationLink(destination: AboutView()) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: .localized("About %@", arguments: Bundle.main.name))
                            .font(.headline)
                        Text("Version \(Bundle.main.version) • FlareStore & LiveContainer Edition")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    FRAppIconView(size: 26)
                }
            }
            Button(.localized("Submit Feedback"), systemImage: "safari") {
                let bugAction: UIAlertAction = .init(title: .localized("Bug Report"), style: .default) { _ in
                    UIApplication.open(_makeGitHubIssueURL(url: _githubUrl))
                }
                let chooseAction: UIAlertAction = .init(title: .localized("Other"), style: .default) { _ in
                    UIApplication.open(URL(string: "\(_githubUrl)/issues/new/choose")!)
                }
                UIAlertController.showAlertWithCancel(
                    title: .localized("Submit Feedback"),
                    message: nil,
                    actions: [bugAction, chooseAction]
                )
            }
            Button(.localized("GitHub Repository"), systemImage: "safari") {
                UIApplication.open(_githubUrl)
            }
        } footer: {
            Text(.localized("Report bugs or submit feedback to the development team on GitHub."))
        }
    }

    @ViewBuilder
    func _directories() -> some View {
        NBSection(.localized("File Management"), systemName: "folder.badge.gearshape") {
            NavigationLink(destination: FileManagerView(directory: URL.documentsDirectory, isRoot: true)) {
                Label(.localized("File Manager"), systemImage: "folder.badge.gearshape")
            }
            Button(.localized("Open Documents"), systemImage: "folder.fill") {
                UIApplication.open(URL.documentsDirectory.toSharedDocumentsURL()!)
            }
            Button(.localized("Open Archives"), systemImage: "archivebox.fill") {
                UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
            }
            Button(.localized("Open Certificates"), systemImage: "checkmark.seal.fill") {
                UIApplication.open(FileManager.default.certificates.toSharedDocumentsURL()!)
            }
        } footer: {
            Text(.localized("File Manager browses everything VexSign stores, with editing and import built in. The buttons below hand the same folders to the Files app."))
        }
    }

    func _makeGitHubIssueURL(url: String) -> String {
        var configurationSection = "### App Configuration:\n"
        switch UserDefaults.standard.integer(forKey: "VexSign.installationMethod") {
        case 0:
            let serverMethod = UserDefaults.standard.integer(forKey: "VexSign.serverMethod")
            let ipFix = UserDefaults.standard.bool(forKey: "VexSign.ipFix")
            let serverType = (serverMethod == 0) ? "Fully Local" : "Semi Local"
            configurationSection += "- Install method: `Server`\n"
            configurationSection += "  - Server type: `\(serverType)`\n"
            configurationSection += "  - IP Fix: `\(ipFix)`\n"
        case 1:
            let pairingPath = HeartbeatManager.pairingFile()
            let pairingExists = FileManager.default.fileExists(atPath: pairingPath)
            configurationSection += "- Install method: `idevice`\n"
            configurationSection += "  - Pairing file: `\(pairingExists ? "Present" : "Not Present")`\n"
        default:
            configurationSection += "- Install method: `Unknown`\n"
        }
        let body = """
        ### Device Information
        - Device: `\(MobileGestalt().getStringForName("PhysicalHardwareNameString") ?? "Unknown")`
        - iOS Version: `\(UIDevice.current.systemVersion)`
        - App Version: `\(Bundle.main.version)`

        \(configurationSection)

        ### Issue Description
        <!-- Describe your issue here -->

        ### Steps to Reproduce
        1. 
        2. 
        3. 

        ### Expected Behavior

        ### Actual Behavior
        """
        let encodedTitle = "[Bug] replace this with a descriptive title ".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "\(url)/issues/new?template=bug.yml&title=\(encodedTitle)&text=\(encodedBody)"
    }
}
