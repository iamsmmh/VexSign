//
//  DownloadCharacterizationTests.swift
//  VexSignTests
//
//  Phase 1 Step 9 — download pipeline characterization without a network.
//
//  DownloadManager's URLSession plumbing is exercised only through the state
//  it leaves behind: the Download phase machine, the progress summary, the
//  ResumeData_<id>.data persistence file, cancel/cleanup semantics, and URL
//  dedupe. No production seam is added; everything here uses the existing
//  internal API surface.
//

import XCTest
import Foundation
@testable import VexSign

final class DownloadCharacterizationTests: XCTestCase {

	private var manager: DownloadManager { DownloadManager.shared }

	private func documentsResumeFile(for id: String) -> URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("ResumeData_\(id).data")
	}

	private func uniqueURL() -> URL {
		URL(string: "file:///tmp/vexsign-dl-\(UUID().uuidString).ipa")!
	}

	/// Polls an async condition on the main actor for up to ~5 seconds.
	private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
		for _ in 0..<50 {
			if await MainActor.run(body: condition) { return }
			try? await Task.sleep(nanoseconds: 100_000_000)
		}
	}

	// MARK: - Download phase machine

	func testDownloadPhaseLifecycle() {
		let download = Download(id: "phase-test", url: uniqueURL())

		XCTAssertEqual(download.phase, .queued, "fresh downloads are queued")

		download.isActive = true
		XCTAssertEqual(download.phase, .downloading)

		download.progress = 0.4
		download.isPaused = true
		download.isActive = false
		XCTAssertEqual(download.phase, .paused)

		download.isPaused = false
		download.progress = 1.0
		XCTAssertEqual(download.phase, .importing, "finished bytes flip straight into importing")

		download.beginImport()
		XCTAssertTrue(download.isImporting)
		XCTAssertEqual(download.phase, .importing)

		download.unpackageProgress = 1.0
		download.isSigning = true
		XCTAssertEqual(download.phase, .signing)

		download.isSigning = false
		XCTAssertEqual(download.phase, .completed)

		// endImport clears the staged-file retry pointer.
		download.pendingFileURL = uniqueURL()
		download.endImport()
		XCTAssertNil(download.pendingFileURL)
		XCTAssertFalse(download.isImporting)
	}

	func testFileNameAndManualDetection() {
		let url = URL(string: "https://example.com/path/App.ipa?token=abc")!

		let named = Download(id: "a", url: url, appName: "Pretty Name")
		XCTAssertEqual(named.fileName, "Pretty Name")

		let derived = Download(id: "b", url: url)
		XCTAssertEqual(derived.fileName, "App.ipa")

		XCTAssertFalse(derived.isManual)
		XCTAssertTrue(Download(id: "VexSignManualDownload-1", url: url).isManual)
	}

	func testOnlyArchivingDownloadsSkipTheNetworkPhases() {
		let download = Download(id: "arch", url: uniqueURL(), onlyArchiving: true)
		download.progress = 0.5
		XCTAssertEqual(download.phase, .importing, "archiving-only downloads go straight to importing")
	}

	// MARK: - Progress summary aggregation

	func testProgressSummaryUsesByteWeightedProgress() {
		let a = Download(id: "a", url: uniqueURL())
		a.isActive = true
		a.bytesDownloaded = 100
		a.totalBytes = 200

		let b = Download(id: "b", url: uniqueURL())
		b.isActive = true
		b.bytesDownloaded = 300
		b.totalBytes = 600

		let summary = DownloadProgressSummary([a, b])
		XCTAssertEqual(summary.phase, .downloading)
		XCTAssertEqual(summary.downloadingCount, 2)
		XCTAssertEqual(summary.progress, 0.5, accuracy: 0.001, "(100+300)/(200+600)")
	}

	func testProgressSummaryFallsBackToAveragesWithoutTotals() {
		let a = Download(id: "a", url: uniqueURL())
		a.isActive = true
		a.progress = 0.5 // no totalBytes -> phaseProgress == progress

		let summary = DownloadProgressSummary([a])
		XCTAssertEqual(summary.progress, 0.5, accuracy: 0.001)
	}

	func testProgressSummaryPhasePrecedence() {
		XCTAssertEqual(DownloadProgressSummary([]).phase, .queued, "empty queue is queued, not completed")

		let done = Download(id: "done", url: uniqueURL())
		done.unpackageProgress = 1.0
		XCTAssertEqual(DownloadProgressSummary([done]).phase, .completed)

		let importing = Download(id: "imp", url: uniqueURL())
		importing.isImporting = true
		importing.unpackageProgress = 0.3
		let downloading = Download(id: "dl", url: uniqueURL())
		downloading.isActive = true
		downloading.progress = 0.1
		XCTAssertEqual(
			DownloadProgressSummary([importing, downloading]).phase, .downloading,
			"any network activity outranks importing"
		)

		let signing = Download(id: "sig", url: uniqueURL())
		signing.isSigning = true
		XCTAssertEqual(
			DownloadProgressSummary([importing, signing]).phase, .importing,
			"importing outranks signing when both are pending"
		)
	}

	// MARK: - Resume data persistence + cancel cleanup

	func testResumeDataRoundTripAndCancelCleanup() async {
		let download = Download(id: "resume-\(UUID().uuidString)", url: uniqueURL())
		download.resumeData = Data("vexsign-resume-token".utf8)

		await MainActor.run { manager.downloads.append(download) }

		manager.saveResumeData(for: download)
		let resumeFile = documentsResumeFile(for: download.id)
		XCTAssertTrue(FileManager.default.fileExists(atPath: resumeFile.path), "resume data must persist to Documents")
		XCTAssertEqual(try? Data(contentsOf: resumeFile), Data("vexsign-resume-token".utf8))

		await MainActor.run { manager.cancelDownload(download) }

		await waitUntil { !self.manager.downloads.contains { $0.id == download.id } }
		await waitUntil { !FileManager.default.fileExists(atPath: resumeFile.path) }

		let stillListed = await MainActor.run { self.manager.downloads.contains { $0.id == download.id } }
		XCTAssertFalse(stillListed, "cancel must remove the download from tracking")
		XCTAssertFalse(FileManager.default.fileExists(atPath: resumeFile.path), "cancel must delete the resume file")
	}

	func testSaveResumeDataIsANoOpWithoutData() {
		let download = Download(id: "noresume-\(UUID().uuidString)", url: uniqueURL())
		manager.saveResumeData(for: download)
		XCTAssertFalse(FileManager.default.fileExists(atPath: documentsResumeFile(for: download.id).path))
	}

	// MARK: - Pause semantics without an active task

	func testPauseFlagsApplyEvenWithoutATask() {
		let download = Download(id: "pause-test", url: uniqueURL())
		download.isActive = true

		manager.pauseDownload(download)
		XCTAssertTrue(download.isPaused)
		XCTAssertFalse(download.isActive)
	}

	// MARK: - URL dedupe

	func testDuplicateURLReturnsTheExistingDownload() async throws {
		try XCTSkipIf(GameMode.isEnabled, "Game Mode blocks all downloads; cannot exercise dedupe")

		let url = uniqueURL()
		let existing = Download(id: "dedupe-\(UUID().uuidString)", url: url)

		await MainActor.run { manager.downloads.append(existing) }

		let returned = await MainActor.run { self.manager.startDownload(from: url) }

		XCTAssertIdentical(returned, existing, "a second start for the same URL must resume the existing row")
		let count = await MainActor.run { self.manager.downloads.filter { $0.url == url }.count }
		XCTAssertEqual(count, 1, "dedupe must not add a second row")

		// Cleanup: cancel explicitly. The file:// task also fails async via the
		// unsupported-URL path, which removes the row itself — either way the
		// manager must end up clean.
		await MainActor.run { self.manager.cancelDownload(existing) }
		await waitUntil { !self.manager.downloads.contains { $0.url == url } }
		let leftover = await MainActor.run { self.manager.downloads.contains { $0.url == url } }
		XCTAssertFalse(leftover)
	}

	// MARK: - Derived collections

	func testManualAndActiveCollectionsPartitionDownloads() async {
		let manual = Download(id: "VexSignManualDownload-x", url: uniqueURL())
		let automatic = Download(id: "auto-x", url: uniqueURL())
		automatic.onlyArchiving = true

		await MainActor.run {
			self.manager.downloads.append(manual)
			self.manager.downloads.append(automatic)
		}

		await MainActor.run {
			XCTAssertTrue(self.manager.manualDownloads.contains { $0.id == manual.id })
			XCTAssertFalse(self.manager.manualDownloads.contains { $0.id == automatic.id })
			XCTAssertEqual(self.manager.activeNetworkDownloads.count, 0, "archiving-only rows are not network downloads")
			XCTAssertFalse(self.manager.hasUnfinishedWork, "queued/archiving rows are not unfinished work")
		}

		await MainActor.run {
			self.manager.cancelDownload(manual)
			self.manager.cancelDownload(automatic)
		}
		await waitUntil { !self.manager.downloads.contains { $0.id == manual.id || $0.id == automatic.id } }
	}
}
