//
//  FileIntegrity.swift
//  VexSign
//
//  SHA-256 helpers for IPA/archive integrity. Downloaded packages are hashed and
//  logged automatically; File Manager adds "Copy SHA-256" and "Verify Hash…" so a
//  file can be checked against a hash the source published.
//

import Foundation
import CryptoKit

enum FileIntegrity {
	/// Streaming SHA-256 — chunks the file so multi-GB IPAs never load into memory.
	static func sha256(of url: URL) -> String? {
		let handle: FileHandle
		do {
			handle = try FileHandle(forReadingFrom: url)
		} catch {
			return nil
		}
		defer { try? handle.close() }

		var hasher = SHA256()
		let chunkSize = 1 << 20 // 1 MiB

		while true {
			let chunk = handle.readData(ofLength: chunkSize)
			if chunk.isEmpty { break }
			chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
		}

		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	/// True when the file's SHA-256 equals `expected` (case- and prefix-tolerant).
	static func matches(_ url: URL, expected: String) -> Bool {
		guard let actual = sha256(of: url) else { return false }
		return actual == normalize(expected)
	}

	/// Trims, lowercases and strips an optional "sha256:" prefix from a pasted hash.
	static func normalize(_ hash: String) -> String {
		var hash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if hash.hasPrefix("sha256:") { hash.removeFirst("sha256:".count) }
		return hash
	}
}
