import AppKit
import Combine
import Foundation

// MARK: - MRMediaRemote Dynamic Loading

/// Safely loads MediaRemote private framework symbols via dlsym.
/// This avoids crashes from incorrect @_silgen_name type bridging on macOS 26+.
private enum MediaRemoteLoader {

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    }()

    // MARK: - Function Types

    // void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, void (^handler)(CFDictionaryRef _Nullable info))
    private typealias GetNowPlayingInfoFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void

    // void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, void (^handler)(Boolean isPlaying))
    private typealias GetIsPlayingFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Bool) -> Void
    ) -> Void

    // void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue)
    private typealias RegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void

    // MARK: - Safe Calls

    static func getNowPlayingInfo(queue: DispatchQueue, handler: @escaping ([String: Any]) -> Void) {
        guard let h = handle,
              let sym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") else {
            handler([:])
            return
        }
        let fn = unsafeBitCast(sym, to: GetNowPlayingInfoFn.self)
        fn(queue) { cfDict in
            if let cfDict {
                let dict = cfDict as NSDictionary as! [String: Any]
                handler(dict)
            } else {
                handler([:])
            }
        }
    }

    static func getIsPlaying(queue: DispatchQueue, handler: @escaping (Bool) -> Void) {
        guard let h = handle,
              let sym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
            handler(false)
            return
        }
        let fn = unsafeBitCast(sym, to: GetIsPlayingFn.self)
        fn(queue, handler)
    }

    static func registerNotifications(queue: DispatchQueue) {
        guard let h = handle,
              let sym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") else {
            return
        }
        let fn = unsafeBitCast(sym, to: RegisterNotificationsFn.self)
        fn(queue)
    }
}

// Known MRMediaRemote info keys
private let kMRMediaRemoteNowPlayingInfoTitle  = "kMRMediaRemoteNowPlayingInfoTitle"
private let kMRMediaRemoteNowPlayingInfoArtist = "kMRMediaRemoteNowPlayingInfoArtist"
private let kMRMediaRemoteNowPlayingInfoAlbum  = "kMRMediaRemoteNowPlayingInfoAlbum"

// Notification names for Now Playing changes
private let kMRMediaRemoteNowPlayingInfoDidChangeNotification =
    NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
private let kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification =
    NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

// MARK: - NowPlayingService

/// Monitors the currently playing media track (Spotify, Apple Music, etc.)
@MainActor
final class NowPlayingService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var trackTitle: String = ""
    @Published private(set) var artistName: String = ""
    @Published private(set) var albumName: String = ""

    /// Formatted "Artist – Title" for display in the bar
    var displayText: String {
        guard isPlaying, !trackTitle.isEmpty else { return "" }
        if artistName.isEmpty { return trackTitle }
        return "\(artistName) — \(trackTitle)"
    }

    /// Whether there's something worth showing
    var hasTrack: Bool {
        isPlaying && !trackTitle.isEmpty
    }

    private var observers: [NSObjectProtocol] = []
    private var fallbackTimer: Timer?

    init() {
        // Delay registration to avoid dispatch_once issues during SwiftUI layout
        DispatchQueue.main.async { [weak self] in
            self?.startListening()
        }
    }

    // MARK: - Start Listening

    private func startListening() {
        // Register for notifications from the private API
        MediaRemoteLoader.registerNotifications(queue: .main)

        // Listen for track changes
        let infoObserver = NotificationCenter.default.addObserver(
            forName: kMRMediaRemoteNowPlayingInfoDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNowPlaying()
            }
        }
        observers.append(infoObserver)

        // Listen for play/pause changes
        let playingObserver = NotificationCenter.default.addObserver(
            forName: kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchPlayingState()
            }
        }
        observers.append(playingObserver)

        // Fetch initial state
        fetchNowPlaying()
        fetchPlayingState()

        // Setup a timer to periodically poll via AppleScript in case notifications fail (common with Spotify)
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchAppleScriptFallback()
            }
        }
    }

    // MARK: - Fetch Data

    private func fetchNowPlaying() {
        MediaRemoteLoader.getNowPlayingInfo(queue: .main) { [weak self] info in
            Task { @MainActor in
                guard let self else { return }
                let title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String ?? ""
                let artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String ?? ""
                let album  = info[kMRMediaRemoteNowPlayingInfoAlbum] as? String ?? ""
                
                if title.isEmpty {
                    self.fetchAppleScriptFallback()
                } else {
                    self.trackTitle = title
                    self.artistName = artist
                    self.albumName = album
                }
            }
        }
    }

    private func fetchPlayingState() {
        MediaRemoteLoader.getIsPlaying(queue: .main) { [weak self] playing in
            Task { @MainActor in
                guard let self else { return }
                if !playing {
                    self.fetchAppleScriptFallback()
                } else {
                    self.isPlaying = playing
                }
            }
        }
    }

    private func fetchAppleScriptFallback() {
        Task.detached { [weak self] in
            let scriptSource = """
            if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return "PLAYING|" & name of current track & "|" & artist of current track
                    else
                        return "PAUSED"
                    end if
                end tell
            else if application "Music" is running then
                tell application "Music"
                    if player state is playing then
                        return "PLAYING|" & name of current track & "|" & artist of current track
                    else
                        return "PAUSED"
                    end if
                end tell
            end if
            return "UNKNOWN"
            """
            
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let descriptor = script.executeAndReturnError(&error)
                if let result = descriptor.stringValue {
                    guard let self = self else { return }
                    Task { @MainActor in
                        if result.hasPrefix("PLAYING|") {
                            let parts = result.components(separatedBy: "|")
                            if parts.count >= 3 {
                                self.isPlaying = true
                                self.trackTitle = parts[1]
                                self.artistName = parts[2]
                            }
                        } else if result == "PAUSED" {
                            self.isPlaying = false
                        }
                    }
                }
            }
        }
    }
}
