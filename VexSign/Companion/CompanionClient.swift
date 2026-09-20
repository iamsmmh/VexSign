//
//  CompanionClient.swift
//  VexSign
//
//  Reads a companion snapshot from the iPhone's Web Manager. The three endpoints
//  already exist (`/api/status`, `/api/library`, `/api/updates`), so a companion
//  device needs nothing but the address — and the token, when the server requires
//  one. Foundation only, shared by the tvOS and visionOS apps.
//

import Foundation

enum CompanionClientError: LocalizedError, Equatable {
	case missingAddress
	case invalidAddress
	case unreachable(String)
	case unauthorized
	case decoding(String)

	var errorDescription: String? {
		switch self {
		case .missingAddress:
			return "No iPhone address is set. Enter the Web Manager URL shown in VexSign → Settings → Web Manager."
		case .invalidAddress:
			return "That address is not a valid http(s) URL."
		case .unreachable(let detail):
			return "Could not reach the iPhone: \(detail)"
		case .unauthorized:
			return "The iPhone refused the connection. Check the Web Manager username, password and API token."
		case .decoding(let detail):
			return "The iPhone replied with something unexpected: \(detail)"
		}
	}
}

/// One-shot reader for the Web Manager API. No caching, no retries: companions
/// refresh on demand and on a timer, and show the last good snapshot meanwhile.
struct CompanionClient {
	var address: String
	var username: String?
	var password: String?
	var apiToken: String?

	private static let _timeout: TimeInterval = 12

	func snapshot() async throws -> CompanionSnapshot {
		let status: CompanionStatus = try await _get("api/status")
		let library: [CompanionLibraryEntry] = (try? await _get("api/library")) ?? []
		let updates: [CompanionUpdateEntry] = (try? await _get("api/updates")) ?? []

		return CompanionSnapshot(
			status: status,
			library: library,
			updates: updates,
			generatedAt: Date()
		)
	}

	// MARK: - Request

	private var _baseURL: URL? {
		let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		// The Web Manager prints its address without a scheme in some places.
		let normalized = trimmed.contains("://") ? trimmed : "http://" + trimmed
		return URL(string: normalized)
	}

	private func _get<T: Decodable>(_ path: String) async throws -> T {
		guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
			throw CompanionClientError.missingAddress
		}
		guard let base = _baseURL, let scheme = base.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			throw CompanionClientError.invalidAddress
		}

		let url = base.appendingPathComponent(path)
		var request = URLRequest(url: url)
		request.timeoutInterval = Self._timeout
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		if let token = apiToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty {
			request.setValue(token, forHTTPHeaderField: "X-VexSign-Token")
		}
		if let username, let password, !username.isEmpty {
			let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
			request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
		}

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw CompanionClientError.unreachable(error.localizedDescription)
		}

		guard let http = response as? HTTPURLResponse else {
			throw CompanionClientError.unreachable("no HTTP response")
		}
		if http.statusCode == 401 || http.statusCode == 403 {
			throw CompanionClientError.unauthorized
		}
		guard (200..<300).contains(http.statusCode) else {
			throw CompanionClientError.unreachable("HTTP \(http.statusCode)")
		}

		do {
			return try JSONDecoder().decode(T.self, from: data)
		} catch {
			throw CompanionClientError.decoding(error.localizedDescription)
		}
	}
}
