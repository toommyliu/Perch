import AppKit
import Darwin

private let singleInstanceLock: SingleInstanceLockResult? = isRunningUnderXCTest() ? nil : acquireSingleInstanceLock()

if let singleInstanceLock {
    switch singleInstanceLock {
    case .acquired:
        break
    case .alreadyRunning:
        PerchLog.info("Another Perch instance is already running; exiting duplicate instance")
        exit(EXIT_SUCCESS)
    case let .unavailable(message):
        exitIfAnotherInstanceIsRunning()

        // Failing open is safer than making the app unavailable because of a temporary filesystem issue.
        PerchLog.error("Could not acquire single-instance lock: \(message); continuing launch")
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()

application.delegate = appDelegate
application.run()

private enum SingleInstanceLockResult {
    case acquired(fileDescriptor: Int32)
    case alreadyRunning
    case unavailable(String)
}

private func isRunningUnderXCTest() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
}

private func acquireSingleInstanceLock() -> SingleInstanceLockResult {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.app.perch"
    let lockURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(bundleIdentifier).instance.lock")

    let fileDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fileDescriptor != -1 else {
        return .unavailable(String(cString: strerror(errno)))
    }

    guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
        let lockError = errno
        Darwin.close(fileDescriptor)

        if lockError == EWOULDBLOCK {
            return .alreadyRunning
        }

        return .unavailable(String(cString: strerror(lockError)))
    }

    let pidData = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
    pidData.withUnsafeBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            return
        }

        guard Darwin.ftruncate(fileDescriptor, 0) == 0 else {
            PerchLog.error("ftruncate on lock file failed: \(String(cString: strerror(errno)))")
            return
        }

        _ = Darwin.write(fileDescriptor, baseAddress, buffer.count)
    }

    return .acquired(fileDescriptor: fileDescriptor)
}

private func exitIfAnotherInstanceIsRunning() {
    guard isAnotherInstanceRunning() else {
        return
    }

    PerchLog.info("Another Perch instance is already running; exiting duplicate instance")
    exit(EXIT_SUCCESS)
}

private func isAnotherInstanceRunning() -> Bool {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
        return false
    }

    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .contains { $0.processIdentifier != currentProcessIdentifier }
}
