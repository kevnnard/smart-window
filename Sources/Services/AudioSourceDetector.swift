import AppKit
import CoreAudio
import Darwin

/// Finds the apps that are producing sound, per process, via CoreAudio (macOS 14+).
enum AudioSourceDetector {

    struct AudioProcess: Equatable {
        let pid: pid_t
        let bundleID: String?
        let isOutputting: Bool
    }

    struct ResolvedSource: Equatable {
        let bundleID: String
        let name: String
        let isPlaying: Bool
    }

    /// Maps helper bundle ids to their app: `com.google.Chrome.helper` -> `com.google.Chrome`.
    static func ownerBundleID(for bundleID: String) -> String {
        guard let range = bundleID.range(of: ".helper", options: .caseInsensitive) else { return bundleID }
        return String(bundleID[..<range.lowerBound])
    }

    /// Attributes audio processes to their owning regular apps and deduplicates by app.
    /// Order of resolution: the process itself, its helper-stripped bundle id, then its parent chain.
    /// Processes that cannot be attributed to a running app are dropped instead of guessed.
    static func resolveSources(
        audioProcesses: [AudioProcess],
        appForPID: (pid_t) -> (bundleID: String, name: String)?,
        appForBundleID: (String) -> String?,
        parentPID: (pid_t) -> pid_t?,
        ownBundleID: String?
    ) -> [ResolvedSource] {
        var order: [String] = []
        var resolved: [String: ResolvedSource] = [:]
        for process in audioProcesses {
            guard let owner = owningApp(of: process, appForPID: appForPID,
                                        appForBundleID: appForBundleID, parentPID: parentPID),
                  owner.bundleID != ownBundleID else { continue }
            if let existing = resolved[owner.bundleID] {
                resolved[owner.bundleID] = ResolvedSource(bundleID: owner.bundleID, name: existing.name,
                                                          isPlaying: existing.isPlaying || process.isOutputting)
            } else {
                order.append(owner.bundleID)
                resolved[owner.bundleID] = ResolvedSource(bundleID: owner.bundleID, name: owner.name,
                                                          isPlaying: process.isOutputting)
            }
        }
        return order.compactMap { resolved[$0] }
    }

    private static func owningApp(
        of process: AudioProcess,
        appForPID: (pid_t) -> (bundleID: String, name: String)?,
        appForBundleID: (String) -> String?,
        parentPID: (pid_t) -> pid_t?
    ) -> (bundleID: String, name: String)? {
        if let app = appForPID(process.pid) { return app }
        if let bundleID = process.bundleID {
            let owner = ownerBundleID(for: bundleID)
            if let name = appForBundleID(owner) { return (owner, name) }
        }
        var visited: Set<pid_t> = [process.pid]
        var current = process.pid
        while let parent = parentPID(current), parent > 1, visited.insert(parent).inserted {
            if let app = appForPID(parent) { return app }
            current = parent
        }
        return nil
    }

    // MARK: - Live system

    /// Sources currently known to CoreAudio, or nil when per-process data is unavailable (macOS 13).
    static func currentSources() -> [ResolvedSource]? {
        guard #available(macOS 14.0, *) else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = readAudioProcesses().filter { $0.pid != ownPID }
        return resolveSources(
            audioProcesses: processes,
            appForPID: { pid in
                guard let app = NSRunningApplication(processIdentifier: pid),
                      app.activationPolicy == .regular, let id = app.bundleIdentifier else { return nil }
                return (id, app.localizedName ?? id)
            },
            appForBundleID: { id in
                NSRunningApplication.runningApplications(withBundleIdentifier: id)
                    .first(where: { $0.activationPolicy == .regular })
                    .map { $0.localizedName ?? id }
            },
            parentPID: parentPID(of:),
            ownBundleID: Bundle.main.bundleIdentifier)
    }

    @available(macOS 14.0, *)
    static func readAudioProcesses() -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).compactMap { object in
            var pid: pid_t = 0
            guard read(kAudioProcessPropertyPID, of: object, into: &pid), pid > 0 else { return nil }
            var running: UInt32 = 0
            _ = read(kAudioProcessPropertyIsRunningOutput, of: object, into: &running)
            var bundleRef: Unmanaged<CFString>?
            _ = read(kAudioProcessPropertyBundleID, of: object, into: &bundleRef)
            let bundleID = bundleRef?.takeRetainedValue() as String?
            return AudioProcess(pid: pid, bundleID: bundleID?.isEmpty == false ? bundleID : nil,
                                isOutputting: running != 0)
        }
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
                                into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }

    /// Parent process id via sysctl, or nil when the process is gone.
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }
}
