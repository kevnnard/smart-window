import Foundation

/// Every bar and notch setting resolves per display: a display without its own value uses Default.
@main struct PerDisplaySettingsProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        typealias Settings = DisplayPreferences.Settings
        let suite = "SmartWindow.Probe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let global = Settings(barOpacity: 0.94,
                              widgetOrder: ["RAM", "CPU", "GPU", "Battery"],
                              widgetVisibility: ["RAM": true, "CPU": true, "GPU": false, "Battery": true],
                              separators: ["Battery"],
                              showNotch: true,
                              showWhenIdle: true,
                              notchMatchesBar: false,
                              notchSize: .init(width: 280, height: 34),
                              expandedExtraWidth: 0)

        // Resolution: no override means Default, for every setting.
        let prefs = DisplayPreferences(defaults: defaults)
        check(prefs.settings(for: "A", defaults: global) == global, "a display without overrides uses Default")
        check(prefs.settings(for: nil, defaults: global) == global, "an unknown display uses Default")
        check(prefs.overrideCount(on: "A") == 0, "no overrides counted by default")
        check(global.isWidgetVisible("RAM") && !global.isWidgetVisible("GPU") && global.isWidgetVisible("Unlisted"),
              "widget visibility reads the map, missing widgets show")
        check(global.hasSeparator(after: "Battery") && !global.hasSeparator(after: "CPU"), "separator lookup")

        // Override every setting on A.
        prefs.setBarOpacity(0.7, on: "A")
        prefs.setWidgetOrder(["Battery", "CPU"], on: "A")
        prefs.setWidgetMode(.show, widget: "GPU", on: "A")
        prefs.setSeparator(true, after: "CPU", on: "A")
        prefs.setSeparator(false, after: "Battery", on: "A")
        prefs.setShowNotch(false, on: "A")
        prefs.setShowWhenIdle(false, on: "A")
        prefs.setNotchMatchesBar(true, on: "A")
        prefs.setNotchSize(.init(width: 400, height: 40), on: "A")
        prefs.setExpandedExtraWidth(120, on: "A")
        let a = prefs.settings(for: "A", defaults: global)
        check(a.barOpacity == 0.7, "opacity override")
        check(a.widgetOrder == ["Battery", "CPU", "RAM", "GPU"], "order override keeps every Default widget, missing ones appended")
        check(a.isWidgetVisible("GPU") && a.isWidgetVisible("RAM"), "visibility override merges with Default")
        check(a.hasSeparator(after: "CPU") && !a.hasSeparator(after: "Battery"), "separator overrides per widget")
        check(!a.showNotch && !a.showWhenIdle && a.notchMatchesBar, "notch flags override")
        check(a.notchSize == .init(width: 400, height: 40) && a.expandedExtraWidth == 120, "notch geometry override")
        check(prefs.settings(for: "B", defaults: global) == global, "other displays keep Default")
        check(prefs.overrideCount(on: "A") == 10, "count: 7 single settings + 1 widget + 2 separators")
        for setting: DisplayPreferences.Setting in [.barOpacity, .widgetOrder, .widget("GPU"), .separator("CPU"),
                                                    .separator("Battery"), .showNotch, .showWhenIdle, .notchBackground,
                                                    .notchSize, .expandedExtraWidth] {
            check(prefs.isOverridden(setting, on: "A"), "\(setting) is overridden on A")
            check(!prefs.isOverridden(setting, on: "B"), "\(setting) is not overridden on B")
        }
        check(!prefs.isOverridden(.widget("RAM"), on: "A") && !prefs.isOverridden(.barOpacity, on: nil),
              "untouched rows and unknown displays are not overridden")
        // Same value as Default is still an explicit choice (Custom) until cleared.
        prefs.setBarOpacity(0.94, on: "C")
        check(prefs.isOverridden(.barOpacity, on: "C") && prefs.overrideCount(on: "C") == 1, "custom equal to Default stays custom")

        // Clamping to the slider ranges.
        prefs.setBarOpacity(0.1, on: "C")
        prefs.setExpandedExtraWidth(999, on: "C")
        let c = prefs.settings(for: "C", defaults: global)
        check(c.barOpacity == DisplayPreferences.barOpacityRange.lowerBound
              && c.expandedExtraWidth == DisplayPreferences.expandedExtraWidthRange.upperBound, "values clamped")
        check(DisplayPreferences.barOpacityRange == 0.6...1.0 && DisplayPreferences.expandedExtraWidthRange == 0...200,
              "ranges match Settings sliders")

        // Default changes flow through to settings a display does not override.
        var changed = global
        changed.barOpacity = 0.8
        changed.showWhenIdle = true
        changed.notchSize = .init(width: 300, height: 36)
        let a2 = prefs.settings(for: "A", defaults: changed)
        check(a2.barOpacity == 0.7 && !a2.showWhenIdle && a2.notchSize.width == 400, "overrides win over a changed Default")
        check(prefs.settings(for: "B", defaults: changed) == changed, "non-overridden display follows the changed Default")

        // Clear one override.
        prefs.clear(.barOpacity, on: "A")
        prefs.clear(.widget("GPU"), on: "A")
        prefs.clear(.separator("CPU"), on: "A")
        prefs.clear(.notchSize, on: "A")
        let cleared = prefs.settings(for: "A", defaults: global)
        check(cleared.barOpacity == 0.94 && !cleared.isWidgetVisible("GPU") && !cleared.hasSeparator(after: "CPU")
              && cleared.notchSize == global.notchSize, "cleared settings return to Default")
        check(!prefs.isOverridden(.barOpacity, on: "A") && prefs.isOverridden(.widgetOrder, on: "A"),
              "clearing one keeps the others")
        check(prefs.overrideCount(on: "A") == 6, "count drops with each cleared override")
        prefs.setBarOpacity(nil, on: "C")
        prefs.setExpandedExtraWidth(nil, on: "C")
        check(prefs.overrideCount(on: "C") == 0 && prefs.overrides["C"] == nil, "setting nil clears; empty entry removed")

        // Persistence round trip of every new field.
        let reloaded = DisplayPreferences(defaults: defaults)
        check(reloaded.settings(for: "A", defaults: global) == prefs.settings(for: "A", defaults: global)
              && reloaded.overrideCount(on: "A") == 6, "relaunch keeps every new override")

        // Clear all for a display.
        reloaded.clearAll(on: "A")
        check(reloaded.overrideCount(on: "A") == 0 && reloaded.settings(for: "A", defaults: global) == global,
              "clear all returns the display to Default")
        check(DisplayPreferences(defaults: defaults).overrides["A"] == nil, "clear all persists")

        // Remembered displays: connected ones first, then not-connected ones that customize something.
        let mac = DisplayPreferences.DisplayInfo(name: "Built-in Retina Display", isBuiltIn: true, hasCameraNotch: true,
                                                 pixelWidth: 3024, pixelHeight: 1964)
        let dell = DisplayPreferences.DisplayInfo(name: "DELL U2723QE", isBuiltIn: false, hasCameraNotch: false,
                                                  pixelWidth: 3840, pixelHeight: 2160)
        let lg = DisplayPreferences.DisplayInfo(name: "LG UltraFine", isBuiltIn: false, hasCameraNotch: false,
                                                pixelWidth: 2560, pixelHeight: 1440)
        let known = DisplayPreferences(defaults: defaults)
        known.remember(mac, for: "MAC")
        known.remember(dell, for: "DELL")
        known.remember(lg, for: "LG")
        known.setBarOpacity(0.8, on: "DELL")
        known.setShowNotch(false, on: "DELL")
        let list = known.knownDisplays(connected: [(key: "MAC", info: mac)])
        check(list.map(\.key) == ["MAC", "DELL"], "connected first, then remembered displays with overrides")
        check(list[0].isConnected && !list[1].isConnected, "connection state reported")
        check(list[1].info == dell && list[1].name == "DELL U2723QE" && list[1].overrideCount == 2,
              "a not-connected display keeps its last known name, size and override count")
        check(DisplayPreferences(defaults: defaults).displayInfo["LG"] == lg, "remembered displays persist")
        // Overrides saved before names were remembered are still listed.
        known.setShowWhenIdle(false, on: "OLD")
        let withOld = known.knownDisplays(connected: [])
        check(withOld.map(\.key).contains("OLD") && withOld.first { $0.key == "OLD" }?.info == nil,
              "a display with overrides but no remembered name is listed")
        check(withOld.first { $0.key == "OLD" }?.name == "Display", "unnamed display gets a generic name")

        // Old displayOverrides.v1 data decodes unchanged.
        let legacySuite = "SmartWindow.Probe.\(UUID().uuidString)"
        let legacy = UserDefaults(suiteName: legacySuite)!
        defer { legacy.removePersistentDomain(forName: legacySuite) }
        legacy.set(Data(#"{"X":{"widgets":{"CPU":false},"nowPlaying":true,"notchSize":{"width":300,"height":40}},"Y":{"widgets":{}}}"#.utf8),
                   forKey: "displayOverrides.v1")
        let migrated = DisplayPreferences(defaults: legacy)
        let x = migrated.settings(for: "X", defaults: global)
        check(!x.isWidgetVisible("CPU") && x.showNotch && x.notchSize == .init(width: 300, height: 40), "legacy fields resolve")
        check(x.barOpacity == global.barOpacity && x.widgetOrder == global.widgetOrder && x.showWhenIdle == global.showWhenIdle
              && x.notchMatchesBar == global.notchMatchesBar && x.expandedExtraWidth == global.expandedExtraWidth,
              "fields missing from legacy data use Default")
        check(migrated.overrideCount(on: "X") == 3, "legacy overrides counted")
        check(migrated.widgetMode("CPU", on: "X") == .hide && migrated.nowPlayingMode(on: "X") == .show,
              "legacy API still reads legacy data")
        migrated.setBarOpacity(0.7, on: "X")
        let rewritten = DisplayPreferences(defaults: legacy)
        check(rewritten.overrideCount(on: "X") == 4 && rewritten.notchSize(on: "X") == .init(width: 300, height: 40),
              "saving a new field keeps the legacy fields")
        print("PASS: per-display resolution, override/clear/count, legacy decode and round trip")
    }
}
