import Foundation
import os

enum PerchLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.app.perch"

    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let presentation = Logger(subsystem: subsystem, category: "presentation")
    static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
    static let actions = Logger(subsystem: subsystem, category: "actions")
}
