import Foundation
import Combine

/// Additive preferences: absent overrides inherit the existing global settings.
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
    struct Override: Codable, Equatable {
        var widgets: [String: Bool] = [:]
        var nowPlaying: Bool?
        /// nil means Default: the display uses the global notch size. Optional so overrides saved
        /// before this field existed keep decoding.
        var notchSize: NotchSize?
    }
    private let defaults: UserDefaults
    private static let storageKey = "displayOverrides.v1"
    @Published private(set) var overrides: [String: Override]
    @Published var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: "showNowPlaying") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showNowPlaying = defaults.object(forKey: "showNowPlaying") as? Bool ?? true
        overrides = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Override].self, from: $0) } ?? [:]
    }

    func widgetMode(_ widget: String, on key: String?) -> Mode { Mode(key.flatMap { overrides[$0]?.widgets[widget] }) }
    func nowPlayingMode(on key: String?) -> Mode { Mode(key.flatMap { overrides[$0]?.nowPlaying }) }
    func widgetVisible(_ widget: String, on key: String?, global: Bool) -> Bool {
        widgetMode(widget, on: key).value ?? global
    }
    func nowPlayingVisible(on key: String?) -> Bool {
        nowPlayingMode(on: key).value ?? showNowPlaying
    }
    func setWidgetMode(_ mode: Mode, widget: String, on key: String) {
        guard !key.isEmpty, !widget.isEmpty else { return }
        var value = overrides[key] ?? Override()
        value.widgets[widget] = mode.value
        save(value, on: key)
    }
    func setNowPlayingMode(_ mode: Mode, on key: String) {
        guard !key.isEmpty else { return }
        var value = overrides[key] ?? Override()
        value.nowPlaying = mode.value
        save(value, on: key)
    }
    /// The display's custom notch size, or nil when it uses the global size.
    func notchSize(on key: String?) -> NotchSize? { key.flatMap { overrides[$0]?.notchSize } }
    func effectiveNotchSize(on key: String?, globalWidth: Double, globalHeight: Double) -> NotchSize {
        notchSize(on: key) ?? NotchSize(width: globalWidth, height: globalHeight)
    }
    /// Sets a custom size (clamped to the allowed ranges), or nil to return to Default.
    func setNotchSize(_ size: NotchSize?, on key: String) {
        guard !key.isEmpty else { return }
        var value = overrides[key] ?? Override()
        value.notchSize = size?.clamped
        save(value, on: key)
    }
    func reset(_ key: String) {
        overrides.removeValue(forKey: key)
        persist()
    }
    private func save(_ value: Override, on key: String) {
        if value.widgets.isEmpty && value.nowPlaying == nil && value.notchSize == nil {
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
