import SwiftUI
import NimbleViews
import NimbleExtensions
import CoreData

// MARK: - Home — organized dashboard, Settings lives in its own tab

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    @State private var isAddingCertificate = false
    @State private var showIPAExplorer = false
    @AppStorage("VexSign.migrationBannerDismissed_v2") private var bannerDismissed = false

    // Live counts for the overview cards
    @FetchRequest(entity: CertificatePair.entity(), sortDescriptors: []) private var certificates: FetchedResults<CertificatePair>
    @FetchRequest(entity: AltSource.entity(), sortDescriptors: []) private var sources: FetchedResults<AltSource>
    @FetchRequest(entity: Signed.entity(), sortDescriptors: []) private var signedApps: FetchedResults<Signed>
    @FetchRequest(entity: Imported.entity(), sortDescriptors: []) private var importedApps: FetchedResults<Imported>

    private var libraryCount: Int { signedApps.count + importedApps.count }

    private func openTab(_ tab: TabEnum) {
        let prefs = TabBarPreferences.shared
        if prefs.isMinimal, !TabBarPreferences.minimalTabs.contains(tab) {
            prefs.setMinimal(false)
        }
        prefs.setHidden(tab, false)
        TabSelectionObserver.shared.selectedTab = tab
    }

    private func openSettingsTab() {
        TabSelectionObserver.shared.selectedTab = .settings
    }

    var body: some View {
        NBNavigationView(.localized("Home")) {
            ScrollView {
                VStack(spacing: Theme.Spacing.section) {
                    if !bannerDismissed { migrationBanner }
                    hero
                    if updateChecker.updateCount > 0 {
                        homeUpdatesSection
                    }
                    statsRow
                    quickActions
                    manageSection
                    toolsSection
                    settingsBanner
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openSettingsTab() } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text(.localized("Settings")))
                    .accessibilityHint(Text(.localized("Open Settings tab")))
                }
            }
            .sheet(isPresented: $isAddingCertificate) {
                CertificatesAddView()
            }
            .task {
                if updateChecker.availableUpdates.isEmpty {
                    await updateChecker.checkNow()
                }
            }
        }
    }

    // MARK: Migration banner — Sources→App Store, Logs→Settings
    private var migrationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.userTint.opacity(0.14)).frame(width: 36, height: 36)
                    Image(systemName: "sparkles").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.userTint) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(.localized("What’s new")).font(.caption.weight(.heavy)).tracking(0.6).foregroundStyle(Color.userTint)
                    Text(.localized("Sources is now App Store • Logs is in Settings")).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer()
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { bannerDismissed = true } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).padding(6).background(Color.primary.opacity(0.08), in: Circle())
                }
                .accessibilityLabel(Text(.localized("Dismiss")))
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Label(.localized("App Store"), systemImage: "bag.fill").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Theme.tintSoft, in: Capsule()).foregroundStyle(Theme.tint)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Label(.localized("Files"), systemImage: "folder.fill").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(red: 0.55, green: 0.47, blue: 0.96).opacity(0.13), in: Capsule())
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Label(.localized("Downloads"), systemImage: "arrow.down.circle.fill").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(red: 0.20, green: 0.66, blue: 0.44).opacity(0.13), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(.localized("New tabs: App Store, Files, Downloads")))
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Hero — gradient header with logo, name and status

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                // Soft gradient halo behind icon
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.userTint.opacity(0.22), Color.userTintDeep.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 112, height: 112)
                    .blur(radius: 8)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.userTint.opacity(0.28), radius: 10, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.0), lineWidth: 1)
                    )
            }

            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Text("VexSign")
                        .font(.title2.bold())
                    // version badge
                    Text(Bundle.main.version)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.userTint.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.userTint)
                        .monospacedDigit()
                }

                Text(.localized("Sign, install, and manage your apps."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                        .shadow(color: .green.opacity(0.5), radius: 4)
                    Text(.localized("Ready to sign"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(verbatim: certificates.isEmpty ? String.localized("No Certificate") : String.localized("Certificate Ready"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(certificates.isEmpty ? .orange : .secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.cardShadow(for: colorScheme), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(Theme.tint.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
        )
        // subtle top gradient accent line
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: NBRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.userTint.opacity(0.55), Color.userTintDeep.opacity(0.0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1.2)
                .clipShape(RoundedRectangle(cornerRadius: NBRadius.large, style: .continuous))
                .padding(.horizontal, 1)
        }
    }

    // MARK: - Updates Available Card for Home (App & Quantity)
    private var homeUpdatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.userTint.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.userTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(.localized("Updates Available"))
                            .font(.headline)
                        Text("\(updateChecker.updateCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.userTint, in: Capsule())
                            .foregroundStyle(.white)
                    }

                    Text(.localized("New versions detected from your repository sources"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink(destination: UpdatesView()) {
                    HStack(spacing: 3) {
                        Text(.localized("See All"))
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.userTint)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                ForEach(updateChecker.availableUpdates.prefix(3)) { item in
                    HStack(spacing: 12) {
                        AsyncImage(url: item.iconURL) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fit)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.userTint.opacity(0.12))
                                    .overlay(
                                        Image(systemName: "app.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.userTint)
                                    )
                            }
                        }
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(item.installedVersion ?? "1.0")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Text(item.sourceVersion ?? "1.1")
                                    .foregroundStyle(Color.userTint)
                                    .fontWeight(.bold)
                                Text("• \(item.sourceName)")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                        }

                        Spacer()

                        if let url = item.downloadURL {
                            Button {
                                _ = DownloadManager.shared.startDownload(
                                    from: url,
                                    id: item.app.currentUniqueId,
                                    appName: item.displayName,
                                    appDescription: item.app.localizedDescription
                                )
                                Toast.info(.localized("Download started"), systemImage: "arrow.down.circle")
                            } label: {
                                Text(.localized("UPDATE"))
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.userTint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if updateChecker.updateCount > 1 {
                    NavigationLink(destination: UpdatesView()) {
                        HStack {
                            Spacer()
                            Label(
                                String.localized("Update All (%lld Apps)", arguments: updateChecker.updateCount),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.userTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Color.userTint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.userTint.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Stats row — 3 compact cards (Sources → App Store)

    private var statsRow: some View {
        HStack(spacing: 12) {
            HomeStatCard(
                icon: "checkmark.seal.fill",
                tint: Color.userTint,
                value: "\(certificates.count)",
                title: .localized("Certificates"),
                subtitle: certificates.isEmpty ? .localized("Add one") : .localized("Ready")
            )
            HomeStatCard(
                icon: "bag.fill",
                tint: Color(red: 0.22, green: 0.60, blue: 0.96),
                value: "\(sources.count)",
                title: .localized("App Store"),
                subtitle: sources.isEmpty ? .localized("Add source") : "\(sources.count) " + .localized("Active")
            )
            HomeStatCard(
                icon: "square.stack.3d.up.fill",
                tint: Color(red: 0.96, green: 0.62, blue: 0.12),
                value: "\(libraryCount)",
                title: .localized("Library"),
                subtitle: libraryCount == 0 ? .localized("Empty") : .localized("Apps")
            )
        }
    }

    // MARK: Quick Actions — 2×2 grid

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: .localized("Quick Actions"), icon: "bolt.fill", tint: Color.userTint)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                HomeActionCard(
                    title: .localized("Library"),
                    subtitle: libraryCount == 0 ? .localized("No apps yet") : "\(libraryCount) " + .localized("Apps"),
                    systemImage: "square.grid.2x2.fill",
                    tint: Color(red: 0.95, green: 0.55, blue: 0.15),
                    background: Color(red: 0.95, green: 0.55, blue: 0.15).opacity(0.13)
                ) { openTab(.library) }

                HomeActionCard(
                    title: .localized("App Store"),
                    subtitle: sources.isEmpty ? .localized("Browse catalog") : .localized("Explore apps"),
                    systemImage: "bag.fill",
                    tint: Color(red: 0.18, green: 0.62, blue: 0.96),
                    background: Color(red: 0.18, green: 0.62, blue: 0.96).opacity(0.12)
                ) { openTab(.appStore) }

                HomeActionCard(
                    title: .localized("Files"),
                    subtitle: .localized("Ksign-style browser"),
                    systemImage: "folder.fill",
                    tint: Color(red: 0.55, green: 0.47, blue: 0.96),
                    background: Color(red: 0.55, green: 0.47, blue: 0.96).opacity(0.12)
                ) { openTab(.files) }

                HomeActionCard(
                    title: .localized("Downloads"),
                    subtitle: .localized("Queue & progress"),
                    systemImage: "arrow.down.circle.fill",
                    tint: Color(red: 0.20, green: 0.66, blue: 0.44),
                    background: Color(red: 0.20, green: 0.66, blue: 0.44).opacity(0.12)
                ) { openTab(.downloads) }

                HomeActionCard(
                    title: .localized("Import Certificate"),
                    subtitle: .localized("P12 + Provision"),
                    systemImage: "plus.rectangle.on.folder.fill",
                    tint: Color.userTint,
                    background: Color.userTint.opacity(0.13)
                ) { isAddingCertificate = true }

                HomeActionCard(
                    title: .localized("IPA Explorer"),
                    subtitle: .localized("Browse & edit"),
                    systemImage: "doc.text.magnifyingglass",
                    tint: Color(red: 0.48, green: 0.42, blue: 0.96),
                    background: Color(red: 0.48, green: 0.42, blue: 0.96).opacity(0.12)
                ) {
                    showIPAExplorer = true
                }
            }
            // Hidden navigation destination for IPA Explorer (organized deep link)
            .background(
                NavigationLink(isActive: $showIPAExplorer) {
                    IPAExplorerHomeView()
                } label: { EmptyView() }
                .hidden()
            )
        }
    }

    // MARK: Manage

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: .localized("Manage"), icon: "slider.horizontal.3", tint: Color.userTint)

            VStack(spacing: 0) {
                NavigationLink { CertificatesView() } label: {
                    HomeToolRow(icon: "checkmark.seal.fill", iconTint: Color.userTint, title: .localized("Certificates"), subtitle: certificates.isEmpty ? .localized("Add and manage signing certificates") : "\(certificates.count) " + .localized("installed"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                NavigationLink { ConfigurationView() } label: {
                    HomeToolRow(icon: "signature", iconTint: Color(red: 0.20, green: 0.66, blue: 0.44), title: .localized("Signing Options"), subtitle: .localized("Entitlements, bundle ID, PPQ & more"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                NavigationLink { SigningProfilesView() } label: {
                    HomeToolRow(icon: "person.crop.rectangle.stack.fill", iconTint: Color(red: 0.48, green: 0.42, blue: 0.96), title: .localized("Signing Profiles"), subtitle: .localized("Save and reuse signing presets"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                NavigationLink { InstallationView() } label: {
                    HomeToolRow(icon: "arrow.down.app.fill", iconTint: Color(red: 0.18, green: 0.62, blue: 0.96), title: .localized("Installation"), subtitle: .localized("Server, Tunnel & Anti-Revoke"))
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: Tools — Logs moved to Settings (single nav bar, no double NBNavigationView)

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: .localized("Tools"), icon: "wrench.and.screwdriver.fill", tint: Color.userTint)

            VStack(spacing: 0) {
                // Tweaks — now reachable here; tab no longer in main bar (moved to suitable place)
                NavigationLink { TweakLibraryList().navigationTitle(.localized("Tweaks")) } label: {
                    HomeToolRow(icon: "wrench.and.screwdriver.fill", iconTint: Color(red: 0.96, green: 0.46, blue: 0.18), title: .localized("Tweaks"), subtitle: .localized("Inject and manage tweaks"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                // Logs — single nav bar: push LogsHistory (no nested NBNavigationView)
                NavigationLink { LogsHistoryView() } label: {
                    HomeToolRow(icon: "text.alignleft", iconTint: Color(red: 0.45, green: 0.45, blue: 0.50), title: .localized("Logs"), subtitle: .localized("Activity logs • now in Settings"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                NavigationLink { IPAExplorerHomeView() } label: {
                    HomeToolRow(icon: "folder.fill", iconTint: Color(red: 0.95, green: 0.71, blue: 0.15), title: .localized("IPA Explorer"), subtitle: .localized("Inspect bundles & entitlements"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                NavigationLink { EcosystemView() } label: {
                    HomeToolRow(icon: "square.stack.3d.up.fill", iconTint: Color(red: 0.20, green: 0.66, blue: 0.44), title: "Ecosystem", subtitle: .localized("Repository sync & health"))
                }
                Divider().padding(.leading, 52).opacity(0.6)
                NavigationLink { UpdateMatchingSettingsView() } label: {
                    HomeToolRow(
                        icon: "slider.horizontal.3",
                        iconTint: Color.userTint,
                        title: .localized("Update Matching"),
                        subtitle: updateChecker.updateCount > 0 ? "\(updateChecker.updateCount) " + .localized("updates available") : .localized("Rules, developer & beta filters")
                    )
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: Settings banner — replaces the old “More options” button

    private var settingsBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.userTint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.userTint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(.localized("Everything else lives in Settings"))
                        .font(.subheadline.weight(.semibold))
                    Text(.localized("Appearance, downloads, storage, backup, cleanup and app preferences."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }

            Button { openSettingsTab() } label: {
                HStack(spacing: 6) {
                    Text(.localized("Open Settings"))
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.userTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(.localized("No more “More” button — the Settings tab is always visible."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.userTint.opacity(0.10), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text(verbatim: "VexSign • " + Bundle.main.version + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—") + ")")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(.localized("On-device signing • No data leaves your device"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Reusable pieces

private struct HomeSectionHeader: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

private struct HomeStatCard: View {
    let icon: String
    let tint: Color
    let value: String
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.13)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(cs == .dark ? 0.08 : 0.05), lineWidth: 1)
        )
    }
}

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let background: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var cs

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(background)
                        .frame(width: 42, height: 42)
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(.localized("Open"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(height: 132)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(cs == .dark ? 0.08 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

private struct HomeToolRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.13))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}


