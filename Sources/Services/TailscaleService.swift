import AppKit
import Combine
import Foundation
import Darwin

/// Read-only Tailscale monitoring. Duration means continuously observed online
/// time in SmartWindow, not the tunnel's actual connection age.
@MainActor
final class TailscaleService: ObservableObject {
    static let shared = TailscaleService()

    enum State: Equatable {
        case notInstalled, unavailable, stopped, connecting, connected
    }

    @Published private(set) var state: State = .unavailable
    @Published private(set) var connectedSince: Date?
    @Published private(set) var tailnetName = ""
    @Published private(set) var tailscaleIP = ""
    @Published private(set) var backendState = ""

    var isInstalled: Bool { state != .notInstalled }
    var isConnected: Bool { state == .connected }

    func connectedDuration(now: Date = Date()) -> String? {
        connectedSince.map { Self.format(duration: now.timeIntervalSince($0)) }
    }

    nonisolated static let downloadURL = URL(string: "https://tailscale.com/download/mac")!
    nonisolated static let cliCandidates = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
    ]

    nonisolated static func locateCLI() -> String? {
        cliCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private let queue = DispatchQueue(label: "smartwindow.tailscale", qos: .utility)
    private var timer: Timer?
    private var polling = false
    private var lastObservation: Date?
    private var generation = 0
    private var sleeping = false
    private var sleepObservers: [NSObjectProtocol] = []

    init(monitoring: Bool = true) {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = false
                    self?.poll()
                }
            }
        ]
        if monitoring { Task { @MainActor [weak self] in self?.startPolling() } }
    }

    deinit {
        timer?.invalidate()
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func handleSleep() {
        generation += 1
        sleeping = true
        connectedSince = nil
        lastObservation = nil
        state = .unavailable
    }

    private func startPolling() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard !polling, !sleeping else { return }
        polling = true
        let startedGeneration = generation
        queue.async { [weak self] in
            let snapshot = Self.readStatus()
            Task { @MainActor in
                guard let self else { return }
                self.polling = false
                guard self.generation == startedGeneration else {
                    self.poll()
                    return
                }
                self.apply(snapshot)
            }
        }
    }

    struct Snapshot: Equatable {
        var state: State
        var backendState: String
        var tailnetName: String
        var tailscaleIP: String

        static let unavailable = Snapshot(state: .unavailable, backendState: "unavailable", tailnetName: "", tailscaleIP: "")
    }

    nonisolated static func readStatus() -> Snapshot {
        guard let cli = locateCLI() else {
            return Snapshot(state: .notInstalled, backendState: "", tailnetName: "", tailscaleIP: "")
        }
        return runCLI(executable: cli, arguments: ["status", "--json"])
    }

    /// Bounded by a monotonic deadline, not pipe EOF (which a descendant may retain).
    nonisolated static func runCLI(executable: String, arguments: [String], timeout: TimeInterval = 3) -> Snapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .unavailable }
        let handle = pipe.fileHandleForReading
        defer { try? handle.close(); try? pipe.fileHandleForWriting.close() }
        let fd = handle.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return .unavailable
        }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                // Reject runaway output instead of allowing unbounded memory consumption.
                if data.count > 1_048_576 { break }
                continue
            }
            if count < 0 && errno != EAGAIN && errno != EINTR { break }
            if !process.isRunning {
                return process.terminationStatus == 0 ? parse(data) : .unavailable
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Never wait for EOF or waitUntilExit after the deadline. Foundation reaps
        // its Process asynchronously; kill only this invocation, never the VPN daemon.
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        return .unavailable
    }

    nonisolated static func parse(_ data: Data) -> Snapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let backend = json["BackendState"] as? String else { return .unavailable }
        let node = json["Self"] as? [String: Any]
        let ips = node?["TailscaleIPs"] as? [String] ?? []
        let tailnet = (json["CurrentTailnet"] as? [String: Any])?["Name"] as? String ?? ""
        let state: State
        switch backend {
        case "Running":
            guard let online = node?["Online"] as? Bool else { return .unavailable }
            state = online ? .connected : .connecting
        case "Starting": state = .connecting
        case "Stopped", "NeedsLogin", "NeedsMachineAuth", "NoState": state = .stopped
        default: return .unavailable
        }
        return Snapshot(state: state, backendState: backend, tailnetName: tailnet,
                        tailscaleIP: ips.first(where: { $0.contains(".") }) ?? ips.first ?? "")
    }

    func apply(_ snapshot: Snapshot) {
        let now = Date()
        // A sleep / long polling gap invalidates continuity; never count it as proven uptime.
        let continuous = lastObservation.map { now.timeIntervalSince($0) < 15 } ?? false
        if snapshot.state == .connected {
            if state != .connected || !continuous { connectedSince = now }
        } else {
            connectedSince = nil
        }
        lastObservation = now
        state = snapshot.state
        backendState = snapshot.backendState
        tailnetName = snapshot.tailnetName
        tailscaleIP = snapshot.tailscaleIP
    }

    nonisolated static func format(duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total % 60)s"
    }
}
