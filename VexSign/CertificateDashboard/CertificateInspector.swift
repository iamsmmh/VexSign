import Foundation
import Security

struct CertificateHealth: Identifiable, Sendable {
    enum Revocation: String, Sendable { case good, revoked, unknown }
    let id: String
    let name: String
    let teamID: String
    let teamName: String
	let expires: Date
	/// The leaf certificate can expire before the provisioning profile and is the
	/// date that most directly explains a signing failure.
	let certificateExpires: Date?
	let deviceCount: Int
    let allDevices: Bool
    let applicationIdentifier: String
    let push: Bool
    let debugEntitlement: Bool
    let entitlements: String
    let provision: String
    let revocation: Revocation
    let checkedAt: Date
	let detail: String
    var effectiveExpiry: Date { min(expires, certificateExpires ?? expires) }
    var daysRemaining: Int { Int(floor(effectiveExpiry.timeIntervalSinceNow / 86_400)) }
    var score: Int {
        guard effectiveExpiry > Date(), revocation != .revoked else { return 0 }
        let base = revocation == .good ? 100 : 60
        return max(0, base - (daysRemaining < 7 ? 40 : daysRemaining < 30 ? 20 : 0))
    }
}

enum CertificateInspector {
    /// Reads a profile's descriptive payload, NOT proof of its CMS signature.
    /// Signing eligibility still belongs to the existing signing preflight.
    static func inspect(id: String, name: String, p12: URL, password: String, profile: URL, online: Bool) async throws -> CertificateHealth {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: profile, options: .mappedIfSafe)
            guard data.count <= 10 * 1_024 * 1_024,
                  let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
                throw RepositoryError.invalid("Invalid provisioning profile.")
            }
            let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
            guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let expiry = plist["ExpirationDate"] as? Date else { throw RepositoryError.invalid("Profile has no expiration date.") }
			let entitlements = (plist["Entitlements"] as? [String: Any]) ?? [:]
			let entitlementData = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)

			// Import the P12 even for an offline inspection. This validates the saved
			// password and lets the UI distinguish certificate expiry from profile expiry.
			let keyData = try Data(contentsOf: p12)
			var imported: CFArray?
			let importResult = SecPKCS12Import(keyData as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &imported)
			guard importResult == errSecSuccess,
				  let items = imported as? [[String: Any]],
				  let item = items.first,
				  let chain = item[kSecImportItemCertChain as String] as? [SecCertificate],
				  !chain.isEmpty else {
				throw SecureSecretStore.Failure(status: importResult == errSecSuccess ? errSecDecode : importResult)
			}
			let certificateExpires = Self.notAfter(chain[0])

			var status: CertificateHealth.Revocation = .unknown
			var detail = "OCSP has not been checked. Profile metadata is not signature verification."
			if online {
				let requestedPolicy: SecPolicy? = SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationOCSPMethod | kSecRevocationRequirePositiveResponse))
                guard let revocationPolicy = requestedPolicy else {
                    throw RepositoryError.invalid("Unable to create OCSP policy.")
                }
                let policies = [SecPolicyCreateBasicX509(), revocationPolicy]
                var trust: SecTrust?
                guard SecTrustCreateWithCertificates(chain as CFArray, policies as CFArray, &trust) == errSecSuccess, let trust else {
                    throw RepositoryError.invalid("Could not create certificate trust evaluation.")
                }
                SecTrustSetNetworkFetchAllowed(trust, true)
                var error: CFError?
                if SecTrustEvaluateWithError(trust, &error) {
                    status = .good; detail = "System trust evaluation passed with positive OCSP evidence. This is not a guarantee of installation eligibility."
                } else if let error {
                    if CFErrorGetCode(error) == errSecCertificateRevoked { status = .revoked }
                    detail = CFErrorCopyDescription(error) as String
                }
            }
			return CertificateHealth(id: id, name: name,
									 certificateExpires: certificateExpires,
									 teamID: (plist["TeamIdentifier"] as? [String])?.joined(separator: ", ") ?? "Unknown",
                                     teamName: plist["TeamName"] as? String ?? "Unknown", expires: expiry,
                                     deviceCount: (plist["ProvisionedDevices"] as? [String])?.count ?? 0,
                                     allDevices: (plist["ProvisionsAllDevices"] as? Bool) ?? false,
                                     applicationIdentifier: entitlements["application-identifier"] as? String ?? "Unknown",
                                     push: entitlements["aps-environment"] != nil,
                                     debugEntitlement: (entitlements["get-task-allow"] as? Bool) ?? false,
                                     entitlements: String(decoding: entitlementData, as: UTF8.self),
                                     provision: String(decoding: plistData, as: UTF8.self), revocation: status, checkedAt: Date(), detail: detail)
        }.value
    }

	private static func notAfter(_ certificate: SecCertificate) -> Date? {
		let key = kSecOIDX509V1ValidityNotAfter as String
		guard let values = SecCertificateCopyValues(certificate, [key] as CFArray, nil) as? [String: Any],
			  let validity = values[key] as? [String: Any],
			  let value = validity[kSecPropertyKeyValue as String] as? Date else {
			return nil
		}
		return value
	}
}
