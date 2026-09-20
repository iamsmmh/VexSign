//
//  HiddenAppsSettingsView.swift
//  VexSign — LiveContainer / AppNest Hidden Apps Vault
//

import SwiftUI
import CoreData
import NimbleViews
import NimbleExtensions

struct HiddenAppsSettingsView: View {
    @ObservedObject private var lock = AppLockManager.shared
    @State private var isAuthenticated = false
    @State private var searchText = ""
    @AppStorage("VexSign.security.concealNotifications") private var concealNotifications = true

    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.name, ascending: true)],
        animation: .snappy
    ) private var signedApps: FetchedResults<Signed>

    @FetchRequest(
        entity: Imported.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Imported.name, ascending: true)],
        animation: .snappy
    ) private var importedApps: FetchedResults<Imported>

    private var allApps: [AppInfoPresentable] {
        var list: [AppInfoPresentable] = []
        list.append(contentsOf: signedApps.map { $0 as AppInfoPresentable })
        list.append(contentsOf: importedApps.map { $0 as AppInfoPresentable })
        return list
    }

    private var filteredApps: [AppInfoPresentable] {
        if searchText.isEmpty {
            return allApps
        }
        return allApps.filter { app in
            (app.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (app.identifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var hiddenCount: Int {
        allApps.filter { app in
            guard let uuid = app.uuid else { return false }
            return lock.isAppHidden(uuid)
        }.count
    }

    var body: some View {
        Group {
            if isAuthenticated {
                authenticatedContent
            } else {
                unauthenticatedLockView
            }
        }
        .onAppear {
            requestAccess()
        }
    }

    private var unauthenticatedLockView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.userTint.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.userTint)
            }

            VStack(spacing: 6) {
                Text(.localized("Hidden Apps Vault"))
                    .font(.title2.weight(.bold))
                Text(.localized("Authentication is required to view and configure hidden applications."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                requestAccess()
            } label: {
                Label(
                    AppLockManager.biometryName != nil ? String.localized("Unlock with %@", arguments: AppLockManager.biometryName!) : .localized("Unlock with Passcode"),
                    systemImage: "faceid"
                )
                .font(.headline)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color.userTint, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var authenticatedContent: some View {
        NBList(.localized("Hidden Apps Vault")) {
            vaultOverviewSection

            privacyOptionsSection

            appsListSection
        }
        .searchable(text: $searchText, placement: .platform(), prompt: Text(.localized("Search installed apps...")))
    }

    private var vaultOverviewSection: some View {
        NBSection(.localized("Vault Status")) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(.localized("Hidden Applications"))
                            .font(.headline)
                        if hiddenCount > 0 {
                            Text("\(hiddenCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.purple, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(.localized("Hidden apps are excluded from the main Library list until authenticated."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text(.localized("Ported from LiveContainer. When an application is marked hidden, it vanishes from standard views and searches. Authenticate at the bottom of the Library to reveal them."))
        }
    }

    private var privacyOptionsSection: some View {
        NBSection(.localized("Privacy Options")) {
            Toggle(.localized("Conceal in Notifications"), isOn: $concealNotifications)
                .tint(Color.userTint)
        } footer: {
            Text(.localized("Masks the names and bundle IDs of hidden applications in notification alerts and background sync status."))
        }
    }

    private var appsListSection: some View {
        NBSection(.localized("Manage Hidden Apps"), secondary: "\(hiddenCount) " + .localized("hidden")) {
            if allApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(.localized("No Applications in Library"))
                        .font(.subheadline.weight(.semibold))
                    Text(.localized("Import or sign an app first to manage hiding."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if filteredApps.isEmpty {
                Text(.localized("No matching apps found."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(filteredApps, id: \.uuid) { app in
                    if let uuid = app.uuid {
                        let isHidden = lock.isAppHidden(uuid)

                        HStack(spacing: 12) {
                            FRAppIconView(app: app, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name ?? .localized("Unknown"))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(app.identifier ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { isHidden },
                                set: { _ in
                                    NBHaptic.selection()
                                    lock.toggleHideApp(uuid)
                                }
                            ))
                            .labelsHidden()
                            .tint(Color.purple)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } footer: {
            Text(.localized("Toggle on to conceal an application from your standard library interface."))
        }
    }

    private func requestAccess() {
        lock.authenticateToRevealHidden { success in
            self.isAuthenticated = success
        }
    }
}
