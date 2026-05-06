import Foundation

enum CalendarAccessState: Equatable {
    case notDetermined
    case fullAccess
    case writeOnly
    case denied
    case restricted
    case unknown
}

enum CalendarAccessSettingsAction: Equatable {
    case requestAccess
    case openPrivacySettings
}

extension CalendarAccessState {
    var statusTitle: String {
        switch self {
        case .notDetermined:
            return "Calendar access not set"
        case .fullAccess:
            return "Calendar access enabled"
        case .writeOnly:
            return "Full calendar access required"
        case .denied:
            return "Calendar access denied"
        case .restricted:
            return "Calendar access restricted"
        case .unknown:
            return "Calendar access unavailable"
        }
    }

    var statusDetail: String {
        switch self {
        case .notDetermined:
            return "Perch needs full calendar access to read upcoming events."
        case .fullAccess:
            return "Perch can read your calendars and show upcoming events."
        case .writeOnly:
            return "Perch can only write calendar events. Enable full access in System Settings so it can read upcoming events."
        case .denied:
            return "Enable calendar access in System Settings to show upcoming events."
        case .restricted:
            return "Calendar access is restricted by macOS or device management."
        case .unknown:
            return "Perch cannot determine calendar access. Check Calendar privacy settings."
        }
    }

    var isSufficientForReadingEvents: Bool {
        self == .fullAccess
    }

    var settingsAction: CalendarAccessSettingsAction? {
        switch self {
        case .notDetermined:
            return .requestAccess
        case .fullAccess:
            return nil
        case .writeOnly, .denied, .restricted, .unknown:
            return .openPrivacySettings
        }
    }
}
