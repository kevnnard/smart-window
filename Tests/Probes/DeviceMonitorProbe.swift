import Foundation

// Device monitor (odd/tasks/device-hud.md T2): which HID services count as devices (S1), when the
// monitor reads and announces (S5, S8), and the Bluetooth permission (S9).
@main
@MainActor
struct DeviceMonitorProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    /// Timers the probe fires by moving time forward.
    @MainActor
    final class FakeClock {
        var now: TimeInterval = 0
        private var pending: [(id: Int, fire: TimeInterval, action: @MainActor () -> Void)] = []
        private var nextID = 0

        func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> DeviceMonitorTimer {
            nextID += 1
            let id = nextID
            pending.append((id, now + delay, action))
            return DeviceMonitorTimer { [weak self] in self?.pending.removeAll { $0.id == id } }
        }

        func advance(by seconds: TimeInterval) {
            let end = now + seconds
            while let next = pending.filter({ $0.fire <= end + 0.000_1 }).min(by: { $0.fire < $1.fire }) {
                pending.removeAll { $0.id == next.id }
                now = next.fire
                next.action()
            }
            now = end
        }
    }

    static func main() {
        // S1: built-in, internal, hub and virtual HID services are not devices.
        let internalKeyboard: [String: Any] = ["Product": "Apple Internal Keyboard / Trackpad", "Built-In": true,
                                               "Transport": "FIFO", "LocationID": 111, "PrimaryUsagePage": 1,
                                               "PrimaryUsage": 6]
        let builtInHeadset: [String: Any] = ["Product": "Headset", "Built-In": 1, "Transport": "Audio",
                                             "PrimaryUsagePage": 12, "PrimaryUsage": 1, "IORegistryEntryID": 9]
        let spiTrackpad: [String: Any] = ["Product": "Trackpad", "Transport": "SPI", "LocationID": 7]
        let touchBar: [String: Any] = ["Product": "Touch Bar Display", "Transport": "USB", "LocationID": 8]
        let t2: [String: Any] = ["Product": "Apple T2 Controller", "Transport": "USB", "LocationID": 10]
        let hub: [String: Any] = ["Product": "USB2.0 Hub", "Transport": "USB", "LocationID": 11]
        let virtual: [String: Any] = ["Product": "Karabiner DriverKit VirtualHIDKeyboard", "Transport": "USB",
                                      "LocationID": 12]
        let virtualFlag: [String: Any] = ["Product": "Remote Keyboard", "HIDVirtualDevice": true, "LocationID": 13]
        for service in [internalKeyboard, builtInHeadset, spiTrackpad, touchBar, t2, hub, virtual, virtualFlag] {
            check(!DeviceMonitorPolicy.isExternal(service), "\(service["Product"]!) is not an external device")
        }
        let magicMouse: [String: Any] = ["Product": "Magic Mouse", "Transport": "Bluetooth Low Energy",
                                         "DeviceAddress": "d1-00-99-27-1f-85", "BatteryPercent": 64,
                                         "PrimaryUsagePage": 1, "PrimaryUsage": 2]
        let magicMouseService: [String: Any] = ["Product": "Magic Mouse", "Transport": "Bluetooth Low Energy",
                                                "DeviceAddress": "d1-00-99-27-1f-85", "PrimaryUsagePage": 0xFF00,
                                                "PrimaryUsage": 11]
        let usbKeyboardVendor: [String: Any] = ["Product": "NuPhy Air75", "Transport": "USB", "LocationID": 0x0110_0000,
                                                "PrimaryUsagePage": 0xFF60, "PrimaryUsage": 0x61]
        let usbKeyboard: [String: Any] = ["Product": "NuPhy Air75", "Transport": "USB", "LocationID": 0x0110_0000,
                                          "PrimaryUsagePage": 1, "PrimaryUsage": 6]
        let gitHubKey: [String: Any] = ["Product": "GitHub Key", "Transport": "USB", "SerialNumber": "GH1"]
        check(DeviceMonitorPolicy.isExternal(magicMouse) && DeviceMonitorPolicy.isExternal(usbKeyboard),
              "Bluetooth and USB HID devices count")
        check(DeviceMonitorPolicy.isExternal(gitHubKey), "only the word Hub marks a hub, not a name containing it")

        let devices = DeviceMonitorPolicy.externalHIDDevices(fromRegistry: [
            internalKeyboard, magicMouseService, usbKeyboardVendor, builtInHeadset, magicMouse, usbKeyboard, hub,
        ])
        check(devices.map(\.id) == ["D1:00:99:27:1F:85", String(0x0110_0000)],
              "one entry per external device, in first-seen order, got \(devices.map(\.id))")
        check(devices.first?.batteries.first?.level == 64, "the interface that reports a battery wins")
        check(devices.first?.kind == .mouse && devices.last?.kind == .keyboard,
              "the standard interface decides the kind, not a vendor one")
        check(devices.first?.transport == .bluetooth && devices.last?.transport == .usb, "transport")

        // S8: what is connected at launch is not announced.
        let clock = FakeClock()
        var connected: [DeviceInfo] = [mouse(battery: 80)]
        var reads = 0
        var events: [DeviceEvent] = []
        let engine = DeviceMonitorEngine(
            snapshot: { completion in
                reads += 1
                completion(connected)
            },
            schedule: clock.schedule,
            publish: { events.append($0) })
        engine.start()
        check(reads == 1 && events.isEmpty, "the first snapshot only records what is connected")

        // Notifications burst; one read after they settle.
        connected.append(keyboard())
        engine.trigger()
        clock.advance(by: 0.2)
        engine.trigger()
        clock.advance(by: 0.2)
        engine.trigger()
        clock.advance(by: DeviceMonitorPolicy.debounce - 0.05)
        check(reads == 1, "no read while notifications keep coming")
        clock.advance(by: 0.1)
        check(reads == 2, "one read after the burst, got \(reads)")
        check(events.map(\.change) == [.connected] && events.first?.device.name == "NuPhy Air75",
              "a device without battery (not audio) is announced at once")

        // AirPods report their battery a moment after they connect: read again before announcing.
        events = []
        connected.append(airPods(left: nil, right: nil, chargingCase: nil))
        engine.trigger()
        clock.advance(by: DeviceMonitorPolicy.debounce)
        check(reads == 3 && events.isEmpty, "a new headphone without battery waits for a second read")
        clock.advance(by: DeviceMonitorPolicy.lateBatteryRetries[0])
        check(reads == 4 && events.isEmpty, "still no battery: one more try")
        connected[2] = airPods(left: 90, right: 88, chargingCase: 40)
        clock.advance(by: DeviceMonitorPolicy.lateBatteryRetries[1])
        check(reads == 5 && events.count == 1 && events[0].change == .connected,
              "announced once the battery shows up, got \(events.map(\.change))")
        check(events.first?.device.batteries.compactMap(\.level) == [90, 88, 40], "with its battery")

        // Headphones that never report a battery are announced after the last try.
        events = []
        connected.append(DeviceInfo(id: "44:73:D6:A3:F9:26", name: "Zone Vibe 125",
                                    kind: .headset, batteries: [], transport: .bluetooth))
        engine.trigger()
        clock.advance(by: DeviceMonitorPolicy.debounce + DeviceMonitorPolicy.lateBatteryRetries.reduce(0, +) + 0.01)
        check(events.map(\.change) == [.connected] && events.first?.device.name == "Zone Vibe 125",
              "announced without battery after the retries, got \(events.map(\.change))")

        // A disconnect does not wait.
        events = []
        connected.removeAll { $0.name == "NuPhy Air75" }
        engine.trigger()
        clock.advance(by: DeviceMonitorPolicy.debounce)
        check(events.map(\.change) == [.disconnected], "disconnect announced after the debounce")

        // S5: the slow poll notices a battery falling to 20 % and 10 %, once each.
        events = []
        let readsBeforePoll = reads
        connected[0] = mouse(battery: 19)
        clock.advance(by: DeviceMonitorPolicy.batteryPoll)
        check(reads == readsBeforePoll + 1, "one read per poll interval")
        check(events.map(\.change) == [.droppedLow], "dropped low at 20 %, got \(events.map(\.change))")
        clock.advance(by: DeviceMonitorPolicy.batteryPoll)
        check(events.count == 1, "the same tier is announced once")
        connected[0] = mouse(battery: 9)
        clock.advance(by: DeviceMonitorPolicy.batteryPoll)
        check(events.map(\.change) == [.droppedLow, .droppedLow], "and again at 10 %")

        // A change while a read is running is read again afterwards.
        var held: (@MainActor ([DeviceInfo]?) -> Void)?
        var slowReads = 0
        var slowEvents: [DeviceEvent] = []
        var slowConnected: [DeviceInfo] = []
        let slowClock = FakeClock()
        let slow = DeviceMonitorEngine(
            snapshot: { completion in
                slowReads += 1
                held = completion
            },
            schedule: slowClock.schedule,
            publish: { slowEvents.append($0) })
        slow.start()
        held?(slowConnected)
        slowConnected = [keyboard()]
        slow.trigger()
        slowClock.advance(by: DeviceMonitorPolicy.debounce)
        check(slowReads == 2, "the trigger reads")
        slow.trigger()
        slowClock.advance(by: DeviceMonitorPolicy.debounce)
        check(slowReads == 2, "no second read while one is running")
        held?(slowConnected)
        slowClock.advance(by: DeviceMonitorPolicy.debounce)
        check(slowReads == 3, "the change during the read is read again")
        held?(slowConnected)
        check(slowEvents.map(\.change) == [.connected], "announced once, got \(slowEvents.map(\.change))")

        // A failed read is not an empty snapshot: retain the known connected device.
        slow.trigger()
        slowClock.advance(by: DeviceMonitorPolicy.debounce)
        held?(nil)
        check(slowEvents.map(\.change) == [.connected], "read failure never manufactures a disconnect")
        slow.trigger()
        slowClock.advance(by: DeviceMonitorPolicy.debounce)
        held?(slowConnected)
        check(slowEvents.map(\.change) == [.connected], "recovery never manufactures a reconnect")

        slow.stop()
        let readsAfterStop = slowReads
        slow.trigger()
        slowClock.advance(by: DeviceMonitorPolicy.batteryPoll * 2)
        check(slowReads == readsAfterStop, "a stopped monitor does not read")

        // S9: optional permission, never asked without a usage description (unbundled debug build).
        check(AppPermission.optional.contains(.bluetooth) && !AppPermission.bluetooth.isRequired, "Bluetooth is optional")
        check(AppPermission.bluetooth.settingsURL.absoluteString.hasSuffix("?Privacy_Bluetooth"), "Bluetooth pane")
        check(!AppPermission.bluetooth.purpose.isEmpty, "explains what it is for")
        check(BluetoothAccess.status(infoDictionary: [:]) == .unknown,
              "without the usage description Bluetooth is never asked")
        let plist = (try? Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let usage = plist?[BluetoothAccess.usageKey] as? String
        check(usage?.isEmpty == false, "Info.plist explains why Bluetooth is used")

        print("PASS: DeviceMonitorProbe verified")
    }

    static func mouse(battery: Int) -> DeviceInfo {
        DeviceInfo(id: "D1:00:99:27:1F:85", name: "BT5.0 Mouse", kind: .mouse,
                   batteries: [DeviceBattery(part: .main, level: battery)], transport: .bluetooth)
    }

    static func keyboard() -> DeviceInfo {
        DeviceInfo(id: "17825792", name: "NuPhy Air75", kind: .keyboard, batteries: [], transport: .usb)
    }

    static func airPods(left: Int?, right: Int?, chargingCase: Int?) -> DeviceInfo {
        let parts = left == nil && right == nil && chargingCase == nil ? [] : [
            DeviceBattery(part: .left, level: left), DeviceBattery(part: .right, level: right),
            DeviceBattery(part: .chargingCase, level: chargingCase),
        ]
        return DeviceInfo(id: "20:F4:D4:24:BD:59", name: "Kevnnard's AirPods", kind: .airpods,
                          batteries: parts, transport: .bluetooth)
    }
}
