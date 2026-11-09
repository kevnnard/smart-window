import AppKit

// Focus HUD (design/notch-focus-hud/01-focus-wings.html): reading the Focus database, telling
// changes apart, and what the wings show.
@main
@MainActor
struct FocusHUDProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        // ~/Library/DoNotDisturb/DB/ModeConfigurations.json: every Focus with its name, symbol and color.
        let configurations = Data("""
        {"data":[{"modeConfigurations":{
          "com.apple.focus.work":{"mode":{"name":"Work","modeIdentifier":"com.apple.focus.work",
            "symbolImageName":"briefcase.fill","tintColorName":"systemTealColor"}},
          "com.apple.sleep.sleep-mode":{"mode":{"name":"Sleep","modeIdentifier":"com.apple.sleep.sleep-mode",
            "symbolImageName":"bed.double.fill","tintColorName":"systemMintColor"}}
        }}]}
        """.utf8)
        let modes = FocusDatabase.modes(fromConfigurations: configurations)
        check(modes.count == 2, "reads both Focus modes, got \(modes.count)")
        let work = FocusModeDescriptor(identifier: "com.apple.focus.work", name: "Work",
                                       symbolName: "briefcase.fill", tintColorName: "systemTealColor")
        check(modes["com.apple.focus.work"] == work, "Work keeps its name, symbol and color")
        check(FocusDatabase.modes(fromConfigurations: Data("not json".utf8)).isEmpty, "bad JSON reads no modes")

        // ~/Library/DoNotDisturb/DB/Assertions.json: the Focus turned on by hand, latest last.
        let active = Data("""
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.sleep.sleep-mode"},"assertionStartDateTimestamp":10},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"},"assertionStartDateTimestamp":20}
        ]}]}
        """.utf8)
        check(FocusDatabase.activeIdentifier(fromAssertions: active) == "com.apple.focus.work",
              "the latest assertion is the active Focus")
        check(FocusDatabase.activeIdentifier(fromAssertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)) == nil,
              "no assertion, no Focus")
        check(FocusDatabase.activeIdentifier(fromAssertions: Data(#"{"data":[{}]}"#.utf8)) == nil, "empty store, no Focus")
        check(FocusDatabase.active(assertions: active, configurations: configurations) == work, "active Focus details")
        let custom = Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"x.custom"}}]}]}"#.utf8)
        let unknown = FocusDatabase.active(assertions: custom, configurations: configurations)
        check(unknown?.identifier == "x.custom" && unknown?.name == "Focus" && unknown?.symbolName == "moon.fill",
              "a Focus without configuration still shows, as a generic Focus")

        // The database names the Focus; the public status still catches a Focus it does not list,
        // such as one turned on by a schedule.
        check(FocusDatabase.resolve(database: work, publicFocused: false) == work, "the database wins")
        check(FocusDatabase.resolve(database: nil, publicFocused: true) == .generic, "public status fills the gap")
        check(FocusDatabase.resolve(database: nil, publicFocused: false) == nil, "both off")
        check(FocusDatabase.resolve(database: nil, publicFocused: nil) == nil, "no public status, no Focus")

        // Changes: the first reading is the starting point; on, off and switching each show once.
        let sleep = modes["com.apple.sleep.sleep-mode"]!
        var tracker = FocusChangeTracker()
        check(tracker.update(work) == nil, "the Focus already on at launch is not announced")
        check(tracker.update(work) == nil, "the same Focus is not a change")
        check(tracker.update(nil) == SystemHUDEvent(focus: work, isOn: false), "turning Work off shows Work Off")
        check(tracker.update(nil) == nil, "still off")
        check(tracker.update(sleep) == SystemHUDEvent(focus: sleep, isOn: true), "turning Sleep on shows Sleep On")
        check(tracker.update(work) == SystemHUDEvent(focus: work, isOn: true), "switching shows the new Focus")

        // What the wings show.
        let on = SystemHUDEvent(focus: work, isOn: true)
        check(on.kind == .focus && on.symbolName == "briefcase.fill" && on.valueText == "On", "Focus on")
        check(SystemHUDEvent(focus: work, isOn: false).valueText == "Off", "Focus off")
        check(work.tintColor == .systemTeal, "Apple's color names map to system colors")
        check(FocusModeDescriptor.generic.tintColor == .systemIndigo, "the generic Focus is indigo like Do Not Disturb")
        check(FocusModeDescriptor(identifier: "a", name: "A", symbolName: "moon.fill", tintColorName: "nope").tintColor
              == .systemIndigo, "an unknown color falls back to indigo")

        // Settings → Notch tells whether the Focus name can be read and opens Full Disk Access.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("focus-probe-\(getpid())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        check(!FocusDatabase.canRead(directory: folder), "no Assertions.json, no access")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("Assertions.json").path, contents: Data("{}".utf8))
        check(FocusDatabase.canRead(directory: folder), "a readable Assertions.json means access")
        check(FocusDatabase.fullDiskAccessSettingsURL.absoluteString
              == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
              "opens Privacy & Security → Full Disk Access")

        print("PASS: FocusHUDProbe verified")
    }
}
