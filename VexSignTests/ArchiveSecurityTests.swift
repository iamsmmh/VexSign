//
//  ArchiveSecurityTests.swift
//  VexSignTests
//
//  Phase 1 Step 5 — archive security characterization.
//
//  Proves, against real archive bytes, the policy implemented by
//  ArchiveSafetyValidator (ZIP pre-validation) and Decompression/AR (tar/deb
//  extraction): traversal, absolute/home paths, NUL names, symlink entries,
//  entry-count and size bombs, malformed input, duplicate entries — and that
//  validation happens BEFORE extraction in the production import paths.
//
//  Adversarial archives are generated at runtime by MiniZipWriter /
//  UnsafeArchiveFactory; their byte layout is self-checked in this file before
//  any security assertion depends on it.
//

import XCTest
import Foundation
@testable import VexSign

final class ArchiveSecurityTests: XCTestCase {

	private var tempFiles: [URL] = []

	override func tearDown() {
		for url in tempFiles {
			try? FileManager.default.removeItem(at: url)
		}
		tempFiles.removeAll()
		super.tearDown()
	}

	private func track(_ url: URL) -> URL {
		tempFiles.append(url)
		return url
	}

	// MARK: - Self-check: MiniZipWriter output is a real readable archive

	/// If this fails, every security test below is vacuous — the writer's byte
	/// layout diverged from the ZIP spec and nothing past this point matters.
	func testMiniZipProducesReadableArchives() throws {
		let archive = MiniZipWriter.zip([
			MiniZipWriter.Entry(name: "Payload/Good.app/Info.plist", content: Data("<plist/>".utf8)),
			MiniZipWriter.Entry(name: "Payload/Good.app/App", content: Data(repeating: 1, count: 128)),
		])
		let url = try track(UnsafeArchiveFactory.write(archive, ext: "zip"))

		// ArchiveSafetyValidator opens the archive with ZIPFoundation and walks
		// every entry; a readable archive with safe names passes.
		try ArchiveSafetyValidator.validate(url)
	}

	func testCRC32MatchesKnownVector() {
		// "hello" — same vector used by FileIntegrity's SHA-256 test.
		XCTAssertEqual(crc32(Data("hello".utf8)), 0x3610A686)
		XCTAssertEqual(crc32(Data()), 0)
	}

	// MARK: - ArchiveSafetyValidator policy, case by case

	private func assertRejected(
		_ archive: Data,
		expecting expectation: (ArchiveSafetyValidator.ValidationError) -> Bool,
		_ label: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws {
		let url = try track(UnsafeArchiveFactory.write(archive, ext: "ipa"))
		do {
			try ArchiveSafetyValidator.validate(url)
			XCTFail("\(label): archive was accepted but must be rejected", file: file, line: line)
		} catch let error as ArchiveSafetyValidator.ValidationError {
			XCTAssertTrue(expectation(error), "\(label): unexpected validation error \(error)", file: file, line: line)
		}
	}

	func testValidatorRejectsParentTraversal() throws {
		try assertRejected(UnsafeArchiveFactory.parentEscape()) {
			if case .traversalPath(let path) = $0 { return path.contains("../escape.txt") }
			return false
		}
	}

	func testValidatorRejectsNestedTraversal() throws {
		try assertRejected(UnsafeArchiveFactory.nestedTraversal()) {
			if case .traversalPath = $0 { return true }
			return false
		}
	}

	func testValidatorRejectsAbsolutePaths() throws {
		try assertRejected(UnsafeArchiveFactory.absolutePath()) {
			if case .absolutePath(let path) = $0 { return path.hasPrefix("/") }
			return false
		}
	}

	func testValidatorRejectsHomeRelativePaths() throws {
		// `~/...` is treated as an absolute-path escape by policy.
		try assertRejected(UnsafeArchiveFactory.homeRelative()) {
			if case .absolutePath(let path) = $0 { return path.hasPrefix("~") }
			return false
		}
	}

	func testValidatorRejectsNULByteNames() throws {
		// Either an explicit traversal rejection or an unreadable archive is a
		// safe outcome; the entry must never be accepted.
		let url = try track(UnsafeArchiveFactory.write(UnsafeArchiveFactory.nulByteName(), ext: "zip"))
		XCTAssertThrowsError(try ArchiveSafetyValidator.validate(url)) { error in
			guard let validationError = error as? ArchiveSafetyValidator.ValidationError else {
				return XCTFail("Expected a ValidationError, got \(error)")
			}
			switch validationError {
			case .traversalPath, .unreadable:
				break
			default:
				XCTFail("Unexpected error for a NUL-byte name: \(validationError)")
			}
		}
	}

	func testValidatorRejectsSymlinkEntries() throws {
		try assertRejected(UnsafeArchiveFactory.symlinkEscape()) {
			if case .symbolicLink(let path) = $0 { return path == "evil-link" }
			return false
		}
	}

	func testValidatorRejectsExcessiveEntryCount() throws {
		// 50 001 entries > the 50 000 cap. Built at runtime (~4 MB, < 1 s).
		try assertRejected(UnsafeArchiveFactory.excessiveEntryCount()) {
			if case .tooManyEntries = $0 { return true }
			return false
		}
	}

	func testValidatorRejectsExcessiveDeclaredSize() throws {
		try assertRejected(UnsafeArchiveFactory.excessiveDeclaredSize()) {
			if case .tooLarge = $0 { return true }
			return false
		}
	}

	func testValidatorFailsSafelyOnGarbage() throws {
		try assertRejected(UnsafeArchiveFactory.notAnArchive()) {
			if case .unreadable = $0 { return true }
			return false
		}
	}

	func testValidatorAllowsDuplicateEntriesPerExistingPolicy() throws {
		// Duplicate names are not rejected by policy: extraction overwrites in
		// order (last wins). Characterized here so a future policy change is a
		// conscious decision.
		let url = try track(UnsafeArchiveFactory.write(UnsafeArchiveFactory.duplicateEntries(), ext: "zip"))
		try ArchiveSafetyValidator.validate(url)
	}

	func testValidatorAcceptsCommittedFixtureIPAs() throws {
		// Every committed fixture must pass the validator — they are the safe
		// baseline the signing/import characterization tests build on.
		let ipas = try FileManager.default.contentsOfDirectory(
			at: TestFixtures.url("IPAs"),
			includingPropertiesForKeys: nil
		).filter { $0.pathExtension == "ipa" }
		XCTAssertFalse(ipas.isEmpty, "fixture corpus missing")
		for ipa in ipas {
			try ArchiveSafetyValidator.validate(ipa)
		}
	}

	// MARK: - Validation happens BEFORE extraction

	func testImportPipelineRejectsTraversalArchiveBeforeExtraction() async throws {
		let evil = try track(UnsafeArchiveFactory.write(UnsafeArchiveFactory.parentEscape(), ext: "ipa"))
		let error = try await FixturePipeline.importIPAFailingDirectFile(evil)

		// The failure must be the validator's, raised from the extract step —
		// the archive never got unpacked.
		guard let importError = error as? ImportError else {
			return XCTFail("Expected an ImportError, got \(error)")
		}
		XCTAssertEqual(importError.step, .extract)
		XCTAssertNotNil(importError.underlying, "The underlying ValidationError must be preserved")

		// No file escaped into the parent of the staging location.
		let escaped = evil.deletingLastPathComponent().appendingPathComponent("escape.txt")
		XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
	}

	func testWorkspaceOpenRejectsTraversalArchiveAndCleansUp() async throws {
		let evil = try track(UnsafeArchiveFactory.write(UnsafeArchiveFactory.parentEscape(), ext: "ipa"))
		let recentsBefore = await IPAWorkspace.recents().count

		await XCTAssertThrowsErrorAsync({
			try await IPAWorkspace.open(ipa: evil)
		}, "A traversal archive must never open as a workspace") { error in
			XCTAssertTrue(
				error is ArchiveSafetyValidator.ValidationError || error is IPAWorkspaceError,
				"Unexpected error type: \(error)"
			)
		}

		let recentsAfter = await IPAWorkspace.recents().count
		XCTAssertEqual(recentsBefore, recentsAfter, "A failed open must not leave a workspace behind")

		let escaped = evil.deletingLastPathComponent().appendingPathComponent("escape.txt")
		XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
	}

	// MARK: - tar extraction (Decompression.swift)

	/// Builds a tar with the given entry names using SWCompression-compatible
	/// POSIX headers, via the system `tar`-format rules implemented manually.
	private func makeTar(_ entries: [(name: String, content: Data, type: UInt8, linkTarget: String?)]) -> Data {
		var tar = Data()
		for entry in entries {
			var header = Data(count: 512)

			func put(_ string: String, at offset: Int) {
				let bytes = Array(string.utf8.prefix(100))
				for (index, byte) in bytes.enumerated() { header[offset + index] = byte }
			}
			func putOctal(_ value: Int, width: Int, at offset: Int) {
				let octal = String(value, radix: 8)
				let padded = String(repeating: "0", count: max(0, width - 1 - octal.count)) + octal
				put(padded, at: offset)
			}

			put(entry.name, at: 0)                                  // name
			putOctal(0o644, width: 8, at: 100)                      // mode
			putOctal(0, width: 8, at: 108)                          // uid
			putOctal(0, width: 8, at: 116)                          // gid
			putOctal(entry.type == 0x35 ? 0 : entry.content.count, width: 12, at: 124) // size
			putOctal(0, width: 12, at: 136)                         // mtime
			for index in 148..<156 { header[index] = 0x20 }         // checksum placeholder
			header[156] = entry.type                                 // type flag
			if let linkTarget = entry.linkTarget {
				let bytes = Array(linkTarget.utf8.prefix(100))
				for (index, byte) in bytes.enumerated() { header[157 + index] = byte }
			}

			var sum: UInt32 = 0
			for byte in header { sum += UInt32(byte) }
			let checksum = String(sum, radix: 8)
			let paddedChecksum = String(repeating: "0", count: max(0, 6 - checksum.count)) + checksum
			for (index, byte) in Array(paddedChecksum.utf8).enumerated() { header[148 + index] = byte }
			header[154] = 0
			header[155] = 0x20

			tar.append(header)
			if entry.type != 0x35, !entry.content.isEmpty {
				tar.append(entry.content)
				let padding = (512 - entry.content.count % 512) % 512
				tar.append(Data(count: padding))
			}
		}
		tar.append(Data(count: 1024)) // end-of-archive blocks
		return tar
	}

	func testTarExtractionSkipsTraversalAbsoluteAndLinkEntries() throws {
		let safeContent = Data("safe-content".utf8)
		let tar = makeTar([
			(name: "safe/file.txt", content: safeContent, type: 0x30, linkTarget: nil),
			(name: "../escape.txt", content: Data("evil".utf8), type: 0x30, linkTarget: nil),
			(name: "/absolute/escape.txt", content: Data("evil".utf8), type: 0x30, linkTarget: nil),
			(name: "~/home-escape.txt", content: Data("evil".utf8), type: 0x30, linkTarget: nil),
			(name: "link-out", content: Data(), type: 0x32, linkTarget: "/etc/passwd"),
			(name: "back\\slash.txt", content: Data("evil".utf8), type: 0x30, linkTarget: nil),
		])
		var tarURL = try track(UnsafeArchiveFactory.write(tar, ext: "tar"))

		try extractFile(at: &tarURL)
		tempFiles.append(tarURL) // the extraction directory

		// The result is a directory containing exactly the safe entry.
		var isDirectory: ObjCBool = false
		XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path, isDirectory: &isDirectory))
		XCTAssertTrue(isDirectory.boolValue)

		let extracted = tarURL.appendingPathComponent("safe/file.txt")
		XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))
		XCTAssertEqual(try Data(contentsOf: extracted), safeContent)

		// Nothing escaped next to the extraction directory.
		let parent = tarURL.deletingLastPathComponent()
		for escaped in ["escape.txt", "home-escape.txt"] {
			XCTAssertFalse(
				FileManager.default.fileExists(atPath: parent.appendingPathComponent(escaped).path),
				"\(escaped) must not be written outside the extraction directory"
			)
		}
		// No symlink materialized anywhere in the extraction tree.
		XCTAssertFalse(FileManager.default.fileExists(atPath: tarURL.appendingPathComponent("link-out").path))
	}

	func testTarExtractionOfPlainArchiveMaterializesAllEntries() throws {
		let tar = makeTar([
			(name: "a.txt", content: Data("A".utf8), type: 0x30, linkTarget: nil),
			(name: "dir/b.txt", content: Data("B".utf8), type: 0x30, linkTarget: nil),
		])
		var tarURL = try track(UnsafeArchiveFactory.write(tar, ext: "tar"))
		try extractFile(at: &tarURL)
		tempFiles.append(tarURL)

		XCTAssertEqual(try String(contentsOf: tarURL.appendingPathComponent("a.txt"), encoding: .utf8), "A")
		XCTAssertEqual(try String(contentsOf: tarURL.appendingPathComponent("dir/b.txt"), encoding: .utf8), "B")
	}

	// MARK: - AR archives (AR.swift)

	func testARRejectsBadMagicAndTruncatedArchives() async throws {
		for garbage in [Data(), Data("!<arch>".utf8), Data(repeating: 0x41, count: 64)] {
			let url = try UnsafeArchiveFactory.write(garbage, ext: "deb")
			tempFiles.append(url)
			do {
				_ = try await AR(with: url).extract()
				XCTFail("AR accepted a malformed archive (\(garbage.count) bytes)")
			} catch let error as ARError {
				if case .badArchive = error { /* expected */ } else {
					XCTFail("Unexpected ARError: \(error)")
				}
			} catch {
				XCTFail("Unexpected error type: \(error)")
			}
		}
	}

	func testARReadsMembersOfCommittedDebs() async throws {
		// The committed deb fixtures were written by the generator's ar writer;
		// AR.swift must list their members (this is the same path TweakAnalyzer
		// uses to reach control.tar.gz / data.tar.gz).
		let debURL = TestFixtures.url("Tweaks/substrate-tweak.deb")
		let members = try await AR(with: debURL).extract()
		XCTAssertEqual(members.map { $0.name }, ["debian-binary", "control.tar.gz", "data.tar.gz"])
		XCTAssertEqual(members[0].content, Data("2.0\n".utf8))
	}
}

// MARK: - Pipeline helper for direct-file import failures

extension FixturePipeline {
	/// Runs the production import pipeline on an arbitrary file (not a
	/// fixture copy) and expects it to fail; returns the error.
	static func importIPAFailingDirectFile(_ file: URL) async throws -> Error {
		let result: Result<AppInfoPresentable, Error> = await withCheckedContinuation { continuation in
			FR.handlePackageFile(file) { outcome in
				continuation.resume(returning: outcome)
			}
		}
		switch result {
		case .success:
			throw ImportError(.database, fileName: file.lastPathComponent, id: "test", reason: "import unexpectedly succeeded")
		case .failure(let error):
			return error
		}
	}
}
