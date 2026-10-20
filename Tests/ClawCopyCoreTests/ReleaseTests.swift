import XCTest
@testable import ClawCopyCore

final class ReleaseVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(ReleaseVersion("0.1.42")?.components, [0, 1, 42])
        XCTAssertEqual(ReleaseVersion("v0.1.42")?.components, [0, 1, 42])
        XCTAssertNil(ReleaseVersion(""))
        XCTAssertNil(ReleaseVersion("v"))
        XCTAssertNil(ReleaseVersion("1..2"))
        XCTAssertNil(ReleaseVersion("1.2-beta"))
        XCTAssertNil(ReleaseVersion("1.2.3.4.5"))
        XCTAssertNil(ReleaseVersion("１.２")) // non-ASCII digits
    }

    func testOrdering() {
        XCTAssertLessThan(ReleaseVersion("0.1.9")!, ReleaseVersion("0.1.10")!)
        XCTAssertLessThan(ReleaseVersion("0.1.42")!, ReleaseVersion("0.2")!)
        XCTAssertEqual(ReleaseVersion("1.2")!, ReleaseVersion("1.2.0")!)
        XCTAssertFalse(ReleaseVersion("0.1.42")! < ReleaseVersion("0.1.42")!)
    }
}

final class ReleaseInfoTests: XCTestCase {
    private let prefix = "https://github.com/owner/repo/releases/"

    private func json(tag: String = "v0.1.42", url: String = "https://github.com/owner/repo/releases/tag/v0.1.42",
                      extra: String = "") -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)","name":"x","body":"notes"\#(extra)}"#.utf8)
    }

    func testParsesALatestReleaseResponse() {
        let release = ReleaseInfo.parse(json(), releasesPagePrefix: prefix)
        XCTAssertEqual(release?.version, ReleaseVersion("0.1.42"))
        XCTAssertEqual(release?.pageURL.absoluteString, "https://github.com/owner/repo/releases/tag/v0.1.42")
    }

    func testRejectsPagesOutsideThisRepositorysReleases() {
        for url in [
            "https://evil.example/owner/repo/releases/tag/v1",
            "https://github.com/other/repo/releases/tag/v1",
            "http://github.com/owner/repo/releases/tag/v1",
            "https://github.com/owner/repo/releases/../../../evil",
            "https://github.com/owner/repo/releases/tag/v1 javascript:alert(1)",
            "https://github.com.evil.example/owner/repo/releases/tag/v1",
        ] {
            XCTAssertNil(ReleaseInfo.parse(json(url: url), releasesPagePrefix: prefix), url)
        }
    }

    func testRejectsDraftsPrereleasesBadTagsAndJunk() {
        XCTAssertNil(ReleaseInfo.parse(json(extra: #","draft":true"#), releasesPagePrefix: prefix))
        XCTAssertNil(ReleaseInfo.parse(json(extra: #","prerelease":true"#), releasesPagePrefix: prefix))
        XCTAssertNil(ReleaseInfo.parse(json(tag: "latest"), releasesPagePrefix: prefix))
        XCTAssertNil(ReleaseInfo.parse(Data("not json".utf8), releasesPagePrefix: prefix))
        XCTAssertNil(ReleaseInfo.parse(Data(count: ReleaseInfo.maxResponseBytes + 1), releasesPagePrefix: prefix))
    }
}
