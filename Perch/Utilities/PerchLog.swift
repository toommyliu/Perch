import Foundation
import os

enum PerchLog {
    private static let logger = Logger(subsystem: "com.app.perch", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        FileHandle.standardError.write("[Perch] \(message)\n".data(using: .utf8) ?? Data())
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        FileHandle.standardError.write("[Perch] ERROR: \(message)\n".data(using: .utf8) ?? Data())
    }
}
