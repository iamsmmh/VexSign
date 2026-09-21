//
//  UnifiedTaskCenterCharacterizationTests.swift
//  VexSignTests
//
//  Phase 1 Step 12 — task center characterization (complements
//  StabilityAndArchitectureTests, which covers phases, terminal finality,
//  snapshot round-trip and the pipeline definition).
//
//  UnifiedTaskCenter must remain the sole task authority; these tests pin the
//  remaining contracts: history persistence + cap, cancellation, the retry
//  handler lifecycle, and the failure description surface.
//

import XCTest
import Foundation
@testable import VexSign

final class UnifiedTaskCenterCharacterizationTests: XCTestCase {

	private var center: UnifiedTaskCenter { UnifiedTaskCenter.shared }

	private var historyFileURL: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		return base.appendingPathComponent("UnifiedTaskHistory.json")
	}

	// MARK: - Persistence

	func testTerminalTasksPersistToTheHistoryFile() throws {
		let marker = "persist-\(UUID().uuidString)"
		let task = center.begin(kind: .sign, title: marker)
		center.transition(task, to: .signing)
		center.transition(task, to: .completed, progress: 1)

		let data = try Data(contentsOf: historyFileURL)
		let snapshots = try JSONDecoder().decode([UnifiedTask.Snapshot].self, from: data)
		XCTAssertTrue(snapshots.contains { $0.id == task.id }, "finished tasks must be persisted")
		XCTAssertTrue(snapshots.contains { $0.title == marker })
	}

	func testHistoryIsCappedAndKeepsNewest() {
		// The cap is 200; create one more than that and assert the trim.
		let batch = UUID().uuidString
		for index in 0..<201 {
			let task = center.begin(kind: .download, title: "\(batch)-\(index)")
			center.transition(task, to: .completed, progress: 1)
		}

		XCTAssertLessThanOrEqual(center.history.count, 200, "history must never exceed the cap")
		XCTAssertTrue(
			center.history.contains { $0.title == "\(batch)-200" },
			"the newest entry must survive the trim"
		)
	}

	func testHistoryIsNewestFirst() {
		let first = center.begin(kind: .install, title: "older-\(UUID().uuidString)")
		center.transition(first, to: .completed)
		let second = center.begin(kind: .install, title: "newer-\(UUID().uuidString)")
		center.transition(second, to: .completed)

		let firstIndex = center.history.firstIndex { $0.id == first.id }
		let secondIndex = center.history.firstIndex { $0.id == second.id }
		XCTAssertNotNil(firstIndex)
		XCTAssertNotNil(secondIndex)
		if let firstIndex, let secondIndex {
			XCTAssertLessThan(secondIndex, firstIndex, "newest entries must come first")
		}
	}

	func testClearHistoryRemovesFileAndEntries() throws {
		let task = center.begin(kind: .sign, title: "to-clear-\(UUID().uuidString)")
		center.transition(task, to: .failed, error: "boom")
		XCTAssertTrue(FileManager.default.fileExists(atPath: historyFileURL.path))

		center.clearHistory()

		XCTAssertTrue(center.history.isEmpty)
		XCTAssertFalse(FileManager.default.fileExists(atPath: historyFileURL.path))
	}

	// MARK: - Cancellation

	func testCancelMovesTaskToHistoryAsCancelled() {
		let task = center.begin(kind: .update, title: "cancel-me")
		center.cancel(task)

		XCTAssertEqual(task.phase, .cancelled)
		XCTAssertFalse(center.tasks.contains { $0.id == task.id })
		XCTAssertTrue(center.history.contains { $0.id == task.id })

		// Cancelling twice is a no-op on a terminal task.
		center.cancel(task)
		XCTAssertEqual(task.phase, .cancelled)
	}

	// MARK: - Retry

	func testRetryWithoutHandlerReturnsFalse() {
		let task = center.begin(kind: .download, title: "no-handler")
		center.transition(task, to: .failed, error: "network")
		XCTAssertFalse(center.retry(task), "after relaunch-style loss of handlers, retry must fail cleanly")
	}

	func testRetryWithHandlerRequeuesTheTask() {
		let task = center.begin(kind: .download, title: "retry-me")
		center.transition(task, to: .failed, error: "flaky")

		var invoked = false
		center.registerRetry(task) { invoked = true }

		XCTAssertTrue(center.retry(task))
		XCTAssertTrue(invoked)
		XCTAssertEqual(task.phase, .queued)
		XCTAssertEqual(task.progress, 0)
		XCTAssertNil(task.failureStage)
		XCTAssertNil(task.errorText)
		XCTAssertTrue(center.tasks.contains { $0.id == task.id }, "retried task returns to the active list")
		XCTAssertFalse(center.history.contains { $0.id == task.id }, "retried task leaves the history")

		// The handler is one-shot.
		XCTAssertFalse(center.retry(task), "a retry handler must not fire twice")
		XCTAssertTrue(invoked)

		// Cleanup.
		center.transition(task, to: .cancelled)
	}

	// MARK: - Failure description

	func testFailureDescriptionReportsStageAndMessage() {
		let task = center.begin(kind: .sign, title: "fail-desc", phase: .signing)
		center.transition(task, to: .failed, error: "cert expired")

		XCTAssertEqual(task.failureStage, .signing, "failure stage is the phase the task was in")
		let description = center.failureDescription
		XCTAssertTrue(description.contains("Signing"), "description: \(description)")
		XCTAssertTrue(description.contains("cert expired"), "description: \(description)")
	}
}
