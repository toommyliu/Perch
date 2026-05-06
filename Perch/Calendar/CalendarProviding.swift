import Foundation

protocol CalendarPermissionProviding {
    func authorizationState() -> CalendarAccessState
    func requestFullAccess() async -> CalendarAccessState
}

protocol CalendarEventProviding {
    func events(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent]
}

typealias CalendarProviding = CalendarPermissionProviding & CalendarEventProviding
