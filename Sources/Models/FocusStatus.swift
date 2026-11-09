import AppKit

/// A macOS Focus as the notch shows it: name, SF Symbol and color.
struct FocusModeDescriptor: Equatable {
    let identifier: String
    let name: String
    let symbolName: String
    /// Apple's color name, such as "systemTealColor".
    let tintColorName: String?

    /// Used when only "a Focus is on" is known, or a Focus has no configuration.
    static let generic = FocusModeDescriptor(identifier: "focus", name: "Focus", symbolName: "moon.fill",
                                             tintColorName: "systemIndigoColor")

    var tintColor: NSColor {
        switch tintColorName {
        case "systemBlueColor": return .systemBlue
        case "systemBrownColor": return .systemBrown
        case "systemCyanColor": return .systemCyan
        case "systemGrayColor": return .systemGray
        case "systemGreenColor": return .systemGreen
        case "systemMintColor": return .systemMint
        case "systemOrangeColor": return .systemOrange
        case "systemPinkColor": return .systemPink
        case "systemPurpleColor": return .systemPurple
        case "systemRedColor": return .systemRed
        case "systemTealColor": return .systemTeal
        case "systemYellowColor": return .systemYellow
        default: return .systemIndigo
        }
    }
}

/// Reads the Focus database in ~/Library/DoNotDisturb/DB. The format is undocumented, so every
/// field is optional and anything unexpected reads as "no Focus".
enum FocusDatabase {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    static let assertionsURL = directory.appendingPathComponent("Assertions.json")
    static let configurationsURL = directory.appendingPathComponent("ModeConfigurations.json")

    /// Privacy & Security → Full Disk Access. macOS has no prompt for it; the user adds the app.
    static let fullDiskAccessSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Whether the active Focus can be read, which needs Full Disk Access.
    static func canRead(directory: URL = directory) -> Bool {
        (try? Data(contentsOf: directory.appendingPathComponent("Assertions.json"))) != nil
    }

    /// Every configured Focus, by identifier.
    static func modes(fromConfigurations data: Data) -> [String: FocusModeDescriptor] {
        var modes: [String: FocusModeDescriptor] = [:]
        for store in stores(in: data) {
            guard let configurations = store["modeConfigurations"] as? [String: Any] else { continue }
            for (identifier, value) in configurations {
                guard let mode = (value as? [String: Any])?["mode"] as? [String: Any] else { continue }
                modes[identifier] = FocusModeDescriptor(
                    identifier: identifier,
                    name: mode["name"] as? String ?? FocusModeDescriptor.generic.name,
                    symbolName: mode["symbolImageName"] as? String ?? FocusModeDescriptor.generic.symbolName,
                    tintColorName: mode["tintColorName"] as? String)
            }
        }
        return modes
    }

    /// The Focus turned on by hand or by a shortcut: the latest assertion record.
    static func activeIdentifier(fromAssertions data: Data) -> String? {
        let records = stores(in: data).flatMap { $0["storeAssertionRecords"] as? [[String: Any]] ?? [] }
        let latest = records.max { timestamp($0) < timestamp($1) }
        return (latest?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
    }

    static func active(assertions: Data, configurations: Data) -> FocusModeDescriptor? {
        guard let identifier = activeIdentifier(fromAssertions: assertions) else { return nil }
        if let mode = modes(fromConfigurations: configurations)[identifier] { return mode }
        let generic = FocusModeDescriptor.generic
        return FocusModeDescriptor(identifier: identifier, name: generic.name, symbolName: generic.symbolName,
                                   tintColorName: generic.tintColorName)
    }

    /// The Focus to show: the database names it; otherwise the public status (nil when unavailable)
    /// still reports a Focus the database does not list, such as one turned on by a schedule.
    static func resolve(database: FocusModeDescriptor?, publicFocused: Bool?) -> FocusModeDescriptor? {
        database ?? (publicFocused == true ? .generic : nil)
    }

    private static func stores(in data: Data) -> [[String: Any]] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return root?["data"] as? [[String: Any]] ?? []
    }

    private static func timestamp(_ record: [String: Any]) -> Double {
        (record["assertionStartDateTimestamp"] as? NSNumber)?.doubleValue ?? 0
    }
}

/// Turns successive readings of the active Focus into notch events: on, off, or a switch.
struct FocusChangeTracker {
    private var started = false
    private var current: FocusModeDescriptor?

    /// Records the active Focus (nil when none); returns the event to show, if it changed.
    mutating func update(_ active: FocusModeDescriptor?) -> SystemHUDEvent? {
        defer {
            started = true
            current = active
        }
        // The Focus already on at launch is the starting point, not a change.
        guard started, active != current else { return nil }
        if let active { return SystemHUDEvent(focus: active, isOn: true) }
        return current.map { SystemHUDEvent(focus: $0, isOn: false) }
    }
}
