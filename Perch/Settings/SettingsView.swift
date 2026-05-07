import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedMode: MenuBarDisplayMode {
        didSet {
            settingsStore.updateDisplayMode(selectedMode)
            onChange()
        }
    }

    @Published var lookAheadDays: Int {
        didSet {
            settingsStore.updateLookAheadDays(lookAheadDays)
            onChange()
        }
    }

    @Published var showEventColors: Bool {
        didSet {
            settingsStore.updateShowEventColors(showEventColors)
            onChange()
        }
    }

    @Published private(set) var accessState: CalendarAccessState
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var globalShortcut: GlobalShortcut
    @Published private(set) var shortcutError: String?

    private let settingsStore: SettingsStore
    private let permissionController: CalendarPermissionController
    private let onChange: () -> Void
    private let onShortcutChangeRequested: (GlobalShortcut) -> HotKeyRegistrationResult
    private var accessStateCancellable: AnyCancellable?

    init(
        settingsStore: SettingsStore,
        permissionController: CalendarPermissionController,
        onShortcutChangeRequested: @escaping (GlobalShortcut) -> HotKeyRegistrationResult = { _ in .success },
        onChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        let settings = settingsStore.settings
        self.selectedMode = settings.displayMode
        self.lookAheadDays = settings.lookAheadDays
        self.showEventColors = settings.showEventColors
        self.globalShortcut = settings.globalShortcut
        self.accessState = permissionController.accessState
        self.onShortcutChangeRequested = onShortcutChangeRequested
        self.onChange = onChange

        accessStateCancellable = permissionController.$accessState
            .sink { [weak self] accessState in
                self?.accessState = accessState
            }
    }

    var accessActionTitle: String? {
        switch accessState.settingsAction {
        case .requestAccess:
            return "Allow Access..."
        case .openPrivacySettings:
            return "Open Privacy Settings..."
        case nil:
            return nil
        }
    }

    func performAccessAction() {
        switch accessState.settingsAction {
        case .requestAccess:
            requestCalendarAccess()
        case .openPrivacySettings:
            openCalendarPrivacySettings()
        case nil:
            break
        }
    }

    func requestCalendarAccess() {
        guard !isRequestingAccess else {
            return
        }

        isRequestingAccess = true

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            _ = await permissionController.requestFullAccess()
            isRequestingAccess = false
            onChange()
        }
    }

    func openCalendarPrivacySettings() {
        permissionController.openPrivacySettings()
    }

    func recordShortcut(from event: NSEvent) {
        guard let candidate = GlobalShortcut.candidate(from: event) else {
            shortcutError = "Press a printable key with Command, Control, or Option."
            return
        }

        applyShortcut(candidate)
    }

    func resetShortcutToDefault() {
        applyShortcut(.defaultValue)
    }

    private func applyShortcut(_ candidate: GlobalShortcut) {
        switch onShortcutChangeRequested(candidate) {
        case .success:
            settingsStore.updateGlobalShortcut(candidate)
            globalShortcut = candidate
            shortcutError = nil
            onChange()
        case .failure:
            shortcutError = "Shortcut is already in use."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow(alignment: .top) {
                    Text("Calendar Access")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(model.accessState.statusTitle)
                                .font(.body.weight(.medium))

                            if model.accessState.isSufficientForReadingEvents {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }

                        Text(model.accessState.statusDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let actionTitle = model.accessActionTitle {
                            Button(actionTitle) {
                                model.performAccessAction()
                            }
                            .disabled(model.isRequestingAccess)
                        }
                    }
                }

                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text("Include events")
                    Picker("Include events", selection: $model.lookAheadDays) {
                        ForEach(CalendarMenubarSettings.supportedLookAheadDays, id: \.self) { days in
                            Text("\(days) \(days == 1 ? "day" : "days")").tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                GridRow {
                    Text("Preview upcoming event in menu bar")
                    Picker("Preview upcoming event in menu bar", selection: $model.selectedMode) {
                        ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                GridRow {
                    Text("Show calendar colors")
                    Toggle("Show calendar colors", isOn: $model.showEventColors)
                        .labelsHidden()
                }

                GridRow(alignment: .top) {
                    Text("Open/close menu")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ShortcutRecorderView(shortcut: model.globalShortcut) { event in
                                model.recordShortcut(from: event)
                            }
                            .frame(width: 150, height: 28)

                            Button("Reset") {
                                model.resetShortcutToDefault()
                            }
                            .disabled(model.globalShortcut == .defaultValue)
                        }

                        if let shortcutError = model.shortcutError {
                            Text(shortcutError)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onRecord: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(ShortcutRecorderButton.startRecording)
        button.onRecordingChanged = { isRecording in
            context.coordinator.isRecording = isRecording
            updateTitle(for: button, isRecording: isRecording)
        }
        button.onKeyDown = { event in
            guard event.keyCode != UInt16(kVK_Escape) else {
                button.stopRecording()
                return
            }

            onRecord(event)
            button.stopRecording()
        }
        updateTitle(for: button, isRecording: context.coordinator.isRecording)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        updateTitle(for: button, isRecording: context.coordinator.isRecording)
    }

    private func updateTitle(for button: ShortcutRecorderButton, isRecording: Bool) {
        button.title = isRecording ? "Type shortcut" : shortcut.displayTitle
    }

    final class Coordinator {
        var isRecording = false
    }
}

final class ShortcutRecorderButton: NSButton {
    var onRecordingChanged: ((Bool) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    @objc func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        onRecordingChanged?(true)
    }

    func stopRecording() {
        isRecording = false
        onRecordingChanged?(false)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        onKeyDown?(event)
    }
}
