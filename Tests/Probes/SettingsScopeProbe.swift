import Foundation

/// Bar & Notch page logic: which scope is edited, the scope line, row status text, the display map,
/// and the one-time move from "Main display only" to per-display Show notch.
@main struct SettingsScopeProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        typealias Known = DisplayPreferences.KnownDisplay
        let lgInfo = DisplayPreferences.DisplayInfo(name: "LG ULTRAWIDE", isBuiltIn: false, hasCameraNotch: false,
                                                    pixelWidth: 2560, pixelHeight: 1080)
        let macInfo = DisplayPreferences.DisplayInfo(name: "Built-in Retina Display", isBuiltIn: true, hasCameraNotch: true,
                                                     pixelWidth: 3024, pixelHeight: 1964)
        let lg = Known(key: "LG", info: lgInfo, isConnected: true, overrideCount: 3)
        let mac = Known(key: "MAC", info: macInfo, isConnected: false, overrideCount: 1)
        let plain = Known(key: "DELL", info: nil, isConnected: true, overrideCount: 0)

        // One known display: no map, edits go to Default (S7).
        check(!SettingsScope.showsMap(knownDisplays: []) && !SettingsScope.showsMap(knownDisplays: [lg]),
              "map hidden with zero or one display")
        check(SettingsScope.showsMap(knownDisplays: [lg, mac]), "map shown with two displays")
        check(SettingsScope.display("LG").resolved(in: [lg]) == .defaults, "one display edits Default")
        check(SettingsScope.display("LG").resolved(in: [lg, mac]) == .display("LG"), "a known display keeps its scope")
        check(SettingsScope.display("GONE").resolved(in: [lg, mac]) == .defaults, "an unknown display falls back to Default")
        check(SettingsScope.defaults.key == nil && SettingsScope.display("LG").key == "LG", "scope key")

        // Scope line (S4).
        let defaultLine = ScopeLine(scope: .defaults, known: [lg, mac, plain])
        check(defaultLine.text == "Default applies to every display without its own setting.", "Default scope text")
        check(defaultLine.links.map(\.key) == ["LG", "MAC"], "only displays with custom settings are linked")
        check(defaultLine.links.map(\.text) == ["LG ULTRAWIDE customizes 3 settings",
                                               "Built-in Retina Display customizes 1 setting"], "link text, singular and plural")
        check(defaultLine.resetTitle == nil && defaultLine.notConnectedNote == nil, "Default has no reset all")

        let lgLine = ScopeLine(scope: .display("LG"), known: [lg, mac])
        check(lgLine.text == "Editing LG ULTRAWIDE only." && lgLine.status == "3 custom" && lgLine.isCustom,
              "display scope text and count")
        check(lgLine.resetTitle == "Reset all settings for LG ULTRAWIDE" && lgLine.notConnectedNote == nil,
              "connected display with overrides offers reset all")
        let macLine = ScopeLine(scope: .display("MAC"), known: [lg, mac])
        check(macLine.notConnectedNote
              == "Built-in Retina Display is not connected. Its settings are remembered and apply when it reconnects.",
              "not-connected display explains remembered settings")
        let plainLine = ScopeLine(scope: .display("DELL"), known: [lg, plain])
        check(plainLine.status == "No custom settings — uses Default" && !plainLine.isCustom && plainLine.resetTitle == nil,
              "display without overrides uses Default")

        // Row status (S4): nothing in Default scope; Default or Custom in a display scope.
        check(SettingsText.rowStatus(scope: .defaults, isCustom: false, defaultValue: "94%") == nil, "no status in Default")
        check(SettingsText.rowStatus(scope: .display("LG"), isCustom: false, defaultValue: "94%") == "Default · 94%",
              "inherited row")
        check(SettingsText.rowStatus(scope: .display("LG"), isCustom: true, defaultValue: "94%") == "Custom · Default is 94%",
              "custom row")
        check(SettingsText.orderStatus(scope: .display("LG"), isCustom: false) == "Default order"
              && SettingsText.orderStatus(scope: .display("LG"), isCustom: true) == "Custom · differs from Default order"
              && SettingsText.orderStatus(scope: .defaults, isCustom: true) == nil, "widget order status")
        check(SettingsText.percent(0.94) == "94%" && SettingsText.percent(1) == "100%", "opacity text")
        check(SettingsText.points(280) == "280 pt" && SettingsText.size(.init(width: 280, height: 34)) == "280 × 34 pt",
              "size text")
        check(SettingsText.expanded(0) == "Same" && SettingsText.expanded(40) == "+40 pt", "expanded width text")
        check(SettingsText.onOff(true) == "On" && SettingsText.background(matchesBar: false) == "Black"
              && SettingsText.background(matchesBar: true) == "Match bar color", "toggle and background text")
        check(SettingsText.widget(visible: true, separator: true) == "Shown, separator after"
              && SettingsText.widget(visible: false, separator: false) == "Hidden", "widget text")
        check(SettingsText.resetLabel("Bar opacity") == "Reset Bar opacity to Default", "reset accessibility label")

        // Display map: aspect ratio kept inside the map box; badges.
        let wide = DisplayMap.monitorSize(for: lgInfo)
        check(wide.height == DisplayMap.monitorBox.height && wide.width <= DisplayMap.monitorBox.width
              && abs(wide.width / wide.height - 2560.0 / 1080.0) < 0.05, "ultrawide keeps its aspect ratio")
        let laptop = DisplayMap.monitorSize(for: macInfo)
        check(laptop.height == DisplayMap.monitorBox.height && abs(laptop.width - 123) <= 1, "laptop scaled to box height")
        check(DisplayMap.monitorSize(for: nil) == DisplayMap.defaultSize, "unknown size uses the Default card size")
        check(DisplayMap.monitorSize(for: .init(name: "x", isBuiltIn: false, hasCameraNotch: false, pixelWidth: 0,
                                                pixelHeight: 0)) == DisplayMap.defaultSize, "zero size is safe")
        let tall = DisplayMap.monitorSize(for: .init(name: "x", isBuiltIn: false, hasCameraNotch: false, pixelWidth: 100,
                                                     pixelHeight: 10_000))
        check(tall.width >= DisplayMap.minimumWidth, "a portrait display stays wide enough to click")
        check(DisplayMap.badge(overrideCount: 3) == "3 custom" && DisplayMap.badge(overrideCount: 0) == "Uses Default",
              "map badge")
        check(DisplayMap.accessibilityValue(mac) == "3024 × 1964, built-in, not connected, 1 custom setting",
              "map accessibility value")
        check(DisplayMap.accessibilityValue(lg) == "2560 × 1080, 3 custom settings"
              && DisplayMap.accessibilityValue(plain) == "uses Default", "accessibility value without overrides")

        // Tab counts split every override between Bar, Widgets and Notch.
        var override = DisplayPreferences.Override()
        override.barOpacity = 0.8
        override.widgetOrder = ["CPU"]
        override.widgets = ["GPU": true]
        override.separators = ["CPU": true]
        override.nowPlaying = false
        override.notchSize = .init(width: 300, height: 40)
        override.expandedExtraWidth = 40
        check(SettingsTab.bar.customCount(override) == 1 && SettingsTab.widgets.customCount(override) == 3
              && SettingsTab.notch.customCount(override) == 3, "custom count per tab")
        check(SettingsTab.allCases.map { $0.customCount(override) }.reduce(0, +) == override.count
              && SettingsTab.notch.customCount(nil) == 0, "tab counts add up to the display's count")
        check(SettingsTab.allCases.map(\.title) == ["Bar", "Widgets", "Notch"], "tab titles")

        // Preview scale of the notch pill.
        let pill = LivePreview.notchSize(.init(width: 280, height: 34))
        check(abs(pill.width - 168) < 0.01 && abs(pill.height - 20.4) < 0.01, "notch pill drawn at 60%")

        // "Main display only" becomes Show notch off on every other known display, once.
        let suite = "SmartWindow.Probe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = DisplayPreferences(defaults: defaults)
        check(!AppSettings.migrateMainDisplayOnly(defaults: defaults, preferences: prefs, primaryKey: "LG",
                                                  knownKeys: ["LG", "MAC"]),
              "nothing stored: nothing to migrate")
        check(prefs.overrides.isEmpty, "no overrides without the old setting")
        defaults.set(true, forKey: AppSettings.mainDisplayOnlyKey)
        check(!AppSettings.migrateMainDisplayOnly(defaults: defaults, preferences: prefs, primaryKey: "LG",
                                                  knownKeys: ["LG", "MAC"]) && prefs.overrides.isEmpty,
              "All displays: nothing to migrate")
        defaults.set(false, forKey: AppSettings.mainDisplayOnlyKey)
        prefs.setBarOpacity(0.8, on: "DELL")
        check(AppSettings.migrateMainDisplayOnly(defaults: defaults, preferences: prefs, primaryKey: "LG",
                                                 knownKeys: ["LG", "MAC", "DELL", "MAC"]), "Main display only migrates")
        let base = DisplayPreferences.Settings(barOpacity: 0.94, widgetOrder: [], widgetVisibility: [:], separators: [],
                                               showNotch: true, showWhenIdle: true, notchMatchesBar: false,
                                               notchSize: .init(width: 280, height: 34), expandedExtraWidth: 0)
        check(!prefs.settings(for: "MAC", defaults: base).showNotch && !prefs.settings(for: "DELL", defaults: base).showNotch,
              "every other display hides the notch")
        check(prefs.settings(for: "LG", defaults: base).showNotch && !prefs.isOverridden(.showNotch, on: "LG"),
              "the main display keeps Default")
        check(prefs.settings(for: "DELL", defaults: base).barOpacity == 0.8, "existing overrides kept")
        check(defaults.object(forKey: AppSettings.mainDisplayOnlyKey) as? Bool == true, "stored value becomes All displays")
        prefs.setShowNotch(true, on: "MAC")
        check(!AppSettings.migrateMainDisplayOnly(defaults: defaults, preferences: prefs, primaryKey: "LG",
                                                  knownKeys: ["LG", "MAC"])
              && prefs.settings(for: "MAC", defaults: base).showNotch, "runs once: later choices are not overwritten")
        let reloaded = DisplayPreferences(defaults: defaults)
        check(!reloaded.settings(for: "DELL", defaults: base).showNotch, "migrated overrides persist")
        // Without a primary display identity the old value is kept for a later launch.
        let later = "SmartWindow.Probe.\(UUID().uuidString)"
        let laterDefaults = UserDefaults(suiteName: later)!
        defer { laterDefaults.removePersistentDomain(forName: later) }
        laterDefaults.set(false, forKey: AppSettings.mainDisplayOnlyKey)
        let laterPrefs = DisplayPreferences(defaults: laterDefaults)
        check(!AppSettings.migrateMainDisplayOnly(defaults: laterDefaults, preferences: laterPrefs, primaryKey: nil,
                                                  knownKeys: ["MAC"])
              && laterDefaults.object(forKey: AppSettings.mainDisplayOnlyKey) as? Bool == false
              && laterPrefs.overrides.isEmpty, "no primary identity: wait")

        print("PASS: scope, scope line, row status, display map, preview scale and Main display only migration")
    }
}
