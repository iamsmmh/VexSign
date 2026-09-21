//
//  IPAWorkspaceCharacterizationTests.swift
//  VexSignTests
//
//  Phase 1 Step 10 — IPA workspace round-trip, change journal and undo.
//
//  Pins the open → edit → undo → rebuild lifecycle for archive workspaces,
//  the journal's first-backup-wins rule, the recents registry, and the
//  library-app variant (edits land in place; rebuild wraps the bundle in a
//  throwaway Payload/). Traversal rejection at this boundary is covered in
//  ArchiveSecurityTests.
//

import XCTest
import Foundation
import ZIPFoundation
@testable import VexSign

@MainActor
final class IPAWorkspaceCharacterizationTests: XCTestCase {

	private var tempFiles: [URL] = []

	override func tearDown() {
		for url in tempFiles {
			try? FileManager.default.removeItem(at: url)
		}
		tempFiles.removeAll()
		super.tearDown()
	}

	private func tempFile(_ ext: String) -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("vexsign-ws-\(UUID().uuidString).\(ext)")
		tempFiles.append(url)
		return url
	}

	private func entries(of zip: URL) throws -> [String] {
		guard let archive = Archive(url: zip, accessMode: .read) else {
			throw CocoaError(.fileReadCorruptFile)
		}
		return archive.map { $0.path }
	}

	// MARK: - Open + recents round-trip

	func testOpenIPACreatesWorkspaceAndRecentRecord() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		XCTAssertFalse(workspace.isLibraryApp)
		XCTAssertEqual(workspace.name, "App")
		XCTAssertEqual(workspace.changeCount, 0)
		XCTAssertNotNil(workspace.journal, "archive workspaces must have an undo journal")
		XCTAssertTrue(FileManager.default.fileExists(
			atPath: workspace.appURL.appendingPathComponent("Info.plist").path
		))

		// The recents registry picks up the metadata sidecar.
		let recents = IPAWorkspace.recents()
		XCTAssertTrue(recents.contains { $0.id == workspace.id }, "opened workspace must appear in recents")

		// Reopening the recent returns an equivalent workspace.
		let record = try XCTUnwrap(recents.first { $0.id == workspace.id })
		let reopened = try IPAWorkspace.open(recent: record)
		XCTAssertEqual(reopened.name, workspace.name)
		XCTAssertEqual(reopened.appURL.lastPathComponent, workspace.appURL.lastPathComponent)

		// Discard removes the directory and the recent entry.
		let workspaceDirectory = IPAWorkspace.root.appendingPathComponent(workspace.id, isDirectory: true)
		workspace.discard()
		XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceDirectory.path))
		XCTAssertFalse(IPAWorkspace.recents().contains { $0.id == workspace.id })
	}

	func testOpenIPAWithoutPayloadThrowsAppNotFound() async {
		do {
			let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/NoPayload.ipa"))
			workspace.discard()
			XCTFail("an IPA without Payload/*.app must not open")
		} catch let error as IPAWorkspaceError {
			if case .appNotFound = error { /* expected */ } else {
				XCTFail("unexpected workspace error: \(error)")
			}
		} catch {
			XCTFail("unexpected error type: \(error)")
		}
	}

	// MARK: - Journal undo

	func testUndoRestoresModifiedFile() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		let infoPlist = workspace.appURL.appendingPathComponent("Info.plist")
		let original = try Data(contentsOf: infoPlist)

		// Backup first, then edit, then journal — the production order.
		let backupName = workspace.backupForUndo(infoPlist)
		XCTAssertNotNil(backupName)
		try Data("<!-- edited -->".utf8).write(to: infoPlist)
		workspace.journalChange(kind: .modified, url: infoPlist, backupName: backupName)
		XCTAssertTrue(workspace.isDirty)

		XCTAssertTrue(workspace.undoChange(at: infoPlist), "undo must revert the edit")
		XCTAssertEqual(try Data(contentsOf: infoPlist), original, "original bytes must be restored")
		XCTAssertFalse(workspace.undoChange(at: infoPlist), "nothing left to undo for this path")
	}

	func testSecondEditKeepsTheFirstBackup() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		let infoPlist = workspace.appURL.appendingPathComponent("Info.plist")
		let original = try Data(contentsOf: infoPlist)

		// First edit.
		let first = workspace.backupForUndo(infoPlist)
		try Data("edit one".utf8).write(to: infoPlist)
		workspace.journalChange(kind: .modified, url: infoPlist, backupName: first)

		// Second edit — the journal must keep the FIRST backup and drop the second.
		let second = workspace.backupForUndo(infoPlist)
		try Data("edit two".utf8).write(to: infoPlist)
		workspace.journalChange(kind: .modified, url: infoPlist, backupName: second)

		XCTAssertEqual(workspace.journal?.changes.count, 1, "one journal entry per path")
		if let second {
			let backupsDir = try XCTUnwrap(workspace.journal).backupsDirectory
			XCTAssertFalse(
				FileManager.default.fileExists(atPath: backupsDir.appendingPathComponent(second).path),
				"the superseded second backup must be deleted"
			)
		}

		XCTAssertTrue(workspace.undoChange(at: infoPlist))
		XCTAssertEqual(try Data(contentsOf: infoPlist), original, "undo restores the pre-session bytes")
	}

	func testUndoOfAddedFileRemovesIt() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		let added = workspace.appURL.appendingPathComponent("BrandNew.txt")
		try Data("new".utf8).write(to: added)
		workspace.journalChange(kind: .added, url: added, backupName: nil)

		XCTAssertTrue(workspace.undoChange(at: added))
		XCTAssertFalse(FileManager.default.fileExists(atPath: added.path), "undo of an add removes the file")
	}

	func testAddedFileThatGetsEditedStaysAdded() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		let added = workspace.appURL.appendingPathComponent("Edited.txt")
		try Data("v1".utf8).write(to: added)
		workspace.journalChange(kind: .added, url: added, backupName: nil)

		// Editing an added file must NOT create a modified entry (no original exists).
		let backup = workspace.backupForUndo(added)
		try Data("v2".utf8).write(to: added)
		workspace.journalChange(kind: .modified, url: added, backupName: backup)

		XCTAssertEqual(workspace.journal?.changes.count, 1)
		XCTAssertEqual(workspace.journal?.changes.first?.kind, .added, "added entry wins over later edits")
		XCTAssertTrue(workspace.undoChange(at: added))
		XCTAssertFalse(FileManager.default.fileExists(atPath: added.path))
	}

	func testDiscardChangesRestoresTheWholeSession() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		let infoPlist = workspace.appURL.appendingPathComponent("Info.plist")
		let original = try Data(contentsOf: infoPlist)

		let backup = workspace.backupForUndo(infoPlist)
		try Data("changed".utf8).write(to: infoPlist)
		workspace.journalChange(kind: .modified, url: infoPlist, backupName: backup)

		let added = workspace.appURL.appendingPathComponent("Temp.txt")
		try Data("temp".utf8).write(to: added)
		workspace.journalChange(kind: .added, url: added, backupName: nil)

		let reverted = workspace.discardChanges()
		XCTAssertEqual(reverted, 2)
		XCTAssertEqual(try Data(contentsOf: infoPlist), original)
		XCTAssertFalse(FileManager.default.fileExists(atPath: added.path))
	}

	// MARK: - Rebuild

	func testRebuildProducesValidIPAAndResetsTheJournal() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		workspace.markDirty()
		XCTAssertTrue(workspace.isDirty)

		let output = tempFile("ipa")
		let result = try await workspace.rebuild(to: output)

		XCTAssertEqual(result, output)
		XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
		XCTAssertEqual(workspace.builtArchive, output)
		XCTAssertEqual(workspace.changeCount, 0, "a rebuilt IPA is a clean baseline")
		XCTAssertTrue(workspace.journal?.isEmpty ?? false, "rebuild clears the journal")

		let paths = try entries(of: output)
		XCTAssertTrue(paths.contains { $0.contains("App.app/Info.plist") }, "rebuilt IPA must carry the app: \(paths)")
		XCTAssertTrue(paths.contains { $0.hasPrefix("Payload/") }, "layout must stay Payload/...: \(paths)")
	}

	func testDefaultArchiveURLIsSanitizedAndInsideArchives() async throws {
		let workspace = try await IPAWorkspace.open(ipa: TestFixtures.url("IPAs/Minimal.ipa"))
		addTeardownBlock { await MainActor.run { workspace.discard() } }

		let url = workspace.defaultArchiveURL()
		XCTAssertTrue(url.path.hasPrefix(FileManager.default.archives.path))
		XCTAssertEqual(url.pathExtension, "ipa")
		XCTAssertTrue(url.lastPathComponent.contains("_edited_"))
	}

	// MARK: - Library app workspaces

	func testLibraryAppWorkspaceEditsInPlaceAndWrapsPayloadOnRebuild() async throws {
		// Import Minimal.ipa into the library first.
		let imported = try await FixturePipeline.importIPA("IPAs/Minimal.ipa")
		addTeardownBlock { await FixturePipeline.delete(imported) }

		let appLookup = await FixturePipeline.app(withUUID: imported.uuid ?? "")
		let app = try XCTUnwrap(appLookup)
		let workspace = try IPAWorkspace.open(app: app)

		XCTAssertTrue(workspace.isLibraryApp)
		XCTAssertNil(workspace.journal, "library workspaces edit in place and carry no undo journal")
		XCTAssertEqual(workspace.sourceDescription, "Imported App")

		// Rebuild wraps the live bundle in a throwaway Payload/.
		let output = tempFile("ipa")
		let result = try await workspace.rebuild(to: output)
		XCTAssertEqual(result, output)

		let paths = try entries(of: output)
		XCTAssertTrue(paths.contains { $0.contains("App.app/Info.plist") }, "wrapped rebuild must contain the app: \(paths)")

		// discard() must NOT delete a library app's storage.
		let appDirLookup = await FixturePipeline.appDirectory(for: imported)
		let appDir = try XCTUnwrap(appDirLookup)
		workspace.discard()
		XCTAssertTrue(FileManager.default.fileExists(atPath: appDir.path), "library app must survive discard()")
	}
}
