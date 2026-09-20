//
//  AppStoreView.swift
//  VexSign — Apple App Store redesign, merges Sources. Single nav bar.
//  Ported from App Store, SideStore, and Ksign with modern Apple feel.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import NukeUI
import CoreData
import AltSourceKit

// MARK: - App Store (Apple Official Style) — Single NavigationStack, Sources merged

struct AppStoreView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = SourcesViewModel.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    @ObservedObject private var premiumFilter = PremiumFilterPreferences.shared

    @State private var searchText = ""
    @State private var selectedSegment: StoreSegment = .discover
    @State private var isAddingPresenting = false
    @State private var appSortOption: AppSortOption = .name
    @State private var selectedCategory: String = "All"

    private let appCategories = ["All", "Utilities", "Emulators", "Tweaked", "Games", "Jailbreak"]

    private let communityRepos: [CommunityRepoItem] = [
        .init(name: "SideStore Community", subtitle: "Official SideStore community apps", url: URL(string: "https://community-apps.sidestore.io/sidecommunity.json")!, iconName: "globe.desk.fill"),
        .init(name: "Ksign Repo", subtitle: "Esign-style curated tools & signers", url: URL(string: "https://raw.githubusercontent.com/Nyasami/Ksign/refs/heads/main/repo.json")!, iconName: "app.badge.fill"),
        .init(name: "LiveContainer", subtitle: "Run multiple iOS apps side-by-side", url: URL(string: "https://raw.githubusercontent.com/LiveContainer/LiveContainer/refs/heads/main/apps.json")!, iconName: "square.stack.3d.up.fill"),
        .init(name: "OatmealDome", subtitle: "Dolphin iOS & emulation utilities", url: URL(string: "https://altstore.oatmealdome.me/")!, iconName: "gamecontroller.fill"),
        .init(name: "Aidoku", subtitle: "Manga & comic reader", url: URL(string: "https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json")!, iconName: "book.fill"),
        .init(name: "Flycast", subtitle: "Sega Dreamcast emulator", url: URL(string: "https://github.com/chachillie/Flycast-iOS/raw/main/flycast-ios.json")!, iconName: "play.circle.fill"),
        .init(name: "iTorrent", subtitle: "BitTorrent client for iOS", url: URL(string: "https://xitrix.github.io/iTorrent/AltStore.json")!, iconName: "arrow.down.circle.fill"),
        .init(name: "UTM", subtitle: "Virtual machines & Linux on iOS", url: URL(string: "https://alt.getutm.app")!, iconName: "display")
    ]

    struct CommunityRepoItem: Identifiable {
        var id: String { url.absoluteString }
        let name: String
        let subtitle: String
        let url: URL
        let iconName: String
    }

    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
        animation: .snappy
    ) private var sources: FetchedResults<AltSource>

    enum StoreSegment: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case apps = "Apps"
        case repositories = "Repositories"
        case updates = "Updates"
        var id: String { rawValue }
    }

    enum AppSortOption: String, CaseIterable {
        case name = "Name"
        case date = "Date"
        case size = "Size"
    }

    // Model representing an app combined with its source repository
    struct SourcedAppItem: Identifiable {
        var id: String { "\(source.identifier ?? "")-\(app.id ?? app.currentName)" }
        let source: AltSource
        let repository: ASRepository
        let app: ASRepository.App
    }

    private var nonExcludedSources: [AltSource] {
        sources.filter { !VexSignAPI.isSourceExcluded($0.identifier ?? $0.sourceURL?.absoluteString ?? "") }
    }

    private var filteredSources: [AltSource] {
        let base = nonExcludedSources
        guard !searchText.isEmpty else { return base.sorted { ($0.name ?? "") < ($1.name ?? "") } }
        return base.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    // All loaded apps from active repositories
    private var allSourcedApps: [SourcedAppItem] {
        var items: [SourcedAppItem] = []
        var seenIDs = Set<String>()

        for source in nonExcludedSources {
            guard let repo = viewModel.sources[source] else { continue }
            for app in repo.apps {
                let appID = app.id ?? app.currentName
                let uniqueKey = SourcePreferences.hideDuplicates ? appID : "\(source.identifier ?? "")-\(appID)"
                if !seenIDs.contains(uniqueKey) {
                    seenIDs.insert(uniqueKey)
                    items.append(SourcedAppItem(source: source, repository: repo, app: app))
                }
            }
        }
        return items
    }

    private var sortedAndFilteredApps: [SourcedAppItem] {
        let base = allSourcedApps
        let categoryFiltered: [SourcedAppItem]
        if selectedCategory == "All" {
            categoryFiltered = base
        } else {
            let cat = selectedCategory.lowercased()
            categoryFiltered = base.filter { item in
                let appCat = (item.app.category ?? "").lowercased()
                let name = item.app.currentName.lowercased()
                let desc = (item.app.currentDescription ?? "").lowercased()
                if cat == "utilities" {
                    return appCat.contains("util") || appCat.contains("tool") || name.contains("tool") || desc.contains("util") || desc.contains("manage")
                } else if cat == "emulators" {
                    return appCat.contains("emu") || name.contains("emu") || desc.contains("emulator") || desc.contains("retro") || desc.contains("gameboy") || desc.contains("dolphin") || desc.contains("utm")
                } else if cat == "tweaked" {
                    return name.contains("++") || name.contains("mod") || name.contains("pro") || name.contains("tweak") || desc.contains("tweak") || desc.contains("unlocked")
                } else if cat == "games" {
                    return appCat.contains("game") || desc.contains("game") || desc.contains("play") || name.contains("game")
                } else if cat == "jailbreak" {
                    return appCat.contains("jailbreak") || name.contains("troll") || desc.contains("jailbreak") || desc.contains("rootless") || desc.contains("sileo")
                }
                return appCat.contains(cat) || name.contains(cat)
            }
        }

        let searched: [SourcedAppItem]
        if searchText.isEmpty {
            searched = categoryFiltered
        } else {
            searched = categoryFiltered.filter {
                $0.app.currentName.localizedCaseInsensitiveContains(searchText) ||
                ($0.app.currentDescription ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.source.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        switch appSortOption {
        case .name:
            return searched.sorted { $0.app.currentName.localizedCaseInsensitiveCompare($1.app.currentName) == .orderedAscending }
        case .date:
            return searched.sorted { ($0.app.date?.date ?? Date.distantPast) > ($1.app.date?.date ?? Date.distantPast) }
        case .size:
            return searched.sorted { ($0.app.size ?? 0) > ($1.app.size ?? 0) }
        }
    }

    private var updateCount: Int { updateChecker.updateCount }

    // MARK: - Body
    var body: some View {
        // ONE navigation bar — NBNavigationView is the only NavigationStack in this tab
        NBNavigationView(.localized("App Store"), displayMode: .large) {
            ScrollView {
                VStack(spacing: 20) {
                    // Apple official header styling
                    headerTodayDate

                    // Apple-style Segmented Pills
                    segmentPills

                    if !searchText.isEmpty {
                        // Live search across both Apps and Repositories
                        searchResultsView
                    } else {
                        // Section content based on selected segment
                        switch selectedSegment {
                        case .discover:
                            discoverSection
                        case .apps:
                            appsCatalogSection
                        case .repositories:
                            repositoriesSection
                        case .updates:
                            updatesSection
                        }
                    }

                    // Activity Logs reference (clean move to Settings, single nav bar)
                    logsMovedFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .scrollIndicators(.hidden)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search Apps & Sources")))
            .refreshable {
                await viewModel.fetchSources(sources, refresh: true)
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAddingPresenting) {
                SourcesAddView().adaptiveSheetSizing()
            }
            .task(id: Array(sources)) {
                await viewModel.fetchSources(sources)
            }
            .onChange(of: premiumFilter.stamp) { _ in
                Task { await viewModel.fetchSources(sources, refresh: true) }
            }
        }
    }

    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    isAddingPresenting = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(Text(.localized("Add Source")))

                // Profile / Settings Menu (styled like App Store Account button)
                Menu {
                    Section(.localized("Updates")) {
                        NavigationLink(destination: UpdateMatchingSettingsView()) {
                            Label(.localized("Update Matching"), systemImage: "slider.horizontal.3")
                        }
                        NavigationLink(destination: FavoritesAndAutoUpdatesSettingsView()) {
                            Label(.localized("Favorites & Auto Updates"), systemImage: "star.circle.fill")
                        }
                        NavigationLink(destination: UpdatesView()) {
                            Label(updateCount > 0 ? String.localized("Pending Updates (%lld)", arguments: updateCount) : .localized("Pending Updates"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    Section(.localized("Sources")) {
                        Button {
                            Task { await viewModel.fetchSources(sources, refresh: true) }
                        } label: {
                            Label(.localized("Refresh All Sources"), systemImage: "arrow.clockwise")
                        }
                    }
                } label: {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            if updateCount > 0 {
                NavigationLink(destination: UpdatesView()) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("\(updateCount)").font(.caption2.weight(.bold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.userTint, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .foregroundStyle(Color.userTint)
                }
            }
        }
    }

    // MARK: - Apple App Store Date & Editorial Header
    private var headerTodayDate: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(todayDateFormatted)
                    .font(.caption.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    Text(.localized("App Store"))
                        .font(.title2.weight(.bold))
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(.localized("On-device"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if !viewModel.isFinished {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 4)
    }

    private var todayDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Apple Style Segmented Filter Pills
    private var segmentPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StoreSegment.allCases) { seg in
                    let isSelected = selectedSegment == seg
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedSegment = seg
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if seg == .updates && updateCount > 0 {
                                Text("\(updateCount)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? .white.opacity(0.25) : Color.userTint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            Text(seg.rawValue)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.userTint : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        .foregroundStyle(isSelected ? .white : .primary)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Discover Section (Apple Official Today View)
    @ViewBuilder
    private var discoverSection: some View {
        VStack(spacing: 24) {
            // Apple Today Hero Editorial Card
            heroTodayCard

            // Updates alert if available
            if updateCount > 0 {
                updatesNotificationCard
            }

            // Must-Have Utilities & Tweaks Shelf (Apple horizontal carousel)
            mustHaveShelf

            // Top Free Sideloaded Apps (Apple ranked 3-row charts)
            topAppsRankedSection

            // Merged Repositories Master Card
            allRepositoriesBannerCard
        }
    }

    // MARK: Hero Editorial Today Card
    private var heroTodayCard: some View {
        let featuredItem = allSourcedApps.first

        return ZStack(alignment: .bottomLeading) {
            // Vibrant Apple-style gradient with depth
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.36, blue: 0.95),
                    Color(red: 0.20, green: 0.52, blue: 1.0),
                    Color(red: 0.45, green: 0.20, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                // Eyebrow badge
                HStack(spacing: 6) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text("FEATURED ON VEXSIGN")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.9))
                }

                // Main headline
                VStack(alignment: .leading, spacing: 4) {
                    Text(featuredItem?.app.currentName ?? "Discover & Sideload")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(featuredItem?.app.currentDescription ?? "Sign & install any iOS app on-device without PC or revocations.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                // Bottom App Bar with GET button & repo logo badge
                if let item = featuredItem {
                    NavigationLink(destination: SourceAppsDetailView(source: item.repository, app: item.app)) {
                        HStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                AppStoreIconView(app: item.app, size: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                // Repo logo badge
                                RepoMiniBadge(source: item.source)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.app.currentName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(item.source.name ?? .localized("Repository"))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }

                            Spacer()

                            DownloadButtonView(app: item.app)
                                .tint(.white)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "globe.desk.fill")
                        Text("\(nonExcludedSources.count) sources connected")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(18)
        }
        .frame(minHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(red: 0.04, green: 0.36, blue: 0.95).opacity(0.28), radius: 18, y: 10)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    // MARK: Must-Have Utilities & Tweaks Shelf
    @ViewBuilder
    private var mustHaveShelf: some View {
        let items = Array(allSourcedApps.prefix(8))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("Must-Have Apps"))
                            .font(.title3.weight(.bold))
                        Text(.localized("Hand-picked community essentials"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation { selectedSegment = .apps }
                    } label: {
                        Text(.localized("See All"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.userTint)
                    }
                }
                .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink(destination: SourceAppsDetailView(source: item.repository, app: item.app)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .bottomTrailing) {
                                        AppStoreIconView(app: item.app, size: 76)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                                            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)

                                        // Repo logo badge
                                        RepoMiniBadge(source: item.source)
                                            .offset(x: 4, y: 4)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.app.currentName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text(item.app.currentDescription ?? item.source.name ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    DownloadButtonView(app: item.app)
                                }
                                .frame(width: 100)
                                .padding(10)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: Top Apps Ranked List (Apple 3-Row Style)
    @ViewBuilder
    private var topAppsRankedSection: some View {
        let topList = Array(allSourcedApps.prefix(9))
        if !topList.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("Top Free Apps"))
                            .font(.title3.weight(.bold))
                        Text(.localized("Popular across all repositories"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation { selectedSegment = .apps }
                    } label: {
                        Text(.localized("See All"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.userTint)
                    }
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(topList.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(destination: SourceAppsDetailView(source: item.repository, app: item.app)) {
                            HStack(spacing: 12) {
                                // Ranking number
                                Text("\(index + 1)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .center)

                                ZStack(alignment: .bottomTrailing) {
                                    AppStoreIconView(app: item.app, size: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                                    RepoMiniBadge(source: item.source)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.app.currentName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(item.app.currentDescription ?? item.source.name ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    if let ver = item.app.currentVersion {
                                        Text(ver)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer(minLength: 8)

                                DownloadButtonView(app: item.app)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < topList.count - 1 {
                            Divider().padding(.leading, 84).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }

    // MARK: All Repositories Master Card
    private var allRepositoriesBannerCard: some View {
        NavigationLink {
            SourceAppsView(object: nonExcludedSources, viewModel: viewModel, onRefresh: {
                await viewModel.fetchSources(sources, refresh: true)
            })
        } label: {
            HStack(spacing: 14) {
                Image("Repositories")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(.localized("All Repositories"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: String.localized("%lld sources • %lld apps available", arguments: nonExcludedSources.count, allSourcedApps.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apps Catalog Section (Ksign App Store Catalog)
    private var appsCatalogSection: some View {
        VStack(spacing: 16) {
            // Category filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(appCategories, id: \.self) { cat in
                        let isSel = selectedCategory == cat
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                selectedCategory = cat
                            }
                        } label: {
                            Text(cat)
                                .font(.caption.weight(isSel ? .bold : .medium))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(isSel ? Color.userTint : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                                .foregroundStyle(isSel ? .white : .primary)
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(isSel ? 0 : 0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            // Sort bar & count header
            HStack {
                Text(verbatim: String.localized("%lld Apps Available", arguments: sortedAndFilteredApps.count))
                    .font(.headline)
                Spacer()
                Menu {
                    Picker("Sort by", selection: $appSortOption) {
                        ForEach(AppSortOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(appSortOption.rawValue)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(uiColor: .quaternarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 4)

            if sortedAndFilteredApps.isEmpty {
                emptyAppsView
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedAndFilteredApps.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(destination: SourceAppsDetailView(source: item.repository, app: item.app)) {
                            HStack(spacing: 12) {
                                ZStack(alignment: .bottomTrailing) {
                                    AppStoreIconView(app: item.app, size: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                                    RepoMiniBadge(source: item.source)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.app.currentName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(item.app.currentDescription ?? item.source.name ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    HStack(spacing: 6) {
                                        if let ver = item.app.currentVersion {
                                            Text("v\(ver)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        if let size = item.app.size, size > 0 {
                                            Text("• \(size.formattedByteCount)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Text("• \(item.source.name ?? "")").font(.caption2).foregroundStyle(Color.userTint).lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 8)

                                DownloadButtonView(app: item.app)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < sortedAndFilteredApps.count - 1 {
                            Divider().padding(.leading, 78).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }

    // MARK: - Repositories Section (Merged Sources Tab)
    private var repositoriesSection: some View {
        VStack(spacing: 16) {
            // Repositories summary header
            HStack {
                Text(.localized("Sources & Repositories"))
                    .font(.headline)
                Spacer()
                Button {
                    isAddingPresenting = true
                } label: {
                    Label(.localized("Add Source"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.userTint, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 4)

            // Master "All Repositories" Card
            allRepositoriesBannerCard

            // Repositories List
            if filteredSources.isEmpty {
                NBContentUnavailable(.localized("No Repositories"), systemImage: "bag.fill", description: .localized("Get started by adding community repositories.")) {
                    Button { isAddingPresenting = true } label: { Label(.localized("Add Source"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Color.userTint)
                }
                .padding(.vertical, 20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredSources.enumerated()), id: \.element.identifier) { index, source in
                        NavigationLink {
                            SourceAppsView(object: [source], viewModel: viewModel, onRefresh: {
                                await viewModel.fetchSources(sources, refresh: true)
                            })
                        } label: {
                            RepositoryRow(source: source, repository: viewModel.sources[source])
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Storage.shared.deleteSource(for: source)
                            } label: {
                                Label(.localized("Delete"), systemImage: "trash")
                            }
                        }

                        if index < filteredSources.count - 1 {
                            Divider().padding(.leading, 74).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }

            // Community Directory (1-Tap Add)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("Community Directory"))
                            .font(.headline)
                        Text(.localized("Tap Add to add verified community repositories"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(communityRepos.enumerated()), id: \.element.id) { index, item in
                        let isAdded = nonExcludedSources.contains { $0.sourceURL?.absoluteString == item.url.absoluteString || ($0.identifier ?? "") == item.url.absoluteString }
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.userTint.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: item.iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.userTint)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                if !isAdded {
                                    Storage.shared.addSource(item.url, name: item.name, identifier: item.url.absoluteString) { err in
                                        if err == nil {
                                            Toast.success(String.localized("Added %@", arguments: item.name), systemImage: "checkmark.circle.fill")
                                            Task { await viewModel.fetchSources(sources, refresh: true) }
                                        }
                                    }
                                }
                            } label: {
                                Text(isAdded ? .localized("ADDED") : .localized("ADD"))
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(isAdded ? Color.secondary.opacity(0.15) : Color.userTint, in: Capsule())
                                    .foregroundStyle(isAdded ? Color.secondary : Color.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(isAdded)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)

                        if index < communityRepos.count - 1 {
                            Divider().padding(.leading, 66).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }

    // MARK: - Updates Section
    private var updatesSection: some View {
        VStack(spacing: 16) {
            updatesNotificationCard

            NavigationLink(destination: UpdateMatchingSettingsView()) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.userTint.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.userTint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("Update Matching Rules"))
                            .font(.subheadline.weight(.semibold))
                        Text(.localized("Configure name matching, beta filters & developers"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if updateCount > 0 {
                NavigationLink(destination: UpdatesView()) {
                    HStack {
                        Label(.localized("View All Pending Updates"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Color.userTint)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.userTint)
                    Text(.localized("All Apps Are Up to Date"))
                        .font(.headline)
                    Text(.localized("Your installed applications are on the latest versions from your sources."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var updatesNotificationCard: some View {
        NavigationLink(destination: UpdatesView()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.userTint.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.userTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(.localized("Updates Available"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: updateCount == 1 ? String.localized("1 app has an update") : String.localized("%lld apps have updates", arguments: updateCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(.localized("UPDATE ALL"))
                    .font(.caption.weight(.heavy))
                    .tracking(0.4)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.userTint, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Results View
    @ViewBuilder
    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !sortedAndFilteredApps.isEmpty {
                Text(verbatim: String.localized("%lld Matching Apps", arguments: sortedAndFilteredApps.count))
                    .font(.headline)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(sortedAndFilteredApps.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(destination: SourceAppsDetailView(source: item.repository, app: item.app)) {
                            HStack(spacing: 12) {
                                ZStack(alignment: .bottomTrailing) {
                                    AppStoreIconView(app: item.app, size: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    RepoMiniBadge(source: item.source)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.app.currentName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.app.currentDescription ?? item.source.name ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                DownloadButtonView(app: item.app)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < sortedAndFilteredApps.count - 1 {
                            Divider().padding(.leading, 74).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }

            if !filteredSources.isEmpty {
                Text(verbatim: String.localized("%lld Matching Sources", arguments: filteredSources.count))
                    .font(.headline)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(filteredSources.enumerated()), id: \.element.identifier) { index, source in
                        NavigationLink {
                            SourceAppsView(object: [source], viewModel: viewModel, onRefresh: {
                                await viewModel.fetchSources(sources, refresh: true)
                            })
                        } label: {
                            RepositoryRow(source: source, repository: viewModel.sources[source])
                        }
                        .buttonStyle(.plain)

                        if index < filteredSources.count - 1 {
                            Divider().padding(.leading, 74).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }

            if sortedAndFilteredApps.isEmpty && filteredSources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text(verbatim: String.localized("No results for “%@”", arguments: searchText))
                        .font(.headline)
                    Text(.localized("Check the spelling or try searching for another app or repository."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var emptyAppsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.localized("No Apps Found"))
                .font(.headline)
            Text(.localized("Make sure you have added repositories, or pull to refresh."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                isAddingPresenting = true
            } label: {
                Label(.localized("Add Source"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.userTint)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Footer: Activity Logs Link (Moved to Settings)
    private var logsMovedFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(.localized("Logs have moved to Settings → Activity Logs for a single navigation bar."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            NavigationLink(destination: LogsHistoryView(inNavigationStack: false)) {
                Label(.localized("View Activity Logs"), systemImage: "text.alignleft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.userTint)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Subviews & Helpers

private struct RepositoryRow: View {
    let source: AltSource
    let repository: ASRepository?

    var body: some View {
        HStack(spacing: 12) {
            RepoIcon(source: source, repository: repository)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name ?? .localized("Unknown Source"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let url = source.sourceURL?.absoluteString {
                    Text(url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let url = source.sourceURL, VexSignAPI.isPremiumSource(url) {
                        Label("Premium", systemImage: "crown.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    let count = repository?.apps.count ?? source.appsCount
                    Text("\(count) apps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(.localized("VIEW"))
                .font(.caption.weight(.heavy))
                .tracking(0.4)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.userTint, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if let url = source.sourceURL {
                Button(.localized("Copy URL"), systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = url.absoluteString
                }
            }
            if let website = repository?.website {
                Button(.localized("Open Website"), systemImage: "safari") {
                    UIApplication.open(website)
                }
            }
            Button(role: .destructive) {
                Storage.shared.deleteSource(for: source)
            } label: {
                Label(.localized("Delete"), systemImage: "trash")
            }
        }
    }
}

private struct RepoIcon: View {
    let source: AltSource
    let repository: ASRepository?

    var body: some View {
        let url = repository?.iconURL ?? source.iconURL
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Image("Repositories").resizable().scaledToFill()
                }
            }
            .processors([.resize(width: 104)])
        } else {
            Image("Repositories").resizable().scaledToFill()
        }
    }
}

private struct RepoMiniBadge: View {
    let source: AltSource
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemBackground))
                .frame(width: 18, height: 18)

            if let url = source.iconURL {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image("AppLogo").resizable().scaledToFill()
                    }
                }
                .processors([.resize(width: 28), .circle()])
                .frame(width: 14, height: 14)
            } else {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
            }
        }
    }
}

private struct AppStoreIconView: View {
    let app: ASRepository.App
    let size: CGFloat

    var body: some View {
        if let url = app.iconURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Color(uiColor: .tertiarySystemFill)
                }
            }
            .processors([.resize(width: size * 2)])
            .frame(width: size, height: size)
        } else {
            ZStack {
                Color(uiColor: .tertiarySystemFill)
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
    }
}

private extension AltSource {
    var appsCount: Int {
        (value(forKey: "apps") as? Set<NSManagedObject>)?.count ?? 0
    }
}
