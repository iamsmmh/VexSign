//
//  FixtureSupport.swift
//  VexSignTests
//
//  Phase 1 test foundation: fixture lookup, deterministic adversarial-archive
//  generation (MiniZipWriter), and helpers that drive the production import /
//  signing pipelines from tests.
//
//  Committed fixtures (IPAs, tweaks, repo JSON) live next to this file and are
//  produced by `tools/make_test_fixtures.py`. Adversarial archives (traversal,
//  symlinks, bombs) are generated at test runtime by `MiniZipWriter` — the
//  byte layout mirrors the generator's `zip_store` exactly and is self-checked
//  by `testMiniZipProducesReadableArchives` before any security test relies
//  on it.
//

import XCTest
import Foundation
@testable import VexSign

// MARK: - Fixture lookup

enum TestFixtures {
	/// Fixtures are addressed relative to this source file (they live in the
	/// `Fixtures/` folder next to it), so the directory layout is preserved
	/// exactly and no resource-bundling rules apply.
	static var root: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures", isDirectory: true)
	}

	static func url(_ relativePath: String) -> URL {
		root.appendingPathComponent(relativePath)
	}

	/// Copies a fixture into a unique temporary location (callers own cleanup).
	static func copyToTemp(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
		let source = url(relativePath)
		guard FileManager.default.fileExists(atPath: source.path) else {
			throw XCTSkip("Missing fixture: \(relativePath)")
		}
		let destination = FileManager.default.temporaryDirectory
			.appendingPathComponent("VexSignFixture_\(UUID().uuidString)", isDirectory: true)
			.appendingPathComponent(source.lastPathComponent)
		try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.copyItem(at: source, to: destination)
		return destination
	}

	/// Network-dependent tests are integration tests: skipped unless the
	/// environment opts in, so the normal suite is deterministic.
	static var integrationTestsEnabled: Bool {
		ProcessInfo.processInfo.environment["VEXSIGN_INTEGRATION_TESTS"] == "1"
	}
}

// MARK: - CRC-32 (zlib polynomial, for MiniZipWriter)

private let crc32Table: [UInt32] = {
	(0..<256).map { byte -> UInt32 in
		var value = UInt32(byte)
		for _ in 0..<8 {
			value = (value & 1 == 1) ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
		}
		return value
	}
}()

func crc32(_ data: Data) -> UInt32 {
	var value: UInt32 = 0xFFFFFFFF
	for byte in data {
		value = crc32Table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
	}
	return value ^ 0xFFFFFFFF
}

// MARK: - MiniZipWriter

/// Minimal STORE-only ZIP writer with full control over entry names and
/// metadata. Produces archives that ZIPFoundation reads; used to build both a
/// known-good archive (self-check) and adversarial archives for the security
/// characterization tests. The layout matches `tools/make_test_fixtures.py`.
enum MiniZipWriter {
	struct Entry {
		var name: String
		var content: Data
		var isSymlink: Bool = false
		/// Overrides the uncompressed size stored in the headers (for bomb
		/// fixtures whose metadata deliberately lies about the payload).
		var declaredUncompressedSize: UInt32? = nil
	}

	/// Fixed DOS timestamp (2024-01-02 03:04:06) so archives are deterministic.
	private static let dosTime: UInt16 = (0x60 << 9) | (3 << 11) | (4 << 5) | UInt16(6 / 2)
	private static let dosDate: UInt16 = ((2024 - 1980) << 9) | (1 << 5) | 2

	static func zip(_ entries: [Entry]) -> Data {
		var local = Data()
		var central = Data()
		var offset: UInt32 = 0

		for entry in entries {
			let nameBytes = Data(entry.name.utf8)
			let crc = crc32(entry.content)
			let uncompressed = entry.declaredUncompressedSize ?? UInt32(entry.content.count)
			let externalAttributes: UInt32 = entry.isSymlink ? 0xA000_0000 : 0x81A4_0000

			local.append(signature: 0x04034B50)
			local.append(u16: 20)                  // version needed
			local.append(u16: 0)                   // flags
			local.append(u16: 0)                   // method: store
			local.append(u16: dosTime)
			local.append(u16: dosDate)
			local.append(u32: crc)
			local.append(u32: uncompressed)        // compressed size (store)
			local.append(u32: uncompressed)
			local.append(u16: UInt16(nameBytes.count))
			local.append(u16: 0)                   // extra length
			local.append(nameBytes)
			local.append(entry.content)

			central.append(signature: 0x02014B50)
			central.append(u16: 20)                // version made by
			central.append(u16: 20)                // version needed
			central.append(u16: 0)
			central.append(u16: 0)
			central.append(u16: dosTime)
			central.append(u16: dosDate)
			central.append(u32: crc)
			central.append(u32: uncompressed)
			central.append(u32: uncompressed)
			central.append(u16: UInt16(nameBytes.count))
			central.append(u16: 0)                 // extra
			central.append(u16: 0)                 // comment
			central.append(u16: 0)                 // disk start
			central.append(u16: 0)                 // internal attributes
			central.append(u32: externalAttributes)
			central.append(u32: offset)
			central.append(nameBytes)

			offset += 30 + UInt32(nameBytes.count) + UInt32(entry.content.count)
		}

		var eocd = Data()
		eocd.append(signature: 0x06054B50)
		eocd.append(u16: 0)
		eocd.append(u16: 0)
		eocd.append(u16: UInt16(entries.count))
		eocd.append(u16: UInt16(entries.count))
		eocd.append(u32: UInt32(central.count))
		eocd.append(u32: offset)
		eocd.append(u16: 0)

		return local + central + eocd
	}
}

private extension Data {
	mutating func append(u16 value: UInt16) {
		var littleEndian = value.littleEndian
		withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
	}

	mutating func append(u32 value: UInt32) {
		var littleEndian = value.littleEndian
		withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
	}

	mutating func append(signature value: UInt32) {
		append(u32: value)
	}
}

// MARK: - Adversarial archive factory

/// The malicious archives used by the security characterization tests, each a
/// minimal ZIP whose single unsafe entry triggers one policy branch of
/// `ArchiveSafetyValidator` (or one behavior of the extraction pipeline).
enum UnsafeArchiveFactory {
	static func parentEscape() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "Payload/App.app/Info.plist", content: Data("<plist/>".utf8)),
			MiniZipWriter.Entry(name: "../escape.txt", content: Data("escaped".utf8)),
		])
	}

	static func nestedTraversal() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "Payload/../../../escape-nested.txt", content: Data("escaped".utf8)),
		])
	}

	static func absolutePath() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "/etc/vexsign-test-absolute", content: Data("absolute".utf8)),
		])
	}

	static func homeRelative() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "~/vexsign-test-tilde", content: Data("tilde".utf8)),
		])
	}

	static func nulByteName() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "bad\u{0}name.txt", content: Data("nul".utf8)),
		])
	}

	static func symlinkEscape() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "evil-link", content: Data("/etc/passwd".utf8), isSymlink: true),
		])
	}

	static func duplicateEntries() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "dup.txt", content: Data("first".utf8)),
			MiniZipWriter.Entry(name: "dup.txt", content: Data("second".utf8)),
		])
	}

	/// 50 001 empty entries — one past ArchiveSafetyValidator's entry cap.
	/// Generated at runtime so the repository never carries a multi-MB bomb.
	static func excessiveEntryCount() -> Data {
		var entries: [MiniZipWriter.Entry] = []
		entries.reserveCapacity(50_001)
		for index in 0...50_000 {
			entries.append(MiniZipWriter.Entry(name: "e\(index)", content: Data()))
		}
		return MiniZipWriter.zip(entries)
	}

	/// Two entries whose *declared* uncompressed sizes sum past the 8 GB cap
	/// while the stored payload is one byte — metadata bombs must be rejected
	/// without reading any payload.
	static func excessiveDeclaredSize() -> Data {
		MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "big-a.bin", content: Data([0]), declaredUncompressedSize: 5_000_000_000),
			MiniZipWriter.Entry(name: "big-b.bin", content: Data([0]), declaredUncompressedSize: 5_000_000_000),
		])
	}

	static func notAnArchive() -> Data {
		Data("this is definitely not a zip archive".utf8)
	}

	/// Writes `data` to a unique temp file with the given extension.
	static func write(_ data: Data, ext: String) throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("VexSignUnsafe_\(UUID().uuidString).\(ext)")
		try data.write(to: url)
		return url
	}
}

// MARK: - Async assertion helpers

/// `XCTAssertThrowsError` for async expressions.
func XCTAssertThrowsErrorAsync<T>(
	_ expression: () async throws -> T,
	_ message: String = "Expected an error",
	file: StaticString = #filePath,
	line: UInt = #line,
	_ errorHandler: (Error) -> Void = { _ in }
) async {
	do {
		_ = try await expression()
		XCTFail(message, file: file, line: line)
	} catch {
		errorHandler(error)
	}
}

// MARK: - Production pipeline helpers

enum FixturePipeline {
	/// Imports a fixture IPA through the real import pipeline
	/// (`FR.handlePackageFile` → `AppFileHandler`) and returns the library row.
	static func importIPA(_ fixture: String, file: StaticString = #filePath, line: UInt = #line) async throws -> AppInfoPresentable {
		let staged = try TestFixtures.copyToTemp(fixture, file: file, line: line)
		defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }

		let result: Result<AppInfoPresentable, Error> = await withCheckedContinuation { continuation in
			FR.handlePackageFile(staged) { outcome in
				continuation.resume(returning: outcome)
			}
		}
		return try result.get()
	}

	/// Imports a fixture IPA and expects the import to fail; returns the error.
	static func importIPAFailing(_ fixture: String, file: StaticString = #filePath, line: UInt = #line) async throws -> Error {
		let staged = try TestFixtures.copyToTemp(fixture, file: file, line: line)
		defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }

		let result: Result<AppInfoPresentable, Error> = await withCheckedContinuation { continuation in
			FR.handlePackageFile(staged) { outcome in
				continuation.resume(returning: outcome)
			}
		}
		switch result {
		case .success:
			XCTFail("Expected the import of \(fixture) to fail", file: file, line: line)
			throw ImportError(.database, fileName: fixture, id: "test", reason: "import unexpectedly succeeded")
		case .failure(let error):
			return error
		}
	}

	/// Deletes a library app on the main actor (its row and on-disk bundle).
	static func delete(_ app: AppInfoPresentable?) async {
		guard let app else { return }
		await MainActor.run {
			Storage.shared.deleteApp(for: app)
		}
	}

	/// Snapshot of the library's uuids, for before/after consistency checks.
	/// Core Data's view context is main-queue bound, so the fetch hops there.
	static func libraryUUIDs() async -> Set<String> {
		await MainActor.run {
			Set(Storage.shared.getAllApps().compactMap { $0.uuid })
		}
	}

	/// The library row for a uuid, read on the main actor.
	static func app(withUUID uuid: String) async -> AppInfoPresentable? {
		await MainActor.run { Storage.shared.app(withUuid: uuid) }
	}

	/// Value snapshot of a managed app so tests can assert off the main actor
	/// without touching the Core Data object from the wrong queue.
	struct AppSnapshot: Sendable {
		let uuid: String?
		let identifier: String?
		let name: String?
		let isSigned: Bool
	}

	static func snapshot(of app: AppInfoPresentable) async -> AppSnapshot {
		await MainActor.run {
			AppSnapshot(
				uuid: app.uuid,
				identifier: app.identifier,
				name: app.name,
				isSigned: app.isSigned
			)
		}
	}

	/// The on-disk `.app` directory of a library app, resolved on the main actor.
	static func appDirectory(for app: AppInfoPresentable) async -> URL? {
		await MainActor.run { Storage.shared.getAppDirectory(for: app) }
	}

	/// The newest `Signed` row created after `before` (by date), if any.
	static func signedApps() async -> [AppInfoPresentable] {
		await MainActor.run {
			Storage.shared.getAllApps().filter { $0.isSigned }
		}
	}
}
