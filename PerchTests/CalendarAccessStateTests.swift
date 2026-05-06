import XCTest
@testable import Perch

final class CalendarAccessStateTests: XCTestCase {
    func testFullAccessCanReadEventsAndHasNoSettingsAction() {
        XCTAssertEqual(CalendarAccessState.fullAccess.statusTitle, "Calendar access enabled")
        XCTAssertTrue(CalendarAccessState.fullAccess.isSufficientForReadingEvents)
        XCTAssertNil(CalendarAccessState.fullAccess.settingsAction)
    }

    func testNotDeterminedRequestsAccessFromSettings() {
        XCTAssertEqual(CalendarAccessState.notDetermined.statusTitle, "Calendar access not set")
        XCTAssertFalse(CalendarAccessState.notDetermined.isSufficientForReadingEvents)
        XCTAssertEqual(CalendarAccessState.notDetermined.settingsAction, .requestAccess)
    }

    func testWriteOnlyRequiresPrivacySettings() {
        XCTAssertEqual(CalendarAccessState.writeOnly.statusTitle, "Full calendar access required")
        XCTAssertFalse(CalendarAccessState.writeOnly.isSufficientForReadingEvents)
        XCTAssertEqual(CalendarAccessState.writeOnly.settingsAction, .openPrivacySettings)
        XCTAssertTrue(CalendarAccessState.writeOnly.statusDetail.contains("only write calendar events"))
    }

    func testDeniedRestrictedAndUnknownOpenPrivacySettings() {
        for accessState in [CalendarAccessState.denied, .restricted, .unknown] {
            XCTAssertFalse(accessState.isSufficientForReadingEvents)
            XCTAssertEqual(accessState.settingsAction, .openPrivacySettings)
            XCTAssertFalse(accessState.statusTitle.isEmpty)
            XCTAssertFalse(accessState.statusDetail.isEmpty)
        }
    }
}
