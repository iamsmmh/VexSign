//
//  FR.swift
//  VexSign
//
//  Created by VexSign TeamSign Team on 22.04.2025.
//

import Foundation.NSURL
import Security
import UIKit.UIImage
import Zsign
import NimbleJSON
import AltSourceKit
import IDeviceSwift
import OSLog

enum FR {
	static func handlePackageFile(
		_ ipa: URL,
		download: Download? = nil,
		completion: @escaping (Result<AppInfoPresentable, Error>) -> Void
	) {
		Task.detached {
			let handler = AppFileHandler(file: ipa, download: download)
			
			do {
				try await handler.copy()
				try await handler.extract()
				try await handler.move()
				let app = try await handler.addToDatabase()
				try? await handler.clean()
				await MainActor.run {
					completion(.success(app))
				}
			} catch {
				try? await handler.clean()
				await MainActor.run {
					completion(.failure(error))
				}
			}
		}
	}
	
	static func signPackageFile(
		_ app: AppInfoPresentable,
		using options: Options,
		icon: UIImage?,
		certificate: CertificatePair?,
		completion: @escaping (Result<Signed, Error>) -> Void
	) {
		Task.detached {
			let log = SigningLog.shared
			log.reset()
			log.info(.localized("Preparing to sign %@", arguments: app.name ?? .localized("app")))

			await SigningLiveActivityManager.shared.start(appName: app.name ?? "App")

			let keepAlive = BackgroundTaskManager(
				taskName: "Signing",
				expirationTitle: .localized("Signing continuing"),
				expirationBody: .localized("The signing will continue when you reopen the app")
			)
			await MainActor.run { keepAlive.start() }
			defer { Task { @MainActor in keepAlive.stop() } }

			let handler = SigningHandler(app: app, options: options)
			handler.appCertificate = certificate
			handler.appIcon = icon

			do {
				try await handler.copy()
				await SigningLiveActivityManager.shared.update(progress: 0.3, status: .localized("Modifying…"))
				try await handler.modify()
				await SigningLiveActivityManager.shared.update(progress: 0.8, status: .localized("Finalizing…"))
				try? await handler.clean()

				guard let signed = handler.signedApp else {
					throw SigningFileHandlerError.appNotFound
				}

				log.success(.localized("Signed successfully"))
				await SigningLiveActivityManager.shared.complete(appName: app.name)
				await MainActor.run {
					completion(.success(signed))
				}
			} catch {
				try? await handler.clean()
				log.error(error.localizedDescription)
				await SigningLiveActivityManager.shared.cancel()
				await MainActor.run {
					completion(.failure(error))
				}
			}
		}
	}
	
	static func handleCertificateFiles(
		p12URL: URL,
		provisionURL: URL,
		p12Password: String,
		certificateName: String = "",
		isDefault: Bool = false,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let keyAccess = p12URL.startAccessingSecurityScopedResource()
			let provisionAccess = provisionURL.startAccessingSecurityScopedResource()
			defer {
				if keyAccess { p12URL.stopAccessingSecurityScopedResource() }
				if provisionAccess { provisionURL.stopAccessingSecurityScopedResource() }
			}
			let handler = CertificateFileHandler(
				key: p12URL,
				provision: provisionURL,
				password: p12Password,
				nickname: certificateName.isEmpty ? nil : certificateName,
				isDefault: isDefault
			)
			
			do {
				guard checkPasswordForCertificate(for: p12URL, with: p12Password, using: provisionURL) else {
					throw CertificateFileHandlerError.invalidIdentity
				}
				try await handler.copy()
				try await handler.addToDatabase()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func checkPasswordForCertificate(
		for key: URL,
		with password: String,
		using provision: URL
	) -> Bool {
		let keyAccess = key.startAccessingSecurityScopedResource()
		let provisionAccess = provision.startAccessingSecurityScopedResource()
		defer {
			if keyAccess { key.stopAccessingSecurityScopedResource() }
			if provisionAccess { provision.stopAccessingSecurityScopedResource() }
		}

		// Security validates both the password and private key without the old
		// OpenSSL CMS warm-up, which asserted on malformed or unreadable profiles.
		guard CertificateReader(provision).decoded != nil,
			  let data = try? Data(contentsOf: key), !data.isEmpty else { return false }
		var items: CFArray?
		let options = [kSecImportExportPassphrase as String: password] as CFDictionary
		guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
			  let identities = items as? [[String: Any]] else { return false }
		return identities.contains { $0[kSecImportItemIdentity as String] != nil }
	}
	
	static func movePairing(_ url: URL) {
		let fileManager = FileManager.default
		let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
		
		try? fileManager.removeFileIfNeeded(at: dest)
		
		try? fileManager.copyItem(at: url, to: dest)
		
		HeartbeatManager.shared.start(true)
	}
	
	static func downloadSSLCertificates(
		from urlString: String,
		completion: @escaping (Bool) -> Void
	) {
		let generator = UINotificationFeedbackGenerator()
		generator.prepare()
		
		NBFetchService().fetch(from: urlString) { (result: Result<ServerView.ServerPackModel, Error>) in
			switch result {
			case .success(let pack):
				do {
					try FileManager.forceWrite(content: pack.key, to: "server.pem")
					try FileManager.forceWrite(content: [pack.cert, pack.ca].joined(separator: "\n"), to: "server.crt")
					try FileManager.forceWrite(content: pack.info.domains.commonName, to: "commonName.txt")
					generator.notificationOccurred(.success)
					completion(true)
				} catch {
					completion(false)
				}
			case .failure(_):
				completion(false)
			}
		}
	}
	
	// MARK: - Premium repository API key wiring

	/// Registers the app-wide repository fetch key provider and loads the effective key.
	/// Precedence: hardcoded developer override → persisted (redeemed, keychain) key.
	/// Call once at launch so every manifest fetch/decrypt attaches it as `X-API-Key`.
	static func registerRepositoryKeyProvider() {
		let effectiveKey: String = {
			if !VexSignAPI.developerPremiumAPIKey.isEmpty {
				return VexSignAPI.developerPremiumAPIKey
			}
			if let persisted = VexSignAPI.premiumAPIKey {
				return persisted
			}
			return ""
		}()
		#if canImport(AltSourceKit)
		EsignSourceKey.customApiKey = effectiveKey
		NBFetchService.apiKeyProvider = { EsignSourceKey.customApiKey }
		#else
		NBFetchService.apiKeyProvider = { effectiveKey }
		#endif
	}

	static func handleSource(
		_ urlString: String,
		showAlerts: Bool = true,
		competion: @escaping (Result<String, Error>) -> Void
	) {
		var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
		if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
			cleaned = "https://" + cleaned
		}

		guard let url = URL(string: cleaned), url.host != nil else {
			let error = NSError(domain: "VexSign", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			if showAlerts {
				DispatchQueue.main.async {
					Toast.error(.localized("Invalid URL"), duration: .sticky)
				}
			}
			competion(.failure(error))
			return
		}

		var headers: [String: String] = VexSignAPI.authHeaders(for: url)
		#if canImport(AltSourceKit)
		// Belt-and-braces: also attach the premium key directly when a non-empty
		// `customApiKey` is configured (single-source path through EsignSourceKey).
		if !EsignSourceKey.customApiKey.isEmpty, headers["X-API-Key"] == nil {
			headers["X-API-Key"] = EsignSourceKey.customApiKey
		}
		#endif

		NBFetchService().fetch<ASRepository>(from: url, headers: headers) { (result: Result<ASRepository, Error>) in
			switch result {
			case .success(let data):
				let id = data.id ?? url.absoluteString

				if !Storage.shared.sourceExists(id) {
					Storage.shared.addSource(url, repository: data, id: id) { _ in
						let sourceName = data.name ?? url.absoluteString
						competion(.success(sourceName))
					}
				} else {
					let error = NSError(domain: "VexSign", code: 1, userInfo: [NSLocalizedDescriptionKey: "Repository already added."])
					if showAlerts {
						DispatchQueue.main.async {
							Toast.error(.localized("Repository already added."), duration: .sticky)
						}
					}
					competion(.failure(error))
				}
			case .failure(let error):
				if showAlerts {
					DispatchQueue.main.async {
						Toast.error(error.localizedDescription, duration: .sticky)
					}
				}
				competion(.failure(error))
			}
		}
	}
	
	static func exportCertificateAndOpenUrl(using template: String) {
		// Helper that performs the export for a given certificate
		func performExport(for certificate: CertificatePair) {
			guard
				let certificateKeyFile = Storage.shared.getFile(.certificate, from: certificate),
				let certificateKeyFileData = try? Data(contentsOf: certificateKeyFile)
			else {
				return
			}
			
			let base64encodedCert = certificateKeyFileData.base64EncodedString()
			
			var allowedQueryParamAndKey = NSCharacterSet.urlQueryAllowed
			allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
			
			guard let encodedCert = base64encodedCert.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) else {
				return
			}
			
			let urlStr = template
				.replacingOccurrences(of: "$(BASE64_CERT)", with: encodedCert)
				.replacingOccurrences(of: "$(PASSWORD)", with: certificate.signingPassword ?? "")
			
			guard let callbackUrl = URL(string: urlStr) else {
				return
			}
			
			UIApplication.shared.open(callbackUrl)
		}
		
		let certificates = Storage.shared.getAllCertificates()
		guard !certificates.isEmpty else { return }
		
		DispatchQueue.main.async {
			var selectionActions: [UIAlertAction] = []
			
			for cert in certificates {
				var title: String
				let decoded = Storage.shared.getProvisionFileDecoded(for: cert)
				
				title = cert.nickname ?? decoded?.Name ?? .localized("Unknown")
				
				if let getTaskAllow = decoded?.Entitlements?["get-task-allow"]?.value as? Bool, getTaskAllow == true {
					title = "🐞 \(title)"
				}
				
				let selectAction = UIAlertAction(title: title, style: .default) { _ in
					performExport(for: cert)
				}
				selectionActions.append(selectAction)
			}
			
			UIAlertController.showAlertWithCancel(
				title: .localized("Export Certificate"),
				message: .localized("Do you want to export your certificate to an external app? That app will be able to sign apps using your certificate."),
				style: .alert,
				actions: selectionActions
			)
		}
	}

	/// Applies premium auth and catalog filtering to the sources that need it.
	static func fetchRepositories(from urls: [URL]) async -> [(url: URL, data: ASRepository)] {
		let requests: [(url: URL, request: URL, headers: [String: String])] = await MainActor.run {
			urls.map { ($0, VexSignAPI.catalogURL(for: $0), VexSignAPI.authHeaders(for: $0)) }
		}

		let service = NBFetchService()

		return await withTaskGroup(of: (URL, ASRepository?).self) { group in
			for item in requests {
				group.addTask {
					let repository: ASRepository? = await withCheckedContinuation { continuation in
						service.fetch(from: item.request, headers: item.headers) { (result: Result<ASRepository, Error>) in
							switch result {
							case .success(let repository):
								continuation.resume(returning: repository)
							case .failure(let error):
								Logger.misc.error("Failed to fetch \(item.url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
								continuation.resume(returning: nil)
							}
						}
					}
					return (item.url, repository)
				}
			}

			var results: [(url: URL, data: ASRepository)] = []
			for await (url, repository) in group {
				if let repository {
					results.append((url: url, data: repository))
				}
			}
			return results
		}
	}
}
