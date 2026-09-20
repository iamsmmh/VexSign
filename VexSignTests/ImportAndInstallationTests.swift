import XCTest
@testable import VexSign

final class ImportAndInstallationTests: XCTestCase {
    private func profileData() throws -> Data {
        // Older valid profiles do not have DER-Encoded-Profile.
        let profile: [String: Any] = [
            "AppIDName": "Test App", "CreationDate": Date(timeIntervalSince1970: 0),
            "Platform": ["iOS"], "ExpirationDate": Date(timeIntervalSince1970: 2_000_000_000),
            "Name": "Test Profile", "TeamIdentifier": ["TESTTEAM"], "TeamName": "Test Team",
            "TimeToLive": 365, "UUID": "test-profile", "Version": 1
        ]
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testProfileReaderIgnoresBinaryCMSTrailer() throws {
        var envelope = Data([0x30, 0x82, 0xff, 0x00])
        envelope.append(try profileData())
        envelope.append(Data([0xff, 0xfe, 0x00, 0x30]))
        let certificate = CertificateReader(try temporaryFile(envelope)).decoded
        XCTAssertEqual(certificate?.Name, "Test Profile")
        XCTAssertNil(certificate?.derEncodedProfile)
    }

    func testProfileReaderRejectsTruncatedAndEmptyFiles() throws {
        for data in [Data(), Data("<?xml version=\"1.0\"?><plist><dict>".utf8)] {
            XCTAssertNil(CertificateReader(try temporaryFile(data)).decoded)
        }
        XCTAssertNil(CertificateReader(URL(fileURLWithPath: "/missing.mobileprovision")).decoded)
    }

    func testMalformedP12DoesNotCrashPasswordValidation() throws {
        let profile = try temporaryFile(profileData())
        for data in [Data(), Data("not a PKCS12 identity".utf8)] {
            let key = try temporaryFile(data)
            XCTAssertFalse(FR.checkPasswordForCertificate(for: key, with: "wrong", using: profile))
        }
    }

    func testFailedImportReportsErrorOnMainThread() throws {
        let completion = expectation(description: "Import reports failure")
        let key = try temporaryFile(Data("bad P12".utf8))
        let profile = try temporaryFile(profileData())
        FR.handleCertificateFiles(p12URL: key, provisionURL: profile, p12Password: "") { error in
            XCTAssertNotNil(error)
            XCTAssertTrue(Thread.isMainThread)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 5)
    }

    func testInstallLinkPreservesNestedManifestQuery() throws {
        let manifest = "https://example.com/genPlist?name=Test%20App&fetchurl=http%3A%2F%2F127.0.0.1%3A5000%2Fapp.ipa"
        let link = ServerInstaller.installLink(manifest: manifest)
        let components = try XCTUnwrap(URLComponents(string: link))
        XCTAssertEqual(components.scheme, "itms-services")
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, manifest)
    }

    func testSSLHostnameValidation() {
        XCTAssertEqual(ServerInstaller.normalizedHostname("*.example.com\n"), "local.example.com")
        XCTAssertEqual(ServerInstaller.normalizedHostname("localhost.example.com"), "localhost.example.com")
        for invalid in ["", "null", "https://example.com", "example.com/path", "bad host", "example.com:443", "example.com?query", "user@example.com"] {
            XCTAssertNil(ServerInstaller.normalizedHostname(invalid), invalid)
        }
    }

    func testOpenIsOnlyAvailableForSuccessfulInstalls() {
        let success = InstallQueue.InstallOutcome.succeeded
        XCTAssertTrue(success.canOpenApp(isExport: false, identifier: "com.example.app"))
        XCTAssertFalse(success.canOpenApp(isExport: true, identifier: "com.example.app"))
        XCTAssertFalse(success.canOpenApp(isExport: false, identifier: nil))
        XCTAssertFalse(success.canOpenApp(isExport: false, identifier: ""))
        for outcome in [InstallQueue.InstallOutcome.pending, .skipped, .failed("Install failed")] {
            XCTAssertFalse(outcome.canOpenApp(isExport: false, identifier: "com.example.app"))
        }
    }

    func testPrimaryNavigationUsesTheRequiredOrder() {
        XCTAssertEqual(TabEnum.defaultTabs, [.files, .library, .home, .appStore, .downloads, .settings])
        XCTAssertFalse(TabBarPreferences.hideableTabs.contains(.home))
        XCTAssertFalse(TabBarPreferences.hideableTabs.contains(.settings))
    }
}
