import XCTest
@testable import Perch

final class MeetingLinkTests: XCTestCase {
    private let extractor = MeetingLinkExtractor()
    private let launchURLBuilder = ZoomMeetingLaunchURLBuilder()

    func testExtractsZoomMeetingFromLocation() {
        let link = extractor.meetingLink(from: [
            nil,
            "Join at https://school.zoom.us/j/1234567890?pwd=abc",
            nil
        ])

        XCTAssertEqual(link?.provider, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://school.zoom.us/j/1234567890?pwd=abc")
    }

    func testExtractsZoomMeetingFromNotesWhenURLFieldIsNotZoom() {
        let link = extractor.meetingLink(from: [
            "https://example.com/event",
            nil,
            "Zoom: https://us02web.zoom.us/my/professor"
        ])

        XCTAssertEqual(link?.provider, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://us02web.zoom.us/my/professor")
    }

    func testRejectsNonZoomAndLookalikeHosts() {
        let link = extractor.meetingLink(from: [
            "https://zoom.us.evil.example/j/1234567890",
            "https://example.com/zoom.us/j/1234567890"
        ])

        XCTAssertNil(link)
    }

    func testBuildsNativeLaunchURLForHTTPSMeetingLink() {
        let launchURL = launchURLBuilder.launchURL(
            for: URL(string: "https://school.zoom.us/j/1234567890?pwd=abc")!
        )

        XCTAssertEqual(launchURL.absoluteString, "zoommtg://school.zoom.us/join?action=join&confno=1234567890&pwd=abc")
    }

    func testFallsBackToWebURLForPersonalMeetingVanityLink() {
        let url = URL(string: "https://us02web.zoom.us/my/professor?pwd=abc")!

        XCTAssertEqual(launchURLBuilder.launchURL(for: url), url)
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

    func testExtractsGoogleMeetLink() {
        let link = extractor.meetingLink(from: [
            "Agenda: https://example.com/doc",
            "Join https://meet.google.com/abc-defg-hij"
        ])

        XCTAssertEqual(link?.provider, .googleMeet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testExtractsMicrosoftTeamsAndWebexLinks() {
        let teams = extractor.meetingLink(from: [
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc"
        ])
        let webex = extractor.meetingLink(from: [
            "https://company.webex.com/meet/alex"
        ])

        XCTAssertEqual(teams?.provider, .microsoftTeams)
        XCTAssertEqual(webex?.provider, .webex)
    }

    func testUsesContextForCustomMeetingLinks() {
        let link = extractor.meetingLink(from: [
            "Video call: https://calls.example.com/room/weekly"
        ])

        XCTAssertEqual(link?.provider, .other)
        XCTAssertEqual(link?.url.absoluteString, "https://calls.example.com/room/weekly")
    }

    func testAssociatesMeetingContextWithNearbyGenericLink() {
        let link = extractor.meetingLink(from: [
            "Meeting agenda: https://docs.example.com — join: https://calls.example.com/room"
        ])

        XCTAssertEqual(link?.provider, .other)
        XCTAssertEqual(link?.url.absoluteString, "https://calls.example.com/room")
    }

    func testDoesNotTreatAnOrdinaryEventURLAsAMeeting() {
        let link = extractor.meetingLink(from: [
            "Read https://example.com/agenda before Tuesday"
        ])

        XCTAssertNil(link)
    }
}
