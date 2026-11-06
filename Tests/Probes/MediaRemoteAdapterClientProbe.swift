import Foundation

@main
struct MediaRemoteAdapterClientProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: MediaRemote adapter stream parsing, commands and backoff") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        func line(_ text: String) -> Data { Data(text.utf8) }
        typealias Client = MediaRemoteAdapterClient

        // Full payload
        let artwork = Data([0x89, 0x50, 0x4E, 0x47])
        let full = line("""
        {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome.helper",\
        "parentApplicationBundleIdentifier":"com.google.Chrome","title":"Video","artist":"Channel",\
        "album":"","duration":241.5,"elapsedTime":60.25,"timestamp":"2026-11-06T10:00:00Z",\
        "playbackRate":1,"playing":true,"artworkMimeType":"image/png","artworkData":"\(artwork.base64EncodedString())"}}
        """)
        guard let first = Client.merge(base: nil, line: full) else { throw Failure.check("full line parsed") }
        try check(first.isFull, "full line is not a diff")
        guard let info = first.state.flatMap(Client.info(from:)) else { throw Failure.check("full payload has info") }
        try check(info.bundleIdentifier == "com.google.Chrome.helper", "bundle id")
        try check(info.parentApplicationBundleIdentifier == "com.google.Chrome", "parent bundle id")
        try check(info.ownerBundleIdentifier == "com.google.Chrome", "parent owns the session")
        try check(info.title == "Video" && info.artist == "Channel" && info.album == "", "text metadata")
        try check(info.duration == 241.5 && info.elapsedTime == 60.25, "duration and elapsed time")
        try check(info.timestamp == Date(timeIntervalSince1970: 1_793_959_200), "timestamp parsed as UTC")
        try check(info.playbackRate == 1 && info.playing, "playing state")
        try check(info.artworkData == artwork && info.artworkMimeType == "image/png", "artwork decoded")

        // Diff merge: adds, overrides, null removes
        let diff = line(#"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0,"elapsedTime":61,"genre":"Pop","artist":null}}"#)
        guard let merged = Client.merge(base: first.state, line: diff), let mergedState = merged.state
        else { throw Failure.check("diff merged") }
        try check(!merged.isFull, "diff line is a diff")
        try check(mergedState["genre"] as? String == "Pop", "diff adds a key")
        try check(mergedState["elapsedTime"] as? Double == 61, "diff overrides a key")
        try check(mergedState["artist"] == nil, "null removes a key")
        try check(mergedState["title"] as? String == "Video", "untouched keys kept")
        let mergedInfo = Client.info(from: mergedState)
        try check(mergedInfo?.playing == false && mergedInfo?.artist == "" && mergedInfo?.playbackRate == 0, "merged info")

        // Diff without a full payload first is ignored
        try check(Client.merge(base: nil, line: diff) == nil, "diff before full payload ignored")

        // Full payload replaces the state; nulls in it are dropped
        let replaced = Client.merge(base: mergedState, line: line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","title":"Song","album":null}}"#))
        try check(replaced?.state?["genre"] == nil && replaced?.state?["album"] == nil
                  && replaced?.state?["bundleIdentifier"] as? String == "com.apple.Music", "full payload replaces state")
        let musicInfo = replaced?.state.flatMap(Client.info(from:))
        try check(musicInfo?.ownerBundleIdentifier == "com.apple.Music" && musicInfo?.playing == false
                  && musicInfo?.duration == nil && musicInfo?.artworkData == nil, "missing keys are absent, not invented")

        // Empty payload means nothing is playing
        let empty = Client.merge(base: mergedState, line: line(#"{"type":"data","diff":false,"payload":{}}"#))
        try check(empty != nil && empty?.isFull == true, "empty payload line parsed")
        try check(empty?.state.flatMap(Client.info(from:)) == nil, "empty payload has no info")
        try check(Client.info(from: [:]) == nil, "empty dictionary has no info")

        // Non-JSON and unknown lines are ignored
        try check(Client.merge(base: mergedState, line: line("perl: warning: something")) == nil, "non-JSON line ignored")
        try check(Client.merge(base: mergedState, line: line("")) == nil, "blank line ignored")
        try check(Client.merge(base: mergedState, line: line(#"{"type":"other","diff":false,"payload":{}}"#)) == nil, "unknown type ignored")
        try check(Client.merge(base: mergedState, line: line(#"[1,2]"#)) == nil, "non-object JSON ignored")

        // Commands
        try check(Client.Command.play.rawValue == 0 && Client.Command.pause.rawValue == 1
                  && Client.Command.togglePlayPause.rawValue == 2 && Client.Command.nextTrack.rawValue == 4
                  && Client.Command.previousTrack.rawValue == 5, "MRCommand ids")
        try check(Client.commandID(for: .playPause) == 2, "play/pause toggles")
        try check(Client.commandID(for: .next) == 4, "next track")
        try check(Client.commandID(for: .previous) == 5, "previous track")
        let script = URL(fileURLWithPath: "/A/mediaremote-adapter.pl")
        let framework = URL(fileURLWithPath: "/A/MediaRemoteAdapter.framework")
        try check(Client.streamArguments(script: script, framework: framework)
                  == ["/A/mediaremote-adapter.pl", "/A/MediaRemoteAdapter.framework", "stream", "--debounce=100"], "stream arguments")
        try check(Client.sendArguments(script: script, framework: framework, command: .togglePlayPause)
                  == ["/A/mediaremote-adapter.pl", "/A/MediaRemoteAdapter.framework", "send", "2"], "send arguments")
        try check(Client.AdapterError.exit(3).localizedDescription == "Could not reach the Now Playing service (exit 3).", "send failure message")
        try check(Client.getArguments(script: script, framework: framework)
                  == ["/A/mediaremote-adapter.pl", "/A/MediaRemoteAdapter.framework", "get", "--no-artwork"], "get arguments")

        // Send is bound to the expected owner, checked with a fresh `get`
        let chrome = NowPlayingInfo(bundleIdentifier: "com.google.Chrome.helper",
                                    parentApplicationBundleIdentifier: "com.google.Chrome", title: "Video")
        let musicOwn = NowPlayingInfo(bundleIdentifier: "com.apple.Music", title: "Song")
        try check(Client.shouldSend(expectedOwner: "com.apple.Music", currentInfo: musicOwn), "owner matches through bundle id")
        try check(Client.shouldSend(expectedOwner: "com.google.Chrome", currentInfo: chrome), "owner matches through parent app")
        try check(!Client.shouldSend(expectedOwner: "com.google.Chrome.helper", currentInfo: chrome), "helper id is not the owner")
        try check(!Client.shouldSend(expectedOwner: "com.apple.Music", currentInfo: chrome), "another app is now playing")
        try check(!Client.shouldSend(expectedOwner: "com.apple.Music", currentInfo: nil), "nothing is playing")
        try check(Client.AdapterError.notNowPlaying(appName: "Apple Music").localizedDescription
                  == "Apple Music is no longer the Mac's Now Playing app. Nothing was sent.", "owner changed message")

        // `get` prints a bare payload or null
        let getOutput = line(#"{"bundleIdentifier":"com.google.Chrome.helper","parentApplicationBundleIdentifier":"com.google.Chrome","title":"Video","playing":true}"# + "\n")
        try check((try? Client.getOutputInfo(getOutput))??.ownerBundleIdentifier == "com.google.Chrome", "get payload parsed")
        try check((try? Client.getOutputInfo(line("null\n"))) == .some(nil), "get null means nothing playing")
        try check((try? Client.getOutputInfo(line("perl: warning"))) == nil, "unreadable get output is an error")
        try check(Client.AdapterError.invalidOutput.localizedDescription
                  == "Could not read the Now Playing service's answer. Nothing was sent.", "invalid output message")

        // Backoff
        try check((0..<6).map(Client.backoffDelay(attempt:)) == [2, 5, 15, 15, 15, 15], "backoff schedule capped")
        try check(Client.backoffDelay(attempt: -1) == 2, "negative attempt clamps to first delay")
    }
}
