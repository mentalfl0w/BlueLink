import XCTest
@testable import BlueLink

final class SparkleConfigurationTests: XCTestCase {
    func testBundleCarriesTheStableSparkleFeedAndKey() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertTrue(MacSparkleConfiguration.isConfigured(infoDictionary: info))
        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://github.com/mentalfl0w/BlueLink/releases/latest/download/appcast.xml"
        )
    }

    func testInvalidPublicKeyDisablesSparkle() {
        let info: [String: Any] = [
            "SUFeedURL": MacSparkleConfiguration.stableFeedURL,
            "SUPublicEDKey": "not-a-32-byte-eddsa-key",
        ]
        XCTAssertFalse(MacSparkleConfiguration.isConfigured(infoDictionary: info))
    }
}
