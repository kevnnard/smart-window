import Foundation

@main struct FocusModeProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        let suite = "SmartWindow.FocusProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let focus = FocusMode(defaults: defaults)
        let displays = DisplayPreferences(defaults: defaults)
        let order = ["RAM", "CPU", "Keyboard"]
        let global = ["RAM": true, "CPU": false, "Keyboard": true]
        displays.setWidgetMode(.hide, widget: "RAM", on: "A")
        let overrides = displays.overrides
        func visible(on key: String) -> [String] {
            focus.visibleWidgets(in: order) { displays.widgetVisible($0, on: key, global: global[$0] ?? true) }
        }
        check(!focus.isEnabled && visible(on: "A") == ["Keyboard"], "default preserves display and global settings")
        check(visible(on: "B") == ["RAM", "Keyboard"], "default preserves original order")
        focus.isEnabled = true
        check(visible(on: "A").isEmpty && visible(on: "B").isEmpty, "focus hides secondary widgets on every screen")
        check(displays.nowPlayingVisible(on: "A"), "focus does not hide music")
        check(FocusMode(defaults: defaults).isEnabled, "focus survives relaunch")
        focus.isEnabled.toggle()
        check(visible(on: "A") == ["Keyboard"] && visible(on: "B") == ["RAM", "Keyboard"], "exit restores both screens")
        check(displays.overrides == overrides && order == ["RAM", "CPU", "Keyboard"] && global["CPU"] == false, "preferences are never overwritten")
        print("PASS: global focus filtering preserves widget order and display preferences")
    }
}
