import Foundation

/// What a device is, for its icon and the screen reader. Decided from the data the system reports,
/// never from the brand alone; anything unknown is generic.
enum DeviceKind: String, CaseIterable, Equatable {
    case airpods
    case headphones
    case headset
    case mouse
    case keyboard
    case trackpad
    case gameController
    case generic

    /// From a Bluetooth device: name hints first, then the minor type system_profiler reports.
    init(name: String, minorType: String?) {
        if let hinted = Self(nameHint: name) {
            self = hinted
            return
        }
        switch minorType?.lowercased() ?? "" {
        case let type where type.contains("headphone"): self = .headphones
        case let type where type.contains("headset"): self = .headset
        case let type where type.contains("mouse"): self = .mouse
        case let type where type.contains("keyboard"): self = .keyboard
        case let type where type.contains("trackpad") || type.contains("pointing") || type.contains("touchpad"):
            self = .trackpad
        case let type where type.contains("gamepad") || type.contains("joystick"): self = .gameController
        default: self = .generic
        }
    }

    /// From a HID device's primary usage page and usage.
    init(name: String, usagePage: Int?, usage: Int?) {
        if let hinted = Self(nameHint: name) {
            self = hinted
            return
        }
        switch (usagePage, usage) {
        case (0x01, 0x02): self = .mouse
        case (0x01, 0x06): self = .keyboard
        case (0x01, 0x04), (0x01, 0x05): self = .gameController
        case (0x0D, 0x05): self = .trackpad
        default: self = .generic
        }
    }

    private init?(nameHint name: String) {
        let name = name.lowercased()
        if name.contains("airpods") { self = .airpods }
        else if name.contains("trackpad") { self = .trackpad }
        else if name.contains("mouse") { self = .mouse }
        else if name.contains("keyboard") { self = .keyboard }
        else if name.contains("controller") || name.contains("gamepad") { self = .gameController }
        else { return nil }
    }

    /// SF Symbol for the left wing; all exist on macOS 13 (a headset uses the headphones symbol there).
    var symbolName: String {
        switch self {
        case .airpods: return "airpods"
        case .headphones, .headset: return "headphones"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .gameController: return "gamecontroller.fill"
        case .generic: return "dot.radiowaves.left.and.right"
        }
    }

    /// What the screen reader calls it.
    var spokenName: String {
        switch self {
        case .airpods: return "earbuds"
        case .headphones: return "headphones"
        case .headset: return "headset"
        case .mouse: return "mouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "trackpad"
        case .gameController: return "game controller"
        case .generic: return "Bluetooth device"
        }
    }
}

/// One battery of a device. A nil level means the part exists but reports nothing, never 0 %.
struct DeviceBattery: Equatable {
    enum Part: String, Equatable {
        case main
        case left
        case right
        case chargingCase

        var label: String {
            switch self {
            case .main: return "Battery"
            case .left: return "Left"
            case .right: return "Right"
            case .chargingCase: return "Case"
            }
        }
    }

    let part: Part
    /// 0...100, nil when not reported.
    var level: Int?
    /// nil when the system does not say.
    var isCharging: Bool?

    init(part: Part, level: Int?, isCharging: Bool? = nil) {
        self.part = part
        self.level = level.map { min(100, max(0, $0)) }
        self.isCharging = isCharging
    }

    var charging: Bool { isCharging == true }
}

/// A connected device as one snapshot sees it.
struct DeviceInfo: Equatable {
    enum Transport: Equatable {
        case bluetooth
        case usb
    }

    /// Bluetooth address (upper case, colons) or a USB serial, location or registry id.
    let id: String
    let name: String
    let kind: DeviceKind
    var batteries: [DeviceBattery]
    let transport: Transport

    /// The lowest level of a part that is not charging; charging parts are not dropping.
    var lowestLevel: Int? {
        batteries.filter { !$0.charging }.compactMap(\.level).min()
    }
}

/// Reads devices from system_profiler and ioreg output. The formats are undocumented, so every field
/// is optional and anything unexpected is skipped.
enum DeviceParsers {
    /// `system_profiler SPBluetoothDataType -json`: the devices under "device_connected".
    static func bluetoothDevices(fromSystemProfiler data: Data) -> [DeviceInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        return controllers.flatMap { controller -> [DeviceInfo] in
            entries(controller["device_connected"]).compactMap { name, properties in
                bluetoothDevice(name: name, properties: properties)
            }
        }
    }

    /// `ioreg -a -r -k BatteryPercent`: a plist array of HID services.
    static func hidDevices(fromPlist data: Data) -> [DeviceInfo] {
        guard let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            return []
        }
        return hidDevices(fromRegistry: list)
    }

    /// HID services with "Product", "BatteryPercent", "BatteryStatusFlags", "DeviceAddress" or
    /// "SerialNumber", "Transport" and the primary usage.
    static func hidDevices(fromRegistry services: [[String: Any]]) -> [DeviceInfo] {
        services.compactMap { service in
            guard let name = (service["Product"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) else { return nil }
            let address = (service["DeviceAddress"] as? String).flatMap(normalizedAddress)
            let fallback = [service["SerialNumber"], service["LocationID"], service["IORegistryEntryID"]]
                .lazy.compactMap { $0.flatMap(identifier) }.first
            guard let id = address ?? fallback else { return nil }
            let transportName = (service["Transport"] as? String)?.lowercased() ?? ""
            let transport: DeviceInfo.Transport = transportName.contains("bluetooth")
                || (transportName.isEmpty && address != nil) ? .bluetooth : .usb
            var batteries: [DeviceBattery] = []
            if let level = percent(service["BatteryPercent"]) {
                // Status bit meanings vary by driver. Only trust an explicit charging boolean.
                let charging = (service["BatteryIsCharging"] ?? service["IsCharging"]) as? Bool
                batteries = [DeviceBattery(part: .main, level: level, isCharging: charging)]
            }
            let kind = DeviceKind(name: name, usagePage: service["PrimaryUsagePage"] as? Int,
                                  usage: service["PrimaryUsage"] as? Int)
            return DeviceInfo(id: id, name: name, kind: kind, batteries: batteries, transport: transport)
        }
    }

    /// One entry per device: the Bluetooth list wins, HID fills in a missing battery and adds devices
    /// Bluetooth does not know (USB).
    static func merge(bluetooth: [DeviceInfo], hid: [DeviceInfo]) -> [DeviceInfo] {
        var merged = bluetooth
        for device in hid {
            if let index = merged.firstIndex(where: { $0.id == device.id }) {
                if merged[index].batteries.allSatisfy({ $0.level == nil }) && !device.batteries.isEmpty {
                    merged[index].batteries = device.batteries
                } else {
                    for batteryIndex in merged[index].batteries.indices {
                        let part = merged[index].batteries[batteryIndex].part
                        guard let supplement = device.batteries.first(where: { $0.part == part }) else { continue }
                        if merged[index].batteries[batteryIndex].level == nil {
                            merged[index].batteries[batteryIndex].level = supplement.level
                        }
                        if merged[index].batteries[batteryIndex].isCharging == nil {
                            merged[index].batteries[batteryIndex].isCharging = supplement.isCharging
                        }
                    }
                }
            } else {
                merged.append(device)
            }
        }
        return merged
    }

    /// "80%", "80 %", "80" or 80 as 0...100; anything else is not reported.
    static func percent(_ value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let value as Int: number = value
        case let value as Double: number = Int(value.rounded())
        case let value as String:
            number = Int(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        default: number = nil
        }
        return number.map { min(100, max(0, $0)) }
    }

    private static func bluetoothDevice(name: String, properties: [String: Any]) -> DeviceInfo? {
        guard let id = (properties["device_address"] as? String).flatMap(normalizedAddress) else { return nil }
        var batteries: [DeviceBattery] = []
        if let main = percent(properties["device_batteryLevelMain"] ?? properties["device_batteryLevel"]) {
            batteries.append(DeviceBattery(part: .main, level: main))
        }
        let left = percent(properties["device_batteryLevelLeft"])
        let right = percent(properties["device_batteryLevelRight"])
        let chargingCase = percent(properties["device_batteryLevelCase"])
        let parts = [DeviceBattery(part: .left, level: left), DeviceBattery(part: .right, level: right),
                     DeviceBattery(part: .chargingCase, level: chargingCase)]
        let reportedParts = parts.filter { $0.level != nil }
        // Only actual multi-battery readings warrant a card. Once multi-part, preserve the missing
        // case/earbud slot as Not reported; a lone reported part remains a single-battery wing.
        batteries += reportedParts.count >= 2 ? parts : reportedParts
        let kind = DeviceKind(name: name, minorType: properties["device_minorType"] as? String)
        return DeviceInfo(id: id, name: name, kind: kind, batteries: batteries, transport: .bluetooth)
    }

    /// [{name: {…}}, …] as system_profiler writes it, or a plain {name: {…}}.
    private static func entries(_ value: Any?) -> [(String, [String: Any])] {
        let dictionaries = (value as? [[String: Any]]) ?? (value as? [String: Any]).map { [$0] } ?? []
        return dictionaries.flatMap { dictionary in
            dictionary.sorted { $0.key < $1.key }.compactMap { name, properties in
                (properties as? [String: Any]).map { (name, $0) }
            }
        }
    }

    /// "aa-bb-cc-dd-ee-ff" and "AA:BB:CC:DD:EE:FF" are the same device.
    private static func normalizedAddress(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    private static func identifier(_ value: Any) -> String? {
        switch value {
        case let value as String: return value.isEmpty ? nil : value
        case let value as Int: return String(value)
        default: return nil
        }
    }
}

/// Something that happened to a device, shown once in the notch.
struct DeviceEvent: Equatable {
    enum Change: Equatable {
        case connected
        case disconnected
        /// An already connected device fell to 20 % or 10 % or less.
        case droppedLow
    }

    let change: Change
    /// The device as last seen; for a disconnect, before it went away.
    let device: DeviceInfo
}

/// Tells device changes apart from successive snapshots of the connected devices.
struct DeviceChangeTracker {
    private var started = false
    private var connected: [DeviceInfo] = []
    /// Per device, the low threshold already announced: 0 above 20 %, 1 at 20 % or less, 2 at 10 % or less.
    private var announcedTier: [String: Int] = [:]

    static func tier(_ level: Int) -> Int {
        level <= DeviceHUDPresentation.redThreshold ? 2 : level <= DeviceHUDPresentation.lowThreshold ? 1 : 0
    }

    /// Records the connected devices; returns the events to show, disconnects first.
    mutating func update(_ snapshot: [DeviceInfo]) -> [DeviceEvent] {
        var seen = Set<String>()
        let current = snapshot.filter { seen.insert($0.id).inserted }
        defer {
            started = true
            connected = current
        }
        var events = connected.filter { !seen.contains($0.id) }.map { gone -> DeviceEvent in
            announcedTier[gone.id] = nil
            return DeviceEvent(change: .disconnected, device: gone)
        }
        let previous = Set(connected.map(\.id))
        for device in current {
            let tier = device.lowestLevel.map(Self.tier)
            guard previous.contains(device.id) else {
                // A device connecting already low says Low in its connect; that counts as announced.
                announcedTier[device.id] = tier
                if started { events.append(DeviceEvent(change: .connected, device: device)) }
                continue
            }
            guard let tier else { continue }
            guard let announced = announcedTier[device.id] else {
                // The first reading of a battery known only now is where it starts, not a drop.
                announcedTier[device.id] = tier
                continue
            }
            announcedTier[device.id] = tier
            if tier > announced {
                events.append(DeviceEvent(change: .droppedLow, device: device))
            }
        }
        return events
    }
}

/// What the notch shows for a device event (design/notch-device-hud/03-drop-card.html).
struct DeviceHUDPresentation: Equatable {
    /// Amber at or below, always with the word Low.
    static let lowThreshold = 20
    /// Red at or below.
    static let redThreshold = 10

    enum Style: Equatable {
        /// Icon and name left, value right.
        case wings
        /// A 400 pt card below the notch with one ring per battery part.
        case card
    }

    enum Tone: Equatable {
        case normal
        case amber
        case red
        case charging
        /// Gray, for a disconnect.
        case off
    }

    /// The mark next to the value in the right wing.
    enum Indicator: Equatable {
        case connectedDot
        case hollowDot
        case battery(level: Int)
        /// The card shows the levels; the wing only says what happened.
        case none
    }

    struct Part: Equatable {
        let label: String
        /// nil: dashed ring and "Not reported".
        let level: Int?
        let text: String
        let tone: Tone
        let isLow: Bool
        let isCharging: Bool
    }

    let style: Style
    /// Seconds on screen: wings 2, card 3.
    let duration: TimeInterval
    let symbolName: String
    /// The full device name: wings text (wraps to two lines) or card title.
    let title: String
    /// Right wing: "62%", "Connected", "Disconnected" or, over a card, "Low battery".
    let valueText: String
    let tone: Tone
    let isLow: Bool
    /// "Low" next to a single battery's number in the wings; color is never alone.
    let lowTag: String?
    let isCharging: Bool
    let indicator: Indicator
    /// Card rings, in the order the device reports them.
    let parts: [Part]
    let accessibilityLabel: String

    init(_ event: DeviceEvent) {
        let device = event.device
        let gone = event.change == .disconnected
        let usesCard = !gone && device.batteries.count >= 2
        style = usesCard ? .card : .wings
        duration = usesCard ? 3 : 2
        symbolName = device.kind.symbolName
        title = device.name
        parts = usesCard ? device.batteries.map(Self.part) : []
        let single = usesCard ? nil : device.batteries.first { $0.level != nil }

        if gone {
            valueText = "Disconnected"
            tone = .off
            isLow = false
            lowTag = nil
            isCharging = false
            indicator = .hollowDot
        } else if usesCard {
            let lowest = device.lowestLevel
            isLow = lowest.map { $0 <= Self.lowThreshold } ?? false
            isCharging = device.batteries.contains { $0.charging }
            if event.change == .droppedLow, isLow, let lowest {
                valueText = "Low battery"
                tone = Self.tone(level: lowest, charging: false)
            } else {
                valueText = "Connected"
                tone = .normal
            }
            lowTag = nil
            indicator = event.change == .droppedLow ? .none : .connectedDot
        } else if let single, let level = single.level {
            valueText = "\(level)%"
            isCharging = single.charging
            tone = Self.tone(level: level, charging: isCharging)
            isLow = !isCharging && level <= Self.lowThreshold
            lowTag = isLow ? "Low" : nil
            indicator = .battery(level: level)
        } else {
            valueText = "Connected"
            tone = .normal
            isLow = false
            lowTag = nil
            isCharging = false
            indicator = .connectedDot
        }
        accessibilityLabel = Self.sentence(event, single: single, usesCard: usesCard)
    }

    static func tone(level: Int, charging: Bool) -> Tone {
        if charging { return .charging }
        if level <= redThreshold { return .red }
        return level <= lowThreshold ? .amber : .normal
    }

    private static func part(_ battery: DeviceBattery) -> Part {
        guard let level = battery.level else {
            return Part(label: battery.part.label, level: nil, text: "Not reported", tone: .normal,
                        isLow: false, isCharging: battery.charging)
        }
        return Part(label: battery.part.label, level: level, text: "\(level)%",
                    tone: tone(level: level, charging: battery.charging),
                    isLow: !battery.charging && level <= lowThreshold, isCharging: battery.charging)
    }

    /// One sentence per event, as in the design's live region.
    private static func sentence(_ event: DeviceEvent, single: DeviceBattery?, usesCard: Bool) -> String {
        let device = event.device
        let kindName = device.kind == .generic && device.transport == .usb ? "USB device" : device.kind.spokenName
        let what = "\(device.name), \(kindName)"
        if event.change == .disconnected { return "\(what), disconnected." }
        let verb = event.change == .droppedLow ? "battery low" : "connected"
        if usesCard {
            let parts = device.batteries.map { battery -> String in
                guard let level = battery.level else { return "\(battery.part.label) not reported" }
                return "\(battery.part.label) \(level) percent" + detail(level: level, charging: battery.charging)
            }
            return "\(what), \(verb). " + parts.joined(separator: ". ") + "."
        }
        guard let single, let level = single.level else { return "\(what), \(verb). No battery level reported." }
        return "\(what), \(verb). Battery \(level) percent" + detail(level: level, charging: single.charging) + "."
    }

    private static func detail(level: Int, charging: Bool) -> String {
        charging ? ", charging" : level <= lowThreshold ? ", low" : ""
    }
}
