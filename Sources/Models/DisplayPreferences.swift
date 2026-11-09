import Foundation
import Combine

/// Additive preferences: absent overrides inherit the existing global settings (Default).
final class DisplayPreferences: ObservableObject {
    static let shared = DisplayPreferences()
    enum Mode: String, CaseIterable, Identifiable {
        case inherit, show, hide
        var id: String { rawValue }
        var label: String { self == .inherit ? "Default" : (self == .show ? "Show" : "Hide") }
        var value: Bool? { self == .inherit ? nil : self == .show }
        init(_ value: Bool?) { self = value.map { $0 ? .show : .hide } ?? .inherit }
    }
    /// Notch badge size for one display, in points. Ranges match the global sliders in Settings.
    struct NotchSize: Codable, Equatable {
        static let widthRange: ClosedRange<Double> = 180...440
        static let heightRange: ClosedRange<Double> = 30...46
        var width: Double
        var height: Double

        var clamped: NotchSize {
            NotchSize(width: min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound),
                      height: min(max(height, Self.heightRange.lowerBound), Self.heightRange.upperBound))
        }
    }
    /// Ranges of the bar opacity and Expanded width sliders.
    static let barOpacityRange: ClosedRange<Double> = 0.6...1.0
    static let expandedExtraWidthRange: ClosedRange<Double> = 0...200

    /// Every bar and notch setting, as Default (AppSettings) or as resolved for one display.
    struct Settings: Equatable {
        var barOpacity: Double
        var widgetOrder: [String]
        var widgetVisibility: [String: Bool]
        /// Widgets followed by a separator.
        var separators: Set<String>
        var showNotch: Bool
        /// Show the notch when nothing is playing.
        var showWhenIdle: Bool
        /// Notch background: the bar color when true, black otherwise.
        var notchMatchesBar: Bool
        var notchSize: NotchSize
        var expandedExtraWidth: Double

        func isWidgetVisible(_ widget: String) -> Bool { widgetVisibility[widget] ?? true }
        func hasSeparator(after widget: String) -> Bool { separators.contains(widget) }
    }

    /// One overridable setting, as one row in Settings. Widget visibility and separators are one
    /// setting per widget; the notch size is one setting for width and height.
    enum Setting: Hashable {
        case barOpacity, widgetOrder, widget(String), separator(String)
        case showNotch, showWhenIdle, notchBackground, notchSize, expandedExtraWidth
    }

    struct Override: Codable, Equatable {
        var widgets: [String: Bool] = [:]
        /// Show notch. Named for the setting it started as (Now Playing).
        var nowPlaying: Bool?
        /// nil means Default: the display uses the global notch size.
        var notchSize: NotchSize?
        var barOpacity: Double?
        var widgetOrder: [String]?
        var separators: [String: Bool] = [:]
        var showWhenIdle: Bool?
        var notchMatchesBar: Bool?
        var expandedExtraWidth: Double?

        init() {}

        /// Every field is optional in storage, so overrides saved by older versions keep decoding.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            widgets = try c.decodeIfPresent([String: Bool].self, forKey: .widgets) ?? [:]
            nowPlaying = try c.decodeIfPresent(Bool.self, forKey: .nowPlaying)
            notchSize = try c.decodeIfPresent(NotchSize.self, forKey: .notchSize)
            barOpacity = try c.decodeIfPresent(Double.self, forKey: .barOpacity)
            widgetOrder = try c.decodeIfPresent([String].self, forKey: .widgetOrder)
            separators = try c.decodeIfPresent([String: Bool].self, forKey: .separators) ?? [:]
            showWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .showWhenIdle)
            notchMatchesBar = try c.decodeIfPresent(Bool.self, forKey: .notchMatchesBar)
            expandedExtraWidth = try c.decodeIfPresent(Double.self, forKey: .expandedExtraWidth)
        }

        var count: Int {
            let single: [Any?] = [nowPlaying, notchSize, barOpacity, widgetOrder, showWhenIdle, notchMatchesBar,
                                  expandedExtraWidth]
            return widgets.count + separators.count + single.compactMap { $0 }.count
        }

        func applied(to base: Settings) -> Settings {
            var value = base
            if let barOpacity { value.barOpacity = barOpacity }
            if let widgetOrder {
                // Keeps every Default widget: unknown ones are dropped, missing ones appended.
                let order = widgetOrder.filter(base.widgetOrder.contains)
                value.widgetOrder = order + base.widgetOrder.filter { !order.contains($0) }
            }
            value.widgetVisibility.merge(widgets) { _, own in own }
            for (widget, on) in separators {
                if on { value.separators.insert(widget) } else { value.separators.remove(widget) }
            }
            if let nowPlaying { value.showNotch = nowPlaying }
            if let showWhenIdle { value.showWhenIdle = showWhenIdle }
            if let notchMatchesBar { value.notchMatchesBar = notchMatchesBar }
            if let notchSize { value.notchSize = notchSize }
            if let expandedExtraWidth { value.expandedExtraWidth = expandedExtraWidth }
            return value
        }

        func has(_ setting: Setting) -> Bool {
            switch setting {
            case .barOpacity: return barOpacity != nil
            case .widgetOrder: return widgetOrder != nil
            case .widget(let id): return widgets[id] != nil
            case .separator(let id): return separators[id] != nil
            case .showNotch: return nowPlaying != nil
            case .showWhenIdle: return showWhenIdle != nil
            case .notchBackground: return notchMatchesBar != nil
            case .notchSize: return notchSize != nil
            case .expandedExtraWidth: return expandedExtraWidth != nil
            }
        }

        mutating func clear(_ setting: Setting) {
            switch setting {
            case .barOpacity: barOpacity = nil
            case .widgetOrder: widgetOrder = nil
            case .widget(let id): widgets[id] = nil
            case .separator(let id): separators[id] = nil
            case .showNotch: nowPlaying = nil
            case .showWhenIdle: showWhenIdle = nil
            case .notchBackground: notchMatchesBar = nil
            case .notchSize: notchSize = nil
            case .expandedExtraWidth: expandedExtraWidth = nil
            }
        }
    }

    /// Last known description of a display, so it can be listed and drawn while not connected.
    struct DisplayInfo: Codable, Equatable {
        var name: String
        var isBuiltIn: Bool
        var hasCameraNotch: Bool
        var pixelWidth: Int
        var pixelHeight: Int
    }

    /// A display Settings can scope to: connected, or not connected but with its own settings.
    struct KnownDisplay: Identifiable, Equatable {
        let key: String
        /// nil for overrides saved before display names were remembered.
        let info: DisplayInfo?
        let isConnected: Bool
        let overrideCount: Int
        var id: String { key }
        var name: String { info?.name ?? "Display" }
    }

    private let defaults: UserDefaults
    private static let storageKey = "displayOverrides.v1"
    private static let infoKey = "displayInfo.v1"
    @Published private(set) var overrides: [String: Override]
    @Published private(set) var displayInfo: [String: DisplayInfo]
    /// Show notch on displays set to Default.
    @Published var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: "showNowPlaying") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showNowPlaying = defaults.object(forKey: "showNowPlaying") as? Bool ?? true
        overrides = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Override].self, from: $0) } ?? [:]
        displayInfo = defaults.data(forKey: Self.infoKey)
            .flatMap { try? JSONDecoder().decode([String: DisplayInfo].self, from: $0) } ?? [:]
    }

    // MARK: Resolution

    /// Default with this display's overrides applied; Default itself for an unknown display.
    func settings(for key: String?, defaults base: Settings) -> Settings {
        guard let key, let value = overrides[key] else { return base }
        return value.applied(to: base)
    }
    func isOverridden(_ setting: Setting, on key: String?) -> Bool {
        key.flatMap { overrides[$0]?.has(setting) } ?? false
    }
    func overrideCount(on key: String) -> Int { overrides[key]?.count ?? 0 }

    // MARK: Overrides (nil returns the setting to Default)

    func setBarOpacity(_ opacity: Double?, on key: String) {
        update(key) { $0.barOpacity = opacity.map { Self.clamp($0, Self.barOpacityRange) } }
    }
    func setWidgetOrder(_ order: [String]?, on key: String) {
        update(key) { $0.widgetOrder = order }
    }
    func setWidgetVisible(_ visible: Bool?, widget: String, on key: String) {
        guard !widget.isEmpty else { return }
        update(key) { $0.widgets[widget] = visible }
    }
    func setSeparator(_ shown: Bool?, after widget: String, on key: String) {
        guard !widget.isEmpty else { return }
        update(key) { $0.separators[widget] = shown }
    }
    func setShowNotch(_ shown: Bool?, on key: String) {
        update(key) { $0.nowPlaying = shown }
    }
    func setShowWhenIdle(_ shown: Bool?, on key: String) {
        update(key) { $0.showWhenIdle = shown }
    }
    func setNotchMatchesBar(_ matches: Bool?, on key: String) {
        update(key) { $0.notchMatchesBar = matches }
    }
    /// Sets a custom size (clamped to the allowed ranges), or nil to return to Default.
    func setNotchSize(_ size: NotchSize?, on key: String) {
        update(key) { $0.notchSize = size?.clamped }
    }
    func setExpandedExtraWidth(_ extra: Double?, on key: String) {
        update(key) { $0.expandedExtraWidth = extra.map { Self.clamp($0, Self.expandedExtraWidthRange) } }
    }
    func clear(_ setting: Setting, on key: String) {
        update(key) { $0.clear(setting) }
    }
    func clearAll(on key: String) {
        overrides.removeValue(forKey: key)
        persist()
    }

    // MARK: Known displays

    /// Remembers a display's name, kind and size; publishes only when something changed.
    func remember(_ info: DisplayInfo, for key: String) {
        guard !key.isEmpty, displayInfo[key] != info else { return }
        displayInfo[key] = info
        guard let data = try? JSONEncoder().encode(displayInfo) else { return }
        defaults.set(data, forKey: Self.infoKey)
    }
    /// Connected displays in the given order, then not-connected displays with overrides by name.
    func knownDisplays(connected: [(key: String, info: DisplayInfo)]) -> [KnownDisplay] {
        let connectedKeys = Set(connected.map(\.key))
        let present = connected.map {
            KnownDisplay(key: $0.key, info: $0.info, isConnected: true, overrideCount: overrideCount(on: $0.key))
        }
        let absent = overrides.keys
            .filter { !connectedKeys.contains($0) && overrideCount(on: $0) > 0 }
            .map { KnownDisplay(key: $0, info: displayInfo[$0], isConnected: false, overrideCount: overrideCount(on: $0)) }
            .sorted { ($0.name, $0.key) < ($1.name, $1.key) }
        return present + absent
    }

    // MARK: Legacy API (Displays and Notch panes)

    func widgetMode(_ widget: String, on key: String?) -> Mode { Mode(key.flatMap { overrides[$0]?.widgets[widget] }) }
    func nowPlayingMode(on key: String?) -> Mode { Mode(key.flatMap { overrides[$0]?.nowPlaying }) }
    func widgetVisible(_ widget: String, on key: String?, global: Bool) -> Bool {
        widgetMode(widget, on: key).value ?? global
    }
    func nowPlayingVisible(on key: String?) -> Bool {
        nowPlayingMode(on: key).value ?? showNowPlaying
    }
    func setWidgetMode(_ mode: Mode, widget: String, on key: String) {
        setWidgetVisible(mode.value, widget: widget, on: key)
    }
    func setNowPlayingMode(_ mode: Mode, on key: String) {
        setShowNotch(mode.value, on: key)
    }
    /// The display's custom notch size, or nil when it uses the global size.
    func notchSize(on key: String?) -> NotchSize? { key.flatMap { overrides[$0]?.notchSize } }
    func effectiveNotchSize(on key: String?, globalWidth: Double, globalHeight: Double) -> NotchSize {
        notchSize(on: key) ?? NotchSize(width: globalWidth, height: globalHeight)
    }
    func reset(_ key: String) { clearAll(on: key) }

    // MARK: Storage

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
    private func update(_ key: String, _ change: (inout Override) -> Void) {
        guard !key.isEmpty else { return }
        var value = overrides[key] ?? Override()
        change(&value)
        if value.count == 0 {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = value
        }
        persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
