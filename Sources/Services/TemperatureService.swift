import Foundation
import IOKit

// MARK: - IOHIDEventSystem private bindings
//
// These symbols are exported by IOKit but not declared in public headers.
// They are the same calls used by `powermetrics`-style tools to read the
// SoC die temperature sensors on Apple Silicon without root.

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

// MARK: - ThermalSensorReader

/// Reads real temperature sensors through the IOHID event system.
/// Not main-actor bound so polling can run off the UI thread.
final class ThermalSensorReader {

    struct Reading {
        let name: String
        let celsius: Double
    }

    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(temperatureEventType << 16) // kIOHIDEventFieldTemperatureLevel

    /// Sensor usage page/usage for temperature sensors (AppleSensorHID).
    private static let matching: [String: Any] = [
        "PrimaryUsagePage": 0xff00,
        "PrimaryUsage": 5,
    ]

    private let client: AnyObject?
    private let services: [AnyObject]

    init() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            self.client = nil
            self.services = []
            return
        }
        _ = IOHIDEventSystemClientSetMatching(client, Self.matching as CFDictionary)
        self.client = client
        self.services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
    }

    /// Every sensor that returns a plausible temperature event right now.
    func readAll() -> [Reading] {
        services.compactMap { service in
            guard let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
                return nil
            }
            let value = IOHIDEventGetFloatValue(event, Self.temperatureField)
            // Some PMU channels report sentinel garbage (e.g. -9201). Keep only sane values.
            guard value > 0, value < 150 else { return nil }
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            return Reading(name: name, celsius: value)
        }
    }

    // MARK: Classification

    /// Sensor names that measure the CPU / SoC die across Apple Silicon generations:
    /// - M1/M2/M3: "pACC MTR Temp Sensor…", "eACC MTR Temp Sensor…", "PMGR SOC Die Temp Sensor…"
    /// - M4: "PMU tdie1…tdieN"
    static func isCPUSensor(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("tdie") || n.contains("pacc") || n.contains("eacc") || n.contains("soc die")
    }

    /// GPU die sensors ("GPU MTR Temp Sensor…" on M1-M3; M4 folds GPU into tdie).
    static func isGPUSensor(_ name: String) -> Bool {
        name.lowercased().contains("gpu")
    }
}

// MARK: - TemperatureService

/// Publishes the hottest CPU/SoC die sensor and the OS thermal pressure state.
/// `cpuTemperature` is `nil` when no real sensor is readable; the UI must not
/// show a number in that case.
@MainActor
final class TemperatureService: ObservableObject {

    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var gpuTemperature: Double?
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    var isAvailable: Bool { cpuTemperature != nil }

    private let reader = ThermalSensorReader()
    private let queue = DispatchQueue(label: "smartwindow.thermal", qos: .utility)
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?

    init() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    deinit {
        timer?.invalidate()
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    private func poll() {
        let reader = self.reader
        queue.async { [weak self] in
            let readings = reader.readAll()
            let cpu = readings.filter { ThermalSensorReader.isCPUSensor($0.name) }.map(\.celsius).max()
            let gpu = readings.filter { ThermalSensorReader.isGPUSensor($0.name) }.map(\.celsius).max()
            let state = ProcessInfo.processInfo.thermalState
            Task { @MainActor in
                guard let self else { return }
                self.cpuTemperature = cpu
                self.gpuTemperature = gpu
                self.thermalState = state
            }
        }
    }
}
