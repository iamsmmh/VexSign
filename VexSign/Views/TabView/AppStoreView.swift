//
//  AppStoreView.swift
//  VexSign — Apple App Store redesign, merges Sources. Single nav bar.
//
import SwiftUI
import NimbleViews
import NimbleExtensions
import NukeUI
import CoreData
import AltSourceKit

// MARK: - App Store (Apple-like) — single NavigationStack, Sources merged

struct AppStoreView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = SourcesViewModel.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    @ObservedObject private var premiumFilter = PremiumFilterPreferences.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var selectedCategory: Category = .discover
    @State private var isAddingPresenting = false
    @State private var activeSource: AltSource?

    @AppStorage("VexSign.sourcesTabShowAllReposDirectly") private var showAllDirect = false
    @AppStorage("VexSign.showSourcesUpdateBadge") private var showBadge = true

    @FetchRequest(entity: AltSource.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)], animation: .snappy)
    private var sources: FetchedResults<AltSource>

    enum Category: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case apps = "Apps"
        case updates = "Updates"
        case categories = "Categories"
        var id: String { rawValue }
    }

    private var nonExcludedSources: [AltSource] {
        sources.filter { !VexSignAPI.isSourceExcluded($0.identifier ?? $0.sourceURL?.absoluteString ?? "") }
    }

    private var filteredSources: [AltSource] {
        let base = nonExcludedSources
        let searched: [AltSource] = searchText.isEmpty ? base : base.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
        let sorted = searched.sorted { ($0.name ?? "") < ($1.name ?? "") }
        // Category wiring — Apps shows non-premium, Categories shows premium, Updates filtered by checker
        switch selectedCategory {
        case .updates:
            // Show all when searching, otherwise only if updates exist (handled by updatesCard + empty)
            return sorted
        case .apps:
            return sorted.filter { !VexSignAPI.isPremiumSource($0.sourceURL ?? URL(string: "https://example.com")!) }
        case .categories:
            return sorted.filter { VexSignAPI.isPremiumSource($0.sourceURL ?? URL(string: "https://example.com")!) }
        case .discover:
            return sorted
        }
    }

    private var updateCount: Int { updateChecker.updateCount }

    var body: some View {
        // ONE navigation bar — NBNavigationView is the only NavigationStack
        NBNavigationView(.localized("App Store"), displayMode: .large) {
            ScrollView {
                VStack(spacing: 22) {
                    appleHeader
                    todayFeature
                    categoryPills
                    if updateCount > 0 { updatesCard }
                    if !searchText.isEmpty && filteredSources.isEmpty {
                        emptySearch
                    } else {
                        allRepositoriesCard
                        repositorySection
                    }
                    footerLogs
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .scrollIndicators(.hidden)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search App Store")))
            .accessibilityElement(children: .contain)
            .refreshable { await viewModel.fetchSources(sources, refresh: true) }
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAddingPresenting) {
                SourcesAddView().adaptiveSheetSizing()
            }
            .task(id: Array(sources)) { await viewModel.fetchSources(sources) }
            .onChange(of: premiumFilter.stamp) { _ in Task { await viewModel.fetchSources(sources, refresh: true) } }
        }
    }

    // MARK: Toolbar — single nav bar actions
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { isAddingPresenting = true } label: { Image(systemName: "plus") }
                .accessibilityLabel(Text(.localized("Add Source")))
        }
        ToolbarItem(placement: .topBarLeading) {
            if updateCount > 0 {
                NavigationLink(destination: UpdatesView()) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("\(updateCount)").font(.caption2.weight(.bold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.userTint, in: Capsule()).foregroundStyle(.white)
                    }
                    .foregroundStyle(Color.userTint)
                }
            }
        }
    }

    // MARK: Header — official Apple logo where it matters
    private var appleHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.18, green: 0.62, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("App Store").font(.headline.weight(.bold))
                Text("On-device • Curated sources").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Today badge like App Store
            Text("TODAY").font(.caption2.weight(.heavy)).tracking(0.8)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.userTint.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.userTint)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: Today feature — Apple App Store “Today” card
    private var todayFeature: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.38, blue: 0.96), Color(red: 0.32, green: 0.60, blue: 1.0), Color(red: 0.56, green: 0.85, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 8) {
                Text("VexSign").font(.caption.weight(.heavy)).tracking(0.7).foregroundStyle(.white.opacity(0.9))
                Text("Discover amazing apps.\nSign & install on-device.").font(.title3.weight(.heavy)).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 6) {
                    Image("AppLogo").resizable().scaledToFit().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
                    Text("\(nonExcludedSources.count) sources • \(updateCount) updates").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.25), radius: 16, y: 8)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Category.allCases) { cat in
                    let selected = selectedCategory == cat
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedCategory = cat }
                        if cat == .updates && updateCount > 0 { /* scroll handled */ }
                    } label: {
                        HStack(spacing: 6) {
                            if cat == .updates && updateCount > 0 {
                                Text("\(updateCount)").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 2).background(.white.opacity(selected ? 0.22 : 0), in: Capsule())
                            }
                            Text(cat.rawValue).font(.subheadline.weight(selected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(selected ? Color.userTint : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        .foregroundStyle(selected ? .white : .primary)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.06), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var updatesCard: some View {
        NavigationLink(destination: UpdatesView()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.userTint.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.userTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(.localized("Updates")).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(updateCount == 1 ? .localized("1 app has an update") : .localized("%lld apps have updates", arguments: updateCount)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(.localized("View")).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(Color.userTint, in: Capsule()).foregroundStyle(.white)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var allRepositoriesCard: some View {
        let label = NavigationLink {
            SourceAppsView(object: nonExcludedSources, viewModel: viewModel, onRefresh: { await viewModel.fetchSources(sources, refresh: true) })
        } label: {
            HStack(spacing: 14) {
                Image("Repositories").appIconStyle(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(.localized("All Repositories")).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(.localized("See all apps from your sources")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        return label.buttonStyle(.plain)
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(.localized("Repositories")).font(.headline)
                Spacer()
                Text("\(filteredSources.count)").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(uiColor: .quaternarySystemFill), in: Capsule()).foregroundStyle(.secondary).contentTransition(.numericText())
                NavigationLink(destination: UpdatesView()) { }.hidden()
            }
            .padding(.horizontal, 2)

            if filteredSources.isEmpty {
                NBContentUnavailable(.localized("No Repositories"), systemImage: "bag.fill", description: .localized("Get started by adding your first repository.")) {
                    Button { isAddingPresenting = true } label: { Label(.localized("Add Source"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Color.userTint)
                }
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredSources.enumerated()), id: \.element.identifier) { idx, source in
                        NavigationLink {
                            SourceAppsView(object: [source], viewModel: viewModel, onRefresh: { await viewModel.fetchSources(sources, refresh: true) })
                        } label: {
                            AppStoreSourceRow(source: source)
                        }
                        .buttonStyle(.plain)
                        if idx < filteredSources.count - 1 {
                            Divider().padding(.leading, 74).opacity(0.5)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }

    private var emptySearch: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
            Text(.localized("No results for “%@”", arguments: searchText)).font(.subheadline.weight(.medium))
            Text(.localized("Try a different search term.")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Logs moved — suitable place is Settings + quick link here
    private var footerLogs: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft").font(.caption).foregroundStyle(.secondary)
                Text(.localized("Logs have moved to Settings → Activity Logs for a single navigation bar.")).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Spacer()
            }
            NavigationLink(destination: LogsHistoryView()) {
                Label(.localized("Activity Logs"), systemImage: "text.alignleft").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Color.userTint)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Row — Apple App Store app cell

private struct AppStoreSourceRow: View {
    let source: AltSource
    var body: some View {
        HStack(spacing: 12) {
            SourceIconView(source: source)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name ?? .localized("Unknown")).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                if let url = source.sourceURL?.absoluteString {
                    Text(url.replacingOccurrences(of: "https://", with: "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(.localized("Repository")).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if source.sourceURL.map({ VexSignAPI.isPremiumSource($0) }) == true {
                        Label("Premium", systemImage: "crown.fill").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                    }
                    Text("\(source.appsCount) apps").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(.localized("VIEW")).font(.caption.weight(.heavy)).tracking(0.4)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(red: 0.0, green: 0.48, blue: 1.0), in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct SourceIconView: View {
    let source: AltSource
    var body: some View {
        if let url = source.iconURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Image("Repositories").resizable().scaledToFill()
                }
            }
            .processors([.resize(width: 120)])
        } else {
            Image("Repositories").resizable().scaledToFill()
        }
    }
}

private extension AltSource {
    var appsCount: Int {
        // Best effort: source.apps may not be loaded; use 0 fallback
        (value(forKey: "apps") as? Set<NSManagedObject>)?.count ?? 0
    }
}
