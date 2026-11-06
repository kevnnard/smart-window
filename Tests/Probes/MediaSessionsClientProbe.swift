import Foundation

@main
struct MediaSessionsClientProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: media sessions line parsing, artwork semantics, owner resolution and backoff") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        func line(_ text: String) -> Data { Data(text.utf8) }
        typealias Client = MediaSessionsClient
        let diaArt = Data([1, 2, 3])
        let musicArt = Data([4, 5, 6])
        let spotifyArt = Data([7, 8, 9])

        // Full line with 3 sessions
        let first = line("""
        {"current":"company.thebrowser.dia","sessions":[\
        {"bundleIdentifier":"company.thebrowser.dia","displayName":"Dia","processIdentifier":1263,\
        "parentApplicationBundleIdentifier":null,"title":"Video","artist":"Channel","album":"",\
        "duration":1261.461,"elapsedTime":12.5,"timestamp":"2026-11-06T23:15:42.681Z","playbackRate":1,\
        "playing":true,"artworkMimeType":"image/jpeg","artworkData":"\(diaArt.base64EncodedString())"},\
        {"bundleIdentifier":"com.apple.Music","displayName":"Music","processIdentifier":54540,\
        "parentApplicationBundleIdentifier":null,"title":"Am Healing","artist":"Fecent Ricco","album":"EP",\
        "duration":154.343,"elapsedTime":38.1,"timestamp":"2026-11-06T23:13:35.630Z","playbackRate":0,\
        "playing":false,"artworkMimeType":null,"artworkData":"\(musicArt.base64EncodedString())"},\
        {"bundleIdentifier":"com.spotify.client","displayName":"Spotify","processIdentifier":46909,\
        "parentApplicationBundleIdentifier":null,"title":"Mathematics","artist":"Mos Def","album":"Black On Both Sides",\
        "duration":246.44,"elapsedTime":74.66,"timestamp":"2026-11-06T23:13:33.841Z","playbackRate":null,\
        "playing":false,"artworkMimeType":"image/jpeg","artworkData":"\(spotifyArt.base64EncodedString())"}]}
        """)
        guard let one = Client.parse(line: first, previousArtwork: [:]) else { throw Failure.check("full line parsed") }
        try check(one.current == "company.thebrowser.dia", "current Now Playing app")
        try check(one.sessions.map(\.bundleIdentifier) == ["company.thebrowser.dia", "com.apple.Music", "com.spotify.client"],
                  "3 sessions in helper order")
        let dia = one.sessions[0]
        try check(dia.displayName == "Dia" && dia.processIdentifier == 1263 && dia.ownerBundleIdentifier == "company.thebrowser.dia",
                  "Dia identity")
        try check(dia.title == "Video" && dia.artist == "Channel" && dia.album == "", "Dia metadata")
        try check(dia.duration == 1261.461 && dia.elapsedTime == 12.5 && dia.playbackRate == 1 && dia.playing == true,
                  "Dia timing and playing state")
        try check(dia.artworkData == diaArt && dia.artworkMimeType == "image/jpeg", "Dia artwork decoded")
        try check(one.sessions[1].playing == false && one.sessions[1].artworkMimeType == nil
                  && one.sessions[1].artworkData == musicArt, "Music paused with artwork, null mime type absent")
        try check(one.sessions[2].playbackRate == nil, "null playback rate is absent, not invented")

        // Fractional-second ISO 8601 timestamp (UTC)
        let expected = Date(timeIntervalSince1970: 1_794_006_942.681)
        try check(abs((dia.timestamp ?? .distantPast).timeIntervalSince(expected)) < 0.0005, "fractional timestamp parsed")
        try check(Client.timestamp("2026-11-06T23:15:42Z") == Date(timeIntervalSince1970: 1_794_006_942),
                  "whole-second timestamp parsed")
        try check(Client.timestamp("yesterday") == nil && Client.timestamp(42) == nil, "invalid timestamp absent")

        // Artwork semantics across lines: unchanged keeps bytes, null removes, string replaces
        let second = line("""
        {"current":"com.apple.Music","sessions":[\
        {"bundleIdentifier":"company.thebrowser.dia","processIdentifier":1263,"title":"Video","playing":false,"artworkUnchanged":true},\
        {"bundleIdentifier":"com.apple.Music","processIdentifier":54540,"title":"Next","playing":true,"artworkData":null},\
        {"bundleIdentifier":"com.spotify.client","processIdentifier":46909,"title":"Mathematics","playing":false,"artworkData":"\(diaArt.base64EncodedString())"}]}
        """)
        guard let two = Client.parse(line: second, previousArtwork: one.artworkBySession)
        else { throw Failure.check("second line parsed") }
        try check(two.current == "com.apple.Music", "current changed")
        try check(two.sessions[0].artworkData == diaArt, "artworkUnchanged keeps the previous bytes")
        try check(two.sessions[1].artworkData == nil, "null artwork removes it")
        try check(two.sessions[2].artworkData == diaArt, "string artwork replaces the bytes")
        try check(two.artworkBySession == ["company.thebrowser.dia|1263": diaArt, "com.spotify.client|46909": diaArt],
                  "artwork state carried per bundle id and process")

        // Two sessions of one app (same bundle id, different PIDs) never swap artwork
        let tabs = line("""
        {"current":"company.thebrowser.dia","sessions":[\
        {"bundleIdentifier":"company.thebrowser.dia","processIdentifier":100,"title":"A","artworkData":"\(musicArt.base64EncodedString())"},\
        {"bundleIdentifier":"company.thebrowser.dia","processIdentifier":200,"title":"B","artworkData":"\(spotifyArt.base64EncodedString())"}]}
        """)
        guard let tabsOne = Client.parse(line: tabs, previousArtwork: [:]) else { throw Failure.check("two-tab line parsed") }
        try check(tabsOne.artworkBySession == ["company.thebrowser.dia|100": musicArt, "company.thebrowser.dia|200": spotifyArt],
                  "artwork kept per process for one bundle id")
        let tabsSwapped = line("""
        {"current":"company.thebrowser.dia","sessions":[\
        {"bundleIdentifier":"company.thebrowser.dia","processIdentifier":200,"title":"B","artworkUnchanged":true},\
        {"bundleIdentifier":"company.thebrowser.dia","processIdentifier":100,"title":"A","artworkData":"\(diaArt.base64EncodedString())"}]}
        """)
        let tabsTwo = Client.parse(line: tabsSwapped, previousArtwork: tabsOne.artworkBySession)
        try check(tabsTwo?.sessions.map(\.processIdentifier) == [200, 100], "both sessions of one app listed")
        try check(tabsTwo?.sessions[0].artworkData == spotifyArt, "artworkUnchanged keeps that process's own artwork")
        try check(tabsTwo?.sessions[1].artworkData == diaArt, "new artwork replaces only its own process")
        let tabsSilent = Client.parse(line: line("""
        {"current":null,"sessions":[{"bundleIdentifier":"company.thebrowser.dia","processIdentifier":100,"title":"A"},\
        {"bundleIdentifier":"company.thebrowser.dia","processIdentifier":300,"title":"C","artworkUnchanged":true}]}
        """), previousArtwork: tabsOne.artworkBySession)
        try check(tabsSilent?.sessions[0].artworkData == musicArt, "no artwork keys keeps that process's artwork")
        try check(tabsSilent?.sessions[1].artworkData == nil, "a new process of the same app does not inherit artwork")
        try check(SessionsSnapshot.artworkKey(bundleIdentifier: "x.y", processIdentifier: 7) == "x.y|7"
                  && SessionsSnapshot.artworkKey(bundleIdentifier: "x.y", processIdentifier: nil) == "x.y",
                  "artwork key is bundle id and PID, bundle id alone without PID")
        let unknown = Client.parse(line: line(#"{"current":null,"sessions":[{"bundleIdentifier":"x.y","artworkUnchanged":true}]}"#),
                                   previousArtwork: [:])
        try check(unknown?.sessions.first?.artworkData == nil && unknown?.current == nil,
                  "unchanged without previous bytes has no artwork; null current")
        let sparse = unknown?.sessions.first
        try check(sparse?.title == "" && sparse?.duration == nil && sparse?.elapsedTime == nil && sparse?.timestamp == nil
                  && sparse?.playing == nil && sparse?.displayName == nil, "missing keys are absent, not invented")

        // Non-JSON and wrong types are ignored
        try check(Client.parse(line: line("media-sessions: MediaRemote is unavailable"), previousArtwork: [:]) == nil, "non-JSON ignored")
        try check(Client.parse(line: line(""), previousArtwork: [:]) == nil, "blank line ignored")
        try check(Client.parse(line: line("[1,2]"), previousArtwork: [:]) == nil, "non-object JSON ignored")
        try check(Client.parse(line: line(#"{"current":"a","sessions":"nope"}"#), previousArtwork: [:]) == nil, "sessions not an array ignored")
        try check(Client.parse(line: line(#"{"current":"a"}"#), previousArtwork: [:]) == nil, "missing sessions ignored")
        try check(Client.parse(line: line(#"{"current":7,"sessions":[]}"#), previousArtwork: [:]) == nil, "current of wrong type ignored")
        let mixed = Client.parse(line: line("""
        {"current":null,"sessions":[1,"x",{"title":"no id"},{"bundleIdentifier":5},\
        {"bundleIdentifier":"ok.app","title":3,"duration":"long","playing":"yes","artworkData":12,"processIdentifier":"p"}]}
        """), previousArtwork: ["ok.app": diaArt])
        try check(mixed?.sessions.map(\.bundleIdentifier) == ["ok.app"], "entries without a bundle id string are skipped")
        let ok = mixed?.sessions.first
        try check(ok?.title == "" && ok?.duration == nil && ok?.playing == nil && ok?.processIdentifier == nil,
                  "fields of the wrong type are absent")
        try check(ok?.artworkData == nil, "artwork of the wrong type is absent")
        try check(Client.parse(line: line(#"{"current":null,"sessions":[]}"#), previousArtwork: [:])?.sessions.isEmpty == true,
                  "empty session list parsed")

        // Owner resolution: parent app first, then the session bundle id
        try check(Client.owner(bundleIdentifier: "com.google.Chrome.helper", parent: "com.google.Chrome") == "com.google.Chrome",
                  "parent app owns the session")
        try check(Client.owner(bundleIdentifier: "com.apple.Music", parent: nil) == "com.apple.Music", "bundle id without parent")
        try check(Client.owner(bundleIdentifier: "com.apple.Music", parent: "") == "com.apple.Music", "empty parent ignored")
        let helperLine = line("""
        {"current":"com.google.Chrome.helper","sessions":[\
        {"bundleIdentifier":"com.google.Chrome.helper","parentApplicationBundleIdentifier":"com.google.Chrome","playing":true}]}
        """)
        let helper = Client.parse(line: helperLine, previousArtwork: [:])
        try check(helper?.sessions.first?.ownerBundleIdentifier == "com.google.Chrome", "session owner is the parent app")
        try check(helper?.current == "com.google.Chrome", "current resolves to the owning app")

        // Adapter fallback converts the single Now Playing session
        let info = NowPlayingInfo(bundleIdentifier: "com.google.Chrome.helper", parentApplicationBundleIdentifier: "com.google.Chrome",
                                  title: "Video", duration: 10, elapsedTime: 2, playbackRate: 1, playing: true, artworkData: diaArt)
        let converted = MediaSession(info: info)
        try check(converted?.ownerBundleIdentifier == "com.google.Chrome" && converted?.title == "Video"
                  && converted?.playing == true && converted?.duration == 10 && converted?.artworkData == diaArt,
                  "adapter info becomes one session")
        try check(MediaSession(info: NowPlayingInfo()) == nil, "adapter info without bundle id is no session")

        // Process arguments and health
        let runner = URL(fileURLWithPath: "/A/media-sessions.pl")
        let dylib = URL(fileURLWithPath: "/A/libMediaSessionsHelper.dylib")
        try check(Client.arguments(runner: runner, helper: dylib) == ["/A/media-sessions.pl", "/A/libMediaSessionsHelper.dylib"],
                  "runner arguments")
        try check(Client.perlURL.path == "/usr/bin/perl", "fixed perl")
        try check(Client.startupWindow == 3, "first line expected within 3 s")
        try check((0..<5).map(Client.backoffDelay(attempt:)) == [2, 5, 15, 15, 15], "backoff schedule")
    }
}
