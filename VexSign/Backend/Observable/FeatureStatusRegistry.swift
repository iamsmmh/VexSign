//
//  FeatureStatusRegistry.swift
//  VexSign
//
//  The end-to-end feature status system. Each major feature is tracked as a
//  pipeline — setting → persisted value → real consumer — with an honest
//  status instead of a blanket "supported".
//
//  Statuses:
//    implemented  The full chain is wired in code and exercised by unit tests
//                 where it can be (Settings → persistence → consumer).
//    needsDevice  Wired end-to-end, but the last mile (signing/installing on
//                 real hardware) could not be validated in CI and needs a
//                 device pass.
//
//  The registry powers Settings → About → Feature Status and
//  docs/FEATURE_STATUS.md keeps the human-readable twin.
//

import Foundation
import NimbleExtensions

enum FeatureStatus: String, CaseIterable {
	case implemented
	case needsDevice

	var title: String {
		switch self {
		case .implemented: .localized("Implemented")
		case .needsDevice: .localized("Needs device validation")
		}
	}
}

struct FeatureStatusEntry: Identifiable {
	let id: String
	let name: String
	/// The setting / preference that controls it.
	let setting: String
	/// Where the value is persisted.
	let persistedAs: String
	/// The real consumer that acts on it.
	let consumer: String
	let status: FeatureStatus
}

enum FeatureStatusRegistry {
	/// The critical signing/install/update pipeline, in pipeline order.
	static let entries: [FeatureStatusEntry] = [
		FeatureStatusEntry(
			id: "forced-signing",
			name: "Forced signing",
			setting: "Advanced Signing → Force Sign All",
			persistedAs: "Options (signing_options, Core Data / OptionsManager)",
			consumer: "SigningHandler → Zsign",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "sdk-macho",
			name: "SDK spoofing / Mach-O changes",
			setting: "Signing Options → SDK & Mach-O",
			persistedAs: "Options (OptionsManager)",
			consumer: "SigningHandler.modify() → Info.plist & Mach-O patching",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "auto-sign-download",
			name: "Auto-sign on download",
			setting: "Automation → Sign after download",
			persistedAs: "VexSign.autoSign… keys",
			consumer: "DownloadManager → AutoSignManager.sign()",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "compat-optout",
			name: "Compatibility opt-out clearing",
			setting: "Signing Options → Compatibility",
			persistedAs: "Options (OptionsManager)",
			consumer: "SigningHandler.modify() on update/re-sign",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "per-app-cert",
			name: "Per-app certificate selection",
			setting: "App context → Signing certificate",
			persistedAs: "Per-app options / PerAppUpdateRules.pinnedCertificateUUID",
			consumer: "FR.signPackageFile(certificate:) → Zsign",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "quick-sign",
			name: "Quick Sign",
			setting: "Home → Quick Sign row",
			persistedAs: "— (immediate action)",
			consumer: "FR.handlePackageFile → SigningView",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "resign-reinstall",
			name: "Re-sign / re-install",
			setting: "Library → app → Re-sign",
			persistedAs: "— (library action)",
			consumer: "FR.signPackageFile → InstallQueue",
			status: .needsDevice
		),
		FeatureStatusEntry(
			id: "asset-modification",
			name: "Asset / file modifications",
			setting: "Signing customization, IPA Explorer",
			persistedAs: "Per-app options + IPA Explorer edits",
			consumer: "SigningHandler / IPAExplorer file replacement",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "dynamic-island",
			name: "Dynamic Island download controls",
			setting: "Downloads settings",
			persistedAs: "Live Activity state (DownloadManager+LiveActivity)",
			consumer: "DownloadProgressAttributes activity + app-group commands",
			status: .needsDevice
		),
		FeatureStatusEntry(
			id: "strict-hiding",
			name: "Strict app hiding",
			setting: "Settings → Security → Hidden Apps Vault",
			persistedAs: "AppLockManager hidden/strictly-hidden sets",
			consumer: "Library / Home filters (lockManager.isStrictlyHidden)",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "tab-structure",
			name: "Six-tab navigation structure",
			setting: "Settings → Tab Bar (launch tab only)",
			persistedAs: "TabBarPreferences (primary tabs immutable)",
			consumer: "TabbarView / every tab destination",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "appearance",
			name: "Appearance (theme, font, animations)",
			setting: "Settings → Appearance",
			persistedAs: "AppearanceStore (VexSign.visualTheme / fontFamily / fontScale / flareAnimations)",
			consumer: "App root environment, Theme tokens, button styles",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "offline-catalog",
			name: "Offline repository catalog",
			setting: "Automatic (last-known-good snapshots)",
			persistedAs: "SourceSnapshots/ (Application Support)",
			consumer: "SourcesViewModel prefill + stale marking",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "unified-tasks",
			name: "Unified task pipeline",
			setting: "Downloads → Task Center",
			persistedAs: "UnifiedTaskHistory.json (outcomes only)",
			consumer: "DownloadManager mirror, FR.signPackageFile, InstallQueue",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "per-app-rules",
			name: "Per-app update rules",
			setting: "Updates → context menu → Update Rules",
			persistedAs: "VexSign.perAppUpdateRules",
			consumer: "AppUpdateChecker.precomputeAllUpdates",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "source-health",
			name: "Source health monitoring",
			setting: "App Store → Repositories → Source Health",
			persistedAs: "SourcePreferences health records",
			consumer: "SourcesViewModel refresh outcomes",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "https-sources",
			name: "HTTPS-only repository transport",
			setting: "Settings → Security (HTTP opt-in)",
			persistedAs: "VexSign.sources.allowInsecureHTTP",
			consumer: "SourceURLPolicy (add + refresh)",
			status: .implemented
		),
		FeatureStatusEntry(
			id: "encrypted-backup",
			name: "Encrypted backup & restore",
			setting: "Settings → Backup",
			persistedAs: ".vexbackup (AES-GCM, PBKDF2 200k)",
			consumer: "BackupManager + BackupCrypto",
			status: .implemented
		)
	]

	static var implementedCount: Int { entries.filter { $0.status == .implemented }.count }
	static var needsDeviceCount: Int { entries.filter { $0.status == .needsDevice }.count }
}
