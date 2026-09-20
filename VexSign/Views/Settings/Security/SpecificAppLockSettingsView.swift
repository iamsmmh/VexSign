//
//  SpecificAppLockSettingsView.swift
//  VexSign — LiveContainer / AppNest Per-App Biometric Lock
//

import SwiftUI
import CoreData
import NimbleViews
import NimbleExtensions

struct SpecificAppLockSettingsView: View {
    @ObservedObject private var lock = AppLockManager.shared
    @State private var searchText = ""

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

    private var lockedCount: Int {
        allApps.filter { app in
            guard let uuid = app.uuid else { return false }
            return lock.isAppLocked(uuid)
        }.count
    }

    var body: some View {
        NBList(.localized("Specific App Lock")) {
            headerSection

            appsListSection
        }
        .searchable(text: $searchText, placement: .platform(), prompt: Text(.localized("Search installed apps...")))
    }

    private var headerSection: some View {
        NBSection(.localized("Per-App Security")) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.userTint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.userTint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(.localized("Specific App Lock"))
                            .font(.headline)
                        if lockedCount > 0 {
                            Text("\(lockedCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.userTint, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(.localized("Require Face ID, Touch ID or Passcode to open, sign, or inspect selected applications."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text(.localized("Ported from LiveContainer. When an app is locked here, VexSign prompts for biometric verification before opening its details, signing sheet, or launching it."))
        }
    }

    private var appsListSection: some View {
        NBSection(.localized("Applications"), secondary: "\(lockedCount) " + .localized("locked")) {
            if allApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(.localized("No Applications in Library"))
                        .font(.subheadline.weight(.semibold))
                    Text(.localized("Import or sign an app first to apply specific biometric locks."))
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
                        let isLocked = lock.isAppLocked(uuid)

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
                                get: { isLocked },
                                set: { _ in
                                    NBHaptic.selection()
                                    lock.toggleAppLock(uuid)
                                }
                            ))
                            .labelsHidden()
                            .tint(Color.userTint)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } footer: {
            Text(.localized("Toggle on any application you wish to protect with biometrics."))
        }
    }
}
