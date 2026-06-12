import AppKit
import Combine
import Foundation

@MainActor
final class CalendarPermissionController: ObservableObject {
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    @Published private(set) var accessState: CalendarAccessState

    private let permissionProvider: CalendarPermissionProviding
    private let openURL: (URL) -> Void
    private var accessRequestTask: Task<CalendarAccessState, Never>?

    init(
        permissionProvider: CalendarPermissionProviding,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.permissionProvider = permissionProvider
        self.openURL = openURL
        self.accessState = permissionProvider.authorizationState()
    }

    @discardableResult
    func refreshStatus() -> CalendarAccessState {
        let currentState = permissionProvider.authorizationState()
        if accessState != currentState {
            accessState = currentState
        }
        return currentState
    }

    @discardableResult
    func requestFullAccess() async -> CalendarAccessState {
        let currentState = refreshStatus()
        guard currentState == .notDetermined else {
            return currentState
        }

        if let accessRequestTask {
            return updateAccessState(await accessRequestTask.value)
        }

        let accessRequestTask = Task {
            await permissionProvider.requestFullAccess()
        }
        self.accessRequestTask = accessRequestTask

        let requestedState = await accessRequestTask.value
        self.accessRequestTask = nil
        return updateAccessState(requestedState)
    }

    func openPrivacySettings() {
        openURL(Self.privacySettingsURL)
    }

    @discardableResult
    private func updateAccessState(_ currentState: CalendarAccessState) -> CalendarAccessState {
        if accessState != currentState {
            accessState = currentState
        }
        return currentState
    }
}
