import AppKit

// Device HUD (design/notch-device-hud/03-drop-card.html): device kinds, battery parsers, the change
// tracker, wings vs card, texts, the screen reader sentence and the device queue in the HUD state.
@main
@MainActor
struct DeviceHUDProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        // Kind: from the Bluetooth minor type, the HID usage and name hints; unknown is generic.
        check(DeviceKind(name: "Kevnnard's AirPods", minorType: "Headphones") == .airpods, "AirPods by name")
        check(DeviceKind(name: "WH-1000XM4", minorType: "Headphones") == .headphones, "headphones by minor type")
        check(DeviceKind(name: "Zone Vibe 125", minorType: "Headset") == .headset, "headset by minor type")
        check(DeviceKind(name: "BT5.0 Mouse", minorType: "Mouse") == .mouse, "mouse by minor type")
        check(DeviceKind(name: "NuPhy Air75 V2", minorType: "Keyboard") == .keyboard, "keyboard by minor type")
        check(DeviceKind(name: "Magic Trackpad", minorType: nil) == .trackpad, "trackpad by name")
        check(DeviceKind(name: "Pad", minorType: "Pointing") == .trackpad, "Pointing minor type is a trackpad")
        check(DeviceKind(name: "Xbox Wireless Controller", minorType: "Gamepad") == .gameController, "gamepad")
        check(DeviceKind(name: "Stick", minorType: "Joystick") == .gameController, "joystick")
        check(DeviceKind(name: "HC-05", minorType: "Uncategorized") == .generic, "unknown minor type is generic")
        check(DeviceKind(name: "HC-05", minorType: nil) == .generic, "nothing known is generic")
        check(DeviceKind(name: "Thing", usagePage: 0x01, usage: 0x02) == .mouse, "HID mouse")
        check(DeviceKind(name: "Thing", usagePage: 0x01, usage: 0x06) == .keyboard, "HID keyboard")
        check(DeviceKind(name: "Thing", usagePage: 0x01, usage: 0x04) == .gameController, "HID joystick")
        check(DeviceKind(name: "Thing", usagePage: 0x01, usage: 0x05) == .gameController, "HID gamepad")
        check(DeviceKind(name: "Thing", usagePage: 0x0D, usage: 0x05) == .trackpad, "HID digitizer touch pad")
        check(DeviceKind(name: "Thing", usagePage: 0xFF00, usage: 0x01) == .generic, "vendor HID usage is generic")
        let symbols = DeviceKind.allCases.map(\.symbolName)
        check(!symbols.contains(""), "every kind has an SF Symbol")
        for kind in DeviceKind.allCases {
            check(NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) != nil,
                  "\(kind) symbol \(kind.symbolName) exists")
        }

        // system_profiler SPBluetoothDataType -json.
        let profiler = Data("""
        {"SPBluetoothDataType":[{
          "controller_properties":{"controller_address":"00:11:22:33:44:55"},
          "device_connected":[
            {"Kevnnard's AirPods":{"device_address":"AA:BB:CC:DD:EE:01","device_minorType":"Headphones",
              "device_batteryLevelLeft":"80%","device_batteryLevelRight":"76%","device_batteryLevelCase":"45%"}},
            {"BT5.0 Mouse":{"device_address":"aa:bb:cc:dd:ee:02","device_minorType":"Mouse"}},
            {"NuPhy Air75 V2":{"device_address":"AA:BB:CC:DD:EE:03","device_minorType":"Keyboard",
              "device_batteryLevelMain":"62%"}},
            {"Broken":"not a dictionary"}
          ],
          "device_not_connected":[
            {"Old Speaker":{"device_address":"AA:BB:CC:DD:EE:09","device_minorType":"Speaker"}}
          ]
        }]}
        """.utf8)
        let bluetooth = DeviceParsers.bluetoothDevices(fromSystemProfiler: profiler)
        check(bluetooth.count == 3, "reads the three connected devices, not the disconnected one, got \(bluetooth.count)")
        let pods = bluetooth[0]
        check(pods.id == "AA:BB:CC:DD:EE:01" && pods.name == "Kevnnard's AirPods" && pods.kind == .airpods
              && pods.transport == .bluetooth, "AirPods identity, got \(pods)")
        check(pods.batteries.map(\.part) == [.left, .right, .chargingCase], "AirPods parts in order L/R/Case")
        check(pods.batteries.map(\.level) == [80, 76, 45], "AirPods levels, got \(pods.batteries.map(\.level))")
        let mouse = bluetooth[1]
        check(mouse.id == "AA:BB:CC:DD:EE:02", "Bluetooth addresses are normalized to upper case, got \(mouse.id)")
        check(mouse.kind == .mouse && mouse.batteries.isEmpty, "mouse without battery")
        check(bluetooth[2].batteries == [DeviceBattery(part: .main, level: 62)], "keyboard main battery")
        // A bud reported without the case: the case is a part that reports nothing, never 0 %.
        let noCase = DeviceParsers.bluetoothDevices(fromSystemProfiler: Data("""
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_address":"AA:BB:CC:DD:EE:04",
          "device_batteryLevelLeft":"80 %","device_batteryLevelRight":76}}]}]}
        """.utf8))
        check(noCase.first?.batteries.map(\.level) == [80, 76, nil], "case not reported is nil")
        let onePart = DeviceParsers.bluetoothDevices(fromSystemProfiler: Data("""
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods":{"device_address":"AA:BB:CC:DD:EE:04",
          "device_batteryLevelLeft":"80 %"}}]}]}
        """.utf8))
        check(onePart.first.map { DeviceHUDPresentation(DeviceEvent(change: .connected, device: $0)).style } == .wings,
              "only one reported battery uses wings, even if its name is AirPods")
        check(DeviceParsers.bluetoothDevices(fromSystemProfiler: Data("garbage".utf8)).isEmpty, "garbage reads nothing")
        check(DeviceParsers.bluetoothDevices(fromSystemProfiler: Data("{}".utf8)).isEmpty, "no data type reads nothing")
        check(DeviceParsers.bluetoothDevices(fromSystemProfiler: Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty,
              "no connected list reads nothing")
        check(DeviceParsers.bluetoothDevices(fromSystemProfiler: Data(#"""
        {"SPBluetoothDataType":[{"device_connected":[{"X":{"device_batteryLevelMain":"80%"}}]}]}
        """#.utf8)).isEmpty, "a device without an address is skipped")
        check(DeviceParsers.percent("101%") == 100 && DeviceParsers.percent("-5") == 0
              && DeviceParsers.percent("n/a") == nil && DeviceParsers.percent(nil) == nil, "percent parsing")

        // ioreg HID battery dictionaries (AppleDeviceManagementHIDEventService).
        let hid = DeviceParsers.hidDevices(fromRegistry: [
            ["Product": "Magic Trackpad", "BatteryPercent": 8, "BatteryStatusFlags": 0,
             "DeviceAddress": "aa-bb-cc-dd-ee-05", "Transport": "Bluetooth",
             "PrimaryUsagePage": 0x0D, "PrimaryUsage": 0x05],
            ["Product": "Magic Keyboard", "BatteryPercent": 55, "BatteryStatusFlags": 3,
             "SerialNumber": "F0T123", "Transport": "USB", "PrimaryUsagePage": 0x01, "PrimaryUsage": 0x06],
            ["BatteryPercent": "garbage"],
        ])
        check(hid.count == 2, "reads the two HID devices, got \(hid.count)")
        check(hid[0].id == "AA:BB:CC:DD:EE:05" && hid[0].kind == .trackpad && hid[0].transport == .bluetooth,
              "HID address is normalized like Bluetooth, got \(hid[0].id)")
        check(hid[0].batteries == [DeviceBattery(part: .main, level: 8)], "trackpad battery without an explicit charging state")
        check(hid[1].id == "F0T123" && hid[1].transport == .usb && hid[1].kind == .keyboard, "USB keyboard by serial")
        check(hid[1].batteries.first?.isCharging == nil, "undocumented status bits never invent a charging state")
        let explicitCharging = DeviceParsers.hidDevices(fromRegistry: [[
            "Product": "Magic Keyboard", "DeviceAddress": "AA:BB:CC:DD:EE:03", "Transport": "Bluetooth",
            "BatteryPercent": 55, "BatteryIsCharging": true,
        ]])
        check(explicitCharging.first?.batteries.first?.isCharging == true, "an explicit charging boolean is respected")
        let chargedMerge = DeviceParsers.merge(bluetooth: [bluetooth[2]], hid: explicitCharging)
        check(chargedMerge.first?.batteries.first?.isCharging == true, "HID fills charging even when Bluetooth reports a level")
        check(DeviceParsers.hidDevices(fromPlist: Data("garbage".utf8)).isEmpty, "garbage ioreg plist reads nothing")
        // The Bluetooth list wins; HID adds batteries it lacks and devices it does not know.
        let merged = DeviceParsers.merge(bluetooth: bluetooth + [DeviceInfo(id: "AA:BB:CC:DD:EE:05", name: "Magic Trackpad",
                                                                            kind: .trackpad, batteries: [], transport: .bluetooth)],
                                         hid: hid)
        check(merged.count == 5, "merge keeps one entry per device, got \(merged.count)")
        check(merged[3].batteries.first?.level == 8, "HID fills a Bluetooth device's missing battery")

        // Tracker: nothing at launch, then connects, disconnects and low crossings.
        var tracker = DeviceChangeTracker()
        let keyboard = device("K", "NuPhy Air75 V2", .keyboard, [DeviceBattery(part: .main, level: 62)])
        check(tracker.update([keyboard, mouse]).isEmpty, "devices connected at launch are not announced")
        check(tracker.update([keyboard, mouse]).isEmpty, "no change, nothing")
        check(tracker.update([keyboard, mouse, pods]) == [DeviceEvent(change: .connected, device: pods)], "AirPods connect")
        check(tracker.update([keyboard, pods]) == [DeviceEvent(change: .disconnected, device: mouse)], "mouse disconnects")
        // The last known info names a disconnect even when the snapshot changed it.
        let podsLater = device(pods.id, pods.name, .airpods, [])
        _ = tracker.update([keyboard, podsLater])
        check(tracker.update([keyboard]) == [DeviceEvent(change: .disconnected, device: podsLater)],
              "disconnect keeps the last known name and kind")
        check(tracker.update([level(keyboard, 21)]).isEmpty, "21 % is not low")
        let at20 = level(keyboard, 20)
        check(tracker.update([at20]) == [DeviceEvent(change: .droppedLow, device: at20)], "dropping to 20 % is low")
        check(tracker.update([level(keyboard, 15)]).isEmpty, "still low, announced once")
        let at10 = level(keyboard, 10)
        check(tracker.update([at10]) == [DeviceEvent(change: .droppedLow, device: at10)], "dropping to 10 % is red")
        check(tracker.update([level(keyboard, 5)]).isEmpty, "still red, announced once")
        check(tracker.update([level(keyboard, 15)]).isEmpty, "charging a bit below 20 does not re-arm")
        check(tracker.update([level(keyboard, 9)]).count == 1, "a new crossing from 15 to 9 announces the critical tier again")
        check(tracker.update([level(keyboard, 40)]).isEmpty, "recharging above 20 re-arms, silently")
        check(tracker.update([level(keyboard, 18)]).count == 1, "after re-arming a new crossing is announced")
        // The lowest part counts; a charging part is not dropping.
        var buds = DeviceChangeTracker()
        _ = buds.update([pods])
        let lowLeft = device(pods.id, pods.name, .airpods,
                             [DeviceBattery(part: .left, level: 9), DeviceBattery(part: .right, level: 31),
                              DeviceBattery(part: .chargingCase, level: nil)])
        check(buds.update([lowLeft]) == [DeviceEvent(change: .droppedLow, device: lowLeft)], "one bud at 9 % straight to red")
        var charging = DeviceChangeTracker()
        _ = charging.update([keyboard])
        check(charging.update([device("K", "NuPhy Air75 V2", .keyboard,
                                      [DeviceBattery(part: .main, level: 15, isCharging: true)])]).isEmpty,
              "a charging battery under 20 is not dropping")
        // Battery known later: no second connect, and the first reading is a baseline.
        var late = DeviceChangeTracker()
        _ = late.update([])
        let bare = device("M", "BT5.0 Mouse", .mouse, [])
        check(late.update([bare]) == [DeviceEvent(change: .connected, device: bare)], "connect without battery")
        check(late.update([level(bare, 15)]).isEmpty, "battery read later is not a second connect nor a drop")
        check(late.update([level(bare, 8)]).count == 1, "a later real crossing is announced")
        // Connecting already low: the connect says Low, no extra drop right after.
        var lowConnect = DeviceChangeTracker()
        _ = lowConnect.update([])
        let zone = device("Z", "Zone Vibe 125", .headset, [DeviceBattery(part: .main, level: 18)])
        check(lowConnect.update([zone]).map(\.change) == [.connected], "low on connect is one connect")
        check(lowConnect.update([zone]).isEmpty, "and nothing after it")
        // Reconnecting announces again; several changes at once all come out.
        _ = lowConnect.update([])
        check(lowConnect.update([zone, keyboard]).map(\.change) == [.connected, .connected], "wake from sleep")

        // Presentation: two or more parts drop the card; everything else is the wings.
        let podsCard = DeviceHUDPresentation(DeviceEvent(change: .connected, device: pods))
        check(podsCard.style == .card && podsCard.duration == 3, "AirPods drop the card for 3 s")
        check(podsCard.title == "Kevnnard's AirPods" && podsCard.valueText == "Connected", "card title and wing text")
        check(podsCard.parts.map(\.text) == ["80%", "76%", "45%"] && podsCard.parts.map(\.label) == ["Left", "Right", "Case"],
              "one ring per part")
        let noCaseCard = DeviceHUDPresentation(DeviceEvent(change: .connected, device: noCase[0]))
        check(noCaseCard.style == .card, "two reported parts plus an empty one still drop the card")
        check(noCaseCard.parts[2].text == "Not reported" && noCaseCard.parts[2].level == nil, "nothing reported, never 0 %")
        let lowCard = DeviceHUDPresentation(DeviceEvent(change: .droppedLow, device: lowLeft))
        check(lowCard.valueText == "Low battery" && lowCard.tone == .red && lowCard.isLow, "LOW BATTERY tag in red")
        check(lowCard.parts[0].isLow && lowCard.parts[0].tone == .red && !lowCard.parts[1].isLow, "the low bud is red")
        let caseCharging = device(pods.id, pods.name, .airpods,
                                  [DeviceBattery(part: .left, level: 80), DeviceBattery(part: .right, level: 76),
                                   DeviceBattery(part: .chargingCase, level: 45, isCharging: true)])
        let chargingCard = DeviceHUDPresentation(DeviceEvent(change: .connected, device: caseCharging))
        check(chargingCard.parts[2].isCharging && chargingCard.parts[2].tone == .charging
              && !chargingCard.parts[0].isCharging, "bolt on the charging part only")
        let podsOff = DeviceHUDPresentation(DeviceEvent(change: .disconnected, device: pods))
        check(podsOff.style == .wings && podsOff.duration == 2, "disconnects never drop a card")
        check(podsOff.valueText == "Disconnected" && podsOff.tone == .off && podsOff.indicator == .hollowDot,
              "gray, hollow dot, Disconnected")
        let kbd = DeviceHUDPresentation(DeviceEvent(change: .connected, device: keyboard))
        check(kbd.style == .wings && kbd.duration == 2 && kbd.valueText == "62%" && kbd.tone == .normal
              && kbd.lowTag == nil && kbd.indicator == .battery(level: 62), "single battery in the wings")
        let noBattery = DeviceHUDPresentation(DeviceEvent(change: .connected, device: mouse))
        check(noBattery.valueText == "Connected" && noBattery.indicator == .connectedDot && noBattery.tone == .normal,
              "no battery: green dot and Connected")
        let amber = DeviceHUDPresentation(DeviceEvent(change: .connected, device: zone))
        check(amber.valueText == "18%" && amber.tone == .amber && amber.lowTag == "Low", "≤ 20 % is amber with Low")
        let red = DeviceHUDPresentation(DeviceEvent(change: .droppedLow, device: level(keyboard, 10)))
        check(red.tone == .red && red.lowTag == "Low", "≤ 10 % is red with Low")
        check(DeviceHUDPresentation(DeviceEvent(change: .connected, device: level(keyboard, 21))).tone == .normal,
              "21 % is white")
        let kbdCharging = DeviceHUDPresentation(DeviceEvent(change: .connected, device: device(
            "K", "NuPhy Air75 V2", .keyboard, [DeviceBattery(part: .main, level: 15, isCharging: true)])))
        check(kbdCharging.tone == .charging && kbdCharging.isCharging && kbdCharging.lowTag == nil,
              "charging is green with a bolt, not Low")
        check(kbd.symbolName == DeviceKind.keyboard.symbolName, "wings icon by kind")

        // One sentence for screen readers.
        check(podsCard.accessibilityLabel
              == "Kevnnard's AirPods, earbuds, connected. Left 80 percent. Right 76 percent. Case 45 percent.",
              "card sentence, got \(podsCard.accessibilityLabel)")
        check(noCaseCard.accessibilityLabel.hasSuffix("Case not reported."), "not reported is said")
        check(lowCard.accessibilityLabel.contains("battery low. Left 9 percent, low."), "low card sentence")
        check(chargingCard.accessibilityLabel.contains("Case 45 percent, charging."), "charging part sentence")
        check(kbd.accessibilityLabel == "NuPhy Air75 V2, keyboard, connected. Battery 62 percent.", "wings sentence")
        check(amber.accessibilityLabel == "Zone Vibe 125, headset, connected. Battery 18 percent, low.", "low wings sentence")
        check(noBattery.accessibilityLabel == "BT5.0 Mouse, mouse, connected. No battery level reported.",
              "no battery sentence, got \(noBattery.accessibilityLabel)")
        check(podsOff.accessibilityLabel == "Kevnnard's AirPods, earbuds, disconnected.", "disconnect sentence")

        // HUD event: a .device kind next to volume, brightness and Focus.
        let podsEvent = SystemHUDEvent(device: DeviceEvent(change: .connected, device: pods))
        let kbdEvent = SystemHUDEvent(device: DeviceEvent(change: .connected, device: keyboard))
        let mouseEvent = SystemHUDEvent(device: DeviceEvent(change: .connected, device: mouse))
        check(podsEvent.kind == .device && podsEvent.device?.device == pods, "device HUD event")
        check(kbdEvent.valueText == "62%" && kbdEvent.symbolName == DeviceKind.keyboard.symbolName, "device wing values")
        check(podsEvent != kbdEvent, "different devices are different events")
        let volume = SystemHUDEvent(kind: .volume, level: 0.5, muted: false)
        check(volume.device == nil && volume.valueText == "50", "volume events are unchanged")

        // Queue: device events take turns; wings 2 s, card 3 s (scaled down here).
        let scale = 0.04
        let state = SystemHUDState(hideDelay: 0.08, deviceTimeScale: scale)
        check(state.duration(of: podsEvent) == 3 * scale && state.duration(of: kbdEvent) == 2 * scale
              && state.duration(of: volume) == 0.08, "durations: card 3 s, wings 2 s, volume the hide delay")
        state.show(podsEvent)
        state.show(kbdEvent)
        state.show(mouseEvent)
        check(state.event == podsEvent && state.queuedCount == 2, "the first device shows, two wait")
        wait(0.08)
        check(state.event == podsEvent, "the card stays its full 3 s, not cut by the next device")
        wait(0.07)
        check(state.event == kbdEvent, "then the keyboard has its turn")
        wait(0.1)
        check(state.event == mouseEvent, "then the mouse")
        wait(0.12)
        check(state.event == nil && state.queuedCount == 0, "all shown, hidden")
        // Volume still replaces at once; the device queue carries on after it.
        state.show(podsEvent)
        state.show(kbdEvent)
        state.show(volume)
        check(state.event == volume, "volume replaces the device at once")
        wait(0.06)
        check(state.event == volume, "volume keeps its own delay")
        wait(0.1)
        check(state.event == kbdEvent, "the waiting device shows after the volume")
        wait(0.12)
        check(state.event == nil, "hidden after the queue")
        // A device arriving while volume shows replaces it like any change.
        state.show(volume)
        state.show(mouseEvent)
        check(state.event == mouseEvent, "a device replaces volume at once")
        wait(0.12)
        check(state.event == nil, "and hides after 2 s")

        // Existing replace behavior is unchanged with the default API.
        let plain = SystemHUDState(hideDelay: 0.08)
        let silent = SystemHUDEvent(kind: .volume, level: 0, muted: false)
        plain.show(volume)
        wait(0.05)
        plain.show(silent)
        wait(0.05)
        check(plain.event == silent, "a new change restarts the timer")
        wait(0.08)
        check(plain.event == nil, "hides after the delay")

        print("PASS: DeviceHUDProbe verified")
    }

    static func device(_ id: String, _ name: String, _ kind: DeviceKind, _ batteries: [DeviceBattery]) -> DeviceInfo {
        DeviceInfo(id: id, name: name, kind: kind, batteries: batteries, transport: .bluetooth)
    }

    static func level(_ info: DeviceInfo, _ level: Int) -> DeviceInfo {
        device(info.id, info.name, info.kind, [DeviceBattery(part: .main, level: level)])
    }

    static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
