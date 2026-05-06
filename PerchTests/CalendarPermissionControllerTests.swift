import XCTest
@testable import Perch

@MainActor
final class CalendarPermissionControllerTests: XCTestCase {
    func testInitialStateIsReadFromProvider() {
        let provider = FakePermissionProvider(state: .denied)
        let controller = CalendarPermissionController(permissionProvider: provider)

        XCTAssertEqual(controller.accessState, .denied)
    }

    func testRefreshStatusPublishesProviderState() {
        let provider = FakePermissionProvider(state: .notDetermined)
        let controller = CalendarPermissionController(permissionProvider: provider)

        provider.state = .fullAccess

        XCTAssertEqual(controller.refreshStatus(), .fullAccess)
        XCTAssertEqual(controller.accessState, .fullAccess)
    }

    func testRequestFullAccessUpdatesPublishedState() async {
        let provider = FakePermissionProvider(state: .notDetermined, requestResult: .fullAccess)
        let controller = CalendarPermissionController(permissionProvider: provider)

        let state = await controller.requestFullAccess()

        XCTAssertEqual(state, .fullAccess)
        XCTAssertEqual(controller.accessState, .fullAccess)
        XCTAssertEqual(provider.requestCount, 1)
    }

    func testOpenPrivacySettingsOpensExpectedURL() {
        let provider = FakePermissionProvider(state: .denied)
        var openedURLs: [URL] = []
        let controller = CalendarPermissionController(permissionProvider: provider) { url in
            openedURLs.append(url)
        }

        controller.openPrivacySettings()

        XCTAssertEqual(openedURLs, [CalendarPermissionController.privacySettingsURL])
    }
}
