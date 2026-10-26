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
        print("PASS: per-display inheritance, isolation, persistence and reset")
    }
}
