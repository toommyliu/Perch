import XCTest
@testable import Perch

final class ZoomMeetingLinkExtractorTests: XCTestCase {
    private let extractor = ZoomMeetingLinkExtractor()
    private let launchURLBuilder = ZoomMeetingLaunchURLBuilder()

    func testExtractsZoomMeetingFromLocation() {
        let url = extractor.meetingURL(from: [
            nil,
            "Join at https://school.zoom.us/j/1234567890?pwd=abc",
            nil
        ])

        XCTAssertEqual(url?.absoluteString, "https://school.zoom.us/j/1234567890?pwd=abc")
    }

    func testExtractsZoomMeetingFromNotesWhenURLFieldIsNotZoom() {
        let url = extractor.meetingURL(from: [
            "https://example.com/event",
            nil,
            "Zoom: https://us02web.zoom.us/my/professor"
        ])

        XCTAssertEqual(url?.absoluteString, "https://us02web.zoom.us/my/professor")
    }

    func testRejectsNonZoomAndLookalikeHosts() {
        let url = extractor.meetingURL(from: [
            "https://zoom.us.evil.example/j/1234567890",
            "https://example.com/zoom.us/j/1234567890"
        ])

        XCTAssertNil(url)
    }

    func testBuildsNativeLaunchURLForHTTPSMeetingLink() {
        let launchURL = launchURLBuilder.launchURL(
            for: URL(string: "https://school.zoom.us/j/1234567890?pwd=abc")!
        )

        XCTAssertEqual(launchURL.absoluteString, "zoommtg://school.zoom.us/join?action=join&confno=1234567890&pwd=abc")
    }

    func testBuildsNativeLaunchURLForPersonalMeetingLink() {
        let launchURL = launchURLBuilder.launchURL(
            for: URL(string: "https://us02web.zoom.us/my/professor?pwd=abc")!
        )

        XCTAssertEqual(launchURL.absoluteString, "zoommtg://us02web.zoom.us/join?action=join&confno=professor&pwd=abc")
    }

    func testKeepsLookingForMeetingIdentifierAfterEmptySegment() {
        let launchURL = launchURLBuilder.launchURL(
            for: URL(string: "https://school.zoom.us/other/j//w/1234?pwd=abc")!
        )

        XCTAssertEqual(launchURL.absoluteString, "zoommtg://school.zoom.us/join?action=join&confno=1234&pwd=abc")
    }

    func testKeepsNativeZoomLaunchURLUnchanged() {
        let url = URL(string: "zoommtg://zoom.us/join?action=join&confno=1234567890&pwd=abc")!

        XCTAssertEqual(launchURLBuilder.launchURL(for: url), url)
    }
}
