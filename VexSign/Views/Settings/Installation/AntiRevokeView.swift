//
//  AntiRevokeView.swift
//  VexSign
//
//  Settings → Installation → Anti-Revoke: builds a per-device DNS profile that pins a
//  DNS-over-HTTPS resolver for Apple's revocation-check hosts. The user supplies the endpoint
//  (a sinkhole DoH they trust) because VexSign ships no hosted service of its own.
//  Also supports NovaDNS Dynamic for automated PPQ bypass during installation.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct AntiRevokeView: View {
	@AppStorage("VexSign.useNovaDNSDynamic") private var _useNovaDNSDynamic: Bool = false
	@State private var _endpoint = ""
	@State private var _isBuilding = false
	@State private var _isSyncingRules = false
	@State private var _lastBuiltURL: URL?
	@State private var _currentRules: DynamicDNSRules = NovaDNSDynamic.loadCachedRules()

	private var _hasProfile: Bool { AntiRevokeManager.shared.profileURL != nil }
	private var _defaultEndpoint: String { _currentRules.primaryEndpoint }

	// MARK: Body
	var body: some View {
		NBList(.localized("Anti-Revoke")) {
			_statusSection
			_novaDNSSection
			_configSection
			_hostsSection
		}
		.task {
			_currentRules = NovaDNSDynamic.loadCachedRules()
			if _endpoint.isEmpty {
				_endpoint = _currentRules.primaryEndpoint
			}
		}
	}

	@ViewBuilder
	private var _statusSection: some View {
		Section {
			LabeledContent(.localized("Status")) {
				Text(verbatim: _hasProfile ? String.localized("Ready to install") : String.localized("Not protected"))
					.foregroundStyle(_hasProfile ? Color.green : Color.secondary)
			}
		} footer: {
			Text(.localized("iOS only installs DNS profiles from Settings, so the profile is shared for you to save and open there. It cannot un-revoke a certificate Apple has already revoked — it slows down future checks and keep a still-valid certificate working longer."))
		}
	}

	@ViewBuilder
	private var _novaDNSSection: some View {
		Section {
			HStack {
				Toggle(isOn: $_useNovaDNSDynamic) {
					Text(.localized("Use NovaDNS Dynamic"))
				}
				Button {
					guard let url = URL(string: "https://sideloading.net/dns/") else { return }
					Task { @MainActor in
						UIApplication.shared.open(url)
					}
				} label: {
					Image(systemName: "questionmark.circle.fill")
						.foregroundColor(.accentColor)
				}
				.buttonStyle(.plain)
			}

			Button {
				_syncRemoteRules()
			} label: {
				HStack {
					if _isSyncingRules {
						ProgressView()
							.padding(.trailing, 2)
						Text(.localized("Updating Rules…"))
					} else {
						Label(.localized("Sync Dynamic Rules"), systemImage: "arrow.triangle.2.circlepath")
					}
					Spacer()
					if let updated = _currentRules.lastUpdated {
						Text(updated)
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
			}
			.disabled(_isSyncingRules)
		} header: {
			Text(.localized("Dynamic Anti-Revoke"))
		} footer: {
			Text(.localized("NovaDNS Dynamic automatically temporarily unblocks Apple PPQ checks during installation so apps install smoothly while keeping revocation blocking active."))
		}
	}

	@ViewBuilder
	private var _configSection: some View {
		Section {
			TextField(.localized("DNS-over-HTTPS endpoint"), text: $_endpoint)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.keyboardType(.URL)

			Button {
				_build()
			} label: {
				if _isBuilding {
					HStack {
						ProgressView()
							.padding(.trailing, 2)
						Text(.localized("Building…"))
					}
				} else {
					Label(.localized("Generate Profile"), systemImage: "shield.lefthalf.filled")
				}
			}
			.disabled(_isBuilding)

			if let url = _lastBuiltURL ?? AntiRevokeManager.shared.profileURL {
				Button {
					AntiRevokeManager.shareProfile(url)
				} label: {
					Label(.localized("Share Profile"), systemImage: "square.and.arrow.up")
				}

				Button(role: .destructive) {
					AntiRevokeManager.shared.removeGeneratedProfile()
					_lastBuiltURL = nil
					Toast.success(.localized("Profile removed"), systemImage: "trash")
				} label: {
					Label(.localized("Delete Profile"), systemImage: "trash")
				}
			}
		} header: {
			Text(.localized("Resolver"))
		} footer: {
			Text(.localized("Point this at a DNS-over-HTTPS server that refuses to answer Apple's revocation hosts. Without a blocking resolver the profile does nothing — VexSign runs no server of its own."))
		}
	}

	@ViewBuilder
	private var _hostsSection: some View {
		Section {
			ForEach(AntiRevokeManager.revocationHosts, id: \.self) { host in
				Text(host)
					.font(.system(.subheadline, design: .monospaced))
			}
		} header: {
			Text(.localized("Hosts to block"))
		} footer: {
			Text(.localized("Apple queries these hosts to check a certificate's status. A working anti-revoke resolver answers them with nothing, so the check cannot return \"revoked\"."))
		}
	}

	// MARK: Actions

	private func _syncRemoteRules() {
		_isSyncingRules = true
		Task {
			let updated = await NovaDNSDynamic.fetchRules()
			_currentRules = updated
			if _endpoint.isEmpty {
				_endpoint = updated.primaryEndpoint
			}
			_isSyncingRules = false
			Toast.success(.localized("Dynamic rules synced"), systemImage: "checkmark.seal")
		}
	}

	private func _build() {
		let raw = _endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
		let endpoint = raw.isEmpty ? "" : raw

		guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else {
			Toast.error(.localized("Enter an https:// DNS-over-HTTPS endpoint."), duration: .sticky)
			return
		}

		_isBuilding = true
		Task {
			let result: Result<URL, Error> = await MainActor.run {
				do {
					let built = try AntiRevokeManager.shared.buildProfile(
						serverName: url.host ?? "Anti-Revoke",
						serverURL: endpoint
					)
					return .success(built)
				} catch {
					return .failure(error)
				}
			}

			_isBuilding = false
			switch result {
			case .success(let built):
				_lastBuiltURL = built
				Toast.success(.localized("Profile ready"), systemImage: "checkmark.seal")
			case .failure(let error):
				Toast.error(error.localizedDescription, duration: .sticky)
			}
		}
	}
}
