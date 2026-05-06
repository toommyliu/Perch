import AppKit
import Combine
import Foundation

@MainActor
final class CalendarPermissionController: ObservableObject {
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    @Published private(set) var accessState: CalendarAccessState

    private let permissionProvider: CalendarPermissionProviding
    private let openURL: (URL) -> Void

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
        accessState = currentState
        return currentState
    }

    @discardableResult
    func requestFullAccess() async -> CalendarAccessState {
        let currentState = await permissionProvider.requestFullAccess()
        accessState = currentState
        return currentState
    }

    func openPrivacySettings() {
        openURL(Self.privacySettingsURL)
    }
}
