//
//  InstallQueue.swift
//  VexSign
//
//  Created by VexSign Team on 24.08.2026.
//

import Foundation
import SwiftUI
import NimbleExtensions
import IDeviceSwift

/// Every install and export runs through here. One sheet at a time keeps the OTA server from
/// starting twice and lets a job survive a dismissed sheet. On failure the queue no longer
/// abandons the whole run: it marks the app failed, keeps the rest, and offers retry / skip.
@MainActor
final class InstallQueue: ObservableObject {
	static let shared = InstallQueue()

	@Published private(set) var apps: [AnyApp] = []
	@Published private(set) var index = 0
	@Published private(set) var installer: AppInstaller?
	@Published private(set) var isFinished = false
	@Published private(set) var isPaused = false
	@Published var isSheetPresented = false

	/// Per-entry outcome, keyed by the entry's id, so the queue list view can show what happened.
	@Published private(set) var outcomes: [String: InstallOutcome] = [:]

	enum InstallOutcome: Equatable {
		case pending
		case succeeded
		case failed(String)
		case skipped

		func canOpenApp(isExport: Bool, identifier: String?) -> Bool {
			self == .succeeded && !isExport && !(identifier ?? "").isEmpty
		}
	}

	private init() {}

	var current: AnyApp? { apps.indices.contains(index) ? apps[index] : nil }
	var upcoming: [AnyApp] { Array(apps.dropFirst(index + 1)) }
	var showsPill: Bool { current != nil && !isSheetPresented && !isFinished }

	/// Exports share the success counter, but must never get an Open action.
	var installedApps: [AnyApp] {
		apps.filter {
			outcomes[$0.id]?.canOpenApp(isExport: $0.archive, identifier: $0.base.identifier) == true
		}
	}

	var succeededCount: Int { outcomes.values.filter { $0 == .succeeded }.count }
	var failedCount: Int {
		outcomes.values.filter {
			if case .failed = $0 { return true }
			return false
		}.count
	}

	/// A finished run has nothing left to reopen, so closing it retires the queue.
	func sheetDismissed() {
		if isFinished { clear() }
	}

	func enqueue(_ app: AppInfoPresentable, exporting: Bool = false) {
		let entry = AnyApp(base: app, archive: exporting)
		guard !apps.contains(where: { $0.id == entry.id }) else { return }

		if isFinished { _reset() }
		apps.append(entry)
		outcomes[entry.id] = .pending

		InstallQueueWindow.shared.ensure()
		isSheetPresented = true
		activate()
	}

	/// Never starts in the background since an OTA install needs its prompt on screen.
	func activate(useLocalhost: Bool = false) {
		guard
			!isPaused,
			installer == nil,
			let current,
			UIApplication.shared.applicationState != .background
		else {
			return
		}

		let installer = AppInstaller(app: current.base, isSharing: current.archive, useLocalhost: useLocalhost)
		self.installer = installer
		installer.start { [weak self] result in self?._handle(result) }
	}

	/// Pauses between apps: the current install finishes, the next holds.
	func pause() {
		isPaused = true
	}

	func resume() {
		guard isPaused else { return }
		isPaused = false
		if installer == nil { activate() }
	}

	func clear() {
		_reset()
		isSheetPresented = false
		InstallQueueWindow.shared.teardown()
	}

	/// Skips the current app permanently (marks it skipped and moves on).
	func skip() {
		guard let current else { _abandon(); return }
		outcomes[current.id] = .skipped
		_abandon()
	}

	/// Retries the app at `index` (or the current one) by reinstating it and advancing back.
	func retryCurrent(useLocalhost: Bool = false) {
		guard apps.indices.contains(index) else { return }
		_teardownInstaller()
		outcomes[apps[index].id] = .pending
		isPaused = false
		activate(useLocalhost: useLocalhost)
	}

	/// Marks the failed app as pending again and rebuilds a fresh installer for it.
	private func _teardownInstaller() {
		installer?.stop()
		installer = nil
	}

	private func _handle(_ result: Result<AppInstaller.Outcome, Error>) {
		switch result {
		case .success(.cancelled):
			if let current { outcomes[current.id] = .skipped }
			_abandon()
		case .success(.exported(let package)):
			if let current { outcomes[current.id] = .succeeded }
			_abandon()

			guard let package else { return }
			// Let the card leave first or the share sheet presents onto a dying view.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
				UIActivityViewController.show(activityItems: [package])
			}
		case .success:
			if let current { outcomes[current.id] = .succeeded }
			if let app = installer?.app { InstallCleanup.stage(app) }
			// Let the finished ring land before the next app takes over.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?._advance() }
		case .failure(let error):
			if let current {
				outcomes[current.id] = .failed(String(describing: error))
			}
			var actions: [(String, UIAlertAction.Style, (() -> Void)?)] = [
				(.localized("Retry"), .default, { [weak self] in
					HeartbeatManager.shared.start(true)
					self?.retryCurrent()
				})
			]
			if installer?.canRetryUsingLocalhost == true {
				actions.append((.localized("Retry with Semi Local (localhost)"), .default, { [weak self] in
					self?.retryCurrent(useLocalhost: true)
				}))
			}
			actions.append((.localized("Skip"), .default, { [weak self] in
				HeartbeatManager.shared.start(true)
				self?.skip()
			}))
			actions.append((.localized("Stop"), .cancel, { [weak self] in
				HeartbeatManager.shared.start(true)
				self?._abandonAndFinish()
			}))
			UIAlertController.showAlertWithOptions(
				title: .localized("Install Failed"),
				message: "\(error.localizedDescription)\n\n\(String.localized("%lld more apps are waiting.", arguments: max(upcoming.count, 0)))",
				actions: actions
			)
		}
	}

	/// Keeps the last app on screen so its finished state and Open button survive.
	private func _advance() {
		_teardownInstaller()

		guard index + 1 < apps.count else {
			isFinished = true
			if !isSheetPresented { clear() }
			return
		}

		index += 1
		activate()
	}

	/// Dismiss first so the card doesn't blank out mid animation.
	private func _abandon() {
		guard index + 1 < apps.count else {
			guard isSheetPresented else {
				clear()
				return
			}

			_teardownInstaller()
			isFinished = true
			isSheetPresented = false
			return
		}

		_advance()
	}

	/// Finishes with the remainder marked skipped, used by "Stop".
	private func _abandonAndFinish() {
		for entry in apps.dropFirst(index + 1) where outcomes[entry.id] == nil || outcomes[entry.id] == .pending {
			outcomes[entry.id] = .skipped
		}
		_teardownInstaller()
		isFinished = true
		isSheetPresented = false
	}

	private func _reset() {
		_teardownInstaller()
		apps.removeAll()
		index = 0
		isFinished = false
		isPaused = false
		outcomes.removeAll()

		InstallCleanup.flush()
	}
}
