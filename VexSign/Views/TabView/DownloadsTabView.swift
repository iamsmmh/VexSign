//
//  DownloadsTabView.swift
//  VexSign — Downloads tab with proper functionality. Single nav bar.
//
import SwiftUI
import NimbleViews
import NimbleExtensions
import UniformTypeIdentifiers

struct DownloadsTabView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: Filter = .all
    @State private var showAddSheet = false
    @State private var addURLText = ""
    @State private var showImportPicker = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case paused = "Paused"
        case completed = "Done"
        var id: String { rawValue }
        func matches(_ dl: Download) -> Bool {
            switch self {
            case .all: return true
            case .active: return dl.isActive && !dl.isPaused && dl.phase != .completed
            case .paused: return dl.isPaused
            case .completed: return dl.phase == .completed
            }
        }
    }

    private var filtered: [Download] {
        let list = downloadManager.downloads.filter(filter.matches)
        // Most recent first (downloads are appended)
        return list.reversed()
    }

    private var activeCount: Int { downloadManager.downloads.filter { $0.isActive && !$0.isPaused }.count }
    private var pausedCount: Int { downloadManager.downloads.filter { $0.isPaused }.count }

    var body: some View {
        // ONE navigation bar
        NBNavigationView(.localized("Downloads"), displayMode: .large) {
            List {
                header
                filterPills
                if filtered.isEmpty {
                    empty
                } else {
                    downloadsSection
                }
                actionsSection
            }
            .listStyle(.insetGrouped)
            .animation(.snappy, value: downloadManager.downloads.count)
            .animation(.snappy, value: filter)
            .scrollIndicators(.hidden)
            .toolbar { toolbar }
            .refreshable { /* downloads live */ }
            .sheet(isPresented: $showAddSheet) { addSheet }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    let count = FileManagerActions.importFiles(urls, into: URL.documentsDirectory)
                    Toast.success(.localized("%lld file(s) imported", arguments: count), systemImage: "tray.and.arrow.down")
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(.localized("Download from URL…"), systemImage: "link") { showAddSheet = true }
                Button(.localized("Import from Files…"), systemImage: "square.and.arrow.down") { showImportPicker = true }
                if !downloadManager.downloads.isEmpty {
                    Divider()
                    Button(.localized("Pause All"), systemImage: "pause.fill") { downloadManager.pauseAllDownloads() }
                    Button(.localized("Resume All"), systemImage: "play.fill") { downloadManager.resumeAllDownloads() }
                    Divider()
                    Button(.localized("Clear Completed"), systemImage: "trash", role: .destructive) { clearCompleted() }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .topBarLeading) {
            if activeCount > 0 {
                Label("\(activeCount) active", systemImage: "arrow.down.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.userTint)
            }
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.tintSoft).frame(width: 44, height: 44)
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.tint)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("Downloads")).font(.headline)
                        Text(verbatim: downloadManager.downloads.isEmpty ? String.localized("No downloads yet") : String.localized("%lld total • %lld active", arguments: downloadManager.downloads.count, activeCount)).font(.caption).foregroundStyle(.secondary)
                        if downloadManager.currentDownloadSpeed > 0 {
                            Text(verbatim: downloadManager.currentDownloadSpeed.formattedByteCount + "/s").font(.caption2.weight(.medium)).foregroundStyle(Theme.tint).monospacedDigit()
                                .accessibilityLabel(Text("\(downloadManager.currentDownloadSpeed.formattedByteCount) per second"))
                        }
                    }
                    Spacer()
                    if !downloadManager.downloads.isEmpty {
                        VStack(spacing: 4) {
                            Text("\(downloadManager.downloads.count)").font(.title3.bold()).monospacedDigit().foregroundStyle(.primary)
                            Text(.localized("items")).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.quaternary, in: Capsule())
                        .accessibilityElement(children: .combine)
                    }
                }
                if !downloadManager.downloads.isEmpty {
                    let summary = DownloadProgressSummary(downloadManager.downloads)
                    VStack(spacing: 6) {
                        DownloadPhaseBar(phase: summary.phase, progress: summary.progress)
                        HStack {
                            Text("\(Int(summary.progress * 100))%").font(.caption2.weight(.semibold)).foregroundStyle(summary.phase.tint).monospacedDigit()
                            Spacer()
                            Text(summary.phase.title).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(Int(summary.progress * 100)) percent, \(summary.phase.title)"))
                }
            }
            .padding(.vertical, 6)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Theme.card)
    }

    private var filterPills: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { f in
                        let selected = filter == f
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = f }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(color(for: f)).frame(width: 7, height: 7)
                                Text(.localized(f.rawValue)).font(.caption.weight(selected ? .semibold : .regular))
                                let count: Int = {
                                    switch f {
                                    case .all: return downloadManager.downloads.count
                                    case .active: return activeCount
                                    case .paused: return pausedCount
                                    case .completed: return downloadManager.downloads.filter { $0.phase == .completed }.count
                                    }
                                }()
                                if count > 0 {
                                    Text("\(count)").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1).background(selected ? .white.opacity(0.2) : Color.primary.opacity(0.08), in: Capsule()).monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selected ? Color.userTint : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(selected ? .white : .primary)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.06), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
        .headerProminence(.increased)
    }

    private func color(for f: Filter) -> Color {
        switch f {
        case .all: return .secondary
        case .active: return .blue
        case .paused: return .orange
        case .completed: return .green
        }
    }

    private var downloadsSection: some View {
        Section {
            ForEach(filtered, id: \.id) { dl in
                DownloadRow(download: dl)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if dl.canCancel {
                            Button(role: .destructive) { DownloadManager.shared.cancelDownload(dl) } label: { Label(.localized("Cancel"), systemImage: "xmark") }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if dl.isPaused {
                            Button { DownloadManager.shared.resumeDownload(dl) } label: { Label(.localized("Resume"), systemImage: "play.fill") }.tint(.green)
                        } else if dl.isActive {
                            Button { DownloadManager.shared.pauseDownload(dl) } label: { Label(.localized("Pause"), systemImage: "pause.fill") }.tint(.orange)
                        }
                    }
            }
        } header: {
            Text(verbatim: filtered.count == 1 ? String.localized("1 item") : String.localized("%lld items", arguments: filtered.count)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(nil)
        }
        .headerProminence(.increased)
    }

    private var empty: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: filter == .all ? "arrow.down.circle" : "tray")
                    .font(.system(size: 44)).foregroundStyle(.secondary).padding(.top, 8)
                Text(verbatim: filter == .all ? String.localized("No downloads") : String.localized("No %@ downloads", arguments: filter.rawValue.lowercased()))
                    .font(.headline)
                Text(.localized("Download apps from the App Store tab or paste a direct IPA link.")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                Button { showAddSheet = true } label: {
                    Label(.localized("Download from URL"), systemImage: "link").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).tint(Color.userTint).padding(.top, 4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var actionsSection: some View {
        Section {
            NavigationLink(destination: FileManagerView(directory: FileManager.default.downloadStaging)) {
                Label(.localized("Staging Folder"), systemImage: "folder")
            }
            NavigationLink(destination: LogsHistoryView()) {
                Label(.localized("Activity Logs"), systemImage: "text.alignleft")
            }
            if !downloadManager.downloads.isEmpty {
                Button(.localized("Clear Completed"), systemImage: "trash", role: .destructive) { clearCompleted() }
            }
        } header: {
            Label(.localized("Manage"), systemImage: "gearshape").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        } footer: {
            Text(.localized("Active downloads continue in background. Swipe a row to cancel, or use the menu to pause all."))
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(.localized("https://example.com/app.ipa"), text: $addURLText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } header: { Text(.localized("IPA URL")) } footer: { Text(.localized("Paste a direct .ipa link. VexSign will download, unpack and let you sign it.")) }
                Section {
                    Button(.localized("Download")) {
                        guard let url = URL(string: addURLText.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
                            Toast.error(.localized("Invalid URL")); return
                        }
                        _ = DownloadManager.shared.startDownload(from: url)
                        Toast.info(.localized("Download started"), systemImage: "arrow.down.circle")
                        addURLText = ""; showAddSheet = false
                    }
                    .disabled(addURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(.localized("Download from URL"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.localized("Cancel")) { showAddSheet = false } }
            }
        }
        .presentationDetents([.medium])
    }

    private func clearCompleted() {
        let completed = downloadManager.downloads.filter { $0.phase == .completed }
        for dl in completed { DownloadManager.shared.cancelDownload(dl) }
        Toast.success(.localized("Cleared %lld completed", arguments: completed.count), systemImage: "trash")
    }
}

// MARK: - Row

private struct DownloadRow: View {
    let download: Download
    @StateObject private var model = DownloadProgressModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                DownloadPhaseRing(phase: model.phase, progress: model.phaseProgress, size: 28, lineWidth: 2.6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.fileName).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7).accessibilityLabel(Text(download.fileName))
                    HStack(spacing: 4) {
                        Image(systemName: model.phase.icon).font(.caption2)
                        Text(model.phase.title).font(.caption)
                        if let detail = model.phase.processingDetail {
                            Text("• \(detail)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .foregroundStyle(model.phase.tint)
                    .accessibilityElement(children: .combine)
                }
                Spacer()
                // Completed → Open in Files (Ksign-like)
                if model.phase == .completed {
                    Button {
                        if let url = FileManager.default.downloadStaging.toSharedDocumentsURL() { UIApplication.open(url) }
                        Toast.info(.localized("Opened staging folder"), systemImage: "folder")
                    } label: {
                        Label(.localized("Open"), systemImage: "folder.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered).tint(Theme.tint).controlSize(.mini)
                    .accessibilityLabel(Text(.localized("Open in Files")))
                } else {
                    Menu {
                        if download.isPaused {
                            Button(.localized("Resume"), systemImage: "play.fill") { DownloadManager.shared.resumeDownload(download) }
                        } else if download.isActive {
                            Button(.localized("Pause"), systemImage: "pause.fill") { DownloadManager.shared.pauseDownload(download) }
                        }
                        if download.canCancel {
                            Button(.localized("Cancel"), systemImage: "xmark", role: .destructive) { DownloadManager.shared.cancelDownload(download) }
                        }
                        if model.phase == .completed {
                            Button(.localized("Open in Files"), systemImage: "folder") {
                                if let url = FileManager.default.downloadStaging.toSharedDocumentsURL() { UIApplication.open(url) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.body).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text(.localized("Actions")))
                }
            }
            DownloadPhaseBar(phase: model.phase, progress: model.phaseProgress)
            HStack {
                Text("\(Int(model.phaseProgress * 100))%").font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(model.phase.tint)
                Spacer()
                if model.showsByteCount && model.totalBytes > 0 {
                    Text("\(model.bytesDownloaded.formattedByteCount) / \(model.totalBytes.formattedByteCount)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                } else if let detail = model.phase.processingDetail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if DownloadManager.shared.currentDownloadSpeed > 0 && model.phase == .downloading {
                    Text(verbatim: DownloadManager.shared.currentDownloadSpeed.formattedByteCount + "/s").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(Int(model.phaseProgress * 100)) percent, \(model.phase.title)"))
        }
        .padding(.vertical, 4)
        .onAppear { model.bind(to: download) }
        // Persistence hint — DownloadManager keeps downloads in UserDefaults staging; clearing only removes UI
    }
}
