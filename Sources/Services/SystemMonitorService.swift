import AppKit
import Combine
import Foundation
import IOKit.ps

// MARK: - SystemMonitorService

/// Monitors system resources: CPU, RAM, battery, mic, volume.
@MainActor
final class SystemMonitorService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var cpuUsage: Int = 0       // 0-100
    @Published private(set) var ramUsage: Int = 0        // 0-100
    @Published private(set) var gpuUsage: Int = 0        // 0-100
    @Published private(set) var batteryLevel: Int = 100  // 0-100
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var volume: Int = 50         // 0-100
    @Published private(set) var isMicActive: Bool = false

    private var refreshTimer: Timer?

    init() {
        // Delay monitoring start to avoid dispatch_once deadlock during SwiftUI layout
        DispatchQueue.main.async { [weak self] in
            self?.startMonitoring()
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        cpuUsage = Self.fetchCPUUsage()
        ramUsage = Self.fetchRAMUsage()
        gpuUsage = Self.fetchGPUUsage()
        (batteryLevel, isCharging) = Self.fetchBatteryInfo()
        volume = Self.fetchVolume()
        isMicActive = Self.fetchMicStatus()
    }

    // MARK: - CPU Usage

    private static func fetchCPUUsage() -> Int {
        var totalTicks: natural_t = 0
        var idleTicks: natural_t = 0

        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user   = info[offset + Int(CPU_STATE_USER)]
            let system = info[offset + Int(CPU_STATE_SYSTEM)]
            let nice   = info[offset + Int(CPU_STATE_NICE)]
            let idle   = info[offset + Int(CPU_STATE_IDLE)]

            totalTicks += natural_t(user + system + nice + idle)
            idleTicks  += natural_t(idle)
        }

        let size = MemoryLayout<integer_t>.stride * Int(numCPUInfo)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(size))

        guard totalTicks > 0 else { return 0 }
        let usage = 100 - Int((Double(idleTicks) / Double(totalTicks)) * 100)
        return max(0, min(100, usage))
    }

    // MARK: - RAM Usage

    private static func fetchRAMUsage() -> Int {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        let active   = UInt64(stats.active_count) * pageSize
        let wired    = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory

        return Int((Double(used) / Double(total)) * 100)
    }

    // MARK: - Battery

    private static func fetchBatteryInfo() -> (level: Int, charging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return (100, false)
        }

        let level = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        let charging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return (level, charging)
    }

    // MARK: - Volume

    private static func fetchVolume() -> Int {
        // Use AppleScript to get volume — simple and reliable
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        guard let val = result?.int32Value else { return 50 }
        return Int(val)
    }

    // MARK: - Microphone

    private static func fetchMicStatus() -> Bool {
        // Check if any audio input device is active
        let script = NSAppleScript(source: "input volume of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        let inputVol = result?.int32Value ?? 0
        return inputVol > 0
    }

    // MARK: - GPU Usage

    private static func fetchGPUUsage() -> Int {
        // Use IOKit to read GPU utilization from IOAccelerator
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }

        defer { IOObjectRelease(iterator) }

        var maxUtilization: Int = 0
        var entry = IOIteratorNext(iterator)

        while entry != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Look for PerformanceStatistics dictionary
            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                // Apple Silicon reports "GPU Activity(%)" or "Device Utilization %"
                if let gpuActivity = perfStats["GPU Activity(%)"] as? Int {
                    maxUtilization = max(maxUtilization, gpuActivity)
                } else if let deviceUtil = perfStats["Device Utilization %"] as? Int {
                    maxUtilization = max(maxUtilization, deviceUtil)
                } else if let gpuUtil = perfStats["GPU Utilization %"] as? Int {
                    maxUtilization = max(maxUtilization, gpuUtil)
                }
            }
        }

        return max(0, min(100, maxUtilization))
    }
}
