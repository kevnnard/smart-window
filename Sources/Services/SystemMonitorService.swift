import AppKit
import Combine
import AudioToolbox
import CoreAudio
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
    @Published private(set) var volume: Int?             // 0-100, nil when the output device has no software volume control
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var outputDeviceName: String = ""
    @Published private(set) var isMicActive: Bool = false

    private var refreshTimer: Timer?

    /// Previous CPU tick sample. Usage is the delta between two samples;
    /// a single `host_processor_info` read only gives the average since boot.
    private var previousCPUTicks: CPUTicks?

    struct CPUTicks: Equatable {
        var total: UInt64
        var idle: UInt64
    }

    init() {
        // Delay monitoring start to avoid dispatch_once deadlock during SwiftUI layout
        DispatchQueue.main.async { [weak self] in
            self?.startMonitoring()
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        refresh()
        // CPU usage needs two tick samples; take the second one early so the
        // badge shows a real value within ~1s instead of 0% until the first tick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        if let sample = Self.sampleCPUTicks() {
            if let previous = previousCPUTicks {
                cpuUsage = Self.cpuUsage(from: previous, to: sample)
            }
            previousCPUTicks = sample
        }
        ramUsage = Self.fetchRAMUsage()
        gpuUsage = Self.fetchGPUUsage()
        (batteryLevel, isCharging) = Self.fetchBatteryInfo()
        let output = Self.fetchOutputVolume()
        volume = output.volume
        isMuted = output.muted
        outputDeviceName = output.deviceName
        isMicActive = Self.fetchMicStatus()
    }

    // MARK: - CPU Usage

    /// Cumulative ticks across all cores since boot.
    static func sampleCPUTicks() -> CPUTicks? {
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

        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let size = MemoryLayout<integer_t>.stride * Int(numCPUInfo)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(size))
        }

        var total: UInt64 = 0
        var idle: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user   = UInt64(info[offset + Int(CPU_STATE_USER)])
            let system = UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            let nice   = UInt64(info[offset + Int(CPU_STATE_NICE)])
            let idleT  = UInt64(info[offset + Int(CPU_STATE_IDLE)])

            total += user + system + nice + idleT
            idle  += idleT
        }

        return CPUTicks(total: total, idle: idle)
    }

    /// Busy percentage over the interval between two samples.
    static func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> Int {
        guard current.total > previous.total else { return 0 }
        let totalDelta = Double(current.total - previous.total)
        let idleDelta = Double(current.idle &- previous.idle)
        let usage = Int(((totalDelta - idleDelta) / totalDelta * 100).rounded())
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

    struct OutputVolume: Equatable {
        var volume: Int?        // nil when the device exposes no software volume control (common on HDMI/DisplayPort monitors)
        var muted: Bool
        var deviceName: String
    }

    /// Volume of whatever device is currently the default output: built-in speakers,
    /// an external monitor, headphones, AirPlay, and so on.
    static func fetchOutputVolume() -> OutputVolume {
        guard let device = defaultOutputDevice() else {
            return OutputVolume(volume: nil, muted: false, deviceName: "")
        }
        return fetchOutputVolume(for: device)
    }

    static func fetchOutputVolume(for device: AudioDeviceID) -> OutputVolume {
        OutputVolume(
            volume: outputVolumeScalar(device).map { Int(($0 * 100).rounded()) },
            muted: isOutputMuted(device),
            deviceName: deviceName(device)
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// 0.0-1.0 from the virtual main volume, then the main element, then the average of the channels.
    private static func outputVolumeScalar(_ device: AudioDeviceID) -> Float? {
        if let v = readFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain) {
            return v
        }
        if let v = readFloat(device, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain) {
            return v
        }
        let channels = (1...2).compactMap { readFloat(device, kAudioDevicePropertyVolumeScalar, UInt32($0)) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    private static func readFloat(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return max(0, min(1, value))
    }

    private static func isOutputMuted(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private static func deviceName(_ device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let cf = name?.takeRetainedValue() else { return "" }
        return cf as String
    }

    // MARK: - Microphone

    /// True when any audio input device is currently being captured by some process.
    /// Uses `kAudioDevicePropertyDeviceIsRunningSomewhere`, the same signal behind
    /// the system's orange microphone indicator.
    static func fetchMicStatus() -> Bool {
        for device in allAudioDevices() where hasInputStreams(device) {
            if isRunningSomewhere(device) { return true }
        }
        return false
    }

    static func allAudioDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
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
