import Foundation
import OSLog

extension CertificatePair {
    /// Read-through migration leaves legacy storage untouched if Keychain is locked.
    /// Signing fails closed instead of interpreting a locked Keychain as a saved password.
    var signingPassword: String? {
        do { return try requireSigningPassword() }
        catch {
            Logger.misc.error("Certificate password requires an accessible Keychain: \(error.localizedDescription)")
            return nil
        }
    }

    func requireSigningPassword() throws -> String {
        guard let uuid else { throw RepositoryError.invalid("Certificate has no identifier.") }
        let account = "certificate.password.\(uuid)"
        if let stored = try SecureSecretStore.read(account) {
            if password != nil {
                password = nil
                try managedObjectContext?.save()
            }
            return String(decoding: stored, as: UTF8.self)
        }
        // A legacy nil password represented the empty password, not an error.
        // Keychain unavailability is thrown by read() and never follows this path.
        let legacy = password ?? ""
        try SecureSecretStore.write(Data(legacy.utf8), account: account)
        password = nil
        try managedObjectContext?.save()
        return legacy
    }

    func setSigningPassword(_ value: String) throws {
        guard let uuid else { throw RepositoryError.invalid("Certificate has no identifier.") }
        try SecureSecretStore.write(Data(value.utf8), account: "certificate.password.\(uuid)")
        password = nil
    }
}
