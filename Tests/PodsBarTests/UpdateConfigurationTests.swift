import Foundation
import XCTest
@testable import PodsBar

final class UpdateConfigurationTests: XCTestCase {
    private var valid: [String: Any] {
        ["SUFeedURL": "https://github.com/musaAmir/podsbar/releases/latest/download/appcast.xml",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()]
    }

    func testValidConfiguration() throws { try UpdateConfiguration.validate(valid) }

    func testRejectsUnsafeOrMissingFeed() {
        for feed in ["", "http://example.com/feed.xml", "file:///tmp/feed.xml", "https:///",
                     "https://user:password@example.com/feed.xml", "https://example.com/feed.xml#fragment"] {
            var info = valid
            info["SUFeedURL"] = feed
            XCTAssertThrowsError(try UpdateConfiguration.validate(info), "Accepted \(feed)")
        }
        var info = valid
        info.removeValue(forKey: "SUFeedURL")
        XCTAssertThrowsError(try UpdateConfiguration.validate(info))
    }

    func testRejectsMissingOrMalformedSigningKey() {
        for key in ["", "not a public key", Data(repeating: 1, count: 31).base64EncodedString(),
                    Data(repeating: 1, count: 33).base64EncodedString()] {
            var info = valid
            info["SUPublicEDKey"] = key
            XCTAssertThrowsError(try UpdateConfiguration.validate(info))
        }
        var info = valid
        info.removeValue(forKey: "SUPublicEDKey")
        XCTAssertThrowsError(try UpdateConfiguration.validate(info))
    }
}
