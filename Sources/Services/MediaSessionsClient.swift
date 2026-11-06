import AppKit
import Combine
import Foundation

// MARK: - MediaSession

/// One media session from macOS's Now Playing list, as printed by the media sessions helper.
/// Keys the helper does not report stay nil; nothing is invented.
public struct MediaSession: Equatable {
    public var bundleIdentifier: String
    /// Owning app when the session belongs to a helper or web content process.
    public var parentApplicationBundleIdentifier: String?
    public var displayName: String?
    public var processIdentifier: Int?
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?
    /// Elapsed time at `timestamp`.
    public var elapsedTime: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double?
    /// nil when the session did not answer in time.
    public var playing: Bool?
    public var artworkData: Data?
    public var artworkMimeType: String?

    public init(bundleIdentifier: String, parentApplicationBundleIdentifier: String? = nil, displayName: String? = nil,
                processIdentifier: Int? = nil, title: String = "", artist: String = "", album: String = "",
                duration: TimeInterval? = nil, elapsedTime: TimeInterval? = nil, timestamp: Date? = nil,
                playbackRate: Double? = nil, playing: Bool? = nil, artworkData: Data? = nil, artworkMimeType: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.parentApplicationBundleIdentifier = parentApplicationBundleIdentifier
        self.displayName = displayName
        self.processIdentifier = processIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.playing = playing
        self.artworkData = artworkData
        self.artworkMimeType = artworkMimeType
    }

    /// The adapter's single Now Playing session, used while the helper is unavailable.
    public init?(info: NowPlayingInfo) {
        guard let bundle = info.bundleIdentifier ?? info.parentApplicationBundleIdentifier, !bundle.isEmpty else { return nil }
        self.init(bundleIdentifier: bundle, parentApplicationBundleIdentifier: info.parentApplicationBundleIdentifier,
                  title: info.title, artist: info.artist, album: info.album, duration: info.duration,
                  elapsedTime: info.elapsedTime, timestamp: info.timestamp, playbackRate: info.playbackRate,
                  playing: info.playing, artworkData: info.artworkData, artworkMimeType: info.artworkMimeType)
    }

    /// The app that owns the session: the parent app when set, otherwise the session's bundle id.
    public var ownerBundleIdentifier: String {
        MediaSessionsClient.owner(bundleIdentifier: bundleIdentifier, parent: parentApplicationBundleIdentifier)
    }
}

/// One helper line: every session and the app macOS treats as the current Now Playing app.
struct SessionsSnapshot: Equatable {
    /// Owning app of the current Now Playing session, or nil when there is none.
    var current: String?
    var sessions: [MediaSession]

    /// Artwork bytes per session (`artworkKey`), carried into the next line's `artworkUnchanged`.
    var artworkBySession: [String: Data] {
        var result: [String: Data] = [:]
        for session in sessions {
            if let data = session.artworkData {
                result[Self.artworkKey(bundleIdentifier: session.bundleIdentifier,
                                       processIdentifier: session.processIdentifier)] = data
            }
        }
        return result
    }

    /// Same session identity as the helper's artwork tracking: bundle id and process id, so two
    /// sessions of one app never swap artwork. The bundle id alone when the PID is missing.
    static func artworkKey(bundleIdentifier: String, processIdentifier: Int?) -> String {
        guard let processIdentifier else { return bundleIdentifier }
        return "\(bundleIdentifier)|\(processIdentifier)"
    }
}

// MARK: - MediaSessionsClient

/// Runs `media-sessions.pl` (our read-only helper) under `/usr/bin/perl` and publishes every
/// Now Playing session. The helper prints a line at start and on every change; the process is
/// restarted with backoff when it exits or stays silent at startup.
@MainActor
final class MediaSessionsClient: ObservableObject {

    static let shared = MediaSessionsClient()

    enum Status: Equatable {
        /// Launched for the first time, no line yet.
        case starting
        /// The helper is running and has printed a line.
        case available
        /// The helper is missing, exited, or stayed silent; a restart may be pending.
        case unavailable
    }

    @Published private(set) var sessions: [MediaSession] = []
    /// Owning app of the Mac's current Now Playing session.
    @Published private(set) var currentBundleID: String?
    @Published private(set) var status: Status = .starting

    var available: Bool { status == .available }

    nonisolated static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
    /// The helper prints its first line immediately; silence this long means it is unhealthy.
    nonisolated static let startupWindow: TimeInterval = 3

    private var process: Process?
    /// Incremented on every launch/stop so callbacks from an older process are ignored.
    private var generation = 0
    private var restartAttempt = 0
    private var started = false
    private var receivedLine = false
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    deinit {
        process?.terminate()
    }

    // MARK: Lifecycle

    /// Starts the helper once; later calls do nothing while it runs or waits to restart.
    func start() {
        guard !started else { return }
        started = true
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        launch()
    }

    /// Terminates the helper and cancels pending restarts.
    func stop() {
        started = false
        generation += 1
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
        terminateProcess()
        markUnavailable()
    }

    private func launch() {
        generation += 1
        let current = generation
        receivedLine = false
        guard let files = MediaRemoteAdapterLocator.currentAll() else {
            markUnavailable()
            scheduleRestart()
            return
        }

        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = Self.arguments(runner: files.sessionsRunner, helper: files.sessionsHelper)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let reader = SessionsLineReader { [weak self] snapshot in
            DispatchQueue.main.async { self?.received(snapshot, generation: current) }
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
            guard let self, self.generation == current, !self.receivedLine else { return }
            // Silent at startup: terminating it schedules the restart through `processExited`.
            self.markUnavailable()
            self.process?.terminate()
        }
    }

    private func received(_ snapshot: SessionsSnapshot, generation current: Int) {
        guard current == generation else { return }
        receivedLine = true
        restartAttempt = 0
        if status != .available { status = .available }
        if snapshot.sessions != sessions { sessions = snapshot.sessions }
        if snapshot.current != currentBundleID { currentBundleID = snapshot.current }
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
        if status != .unavailable { status = .unavailable }
        if !sessions.isEmpty { sessions = [] }
        if currentBundleID != nil { currentBundleID = nil }
    }

    private func terminateProcess() {
        guard let process else { return }
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
    }

    // MARK: Pure helpers

    nonisolated static func arguments(runner: URL, helper: URL) -> [String] {
        [runner.path, helper.path]
    }

    /// Restart delays: 2 s, 5 s, then 15 s for every later attempt (same as the adapter stream).
    nonisolated static func backoffDelay(attempt: Int) -> TimeInterval {
        MediaRemoteAdapterClient.backoffDelay(attempt: attempt)
    }

    /// The parent app when set, otherwise the session's bundle id.
    nonisolated static func owner(bundleIdentifier: String, parent: String?) -> String {
        if let parent, !parent.isEmpty { return parent }
        return bundleIdentifier
    }

    /// Parses one helper line `{current, sessions[]}`. Artwork: a string is new bytes, null removes
    /// them, `artworkUnchanged` keeps `previousArtwork[artworkKey]` (bundle id + PID, as the helper
    /// tracks it). Returns nil for lines to
    /// ignore (non-JSON, not an object, `sessions` not an array, `current` not a string or null);
    /// session entries without a bundle id string are skipped and fields of the wrong type are nil.
    nonisolated static func parse(line: Data, previousArtwork: [String: Data]) -> SessionsSnapshot? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let entries = object["sessions"] as? [Any] else { return nil }
        let rawCurrent = object["current"]
        let current: String?
        switch rawCurrent {
        case nil, is NSNull: current = nil
        case let text as String: current = text.isEmpty ? nil : text
        default: return nil
        }

        var sessions: [MediaSession] = []
        for case let entry as [String: Any] in entries {
            guard let bundle = entry["bundleIdentifier"] as? String, !bundle.isEmpty else { continue }
            func string(_ key: String) -> String? { entry[key] as? String }
            // JSONSerialization bridges booleans to NSNumber too; only accept real numbers here.
            func number(_ key: String) -> Double? {
                guard let value = entry[key] as? NSNumber, !isBoolean(value) else { return nil }
                return value.doubleValue.isFinite ? value.doubleValue : nil
            }
            var session = MediaSession(bundleIdentifier: bundle)
            session.parentApplicationBundleIdentifier = string("parentApplicationBundleIdentifier")
            session.displayName = string("displayName")
            session.processIdentifier = number("processIdentifier").map { Int($0) }
            session.title = string("title") ?? ""
            session.artist = string("artist") ?? ""
            session.album = string("album") ?? ""
            session.duration = number("duration")
            session.elapsedTime = number("elapsedTime")
            session.timestamp = timestamp(entry["timestamp"])
            session.playbackRate = number("playbackRate")
            if let value = entry["playing"] as? NSNumber, isBoolean(value) { session.playing = value.boolValue }
            session.artworkMimeType = string("artworkMimeType")
            let artworkKey = SessionsSnapshot.artworkKey(bundleIdentifier: bundle,
                                                         processIdentifier: session.processIdentifier)
            if (entry["artworkUnchanged"] as? NSNumber)?.boolValue == true {
                session.artworkData = previousArtwork[artworkKey]
            } else if let text = entry["artworkData"] as? String {
                session.artworkData = Data(base64Encoded: text)
            } else if entry["artworkData"] == nil {
                // Neither key: nothing new was reported, keep what was shown.
                session.artworkData = previousArtwork[artworkKey]
            }
            sessions.append(session)
        }

        // `current` is the session's own bundle id; report the app that owns it.
        let owner = current.map { id in
            sessions.first(where: { $0.bundleIdentifier == id })?.ownerBundleIdentifier ?? id
        }
        return SessionsSnapshot(current: owner, sessions: sessions)
    }

    /// The helper prints ISO 8601 with fractional seconds in UTC; whole seconds are accepted too.
    nonisolated static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private nonisolated static func isBoolean(_ value: NSNumber) -> Bool {
        CFGetTypeID(value) == CFBooleanGetTypeID()
    }
}

// MARK: - SessionsLineReader

/// Splits stdout into lines (a line carries base64 artwork and can be hundreds of KB) and keeps
/// the artwork state between lines. Runs on the pipe's background queue; `readabilityHandler`
/// calls are serialized, so the state needs no lock.
private final class SessionsLineReader: @unchecked Sendable {
    private var buffer = Data()
    private var scanned = 0
    private var artwork: [String: Data] = [:]
    private let onSnapshot: (SessionsSnapshot) -> Void

    init(onSnapshot: @escaping (SessionsSnapshot) -> Void) {
        self.onSnapshot = onSnapshot
    }

    func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer[(buffer.startIndex + scanned)...].firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[(newline + 1)...])
            scanned = 0
            guard let snapshot = MediaSessionsClient.parse(line: line, previousArtwork: artwork) else { continue }
            artwork = snapshot.artworkBySession
            onSnapshot(snapshot)
        }
        scanned = buffer.count
    }
}
