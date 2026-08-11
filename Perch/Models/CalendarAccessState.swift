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

enum ReminderAccessState: Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case unknown
}

enum ReminderAccessSettingsAction: Equatable {
    case requestAccess
    case openPrivacySettings
}

enum PermissionDisplayStatus: Equatable {
    case granted
    case notRequested
    case fullAccessRequired
    case denied
    case restricted
    case unavailable

    var title: String {
        switch self {
        case .granted:
            return "Permission Granted"
        case .notRequested:
            return "Not Requested"
        case .fullAccessRequired:
            return "Full Access Required"
        case .denied:
            return "Access Denied"
        case .restricted:
            return "Access Restricted"
        case .unavailable:
            return "Status Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .granted:
            return "checkmark.circle.fill"
        case .notRequested:
            return "circle.dashed"
        case .fullAccessRequired, .denied, .restricted, .unavailable:
            return "exclamationmark.circle.fill"
        }
    }
}

extension CalendarAccessState {
    var permissionDisplayStatus: PermissionDisplayStatus {
        switch self {
        case .notDetermined:
            return .notRequested
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .fullAccessRequired
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .unknown:
            return .unavailable
        }
    }

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

extension ReminderAccessState {
    var permissionDisplayStatus: PermissionDisplayStatus {
        switch self {
        case .notDetermined:
            return .notRequested
        case .fullAccess:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .unknown:
            return .unavailable
        }
    }

    var isSufficientForReadingReminders: Bool {
        self == .fullAccess
    }

    var settingsAction: ReminderAccessSettingsAction? {
        switch self {
        case .notDetermined:
            return .requestAccess
        case .fullAccess:
            return nil
        case .denied, .restricted, .unknown:
            return .openPrivacySettings
        }
    }
}
