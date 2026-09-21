//
//  SigningCharacterizationTests.swift
//  VexSignTests
//
//  Phase 1 Step 6 — signing pipeline characterization.
//
//  Pins the behavior of SigningHandler / FR.signPackageFile BEFORE the Phase 2
//  engine refactor: stage order (copy → modify → inject → sign → move →
//  register), workspace isolation and cleanup, original-input preservation,
//  and "nothing is registered on failure". Tests run the real pipeline with
//  `.onlyModify` (no certificate needed) or deliberate failure inputs; no
//  cryptographic signing is attempted and no fake signatures are asserted.
//

import XCTest
import Foundation
@testable import VexSign

final class SigningCharacterizationTests: XCTestCase {

	private var cleanupApps: [AppInfoPresentable] = []

	override func tearDown() async throws {
		for app in cleanupApps {
			await FixturePipeline.delete(app)
		}
		cleanupApps.removeAll()
		try await super.tearDown()
	}

	// MARK: Helpers

	private func importTracked(_ fixture: String) async throws -> AppInfoPresentable {
		let app = try await FixturePipeline.importIPA(fixture)
		cleanupApps.append(app)
		return app
	}

	/// Names inside `Documents/Signed` — a failure must never leave a new one.
	private func signedDirectoryNames() -> Set<String> {
		Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.signed.path)) ?? [])
	}

	/// Count of `VexSigning_*` temp workspaces — a full cycle must net zero.
	private func signingWorkspaceCount() -> Int {
		let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
		return names.filter { $0.hasPrefix("VexSigning_") }.count
	}

	// MARK: - Success path (modify only — no certificate required)

	func testOnlyModifyPipelineCopiesModifiesMovesAndRegisters() async throws {
		let fixture = TestFixtures.url("IPAs/Minimal.ipa")
		let fixtureSHA = FileIntegrity.sha256(of: fixture)

		let app = try await importTracked("IPAs/Minimal.ipa")
		let appUUID = await FixturePipeline.snapshot(of: app).uuid

		let libraryBefore = await FixturePipeline.libraryUUIDs()
		let signedDirsBefore = signedDirectoryNames()

		var options = Options.defaultOptions
		options.signingOption = .onlyModify
		options.appIdentifier = "com.vexsign.test.resigned"
		options.appName = "Resigned Fixture"
		options.appVersion = "9.9"

		let handler = SigningHandler(app: app, options: options)

		// Stage 1 — copy: a private workspace appears; the library is untouched.
		try await handler.copy()
		let uuidsAfterCopy = await FixturePipeline.libraryUUIDs()
		XCTAssertEqual(uuidsAfterCopy, libraryBefore, "copy() must not register anything yet")

		// Stage 2..n — modify, move, register (signing skipped for .onlyModify).
		try await handler.modify()

		// Exactly one new library row, and it is the signed copy.
		let libraryAfter = await FixturePipeline.libraryUUIDs()
		let newUUIDs = libraryAfter.subtracting(libraryBefore)
		XCTAssertEqual(newUUIDs.count, 1, "a successful sign registers exactly one app")
		let signedUUID = try XCTUnwrap(newUUIDs.first)
		let signedLookup = await FixturePipeline.app(withUUID: signedUUID)
		let signed = try XCTUnwrap(signedLookup)
		cleanupApps.append(signed)

		let signedSnapshot = await FixturePipeline.snapshot(of: signed)
		XCTAssertTrue(signedSnapshot.isSigned)
		XCTAssertEqual(signedSnapshot.identifier, "com.vexsign.test.resigned")
		XCTAssertNotNil(handler.signedApp)

		// Modifications landed before the output was finalized.
		let outputDirectoryLookup = await FixturePipeline.appDirectory(for: signed)
		let outputDirectory = try XCTUnwrap(outputDirectoryLookup)
		let info = try XCTUnwrap(NSDictionary(contentsOf: outputDirectory.appendingPathComponent("Info.plist")))
		XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.vexsign.test.resigned")
		XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Resigned Fixture")
		XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "9.9")
		XCTAssertEqual(info["CFBundleVersion"] as? String, "9.9")

		// The signed output is a NEW folder — the unsigned import survives.
		let signedDirsAfter = signedDirectoryNames()
		XCTAssertEqual(signedDirsAfter.count, signedDirsBefore.count + 1)
		let uuidsAfterSign = await FixturePipeline.libraryUUIDs()
		XCTAssertTrue(
			uuidsAfterSign.contains(appUUID ?? ""),
			"the original import must stay in the library after signing"
		)

		// The input IPA in the checkout was never touched.
		XCTAssertEqual(FileIntegrity.sha256(of: fixture), fixtureSHA, "signing must never modify the input IPA")

		try await handler.clean()
	}

	func testWorkspaceIsIsolatedAndRemovedAfterAFullCycle() async throws {
		let app = try await importTracked("IPAs/Minimal.ipa")
		let workspacesBefore = signingWorkspaceCount()

		var options = Options.defaultOptions
		options.signingOption = .onlyModify

		let handler = SigningHandler(app: app, options: options)
		try await handler.copy()
		XCTAssertEqual(signingWorkspaceCount(), workspacesBefore + 1, "copy() creates exactly one workspace")

		try await handler.modify()
		try await handler.clean()
		XCTAssertEqual(signingWorkspaceCount(), workspacesBefore, "the workspace must be gone after the cycle")

		if let signed = handler.signedApp {
			cleanupApps.append(signed)
		}
	}

	// MARK: - Failure paths

	func testMissingCertificateFailsBeforeMoveAndRegistersNothing() async throws {
		let app = try await importTracked("IPAs/Minimal.ipa")
		let libraryBefore = await FixturePipeline.libraryUUIDs()
		let signedDirsBefore = signedDirectoryNames()

		// Default options mean signingOption == .default, and no certificate is set.
		let handler = SigningHandler(app: app, options: Options.defaultOptions)
		XCTAssertNil(handler.appCertificate)

		try await handler.copy()
		do {
			try await handler.modify()
			XCTFail("modify() must throw when signing is requested without a certificate")
		} catch let error as SigningFileHandlerError {
			XCTAssertEqual(error, .missingCertifcate)
		}
		try await handler.clean()

		let uuidsAfterFailedSign = await FixturePipeline.libraryUUIDs()
		XCTAssertEqual(
			uuidsAfterFailedSign, libraryBefore,
			"a failed sign must not register anything"
		)
		XCTAssertEqual(
			signedDirectoryNames(), signedDirsBefore,
			"a failed sign must not leave a Signed/<uuid> folder"
		)
		XCTAssertNil(handler.signedApp)
	}

	func testCorruptedInfoPlistFailsModifyWithTypedError() async throws {
		let app = try await importTracked("IPAs/Minimal.ipa")
		let libraryBefore = await FixturePipeline.libraryUUIDs()

		// Corrupt the imported bundle's Info.plist; copy() carries the damage
		// into the workspace and modify() must fail on it.
		let appDirectoryLookup = await FixturePipeline.appDirectory(for: app)
		let appDirectory = try XCTUnwrap(appDirectoryLookup)
		try Data("this is not a property list".utf8).write(
			to: appDirectory.appendingPathComponent("Info.plist")
		)

		var options = Options.defaultOptions
		options.signingOption = .onlyModify
		let handler = SigningHandler(app: app, options: options)

		try await handler.copy()
		do {
			try await handler.modify()
			XCTFail("modify() must throw for an unreadable Info.plist")
		} catch let error as SigningFileHandlerError {
			XCTAssertEqual(error, .infoPlistNotFound)
		}
		try await handler.clean()

		let uuidsAfterInfoPlistFailure = await FixturePipeline.libraryUUIDs()
		XCTAssertEqual(uuidsAfterInfoPlistFailure, libraryBefore)
	}

	func testInjectionFailureCleansUpAndRegistersNothing() async throws {
		let app = try await importTracked("IPAs/Minimal.ipa")
		let libraryBefore = await FixturePipeline.libraryUUIDs()
		let workspacesBefore = signingWorkspaceCount()

		var options = Options.defaultOptions
		options.signingOption = .onlyModify
		// A file that does not exist makes the injection stage throw.
		options.injectionFiles = [
			FileManager.default.temporaryDirectory
				.appendingPathComponent("vexsign-test-missing-\(UUID().uuidString).dylib")
		]

		let handler = SigningHandler(app: app, options: options)
		try await handler.copy()
		do {
			try await handler.modify()
			XCTFail("modify() must throw when an injection file is missing")
		} catch {
			// The injection stage surfaces a filesystem error; the contract
			// under test is the cleanup, not the exact error type.
		}
		try await handler.clean()

		let uuidsAfterInjectionFailure = await FixturePipeline.libraryUUIDs()
		XCTAssertEqual(uuidsAfterInjectionFailure, libraryBefore)
		XCTAssertEqual(signingWorkspaceCount(), workspacesBefore, "clean() removes the failed workspace")
	}

	// MARK: - FR facade (the entry point every UI flow uses)

	func testFRSignPackageFileSucceedsAndCompletesATaskCenterRecord() async throws {
		let app = try await importTracked("IPAs/Minimal.ipa")
		let appUUID = await FixturePipeline.snapshot(of: app).uuid

		var options = Options.defaultOptions
		options.signingOption = .onlyModify

		let result: Result<Signed, Error> = await withCheckedContinuation { continuation in
			FR.signPackageFile(app, using: options, icon: nil, certificate: nil) { outcome in
				continuation.resume(returning: outcome)
			}
		}
		let signed = try result.get()
		cleanupApps.append(signed)

		let completed = await MainActor.run {
			UnifiedTaskCenter.shared.history.contains {
				$0.kind == .sign && $0.subjectID == appUUID && $0.phase == .completed
			}
		}
		XCTAssertTrue(completed, "a successful sign must land in the task history as completed")
	}

	func testFRSignPackageFileFailureMarksTheTaskFailedWithoutRegistering() async throws {
		let app = try await importTracked("IPAs/Minimal.ipa")
		let appUUID = await FixturePipeline.snapshot(of: app).uuid
		let libraryBefore = await FixturePipeline.libraryUUIDs()

		// .default + nil certificate → SigningFileHandlerError.missingCertifcate.
		let result: Result<Signed, Error> = await withCheckedContinuation { continuation in
			FR.signPackageFile(app, using: Options.defaultOptions, icon: nil, certificate: nil) { outcome in
				continuation.resume(returning: outcome)
			}
		}

		switch result {
		case .success:
			XCTFail("signing without a certificate must fail")
		case .failure(let error):
			XCTAssertEqual(error as? SigningFileHandlerError, .missingCertifcate)
		}

		let uuidsAfterFailedFacadeSign = await FixturePipeline.libraryUUIDs()
		XCTAssertEqual(
			uuidsAfterFailedFacadeSign, libraryBefore,
			"a failed sign must not register anything"
		)

		let failedTask = await MainActor.run {
			UnifiedTaskCenter.shared.history.first {
				$0.kind == .sign && $0.subjectID == appUUID && $0.phase == .failed
			}
		}
		XCTAssertNotNil(failedTask, "a failed sign must land in the task history as failed")
		XCTAssertEqual(failedTask?.failureStage, .signing, "the failure stage records where the task was")
	}
}
