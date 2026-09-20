//
//  CompanionAndWidgetTests.swift
//  VexSignTests
//
//  Covers the pure logic behind the new surfaces: the repository widget payload
//  (shared with the widget extension), the companion wire format the Apple TV /
//  Vision Pro / Watch apps speak, and the App Intent entities' resolution rules.
//
//  Everything here is pure — no network, no device, no Core Data writes — so it
//  runs on any host.
//

import XCTest
@testable import VexSign

final class CompanionAndWidgetTests: XCTestCase {

	// MARK: - Repository widget payload

	func testRepoPayloadRoundTripsThroughJSON() throws {
		let payload = WidgetRepoPayload(
			sources: [
				WidgetRepoPayload.Source(
					url: "https://example.com/source.json",
					name: "Example",
					apps: [
						WidgetRepoPayload.App(
							id: "com.example.app.https://example.com/app.ipa",
							name: "Example App",
							bundleID: "com.example.app",
							version: "1.2",
							iconFile: "abc123.png",
							hasUpdate: true
						)
					]
				)
			],
			lastUpdated: Date(timeIntervalSince1970: 1_800_000_000)
		)

		let data = try JSONEncoder().encode(payload)
		let decoded = try JSONDecoder().decode(WidgetRepoPayload.self, from: data)

		XCTAssertEqual(decoded, payload)
		XCTAssertEqual(decoded.appCount, 1)
		XCTAssertEqual(decoded.apps(in: "https://example.com/source.json").first?.name, "Example App")
		XCTAssertTrue(decoded.apps(in: "https://unknown.example").isEmpty)
		XCTAssertEqual(decoded.apps(in: nil).count, 1, "nil means every repository")
	}

	func testRepoPayloadIconNamesAreStableAndUnique() {
		let first = WidgetRepoPayload.iconFileName(for: URL(string: "https://example.com/icon.png")!)
		let again = WidgetRepoPayload.iconFileName(for: URL(string: "https://example.com/icon.png")!)
		let other = WidgetRepoPayload.iconFileName(for: URL(string: "https://example.com/other.png")!)

		XCTAssertEqual(first, again, "the same URL must map to the same cache file")
		XCTAssertNotEqual(first, other)
		XCTAssertTrue(first.hasSuffix(".png"))
		XCTAssertEqual(first.count, 64 + 4, "sha256 hex + .png")
	}

	func testRepoPayloadStaleness() {
		let fresh = WidgetRepoPayload(sources: [], lastUpdated: Date())
		let old = WidgetRepoPayload(sources: [], lastUpdated: Date().addingTimeInterval(-60 * 60 * 25))

		XCTAssertFalse(fresh.isStale)
		XCTAssertTrue(old.isStale)
	}

	func testRepoPayloadPlaceholderIsRenderable() {
		let placeholder = WidgetRepoPayload.placeholder
		XCTAssertFalse(placeholder.sources.isEmpty)
		XCTAssertFalse(placeholder.sources[0].apps.isEmpty)
		XCTAssertFalse(placeholder.isStale)
	}

	// MARK: - Companion wire format

	func testCompanionSnapshotRoundTripsThroughWatchContext() throws {
		let snapshot = CompanionSnapshot(
			status: CompanionStatus(
				certValid: true,
				certName: "Development",
				certExpiry: nil,
				certDaysRemaining: 12,
				certRevoked: false,
				certPPQLess: true,
				installedApps: 7,
				signedApps: 5,
				pendingUpdates: 2,
				storageFree: 1_000_000
			),
			library: [CompanionLibraryEntry(name: "App", bundleID: "com.example.app", version: "1.0", size: 42, signed: true)],
			updates: [CompanionUpdateEntry(name: "App", bundleID: "com.example.app", installedVersion: "1.0", availableVersion: "1.1")],
			generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
		)

		let context = snapshot.contextRepresentation
		let decoded = try XCTUnwrap(CompanionSnapshot.snapshot(from: context))

		XCTAssertEqual(decoded, snapshot)
		XCTAssertEqual(decoded.status.certLabel, "12d")
		XCTAssertEqual(decoded.status.certSummary, "Expires in 12 days")
	}

	func testCompanionSnapshotContextIsRejectableWithoutCrashing() {
		XCTAssertNil(CompanionSnapshot.snapshot(from: [:]))
		XCTAssertNil(CompanionSnapshot.snapshot(from: [CompanionSnapshot.contextKey: Data("not json".utf8)]))
		XCTAssertNil(CompanionSnapshot.snapshot(from: [CompanionSnapshot.contextKey: "wrong type"]))
	}

	func testCompanionStatusLabelsCoverEveryState() {
		func status(days: Int?, revoked: Bool = false) -> CompanionStatus {
			CompanionStatus(
				certValid: !revoked,
				certName: nil,
				certExpiry: nil,
				certDaysRemaining: days,
				certRevoked: revoked,
				certPPQLess: nil,
				installedApps: 0,
				signedApps: 0,
				pendingUpdates: 0,
				storageFree: nil
			)
		}

		XCTAssertEqual(status(days: nil).certLabel, "—")
		XCTAssertEqual(status(days: nil).certSummary, "No certificate")
		XCTAssertEqual(status(days: 0).certLabel, "0d")
		XCTAssertEqual(status(days: 0).certSummary, "Expired")
		XCTAssertEqual(status(days: 1).certSummary, "Expires tomorrow")
		XCTAssertEqual(status(days: 30).certSummary, "Expires in 30 days")
		XCTAssertEqual(status(days: 30, revoked: true).certSummary, "Revoked")
	}

	func testCompanionCommandsHaveStableRawValues() {
		// The watch sends these strings; changing one silently breaks a shipped watch app.
		XCTAssertEqual(CompanionCommand.allCases.map { $0.rawValue }, [
			"refreshSources", "checkCertificates", "updateAll", "cleanNow"
		])
		XCTAssertEqual(CompanionCommand(rawValue: "updateAll")?.title, "Update all apps")
		XCTAssertNil(CompanionCommand(rawValue: "signEverything"))
	}

	func testLibraryEntryFormatting() {
		let entry = CompanionLibraryEntry(name: "App", bundleID: "com.example.app", version: "1.0", size: 1_500_000, signed: true)
		XCTAssertFalse(entry.sizeLabel.isEmpty)
		XCTAssertEqual(entry.id, "com.example.app1.0")
	}

	// MARK: - Companion client

	func testCompanionClientRejectsEmptyAndNonHTTPAddresses() async {
		for address in ["", "   "] {
			let client = CompanionClient(address: address, username: nil, password: nil, apiToken: nil)
			do {
				_ = try await client.snapshot()
				XCTFail("an empty address must not produce a snapshot")
			} catch let error as CompanionClientError {
				XCTAssertEqual(error, .missingAddress)
			} catch {
				XCTFail("unexpected error \(error)")
			}
		}

		let invalid = CompanionClient(address: "ftp://10.0.0.5:8080", username: nil, password: nil, apiToken: nil)
		do {
			_ = try await invalid.snapshot()
			XCTFail("a non-http scheme must be refused")
		} catch let error as CompanionClientError {
			XCTAssertEqual(error, .invalidAddress)
		} catch {
			XCTFail("unexpected error \(error)")
		}
	}

	// MARK: - App Intent entities

	@available(iOS 17.0, *)
	func testSectionEnumMapsOnlyRealTabs() {
		XCTAssertNil(VexSignSection.ipaExplorer.tab, "the explorer is opened through AppNavigationManager, not a tab")
		XCTAssertEqual(VexSignSection.appStore.tab, .appStore)
		XCTAssertEqual(VexSignSection.library.tab, .library)
		XCTAssertEqual(VexSignSection.caseDisplayRepresentations.count, VexSignSection.allCases.count)
	}
}
