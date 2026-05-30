import XCTest
import Combine
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

    func testRefreshStatusDoesNotRepublishUnchangedState() {
        let provider = FakePermissionProvider(state: .fullAccess)
        let controller = CalendarPermissionController(permissionProvider: provider)
        var publishedStates: [CalendarAccessState] = []
        let cancellable = controller.$accessState
            .dropFirst()
            .sink { publishedStates.append($0) }

        XCTAssertEqual(controller.refreshStatus(), .fullAccess)

        XCTAssertEqual(publishedStates, [])
        cancellable.cancel()
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

@MainActor
final class CalendarRefreshCoalescerTests: XCTestCase {
    func testRequestsWhileRefreshIsRunningAreCoalescedIntoOneFollowUp() async {
        let firstRefreshStarted = expectation(description: "first refresh started")
        let firstRefreshMayFinish = expectation(description: "first refresh may finish")
        let secondRefreshFinished = expectation(description: "second refresh finished")
        var refreshCount = 0

        let coalescer = CalendarRefreshCoalescer {
            refreshCount += 1

            if refreshCount == 1 {
                firstRefreshStarted.fulfill()
                await self.fulfillment(of: [firstRefreshMayFinish], timeout: 1)
            } else if refreshCount == 2 {
                secondRefreshFinished.fulfill()
            }
        }

        coalescer.requestRefresh()
        await fulfillment(of: [firstRefreshStarted], timeout: 1)

        coalescer.requestRefresh()
        coalescer.requestRefresh()
        firstRefreshMayFinish.fulfill()

        await fulfillment(of: [secondRefreshFinished], timeout: 1)
        XCTAssertEqual(refreshCount, 2)
    }

    func testRequestAfterRefreshDrainsStartsNewRefresh() async {
        let firstRefreshFinished = expectation(description: "first refresh finished")
        let secondRefreshFinished = expectation(description: "second refresh finished")
        var refreshCount = 0

        let coalescer = CalendarRefreshCoalescer {
            refreshCount += 1

            if refreshCount == 1 {
                firstRefreshFinished.fulfill()
            } else if refreshCount == 2 {
                secondRefreshFinished.fulfill()
            }
        }

        coalescer.requestRefresh()
        await fulfillment(of: [firstRefreshFinished], timeout: 1)
        await Task.yield()
        await Task.yield()

        coalescer.requestRefresh()

        await fulfillment(of: [secondRefreshFinished], timeout: 1)
        XCTAssertEqual(refreshCount, 2)
    }
}
