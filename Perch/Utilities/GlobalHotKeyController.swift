import AppKit
import Carbon
import Foundation

enum HotKeyRegistrationResult: Equatable {
    case success
    case failure(OSStatus)
}

struct HotKeyRegistration {
    let status: OSStatus
    let hotKeyRef: EventHotKeyRef?
}

protocol HotKeyRegistering {
    func register(shortcut: GlobalShortcut, hotKeyID: EventHotKeyID) -> HotKeyRegistration
    func unregister(_ hotKeyRef: EventHotKeyRef)
}

struct CarbonHotKeyRegistrar: HotKeyRegistering {
    func register(shortcut: GlobalShortcut, hotKeyID: EventHotKeyID) -> HotKeyRegistration {
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        return HotKeyRegistration(status: status, hotKeyRef: hotKeyRef)
    }

    func unregister(_ hotKeyRef: EventHotKeyRef) {
        UnregisterEventHotKey(hotKeyRef)
    }
}

final class GlobalHotKeyController {
    private let onToggle: @MainActor () -> Void
    private let registrar: HotKeyRegistering
    private let hotKeyID = EventHotKeyID(
        signature: GlobalHotKeyController.fourCharacterCode("DYLN"),
        id: 1
    )
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeShortcut: GlobalShortcut
    private var isEnabled = true

    init(
        initialShortcut: GlobalShortcut,
        registrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        installHandler: Bool = true,
        onToggle: @escaping @MainActor () -> Void
    ) {
        self.activeShortcut = initialShortcut.isValid ? initialShortcut : .defaultValue
        self.registrar = registrar
        self.onToggle = onToggle

        guard !installHandler || installEventHandler() else {
            return
        }

        registerHotKeyIfNeeded()
    }

    @discardableResult
    func applyShortcut(_ candidate: GlobalShortcut) -> HotKeyRegistrationResult {
        guard candidate.isValid else {
            return .failure(OSStatus(paramErr))
        }

        let previousShortcut = activeShortcut
        let wasRegistered = hotKeyRef != nil

        unregisterHotKeyIfNeeded()
        activeShortcut = candidate

        guard isEnabled else {
            return .success
        }

        let result = registerHotKeyIfNeeded()
        switch result {
        case .success:
            return .success
        case let .failure(status):
            activeShortcut = previousShortcut

            if wasRegistered {
                _ = registerHotKeyIfNeeded()
            }

            return .failure(status)
        }
    }

    // The menu controller disables the global hotkey while the status menu is open.
    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled

        if isEnabled {
            _ = registerHotKeyIfNeeded()
        } else {
            unregisterHotKeyIfNeeded()
        }
    }

    private func installEventHandler() -> Bool {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var receivedHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedHotKeyID
                )

                guard status == noErr else {
                    return status
                }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                guard receivedHotKeyID.signature == controller.hotKeyID.signature,
                      receivedHotKeyID.id == controller.hotKeyID.id
                else {
                    return noErr
                }

                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        controller.onToggle()
                    }
                } else {
                    Task { @MainActor in
                        controller.onToggle()
                    }
                }

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            PerchLog.error("Failed to install global hotkey handler: \(handlerStatus)")
            return false
        }

        return true
    }

    @discardableResult
    private func registerHotKeyIfNeeded() -> HotKeyRegistrationResult {
        guard isEnabled else {
            return .success
        }

        guard hotKeyRef == nil else {
            return .success
        }

        let registration = registrar.register(shortcut: activeShortcut, hotKeyID: hotKeyID)
        guard registration.status == noErr, let hotKeyRef = registration.hotKeyRef else {
            PerchLog.error("Failed to register global hotkey \(activeShortcut.displayTitle): \(registration.status)")
            return .failure(registration.status)
        }

        self.hotKeyRef = hotKeyRef
        PerchLog.info("Registered global hotkey \(activeShortcut.displayTitle)")
        return .success
    }

    private func unregisterHotKeyIfNeeded() {
        guard let hotKeyRef else {
            return
        }

        registrar.unregister(hotKeyRef)
        self.hotKeyRef = nil
        PerchLog.info("Unregistered global hotkey \(activeShortcut.displayTitle)")
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }

    deinit {
        unregisterHotKeyIfNeeded()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
