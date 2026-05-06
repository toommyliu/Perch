import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case always
    case within1Hour
    case within3Hours
    case within6Hours
    case within12Hours
    case never

    var displayTitle: String {
        switch self {
        case .always:
            return "Always"
        case .within1Hour:
            return "Within 1 hour"
        case .within3Hours:
            return "Within 3 hours"
        case .within6Hours:
            return "Within 6 hours"
        case .within12Hours:
            return "Within 12 hours"
        case .never:
            return "Never"
        }
    }

    var leadTime: TimeInterval? {
        switch self {
        case .always:
            return nil
        case .within1Hour:
            return 60 * 60
        case .within3Hours:
            return 3 * 60 * 60
        case .within6Hours:
            return 6 * 60 * 60
        case .within12Hours:
            return 12 * 60 * 60
        case .never:
            return 0
        }
    }
}
