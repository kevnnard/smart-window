import Foundation
import CoreGraphics

// MARK: - Scope

/// What the Bar & Notch page edits: Default, or the settings of one display.
enum SettingsScope: Hashable {
    case defaults
    case display(String)

    var key: String? {
        if case .display(let key) = self { return key }
        return nil
    }

    /// With one display there is nothing to choose between, so the map is hidden and edits go to Default.
    static func showsMap(knownDisplays: [DisplayPreferences.KnownDisplay]) -> Bool { knownDisplays.count > 1 }

    /// This scope, or Default when the map is hidden or the display is no longer known.
    func resolved(in known: [DisplayPreferences.KnownDisplay]) -> SettingsScope {
        guard let key, Self.showsMap(knownDisplays: known), known.contains(where: { $0.key == key }) else {
            return .defaults
        }
        return self
    }
}

// MARK: - Tabs

/// The Bar · Widgets · Notch tabs of the Bar & Notch page.
enum SettingsTab: String, CaseIterable, Identifiable {
    case bar, widgets, notch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bar: return "Bar"
        case .widgets: return "Widgets"
        case .notch: return "Notch"
        }
    }

    /// How many of a display's own settings this tab holds.
    func customCount(_ override: DisplayPreferences.Override?) -> Int {
        guard let o = override else { return 0 }
        switch self {
        case .bar:
            return o.barOpacity == nil ? 0 : 1
        case .widgets:
            return (o.widgetOrder == nil ? 0 : 1) + o.widgets.count + o.separators.count
        case .notch:
            let notch: [Any?] = [o.nowPlaying, o.showWhenIdle, o.notchMatchesBar, o.notchSize, o.expandedExtraWidth]
            return notch.compactMap { $0 }.count
        }
    }
}

// MARK: - Scope line

/// The line under the display map: what the selected scope means and how much it customizes.
struct ScopeLine: Equatable {
    struct Link: Equatable {
        let key: String
        let text: String
    }

    var text: String
    /// Display scope only: "N custom", or that it uses Default.
    var status: String?
    var isCustom = false
    /// Default scope only: each display with its own settings, to jump to it.
    var links: [Link] = []
    var notConnectedNote: String?
    var resetTitle: String?

    init(scope: SettingsScope, known: [DisplayPreferences.KnownDisplay]) {
        guard let key = scope.key, let display = known.first(where: { $0.key == key }) else {
            text = "Default applies to every display without its own setting."
            links = known.filter { $0.overrideCount > 0 }.map {
                Link(key: $0.key, text: "\($0.name) customizes \(SettingsText.settings($0.overrideCount))")
            }
            return
        }
        text = "Editing \(display.name) only."
        isCustom = display.overrideCount > 0
        status = isCustom ? "\(display.overrideCount) custom" : "No custom settings — uses Default"
        if !display.isConnected {
            notConnectedNote = "\(display.name) is not connected. Its settings are remembered and apply when it reconnects."
        }
        if isCustom { resetTitle = "Reset all settings for \(display.name)" }
    }
}

// MARK: - Text

/// Values and row status as shown in the Bar & Notch rows.
enum SettingsText {
    /// "Default · 94%" or "Custom · Default is 94%" in a display scope; nothing in Default.
    static func rowStatus(scope: SettingsScope, isCustom: Bool, defaultValue: String) -> String? {
        guard scope.key != nil else { return nil }
        return isCustom ? "Custom · Default is \(defaultValue)" : "Default · \(defaultValue)"
    }

    static func orderStatus(scope: SettingsScope, isCustom: Bool) -> String? {
        guard scope.key != nil else { return nil }
        return isCustom ? "Custom · differs from Default order" : "Default order"
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func points(_ value: Double) -> String { "\(Int(value.rounded())) pt" }
    static func size(_ size: DisplayPreferences.NotchSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }
    static func expanded(_ extra: Double) -> String { extra == 0 ? "Same" : "+\(Int(extra.rounded())) pt" }
    static func onOff(_ value: Bool) -> String { value ? "On" : "Off" }
    static func background(matchesBar: Bool) -> String { matchesBar ? "Match bar color" : "Black" }
    static func widget(visible: Bool, separator: Bool) -> String {
        (visible ? "Shown" : "Hidden") + (separator ? ", separator after" : "")
    }
    static func resetLabel(_ name: String) -> String { "Reset \(name) to Default" }
    static func settings(_ count: Int) -> String { count == 1 ? "1 setting" : "\(count) settings" }
}

// MARK: - Display map

/// Monitor drawings of the display map, scaled to their pixel aspect ratio.
enum DisplayMap {
    static let monitorBox = CGSize(width: 200, height: 80)
    /// The Default card, and displays whose size is unknown.
    static let defaultSize = CGSize(width: 124, height: 80)
    static let minimumWidth: CGFloat = 60

    static func monitorSize(for info: DisplayPreferences.DisplayInfo?) -> CGSize {
        guard let info, info.pixelWidth > 0, info.pixelHeight > 0 else { return defaultSize }
        let ratio = CGFloat(info.pixelWidth) / CGFloat(info.pixelHeight)
        let width = min(monitorBox.width, monitorBox.height * ratio)
        let height = min(monitorBox.height, width / ratio)
        return CGSize(width: max(minimumWidth, width.rounded()), height: height.rounded())
    }

    static func badge(overrideCount: Int) -> String {
        overrideCount > 0 ? "\(overrideCount) custom" : "Uses Default"
    }

    static func accessibilityValue(_ display: DisplayPreferences.KnownDisplay) -> String {
        var parts: [String] = []
        if let info = display.info, info.pixelWidth > 0 {
            parts.append("\(info.pixelWidth) × \(info.pixelHeight)")
            if info.isBuiltIn { parts.append("built-in") }
        }
        if !display.isConnected { parts.append("not connected") }
        switch display.overrideCount {
        case 0: parts.append("uses Default")
        case 1: parts.append("1 custom setting")
        case let count: parts.append("\(count) custom settings")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

enum LivePreview {
    /// The notch is drawn at 60% so a wide notch still fits beside the window tabs.
    static let scale: CGFloat = 0.6

    static func notchSize(_ size: DisplayPreferences.NotchSize) -> CGSize {
        CGSize(width: CGFloat(size.width) * scale, height: CGFloat(size.height) * scale)
    }
}
