//
//  InstallQueueCharacterizationTests.swift
//  VexSignTests
//
//  Phase 1 Step 11 — install queue characterization.
//
//  The queue is exercised with activation intentionally blocked: pausing the
//  queue before enqueueing makes `activate()` return early, so no AppInstaller
//  is created and nothing reaches the device boundary (which stays un-mocked —
//  real installs are not claimed from tests). This pins dedupe, queue
//  navigation, skip, and reset semantics deterministically.
//

import XCTest
import Foundation
@testable import VexSign

@MainActor
final class InstallQueueCharacterizationTests: XCTestCase {

	private var queue: InstallQueue { InstallQueue.shared }
	private var imported: [AppInfoPresentable] = []

	override func tearDown() async throws {
		queue.clear() // resets apps/index/outcomes/isPaused and hides the queue window
		for app in imported {
			await FixturePipeline.delete(app)
		}
		imported.removeAll()
		try await super.tearDown()
	}

	private func importApp() async throws -> AppInfoPresentable {
		let app = try await FixturePipeline.importIPA("IPAs/Minimal.ipa")
		imported.append(app)
		return app
	}

	// MARK: - InstallOutcome rules (pure)

	func testOutcomeCanOpenAppRules() {
		let succeeded = InstallQueue.InstallOutcome.succeeded
		XCTAssertTrue(succeeded.canOpenApp(isExport: false, identifier: "com.example.app"))
		XCTAssertFalse(succeeded.canOpenApp(isExport: true, identifier: "com.example.app"),
		               "exports share the success counter but never offer Open")
		XCTAssertFalse(succeeded.canOpenApp(isExport: false, identifier: nil))
		XCTAssertFalse(succeeded.canOpenApp(isExport: false, identifier: ""))

		XCTAssertFalse(InstallQueue.InstallOutcome.pending.canOpenApp(isExport: false, identifier: "x"))
		XCTAssertFalse(InstallQueue.InstallOutcome.skipped.canOpenApp(isExport: false, identifier: "x"))
		XCTAssertFalse(InstallQueue.InstallOutcome.failed("boom").canOpenApp(isExport: false, identifier: "x"))
	}

	// MARK: - Enqueue semantics

	func testEnqueueDedupesAndDoesNotActivateWhilePaused() async throws {
		XCTAssertNil(queue.current, "queue must start empty")

		queue.pause() // blocks activate(): no installer, no device access
		let app = try await importApp()

		queue.enqueue(app)
		XCTAssertEqual(queue.apps.count, 1)
		XCTAssertEqual(queue.outcomes[queue.apps[0].id], .pending)
		XCTAssertNil(queue.installer, "paused queue must not spin up an installer")
		XCTAssertTrue(queue.isSheetPresented)

		queue.enqueue(app) // same id -> ignored
		XCTAssertEqual(queue.apps.count, 1, "enqueuing the same app twice must dedupe")
	}

	func testQueueNavigationAndPillVisibility() async throws {
		queue.pause()
		let first = try await importApp()
		let second = try await importApp()

		queue.enqueue(first)
		queue.enqueue(second)

		XCTAssertEqual(queue.apps.count, 2)
		XCTAssertEqual(queue.current?.id, queue.apps.first?.id)
		XCTAssertEqual(queue.upcoming.map(\.id), [queue.apps[1].id])
		XCTAssertTrue(queue.showsPill, "a queued app shows the pill while the sheet is hidden")

		queue.isSheetPresented = true
		XCTAssertFalse(queue.showsPill, "the pill hides while the sheet is up")
	}

	func testSkipMarksSkippedAndAdvances() async throws {
		queue.pause()
		let first = try await importApp()
		let second = try await importApp()

		queue.enqueue(first)
		queue.enqueue(second)
		let skippedID = try XCTUnwrap(queue.current?.id)

		queue.skip()

		XCTAssertEqual(queue.outcomes[skippedID], .skipped)
		XCTAssertEqual(queue.current?.id, queue.apps[1].id, "skip must advance to the next app")
		XCTAssertNil(queue.installer, "still paused: advancing must not start an installer")
	}

	func testPauseAndResumeFlags() async throws {
		XCTAssertFalse(queue.isPaused, "queue starts unpaused")

		queue.pause()
		XCTAssertTrue(queue.isPaused)

		let app = try await importApp()
		queue.enqueue(app)
		XCTAssertNil(queue.installer, "enqueue while paused must not activate")

		// resume() only activates when it actually unpause something; with the
		// installer still nil it would try to start one, so we only characterize
		// the no-op resume path here (already unpaused after a future clear()).
		queue.clear()
		XCTAssertFalse(queue.isPaused)
		queue.resume() // not paused -> guard returns, nothing happens
		XCTAssertNil(queue.installer)
	}

	func testClearResetsEverything() async throws {
		queue.pause()
		let app = try await importApp()
		queue.enqueue(app)
		XCTAssertFalse(queue.apps.isEmpty)

		queue.clear()

		XCTAssertTrue(queue.apps.isEmpty)
		XCTAssertTrue(queue.outcomes.isEmpty)
		XCTAssertEqual(queue.index, 0)
		XCTAssertFalse(queue.isFinished)
		XCTAssertFalse(queue.isPaused, "clear() fully resets, including the pause flag")
		XCTAssertFalse(queue.isSheetPresented)
		XCTAssertNil(queue.installer)
	}

	func testCountersReflectOutcomes() async throws {
		queue.pause()
		let app = try await importApp()
		queue.enqueue(app)

		XCTAssertEqual(queue.succeededCount, 0)
		XCTAssertEqual(queue.failedCount, 0)
		XCTAssertTrue(queue.installedApps.isEmpty, "pending apps are not installable/openable yet")
	}
}
