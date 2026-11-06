import AppKit
import Combine
import Foundation

// MARK: - NowPlayingInfo

/// The media session macOS reports as Now Playing, as streamed by mediaremote-adapter.
/// Keys the adapter does not report stay nil; nothing is invented.
public struct NowPlayingInfo: Equatable {
    public var bundleIdentifier: String?
    /// Owning app when the session belongs to a helper or web content process.
    public var parentApplicationBundleIdentifier: String?
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var duration: TimeInterval?
    /// Elapsed time at `timestamp`.
    public var elapsedTime: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double?
    public var playing: Bool = false
    public var artworkData: Data?
    public var artworkMimeType: String?

    /// The app that owns the session: the parent app when set, otherwise the session's bundle id.
    public var ownerBundleIdentifier: String? {
        if let parent = parentApplicationBundleIdentifier, !parent.isEmpty { return parent }
        if let bundle = bundleIdentifier, !bundle.isEmpty { return bundle }
        return nil
    }
}

// MARK: - MediaRemoteAdapterClient

/// Runs `mediaremote-adapter.pl stream` under `/usr/bin/perl` and publishes the Now Playing session,
/// and sends commands to the Now Playing app. The stream is only the fallback reader while the media
/// sessions helper is unavailable; it is restarted with backoff when it exits or stays silent at startup.
/// The stream runs under `parent-guard.pl`, which ends it when SmartWindow exits, even after a crash.
@MainActor
final class MediaRemoteAdapterClient: ObservableObject {

    static let shared = MediaRemoteAdapterClient()

    /// Current Now Playing session, or nil when nothing plays or the adapter is unavailable.
    @Published private(set) var info: NowPlayingInfo?
    /// The stream process is running and has produced output.
    @Published private(set) var adapterAvailable = false

    /// MRCommand ids accepted by `send`.
    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    enum AdapterError: LocalizedError, Equatable {
        case unavailable, exit(Int32), timeout, launch(String)
        /// The fresh `get` before `send` reported another app, or nothing, as Now Playing.
        case notNowPlaying(appName: String)
        /// The `get` before `send` printed something that is not a payload or null.
        case invalidOutput
        var errorDescription: String? {
            switch self {
            case .unavailable: return "The Now Playing service is not available."
            case .notNowPlaying(let appName): return "\(appName) is no longer the Mac's Now Playing app. Nothing was sent."
            case .invalidOutput: return "Could not read the Now Playing service's answer. Nothing was sent."
            case .exit(let status): return "Could not reach the Now Playing service (exit \(status))."
            case .timeout: return "Could not reach the Now Playing service (timed out)."
            case .launch(let message): return "Could not reach the Now Playing service (\(message))."
            }
        }
    }

    nonisolated static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
    /// Time the stream has to print its first line before it is considered unhealthy.
    nonisolated static let startupWindow: TimeInterval = 3
    nonisolated static let sendTimeout: TimeInterval = 5
    /// The adapter's own `get` gives up after 2 s.
    nonisolated static let ownerCheckTimeout: TimeInterval = 3
    /// Grace period after `terminate()` before a command process is killed.
    nonisolated static let killGrace: TimeInterval = 1
    /// Running `get`/`send` processes, terminated by `stop()` and on app termination.
    nonisolated static let commandProcesses = CommandRegistry<Process>(terminate: { process in
        if process.isRunning { process.terminate() }
    })

    private var process: Process?
    /// Incremented on every start/stop so callbacks from an older process are ignored.
    private var generation = 0
    private var restartAttempt = 0
    private var started = false
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    deinit {
        process?.terminate()
        Self.commandProcesses.cancelAll()
    }

    // MARK: Lifecycle

    /// Starts the stream once; later calls do nothing while it is running or waiting to restart.
    func start() {
        observeTermination()
        guard !started else { return }
        started = true
        launch()
    }

    /// Terminates the stream and cancels pending restarts; running commands continue.
    func stopStream() {
        guard started || process != nil else { return }
        started = false
        generation += 1
        terminateProcess()
        markUnavailable()
    }

    /// Terminates the stream and any running command, and cancels pending restarts.
    func stop() {
        started = false
        generation += 1
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
        terminateProcess()
        Self.commandProcesses.cancelAll()
        markUnavailable()
    }

    /// App termination ends the stream and any command, whether or not the stream runs.
    private func observeTermination() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func launch() {
        generation += 1
        let current = generation
        guard let adapter = MediaRemoteAdapterLocator.currentStream() else {
            markUnavailable()
            scheduleRestart()
            return
        }

        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = Self.guardedStreamArguments(parentGuard: adapter.parentGuard,
                                                        parentPID: ProcessInfo.processInfo.processIdentifier,
                                                        script: adapter.script, framework: adapter.framework)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let reader = StreamReader { [weak self] info in
            DispatchQueue.main.async { self?.received(info, generation: current) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.consume(chunk)
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.processExited(generation: current) }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            markUnavailable()
            scheduleRestart()
            return
        }
        self.process = process

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupWindow) { [weak self] in
            guard let self, self.generation == current, !self.adapterAvailable else { return }
            // Silent at startup: terminating it schedules the restart through `processExited`.
            self.markUnavailable()
            self.process?.terminate()
        }
    }

    private func received(_ info: NowPlayingInfo?, generation current: Int) {
        guard current == generation else { return }
        if !adapterAvailable { adapterAvailable = true }
        restartAttempt = 0
        if info != self.info { self.info = info }
    }

    private func processExited(generation current: Int) {
        guard current == generation else { return }
        process = nil
        markUnavailable()
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard started else { return }
        let delay = Self.backoffDelay(attempt: restartAttempt)
        restartAttempt += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.started, self.generation == current else { return }
            self.launch()
        }
    }

    private func markUnavailable() {
        if adapterAvailable { adapterAvailable = false }
        if info != nil { info = nil }
    }

    private func terminateProcess() {
        guard let process else { return }
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
    }

    // MARK: Commands

    /// Sends a command to the Now Playing app only while it is still `expectedOwner`.
    /// The adapter cannot target an app, so a fresh `get` first confirms the owner the user saw;
    /// when another app (or nothing) is Now Playing, nothing is sent. A window of a few
    /// milliseconds remains between that `get` and the `send`, which the adapter cannot close.
    /// `completion` runs on the main queue with nil on exit status 0.
    func send(_ action: NowPlayingService.TransportAction, expectedOwner: String, appName: String,
              completion: @escaping (AdapterError?) -> Void) {
        observeTermination()
        guard let adapter = MediaRemoteAdapterLocator.current() else {
            completion(.unavailable)
            return
        }
        let check = Self.getArguments(script: adapter.script, framework: adapter.framework)
        let arguments = Self.sendArguments(script: adapter.script, framework: adapter.framework,
                                           command: Self.command(for: action))
        // Capture the epoch now, not when the queued work starts: a `stop()` in between must
        // cancel this command too.
        let epoch = Self.currentCommandEpoch
        DispatchQueue.global(qos: .userInitiated).async {
            let error = Self.sendIfOwner(expectedOwner, appName: appName, check: check, send: arguments,
                                         epoch: epoch)
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// The cancellation epoch commands register under; `stop()` advances it.
    nonisolated static var currentCommandEpoch: Int { commandProcesses.epoch }

    /// Runs the owner check and then the send under `epoch`, the epoch current when the command was
    /// queued. A stale epoch is refused before any process starts.
    nonisolated static func sendIfOwner(_ expectedOwner: String, appName: String,
                                        check: [String], send: [String], epoch: Int) -> AdapterError? {
        let current: NowPlayingInfo?
        switch run(arguments: check, timeout: ownerCheckTimeout, captureOutput: true, epoch: epoch) {
        case .failure(let error): return error
        case .success(let output):
            do { current = try getOutputInfo(output) } catch { return .invalidOutput }
        }
        guard shouldSend(expectedOwner: expectedOwner, currentInfo: current) else {
            return .notNowPlaying(appName: appName)
        }
        // `stop()` ran during the check: the client is shutting down. `run` refuses to start the
        // send under a changed epoch too, so this only skips the work early.
        guard commandProcesses.isCurrent(epoch: epoch) else { return .unavailable }
        if case .failure(let error) = run(arguments: send, timeout: sendTimeout, captureOutput: false,
                                          epoch: epoch) { return error }
        return nil
    }

    /// Runs perl with the arguments and waits up to `timeout`. Succeeds with stdout (empty unless
    /// `captureOutput`) on exit status 0. On timeout the process is terminated, then killed if it
    /// is still running after `killGrace`. The process is registered under `epoch` before it starts,
    /// so `stop()` either refuses it (`.unavailable`, never started) or terminates it.
    nonisolated static func run(arguments: [String], timeout: TimeInterval,
                                captureOutput: Bool, epoch: Int) -> Result<Data, AdapterError> {
        let process = Process()
        process.executableURL = perlURL
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let output = captureOutput ? Pipe() : nil
        let collected = LockedData()
        let reachedEnd = DispatchSemaphore(value: 0)
        if let output {
            process.standardOutput = output
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    reachedEnd.signal()
                } else {
                    collected.append(chunk)
                }
            }
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        func clearPipe() {
            guard let output else { return }
            output.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForReading.close()
        }
        defer {
            commandProcesses.remove(process)
            clearPipe()
        }

        func end() {
            process.terminate()
            if finished.wait(timeout: .now() + killGrace) != .success, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        // Registered before `run()`: a `stop()` from here on either sees it in the set or has
        // already changed the epoch, which the check after `run()` catches.
        guard commandProcesses.register(process, epoch: epoch) else { return .failure(.unavailable) }
        do {
            try process.run()
        } catch {
            return .failure(.launch(error.localizedDescription))
        }
        // `stop()` ran while the process was starting, before it could be terminated.
        guard commandProcesses.isCurrent(epoch: epoch) else {
            end()
            return .failure(.unavailable)
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            end()
            return .failure(.timeout)
        }
        guard process.terminationStatus == 0 else { return .failure(.exit(process.terminationStatus)) }
        // The exit can be observed before the last chunk is read.
        if output != nil { _ = reachedEnd.wait(timeout: .now() + killGrace) }
        return .success(collected.data)
    }

    // MARK: Pure helpers

    nonisolated static func command(for action: NowPlayingService.TransportAction) -> Command {
        switch action {
        case .playPause: return .togglePlayPause
        case .next: return .nextTrack
        case .previous: return .previousTrack
        }
    }

    nonisolated static func commandID(for action: NowPlayingService.TransportAction) -> Int {
        command(for: action).rawValue
    }

    nonisolated static func streamArguments(script: URL, framework: URL) -> [String] {
        [script.path, framework.path, "stream", "--debounce=100"]
    }

    /// perl arguments that run the stream as a child of `parent-guard.pl`, which watches
    /// `parentPID` (SmartWindow) and ends the stream when it is gone.
    nonisolated static func guardedStreamArguments(parentGuard: URL, parentPID: Int32,
                                                   script: URL, framework: URL) -> [String] {
        [parentGuard.path, String(parentPID), perlURL.path] + streamArguments(script: script, framework: framework)
    }

    nonisolated static func sendArguments(script: URL, framework: URL, command: Command) -> [String] {
        [script.path, framework.path, "send", String(command.rawValue)]
    }

    /// One-shot read used to confirm the Now Playing owner before `send`; artwork is not needed.
    nonisolated static func getArguments(script: URL, framework: URL) -> [String] {
        [script.path, framework.path, "get", "--no-artwork"]
    }

    /// A command may go out only while the app the user saw still owns the Now Playing session.
    nonisolated static func shouldSend(expectedOwner: String, currentInfo: NowPlayingInfo?) -> Bool {
        guard let owner = currentInfo?.ownerBundleIdentifier else { return false }
        return owner == expectedOwner
    }

    /// `get` prints the payload as a bare JSON object, or `null` when nothing plays.
    /// Throws `AdapterError.invalidOutput` for anything else.
    nonisolated static func getOutputInfo(_ output: Data) throws -> NowPlayingInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: output, options: [.fragmentsAllowed]) else {
            throw AdapterError.invalidOutput
        }
        if object is NSNull { return nil }
        guard let payload = object as? [String: Any] else { throw AdapterError.invalidOutput }
        return info(from: payload.filter { !($0.value is NSNull) })
    }

    /// Restart delays: 2 s, 5 s, then 15 s for every later attempt.
    nonisolated static func backoffDelay(attempt: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [2, 5, 15]
        return schedule[min(max(attempt, 0), schedule.count - 1)]
    }

    /// Applies one stream line to the last state. A full payload replaces the state; a diff
    /// merges into it and a null value removes the key. Returns nil for lines to ignore:
    /// non-JSON output, other message types, and diffs that arrive before any full payload.
    nonisolated static func merge(base: [String: Any]?, line: Data) -> (state: [String: Any]?, isFull: Bool)? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return nil }
        let isDiff = object["diff"] as? Bool ?? false
        if isDiff {
            guard var state = base else { return nil }
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
            return (state, false)
        }
        return (payload.filter { !($0.value is NSNull) }, true)
    }

    /// Converts a merged payload to the published value; nil when the payload is empty.
    nonisolated static func info(from payload: [String: Any]) -> NowPlayingInfo? {
        guard !payload.isEmpty else { return nil }
        func string(_ key: String) -> String? { payload[key] as? String }
        func number(_ key: String) -> Double? { (payload[key] as? NSNumber)?.doubleValue }
        var info = NowPlayingInfo()
        info.bundleIdentifier = string("bundleIdentifier")
        info.parentApplicationBundleIdentifier = string("parentApplicationBundleIdentifier")
        info.title = string("title") ?? ""
        info.artist = string("artist") ?? ""
        info.album = string("album") ?? ""
        info.duration = number("duration")
        info.elapsedTime = number("elapsedTime")
        info.timestamp = timestamp(payload["timestamp"])
        info.playbackRate = number("playbackRate")
        info.playing = (payload["playing"] as? NSNumber)?.boolValue ?? false
        info.artworkData = string("artworkData").flatMap { Data(base64Encoded: $0) }
        info.artworkMimeType = string("artworkMimeType")
        return info
    }

    /// The adapter serializes dates as `yyyy-MM-dd'T'HH:mm:ss'Z'` in UTC.
    private nonisolated static func timestamp(_ value: Any?) -> Date? {
        if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        }
        if let seconds = (value as? NSNumber)?.doubleValue { return Date(timeIntervalSince1970: seconds) }
        return nil
    }
}

// MARK: - CommandRegistry

/// Lock-protected set of running commands, shared by the background command queue and the
/// main-actor shutdown path. Registration and cancellation take the same lock, so a command is
/// either refused (registered under an old epoch) or tracked before `cancelAll()` runs.
final class CommandRegistry<Item: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ObjectIdentifier: Item] = [:]
    private var cancellations = 0
    private let terminate: (Item) -> Void

    /// `terminate` is called under the registry lock and must not call back into the registry.
    init(terminate: @escaping (Item) -> Void) {
        self.terminate = terminate
    }

    /// Changes on every `cancelAll()`, so a command can tell it was cancelled between steps.
    var epoch: Int {
        lock.lock(); defer { lock.unlock() }
        return cancellations
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count
    }

    func isCurrent(epoch: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancellations == epoch
    }

    /// Tracks `item` only while `epoch` is current; false means `cancelAll()` already ran.
    func register(_ item: Item, epoch: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard cancellations == epoch else { return false }
        items[ObjectIdentifier(item)] = item
        return true
    }

    func remove(_ item: Item) {
        lock.lock(); defer { lock.unlock() }
        items.removeValue(forKey: ObjectIdentifier(item))
    }

    /// Starts a new epoch and terminates every tracked command. Each `run` call still waits for
    /// its own process, kills it if needed, and removes it from the set.
    func cancelAll() {
        lock.lock(); defer { lock.unlock() }
        cancellations += 1
        for item in items.values { terminate(item) }
    }
}

/// Stdout collected from the pipe's background queue and read by the waiting command thread.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(chunk)
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

// MARK: - StreamReader

/// Splits stdout into lines and keeps the merged payload. Runs on the pipe's background queue;
/// `readabilityHandler` calls are serialized, so the state needs no lock.
private final class StreamReader: @unchecked Sendable {
    private var buffer = Data()
    private var scanned = 0
    private var state: [String: Any]?
    private let onInfo: (NowPlayingInfo?) -> Void

    init(onInfo: @escaping (NowPlayingInfo?) -> Void) {
        self.onInfo = onInfo
    }

    func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer[(buffer.startIndex + scanned)...].firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[(newline + 1)...])
            scanned = 0
            guard let result = MediaRemoteAdapterClient.merge(base: state, line: line) else { continue }
            state = result.state
            onInfo(state.flatMap(MediaRemoteAdapterClient.info(from:)))
        }
        scanned = buffer.count
    }
}
