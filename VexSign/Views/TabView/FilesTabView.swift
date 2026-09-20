//
//  FilesTabView.swift
//  VexSign — Files like Ksign: storage overview + quick access + browser. Single nav bar.
//
import SwiftUI
import NimbleViews
import NimbleExtensions
import UniformTypeIdentifiers

struct FilesTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var storage = StorageManager.shared
    @State private var query = ""

    // Quick folders like Ksign — Documents categories
    private struct QuickFolder: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let color: Color
        let url: URL
    }

    private var quickFolders: [QuickFolder] {
        [
            QuickFolder(title: .localized("Documents"), icon: "folder.fill", color: Color(red: 0.0, green: 0.48, blue: 1.0), url: URL.documentsDirectory),
            QuickFolder(title: .localized("Archives"), icon: "archivebox.fill", color: Color(red: 0.55, green: 0.36, blue: 0.96), url: FileManager.default.archives),
            QuickFolder(title: .localized("Certificates"), icon: "checkmark.seal.fill", color: Color(red: 0.20, green: 0.66, blue: 0.44), url: FileManager.default.certificates),
            QuickFolder(title: .localized("Signed"), icon: "app.badge.checkmark.fill", color: Color(red: 0.95, green: 0.55, blue: 0.15), url: FileManager.default.signed),
            QuickFolder(title: .localized("Unsigned"), icon: "doc.fill", color: Color(red: 0.45, green: 0.45, blue: 0.50), url: FileManager.default.unsigned),
            QuickFolder(title: .localized("Tweaks"), icon: "wrench.and.screwdriver.fill", color: Color(red: 0.96, green: 0.33, blue: 0.26), url: FileManager.default.tweaksLibrary),
        ]
    }

    var body: some View {
        // Single navigation stack — NBNavigationView is the ONE bar
        NBNavigationView(.localized("Files"), displayMode: .large) {
            List {
                storageHeader
                quickAccessSection
                browseSection
                infoSection
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search files")))
            .toolbar { toolbar }
            .scrollIndicators(.hidden)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(.localized("New Folder"), systemImage: "folder.badge.plus") {
                    Toast.info(.localized("Use File Manager to create folders"), systemImage: "folder")
                }
                Button(.localized("Import from Files…"), systemImage: "square.and.arrow.down") {
                    DocumentPicker.open([.item], multiple: true) { urls in
                        let count = FileManagerActions.importFiles(urls, into: URL.documentsDirectory)
                        Toast.success(.localized("%lld file(s) imported", arguments: count), systemImage: "tray.and.arrow.down")
                    }
                }
            } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { if let url = URL.documentsDirectory.toSharedDocumentsURL() { UIApplication.open(url) } } label: {
                Label(.localized("Open in Files"), systemImage: "folder")
            }
        }
    }

    // MARK: Storage header — Ksign style
    private var storageHeader: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.userTint.opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "internaldrive.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.userTint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("On My iPhone — VexSign")).font(.subheadline.weight(.semibold))
                        if let total = storage.report?.total {
                            Text(total.formattedFileSize + " " + .localized("used")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(.localized("Documents & data")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let report = storage.report {
                        Text(report.total.formattedFileSize).font(.caption.weight(.semibold)).foregroundStyle(Color.userTint).monospacedDigit()
                    }
                }
                if let report = storage.report {
                    GeometryReader { geo in
                        let used = Double(report.total) // already used
                        // Visual bar — proportional to used vs generous cap (e.g., 5GB) to avoid 0..1 extremes
                        let cap: Double = 5 * 1024 * 1024 * 1024
                        let pct = min(max(used / cap, 0.06), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(uiColor: .quaternarySystemFill)).frame(height: 6)
                            Capsule().fill(LinearGradient(colors: [Color.userTint, Color.userTintDeep], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * pct, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                HStack(spacing: 8) {
                    Label("\(quickFolders.count) locations", systemImage: "point.3.connected.trianglepath.dotted").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(.localized("Ksign-style browser")).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Label(.localized("Storage"), systemImage: "internaldrive").font(.subheadline.weight(.semibold)).foregroundStyle(Color.userTint)
        }
    }

    private var quickAccessSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(quickFolders) { folder in
                    NavigationLink(destination: FileManagerView(directory: folder.url)) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(folder.color.opacity(0.13)).frame(width: 44, height: 44)
                                Image(systemName: folder.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(folder.color)
                            }
                            Text(folder.title).font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                            Text(folder.url.lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Label(.localized("Quick Access"), systemImage: "star.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.userTint)
        } footer: {
            Text(.localized("Ksign-style quick folders — tap to browse each location like Ksign."))
        }
    }

    private var browseSection: some View {
        Section {
            NavigationLink(destination: FileManagerView(directory: URL.documentsDirectory, isRoot: true)) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.localized("Browse Documents")).font(.subheadline.weight(.medium))
                        Text(.localized("All files, imports, archives and certificates")).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    ZStack { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.userTint.opacity(0.13)).frame(width: 32, height: 32)
                        Image(systemName: "folder.fill").foregroundStyle(Color.userTint) }
                }
            }
            NavigationLink(destination: FileManagerView(directory: FileManager.default.archives)) {
                Label(.localized("Archives"), systemImage: "archivebox.fill").foregroundStyle(.primary)
            }
            NavigationLink(destination: FileManagerView(directory: FileManager.default.certificates)) {
                Label(.localized("Certificates"), systemImage: "checkmark.seal.fill").foregroundStyle(.primary)
            }
            NavigationLink(destination: IPSWBrowserView()) {
                Label(.localized("Firmware Browser"), systemImage: "opticaldisc.fill").foregroundStyle(.primary)
            }
            NavigationLink(destination: IPAExplorerHomeView()) {
                Label(.localized("IPA Explorer"), systemImage: "doc.text.magnifyingglass").foregroundStyle(.primary)
            }
        } header: {
            Label(.localized("Browse"), systemImage: "folder.badge.gearshape").font(.subheadline.weight(.semibold)).foregroundStyle(Color.userTint)
        }
    }

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(.localized("How Ksign files works"), systemImage: "info.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(.localized("Files shows everything VexSign stores on-device. Long-press a row for rename, duplicate, share, copy hash and tweak actions. Swipe to delete. Use Quick Access above like Ksign's locations.")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
