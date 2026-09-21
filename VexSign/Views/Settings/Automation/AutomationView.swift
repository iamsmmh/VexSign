//
//  AutomationView.swift
//  VexSign
//
//  Settings → Automation: the opt-in "Do-Not-Disturb of signing" — a scheduled background
//  pass that checks for updates, optionally signs + queues them, runs the cleanup sweep and
//  posts one summary notification. Installing still needs the user in the loop.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct AutomationView: View {
	@AppStorage(BackgroundAutomationPreferences.enabledKey) private var _isEnabled: Bool = false
	@AppStorage(BackgroundAutomationPreferences.policyKey) private var _policyRaw: String = BackgroundAutomationPolicy.notifyOnly.rawValue

	@State private var _isRunning = false
	@State private var _lastResult: AutomationRunResult?

	// MARK: Body
	var body: some View {
		NBList(.localized("Automation")) {
			_enabledSection
			_policySection
			_runSection
		}
	}

	@ViewBuilder
	private var _enabledSection: some View {
		NBSection(.localized("Scheduled Updates")) {
			Toggle(.localized("Automatic Update Checks"), isOn: $_isEnabled)
				.onChange(of: _isEnabled) { enabled in
					if enabled {
						// Wrap the AppDelegate call on the main actor.
						DispatchQueue.main.async {
							if let delegate = UIApplication.shared.delegate as? AppDelegate {
								delegate.scheduleAutomationMaintenance()
							}
						}
					}
				}
		} footer: {
			Text(.localized("VexSign periodically checks your sources for updates while the app runs, so the Updates list is already ready when you open it."))
		}
	}

	@ViewBuilder
	private var _policySection: some View {
		NBSection(.localized("What To Do")) {
			Picker(.localized("When updates are found"), selection: $_policyRaw) {
				ForEach(BackgroundAutomationPolicy.allCases, id: \.rawValue) { policy in
					Text(policy.localizedDescription).tag(policy.rawValue)
				}
			}
			.pickerStyle(.inline)
			.labelsHidden()
		} footer: {
			let policy = BackgroundAutomationPolicy(rawValue: _policyRaw) ?? .notifyOnly
			Text(policy.localizedDetail)
		}
	}

	@ViewBuilder
	private var _runSection: some View {
		Section {
			Button {
				_run()
			} label: {
				HStack {
					Label(.localized("Run Now"), systemImage: "arrow.triangle.2.circlepath")
					Spacer()
					if _isRunning {
						ProgressView()
					}
				}
			}
			.disabled(_isRunning)
		} footer: {
			Text(.localized("Runs one automation pass immediately, exactly as the scheduled task would. Installations are never started without you."))
		}

		if let result = _lastResult {
			Section {
				LabeledContent(.localized("Sources checked"), value: result.refreshedSources.description)
				LabeledContent(.localized("Updates found"), value: result.foundUpdates.description)
				LabeledContent(.localized("Signed"), value: result.signed.description)
				LabeledContent(.localized("Queued for install"), value: result.queueAdded.description)
				if let cleanup = result.cleanup, !cleanup.isIdle {
					LabeledContent(.localized("Cleaned up"), value: cleanup.freedBytes.formattedFileSize)
				}
			}
		}
	}

	private func _run() {
		_isRunning = true
		Task {
			let result = await BackgroundAutomation.run(fromBackground: false)
			_lastResult = result
			_isRunning = false

			if result != nil, result?.foundUpdates == 0 {
				Toast.info(.localized("Everything is up to date."), systemImage: "checkmark.circle")
			}
		}
	}
}
