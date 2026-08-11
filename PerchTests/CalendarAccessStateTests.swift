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

    func testReminderAccessStatesExposeIndependentSettingsActions() {
        XCTAssertEqual(ReminderAccessState.notDetermined.settingsAction, .requestAccess)
        XCTAssertFalse(ReminderAccessState.notDetermined.isSufficientForReadingReminders)
        XCTAssertNil(ReminderAccessState.fullAccess.settingsAction)
        XCTAssertTrue(ReminderAccessState.fullAccess.isSufficientForReadingReminders)

        for accessState in [ReminderAccessState.denied, .restricted, .unknown] {
            XCTAssertEqual(accessState.settingsAction, .openPrivacySettings)
            XCTAssertFalse(accessState.isSufficientForReadingReminders)
        }
    }

    func testPermissionDisplayStatusesDescribeCalendarAccess() {
        XCTAssertEqual(CalendarAccessState.fullAccess.permissionDisplayStatus, .granted)
        XCTAssertEqual(CalendarAccessState.notDetermined.permissionDisplayStatus, .notRequested)
        XCTAssertEqual(CalendarAccessState.writeOnly.permissionDisplayStatus, .fullAccessRequired)
        XCTAssertEqual(CalendarAccessState.denied.permissionDisplayStatus, .denied)
        XCTAssertEqual(CalendarAccessState.restricted.permissionDisplayStatus, .restricted)
        XCTAssertEqual(CalendarAccessState.unknown.permissionDisplayStatus, .unavailable)
    }

    func testPermissionDisplayStatusesDescribeReminderAccess() {
        XCTAssertEqual(ReminderAccessState.fullAccess.permissionDisplayStatus, .granted)
        XCTAssertEqual(ReminderAccessState.notDetermined.permissionDisplayStatus, .notRequested)
        XCTAssertEqual(ReminderAccessState.denied.permissionDisplayStatus, .denied)
        XCTAssertEqual(ReminderAccessState.restricted.permissionDisplayStatus, .restricted)
        XCTAssertEqual(ReminderAccessState.unknown.permissionDisplayStatus, .unavailable)
    }

    func testPermissionDisplayStatusProvidesAccessibleLabelsAndSymbols() {
        XCTAssertEqual(PermissionDisplayStatus.granted.title, "Permission Granted")
        XCTAssertEqual(PermissionDisplayStatus.granted.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(PermissionDisplayStatus.notRequested.title, "Not Requested")
        XCTAssertEqual(PermissionDisplayStatus.notRequested.systemImage, "circle.dashed")
        XCTAssertEqual(PermissionDisplayStatus.denied.title, "Access Denied")
        XCTAssertEqual(PermissionDisplayStatus.denied.systemImage, "exclamationmark.circle.fill")
    }
}
