//
//  IPSWBrowserView.swift
//  VexSign
//
//  Browse and download Apple firmware through the ipsw.me catalog. Files land in
//  Documents/Firmware, so they show up in File Manager and in the Files app —
//  restoring is still Finder / Apple Configurator / a jailbreak tool's job.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct IPSWBrowserView: View {
	@State private var _devices: [IPSWDevice] = []
	@State private var _firmwares: [IPSWFirmware] = []
	@State private var _selectedDevice: IPSWDevice?
	@State private var _isLoadingDevices = false
	@State private var _isLoadingFirmwares = false
	@State private var _downloading: Set<String> = []
	@State private var _deviceQuery = ""
	@State private var _error: String?

	var body: some View {
		NBNavigationView(.localized("Firmware"), displayMode: .inline) {
			List {
				if let error = _error {
					Section {
						Text(error)
							.font(.footnote)
							.foregroundStyle(.red)
					}
				}

				_deviceSection
				_firmwareSection
			}
			.searchable(text: $_deviceQuery, prompt: .localized("Search Devices"))
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
		.task {
			await _loadDevices()
		}
	}

	// MARK: Sections

	@ViewBuilder
	private var _deviceSection: some View {
		NBSection(.localized("Device")) {
			if _isLoadingDevices {
				HStack {
					ProgressView()
						.padding(.trailing, 6)
					Text(.localized("Loading devices…"))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}

			ForEach(_filteredDevices) { device in
				Button {
					_select(device)
				} label: {
					HStack {
						Label(device.name, systemImage: "iphone")
							.foregroundStyle(.primary)
						Spacer()
						Text(device.identifier)
							.font(.caption.monospaced())
							.foregroundStyle(.secondary)
						if _selectedDevice?.identifier == device.identifier {
							Image(systemName: "checkmark")
								.foregroundStyle(.accentColor)
						}
					}
				}
			}
		} footer: {
			Text(.localized("Firmware comes from Apple's CDN through the ipsw.me catalog. Files are stored in Documents → Firmware."))
		}
	}

	@ViewBuilder
	private var _firmwareSection: some View {
		if let device = _selectedDevice {
			NBSection(.localized("Firmware for %@", arguments: device.name)) {
				if _isLoadingFirmwares {
					HStack {
						ProgressView()
							.padding(.trailing, 6)
						Text(.localized("Loading firmware…"))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}

				ForEach(_firmwares) { firmware in
					_firmwareRow(firmware)
				}
			}
		}
	}

	@ViewBuilder
	private func _firmwareRow(_ firmware: IPSWFirmware) -> some View {
		let isDownloading = _downloading.contains(firmware.id)
		let isDownloaded = _downloadedURL(for: firmware) != nil

		HStack(spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text("iOS \(firmware.version)")
						.font(.subheadline.weight(.semibold))
					if firmware.isStillSigned {
						Text(.localized("Signed"))
							.font(.caption2.weight(.semibold))
							.padding(.horizontal, 6)
							.padding(.vertical, 2)
							.background(Color.green.opacity(0.15), in: Capsule())
							.foregroundStyle(.green)
					}
				}
				Text("\(firmware.buildid) • \(firmware.formattedSize)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer()

			if isDownloading {
				ProgressView()
			} else if isDownloaded {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
			} else {
				Button {
					Task { await _download(firmware) }
				} label: {
					Image(systemName: "arrow.down.circle")
						.font(.title3)
				}
				.buttonStyle(.borderless)
				.disabled(firmware.downloadURL == nil)
			}
		}
	}

	// MARK: Loading

	private var _filteredDevices: [IPSWDevice] {
		let query = _deviceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return _devices }
		return _devices.filter {
			$0.name.localizedCaseInsensitiveContains(query)
				|| $0.identifier.localizedCaseInsensitiveContains(query)
		}
	}

	private func _loadDevices() async {
		guard _devices.isEmpty, !_isLoadingDevices else { return }
		_isLoadingDevices = true
		defer { _isLoadingDevices = false }

		do {
			_devices = try await IPSWBrowser.fetchDevices()

			// Start on this device when the catalog knows it.
			if
				let current = IPSWBrowser.currentDeviceIdentifier(),
				let match = _devices.first(where: { $0.identifier == current })
			{
				_select(match)
			}
		} catch {
			_error = error.localizedDescription
		}
	}

	private func _select(_ device: IPSWDevice) {
		_selectedDevice = device
		_firmwares = []
		Task { await _loadFirmwares(for: device) }
	}

	private func _loadFirmwares(for device: IPSWDevice) async {
		guard !_isLoadingFirmwares else { return }
		_isLoadingFirmwares = true
		defer { _isLoadingFirmwares = false }

		do {
			_firmwares = try await IPSWBrowser.fetchFirmwares(for: device.identifier)
		} catch {
			_error = error.localizedDescription
		}
	}

	// MARK: Download

	private func _downloadedURL(for firmware: IPSWFirmware) -> URL? {
		let url = FileManager.default.firmware.appendingPathComponent(firmware.filename)
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	@MainActor
	private func _download(_ firmware: IPSWFirmware) async {
		guard let source = firmware.downloadURL else {
			_error = .localized("The catalog has no download link for that build.")
			return
		}

		let destination = FileManager.default.firmware.appendingPathComponent(firmware.filename)
		_downloading.insert(firmware.id)

		// IPSWs are multi-gigabyte; keep the app alive while the transfer runs.
		let keepAlive = BackgroundTaskManager(
			taskName: "Firmware",
			expirationTitle: .localized("Firmware download continuing"),
			expirationBody: .localized("The download will continue when you reopen the app")
		)
		keepAlive.start()

		defer {
			keepAlive.stop()
			_downloading.remove(firmware.id)
		}

		do {
			try FileManager.default.createDirectoryIfNeeded(at: FileManager.default.firmware)

			let (tempURL, _) = try await URLSession.shared.download(from: source)
			try FileManager.default.removeFileIfNeeded(at: destination)
			try FileManager.default.moveItem(at: tempURL, to: destination)

			Toast.success(
				String.localized("Downloaded %@", arguments: firmware.filename),
				systemImage: "arrow.down.circle.fill"
			)
		} catch {
			Toast.error(error.localizedDescription, duration: .sticky)
		}
	}
}
