import Foundation

@main struct DisplayPreferencesProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        let suite = "SmartWindow.Probe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = DisplayPreferences(defaults: defaults)
        check(prefs.widgetVisible("CPU", on: "A", global: true), "default inherits enabled widget")
        check(!prefs.widgetVisible("GPU", on: "A", global: false), "default inherits disabled widget")
        prefs.setWidgetMode(.hide, widget: "CPU", on: "A")
        check(!prefs.widgetVisible("CPU", on: "A", global: true), "screen A override hides widget")
        check(prefs.widgetVisible("CPU", on: "B", global: true), "screen B remains unchanged")
        prefs.setWidgetMode(.show, widget: "GPU", on: "A")
        check(prefs.widgetVisible("GPU", on: "A", global: false), "explicit show overrides global")
        prefs.setNowPlayingMode(.hide, on: "B")
        check(!prefs.nowPlayingVisible(on: "B") && prefs.nowPlayingVisible(on: "A"), "media independently scoped")
        prefs.showNowPlaying = false
        prefs.setNowPlayingMode(.show, on: "A")
        check(prefs.nowPlayingVisible(on: "A") && !prefs.nowPlayingVisible(on: "C"), "media default and explicit show")
        let reloaded = DisplayPreferences(defaults: defaults)
        check(reloaded.widgetMode("CPU", on: "A") == .hide && reloaded.nowPlayingMode(on: "A") == .show && !reloaded.showNowPlaying, "relaunch persists display overrides")
        reloaded.setWidgetMode(.inherit, widget: "CPU", on: "A")
        check(reloaded.widgetVisible("CPU", on: "A", global: true) && !reloaded.widgetVisible("CPU", on: "A", global: false), "reset inherits future global changes")
        reloaded.reset("A")
        check(reloaded.widgetMode("GPU", on: "A") == .inherit && reloaded.nowPlayingMode(on: "A") == .inherit, "reset removes only target display")
        check(reloaded.nowPlayingMode(on: "B") == .hide, "reset preserves other displays")
        check(reloaded.widgetVisible("CPU", on: nil, global: true), "unknown display inherits global")
        // Per-display notch size: Default inherits the global size, Custom overrides one display.
        let sizes = DisplayPreferences(defaults: defaults)
        check(sizes.notchSize(on: "A") == nil, "notch size defaults to the global size")
        check(sizes.effectiveNotchSize(on: "A", globalWidth: 280, globalHeight: 34) == .init(width: 280, height: 34),
              "Default display uses the global size")
        sizes.setNotchSize(.init(width: 400, height: 40), on: "A")
        check(sizes.effectiveNotchSize(on: "A", globalWidth: 280, globalHeight: 34) == .init(width: 400, height: 40),
              "Custom display uses its own size")
        check(sizes.effectiveNotchSize(on: "B", globalWidth: 280, globalHeight: 34) == .init(width: 280, height: 34),
              "other displays keep the global size")
        check(sizes.effectiveNotchSize(on: nil, globalWidth: 300, globalHeight: 36) == .init(width: 300, height: 36),
              "unknown display uses the global size")
        sizes.setNotchSize(.init(width: 9999, height: 1), on: "C")
        check(sizes.notchSize(on: "C") == .init(width: DisplayPreferences.NotchSize.widthRange.upperBound,
                                                height: DisplayPreferences.NotchSize.heightRange.lowerBound),
              "custom size is clamped to the allowed range")
        check(DisplayPreferences(defaults: defaults).notchSize(on: "A") == .init(width: 400, height: 40),
              "relaunch persists the custom size")
        sizes.setNotchSize(nil, on: "C")
        check(sizes.notchSize(on: "C") == nil && sizes.overrides["C"] == nil, "Default removes an override that holds nothing else")
        sizes.reset("A")
        check(sizes.notchSize(on: "A") == nil, "reset clears the custom size")

        // Data saved before notch sizes existed still loads.
        let legacySuite = "SmartWindow.Probe.\(UUID().uuidString)"
        let legacy = UserDefaults(suiteName: legacySuite)!
        defer { legacy.removePersistentDomain(forName: legacySuite) }
        legacy.set(Data(#"{"X":{"widgets":{"CPU":false},"nowPlaying":true}}"#.utf8), forKey: "displayOverrides.v1")
        let migrated = DisplayPreferences(defaults: legacy)
        check(migrated.widgetMode("CPU", on: "X") == .hide && migrated.nowPlayingMode(on: "X") == .show
              && migrated.notchSize(on: "X") == nil, "legacy overrides decode without a notch size")
        print("PASS: per-display inheritance, isolation, persistence and reset")
    }
}
