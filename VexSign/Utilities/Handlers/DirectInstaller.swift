//
//  DirectInstaller.swift
//  VexSign
//
//  Installs a bundle that is already signed — an IPA from another tool, a
//  distribution server, or a previous VexSign export — without running it through
//  Zsign again. Re-signing an already-signed app with a different identity breaks
//  its keychain access groups and app groups, so "install as-is" is the correct
//  path for those.
//
//  The bundle is verified first: `_CodeSignature` plus a code signature load
//  command on the main executable. installd makes the final call; this check only
//  stops the obviously-unsigned cases before a two-minute OTA dance.
//

import Foundation
import NimbleExtensions
import OSLog

// MARK: - Result

struct DirectInstallVerification: Equatable {
	let bundlePath: String?
	let hasSignatureDirectory: Bool
	let hasSignedExecutable: Bool
	let unsignedNestedBundles: [String]

	var isSigned: Bool {
		bundlePath != nil && hasSignatureDirectory && hasSignedExecutable
	}

	/// Human-readable reasons, shown before the install is offered.
	var issues: [String] {
		// No bundle at all: the rest of the checks have nothing to look at.
		guard bundlePath != nil else {
			return [String.localized("No .app bundle found in this directory.")]
		}

		var issues: [String] = []
		if !hasSignatureDirectory {
			issues.append(String.localized("Missing _CodeSignature — the app was never signed."))
		}
		if !hasSignedExecutable {
			issues.append(String.localized("The main executable has no code signature."))
		}
		for name in unsignedNestedBundles {
			issues.append(String.localized("%@ has no _CodeSignature.", arguments: name))
		}
		return issues
	}
}

// MARK: - Installer

@MainActor
final class DirectInstaller {
	static let shared = DirectInstaller()

	enum DirectInstallError: LocalizedError {
		case appNotFound
		case notSigned([String])

		var errorDescription: String? {
			switch self {
			case .appNotFound:
				String.localized("App files not found.")
			case .notSigned(let issues):
				String.localized("This app isn't signed:\n%@", arguments: issues.joined(separator: "\n"))
			}
		}
	}

	private init() {}

	// MARK: Verification

	/// Checks a library entry's bundle on disk.
	func verify(_ app: AppInfoPresentable) -> DirectInstallVerification {
		guard let directory = Storage.shared.getAppDirectory(for: app) else {
			return DirectInstallVerification(
				bundlePath: nil,
				hasSignatureDirectory: false,
				hasSignedExecutable: false,
				unsignedNestedBundles: []
			)
		}
		return Self.verify(directory: directory)
	}

	/// Checks an unpacked app directory (…/<uuid>/ or the .app itself).
	nonisolated static func verify(directory: URL) -> DirectInstallVerification {
		let fm = FileManager.default

		let bundleURL: URL?
		if directory.pathExtension == "app" {
			bundleURL = directory
		} else {
			bundleURL = fm.getPath(in: directory, for: "app")
		}

		guard let bundleURL else {
			return DirectInstallVerification(
				bundlePath: nil,
				hasSignatureDirectory: false,
				hasSignedExecutable: false,
				unsignedNestedBundles: []
			)
		}

		let signatureURL = bundleURL.appendingPathComponent("_CodeSignature")
		var isDirectory: ObjCBool = false
		let hasSignatureDirectory = fm.fileExists(atPath: signatureURL.path, isDirectory: &isDirectory) && isDirectory.boolValue

		let executableURL = Bundle(url: bundleURL)?.executableURL
		let hasSignedExecutable: Bool
		if let executableURL {
			hasSignedExecutable = MachOEntitlements.hasCodeSignature(forExecutableAt: executableURL)
		} else {
			hasSignedExecutable = false
		}

		return DirectInstallVerification(
			bundlePath: bundleURL.path,
			hasSignatureDirectory: hasSignatureDirectory,
			hasSignedExecutable: hasSignedExecutable,
			unsignedNestedBundles: _unsignedNestedBundles(in: bundleURL)
		)
	}

	/// Frameworks and plug-ins ship their own signatures; a missing one fails the
	/// whole install, so surface them as warnings rather than blocking silently.
	nonisolated private static func _unsignedNestedBundles(in bundleURL: URL) -> [String] {
		let fm = FileManager.default
		var unsigned: [String] = []

		for folder in ["Frameworks", "PlugIns", "Extensions"] {
			let directory = bundleURL.appendingPathComponent(folder)
			guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
				continue
			}

			for item in contents {
				let extensionName = item.pathExtension.lowercased()
				guard ["framework", "appex", "app", "bundle"].contains(extensionName) else { continue }

				let signature = item.appendingPathComponent("_CodeSignature")
				if !fm.fileExists(atPath: signature.path) {
					unsigned.append(item.lastPathComponent)
				}
			}
		}

		return unsigned.sorted()
	}

	// MARK: Install

	/// Verifies, then hands the app to the normal install queue (OTA or idevice,
	/// exactly like a freshly signed app).
	@discardableResult
	func install(_ app: AppInfoPresentable) throws -> DirectInstallVerification {
		let verification = verify(app)

		guard verification.bundlePath != nil else { throw DirectInstallError.appNotFound }
		guard verification.isSigned else { throw DirectInstallError.notSigned(verification.issues) }

		InstallQueue.shared.enqueue(app)
		Logger.misc.info("Direct install queued for \(app.identifier ?? "unknown")")
		return verification
	}
}
