//
//  SettingsView.swift
//  VexSign — organized Settings; tint-coherent, no “More” indirection
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

                // MARK: Personalization — kept together
                NBSection(.localized("Personalization"), systemName: "paintbrush") {
                    NavigationLink(destination: AppearanceView()) {
                        Label(.localized("Appearance"), systemImage: "paintbrush.fill")
                    }
                    NavigationLink(destination: AppIconView(currentIcon: $_currentIcon)) {
                        Label(.localized("App Icon"), systemImage: "app.badge.fill")
                    }
                    NavigationLink(destination: TabBarSettingsView()) {
                        Label(.localized("Tab Bar"), systemImage: "squares.below.rectangle")
                    }
                    NavigationLink(destination: DownloadsSettingsView()) {
                        Label(.localized("Downloads"), systemImage: "arrow.down.circle.fill")
                    }
                    NavigationLink(destination: UpdatesSettingsView()) {
                        HStack {
                            Label(.localized("Updates"), systemImage: "arrow.triangle.2.circlepath")
                            if _selfUpdate.available != nil {
                                Spacer()
                                Circle().fill(Color.userTint).frame(width: 8, height: 8)
                            }
                        }
                    }
                    NavigationLink(destination: AutomationView()) {
                        Label(.localized("Automation"), systemImage: "bolt.badge.clock.fill")
                    }
                } footer: {
                    Text(.localized("Make VexSign yours — theme, icon, tab order and background behaviors."))
                }

                NBSection(.localized("Security")) {
                    NavigationLink(destination: AppLockSettingsView()) {
                        Label(.localized("App Lock"), systemImage: "lock.iphone")
                    }
                    NavigationLink(destination: CertificateExpirySettingsView()) {
                        Label(.localized("Expiry Reminders"), systemImage: "bell.badge.fill")
                    }
                } footer: {
                    Text(.localized("Lock the app behind Face ID or a passcode, and get notified before your certificates expire."))
                }

                NBSection(.localized("Game Mode"), systemName: "gamecontroller") {
                    Toggle(isOn: $_gameMode) {
                        Label(.localized("Game Mode"), systemImage: "gamecontroller.fill")
                    }
                    .tint(Color.userTint)
                    .onChange(of: _gameMode) { enabled in
                        enabled ? GameMode.enable() : GameMode.disable()
                    }
                    NavigationLink(destination: GameModeView()) {
                        Label(.localized("What It Pauses"), systemImage: "info.circle.fill")
                    }
                } footer: {
                    Text(.localized("Stops downloads and the background update pass while you play. Signing and installing what you already have keeps working."))
                }

                NBSection(.localized("Certificates")) {
                    if let cert = selectedCertificate {
                        CertificatesCellView(cert: cert)
                    } else {
                        Text(.localized("No Certificate"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(destination: CertificatesView()) {
                        Label(.localized("Certificates"), systemImage: "checkmark.seal.fill")
                    }
                } footer: {
                    Text(.localized("Add and manage certificates used for signing applications."))
                }

                NBSection(.localized("Signing & Tweaks")) {
                    NavigationLink(destination: ConfigurationView()) {
                        Label(.localized("Signing Options"), systemImage: "signature")
                    }
                    NavigationLink(destination: SigningProfilesView()) {
                        Label(.localized("Signing Profiles"), systemImage: "person.crop.rectangle.stack.fill")
                    }
                    NavigationLink {
                        TweakLibraryList().navigationTitle(.localized("Tweaks"))
                    } label: {
                        Label(.localized("Tweaks"), systemImage: "wrench.and.screwdriver.fill")
                    }
                    NavigationLink(destination: FilesCompressionView()) {
                        Label(.localized("Files & Compression"), systemImage: "archivebox.fill")
                    }
                    NavigationLink(destination: InstallationView()) {
                        Label(.localized("Installation"), systemImage: "arrow.down.app.fill")
                    }
                } footer: {
                    Text(.localized("How apps are signed, compressed and modified — plus how they’re installed."))
                }

                NBSection(.localized("Services")) {
                    NavigationLink(destination: WebManagerView()) {
                        Label(.localized("Web Manager"), systemImage: "externaldrive.badge.wifi")
                    }
                    NavigationLink(destination: EcosystemView()) {
                        Label("Ecosystem", systemImage: "square.stack.3d.up.fill")
                    }
                    NavigationLink(destination: CloudSigningView()) {
                        Label(.localized("Cloud Signing"), systemImage: "cloud.fill")
                    }
                    NavigationLink(destination: IPAExplorerHomeView()) {
                        Label(.localized("IPA Explorer"), systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(destination: LogsHistoryView()) {
                        Label(.localized("Activity Logs"), systemImage: "text.alignleft")
                    }
                }

                _directories()

                NBSection(.localized("Maintenance")) {
                    NavigationLink(destination: CleanupView()) {
                        Label(.localized("Auto Cleanup"), systemImage: "sparkles")
                    }
                    NavigationLink(destination: StorageView()) {
                        Label(.localized("Storage"), systemImage: "internaldrive.fill")
                    }
                    NavigationLink(destination: BackupView()) {
                        Label(.localized("Backup & Restore"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink(destination: ResetView()) {
                        Label(.localized("Reset"), systemImage: "trash.fill")
                    }
                } footer: {
                    Text(.localized("Clean up after signing and installing automatically, check what is using space, back up your setup, or reset the app."))
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
                    Text(verbatim: .localized("About %@", arguments: Bundle.main.name))
                } icon: {
                    FRAppIconView(size: 23)
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
            Text(.localized("If any issues occur within the app please report it via the GitHub repository. When submitting an issue, make sure to submit detailed information."))
        }
    }

    @ViewBuilder
    func _directories() -> some View {
        NBSection(.localized("File Management")) {
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
