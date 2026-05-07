import Foundation

struct CalendarMenubarSettings: Codable, Equatable {
    var displayMode: MenuBarDisplayMode
    var lookAheadDays: Int
    var globalShortcut: GlobalShortcut
    var showEventColors: Bool

    static let supportedLookAheadDays = [1, 3, 7, 14, 30]

    static let defaultValue = CalendarMenubarSettings(
        displayMode: .within6Hours,
        lookAheadDays: 3,
        globalShortcut: .defaultValue,
        showEventColors: true
    )

    init(
        displayMode: MenuBarDisplayMode,
        lookAheadDays: Int,
        globalShortcut: GlobalShortcut = .defaultValue,
        showEventColors: Bool = true
    ) {
        self.displayMode = displayMode
        self.lookAheadDays = lookAheadDays
        self.globalShortcut = globalShortcut.isValid ? globalShortcut : .defaultValue
        self.showEventColors = showEventColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displayMode = try container.decode(MenuBarDisplayMode.self, forKey: .displayMode)
        let lookAheadDays = try container.decode(Int.self, forKey: .lookAheadDays)
        let decodedShortcut = try? container.decodeIfPresent(GlobalShortcut.self, forKey: .globalShortcut)
        let globalShortcut = decodedShortcut.flatMap { $0 } ?? .defaultValue
        let showEventColors = try container.decodeIfPresent(Bool.self, forKey: .showEventColors) ?? true

        self.init(
            displayMode: displayMode,
            lookAheadDays: lookAheadDays,
            globalShortcut: globalShortcut,
            showEventColors: showEventColors
        )
    }
}

final class SettingsStore {
    private let userDefaults: UserDefaults
    private let settingsKey = "CalendarMenubarSettings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var settings: CalendarMenubarSettings {
        get {
            guard let data = userDefaults.data(forKey: settingsKey),
                  let decoded = try? JSONDecoder().decode(CalendarMenubarSettings.self, from: data),
                  CalendarMenubarSettings.supportedLookAheadDays.contains(decoded.lookAheadDays)
            else {
                return .defaultValue
            }

            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }

            userDefaults.set(data, forKey: settingsKey)
        }
    }

    func updateDisplayMode(_ displayMode: MenuBarDisplayMode) {
        var currentSettings = settings
        currentSettings.displayMode = displayMode
        settings = currentSettings
    }

    func updateLookAheadDays(_ lookAheadDays: Int) {
        guard CalendarMenubarSettings.supportedLookAheadDays.contains(lookAheadDays) else {
            return
        }

        var currentSettings = settings
        currentSettings.lookAheadDays = lookAheadDays
        settings = currentSettings
    }

    func updateGlobalShortcut(_ globalShortcut: GlobalShortcut) {
        guard globalShortcut.isValid else {
            return
        }

        var currentSettings = settings
        currentSettings.globalShortcut = globalShortcut
        settings = currentSettings
    }

    func updateShowEventColors(_ showEventColors: Bool) {
        var currentSettings = settings
        currentSettings.showEventColors = showEventColors
        settings = currentSettings
    }
}
