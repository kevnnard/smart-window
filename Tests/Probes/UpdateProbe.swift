import Foundation

// In-app updates: which GitHub release counts as newer, how it is read, and what the downloaded app must prove.
@main
struct UpdateProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        versions()
        release()
        candidate()
        schedule()
        installer()
        print("PASS: UpdateProbe verified")
    }

    static func versions() {
        check(AppVersion("0.7.0") == AppVersion("v0.7.0"), "a leading v is ignored")
        check(AppVersion("0.7.0")! < AppVersion("0.7.1")!, "patch")
        check(AppVersion("0.7.9")! < AppVersion("0.10.0")!, "numeric, not text, order")
        check(AppVersion("0.7")! == AppVersion("0.7.0")!, "missing parts are zero")
        check(AppVersion("1.0.0")! > AppVersion("0.99.99")!, "major wins")
        check(AppVersion("") == nil && AppVersion("abc") == nil && AppVersion("1.x") == nil, "not a version")
        check(AppVersion("0.8.0-beta") == nil, "pre-release tags are not offered")
        check(AppVersion("0.7.0")?.description == "0.7.0", "prints without the v")
    }

    static func release() {
        let json = """
        {"tag_name":"v0.8.0","html_url":"https://github.com/kevnnard/smart-window/releases/tag/v0.8.0",
         "draft":false,"prerelease":false,"body":"# SmartWindow v0.8.0",
         "assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
                   {"name":"SmartWindow.zip","browser_download_url":"https://github.com/kevnnard/smart-window/releases/download/v0.8.0/SmartWindow.zip"}]}
        """
        let release = UpdateRelease.parse(Data(json.utf8))
        check(release?.version == AppVersion("0.8.0"), "version from the tag")
        check(release?.zipURL.absoluteString == "https://github.com/kevnnard/smart-window/releases/download/v0.8.0/SmartWindow.zip",
              "the SmartWindow.zip asset")
        check(release?.pageURL.absoluteString == "https://github.com/kevnnard/smart-window/releases/tag/v0.8.0", "release page")

        let noZip = json.replacingOccurrences(of: "SmartWindow.zip\",", with: "Other.zip\",")
        check(UpdateRelease.parse(Data(noZip.utf8)) == nil, "a release without SmartWindow.zip offers nothing")
        let draft = json.replacingOccurrences(of: "\"draft\":false", with: "\"draft\":true")
        check(UpdateRelease.parse(Data(draft.utf8)) == nil, "drafts are not offered")
        let pre = json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
        check(UpdateRelease.parse(Data(pre.utf8)) == nil, "pre-releases are not offered")
        let elsewhere = json.replacingOccurrences(of: "https://github.com/kevnnard/smart-window/releases/download/",
                                                  with: "https://evil.example/")
        check(UpdateRelease.parse(Data(elsewhere.utf8)) == nil, "the ZIP must come from this repository's releases")
        let http = json.replacingOccurrences(of: "https://github.com/kevnnard/smart-window/releases/download/",
                                             with: "http://github.com/kevnnard/smart-window/releases/download/")
        check(UpdateRelease.parse(Data(http.utf8)) == nil, "https only")
        check(UpdateRelease.parse(Data("not json".utf8)) == nil, "garbage")

        // Only a newer release is offered.
        let r = release!
        check(UpdateRelease.offer(r, installed: AppVersion("0.7.0")!) != nil, "newer is offered")
        check(UpdateRelease.offer(r, installed: AppVersion("0.8.0")!) == nil, "same is not")
        check(UpdateRelease.offer(r, installed: AppVersion("0.9.0")!) == nil, "older is not")
    }

    static func candidate() {
        let installed = AppVersion("0.7.0")!
        let expected = AppVersion("0.8.0")!
        let good = UpdateCandidate(bundleID: "com.kevnnard.smartwindow", version: AppVersion("0.8.0"),
                                   teamID: "4ZXFP3445A", signatureValid: true, notarized: true)
        check(good.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == nil, "a good download")

        var c = good; c.bundleID = "com.example.other"
        check(c.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == .wrongApp, "another app")
        c = good; c.version = AppVersion("0.7.5")
        check(c.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == .wrongVersion, "not the version offered")
        c = good; c.version = AppVersion("0.6.0")
        check(c.problem(expected: AppVersion("0.6.0")!, installed: installed, teamID: "4ZXFP3445A") == .wrongVersion,
              "never a downgrade")
        c = good; c.teamID = "AAAAAAAAAA"
        check(c.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == .wrongSigner, "another developer")
        c = good; c.teamID = nil
        check(c.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == .wrongSigner, "unsigned")
        c = good; c.signatureValid = false
        check(c.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == .badSignature, "tampered")
        c = good; c.notarized = false
        check(c.problem(expected: expected, installed: installed, teamID: "4ZXFP3445A") == .notNotarized, "not notarized")
        check(good.problem(expected: expected, installed: installed, teamID: nil) == .wrongSigner,
              "a running app without a team (dev build) accepts nothing")
        for p in [UpdateProblem.wrongApp, .wrongVersion, .wrongSigner, .badSignature, .notNotarized] {
            check(!p.message.isEmpty && p.message.contains("not installed"), "every problem says nothing was installed")
        }
    }

    static func schedule() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        check(UpdateSchedule.isDue(lastCheck: nil, now: t0), "never checked")
        check(!UpdateSchedule.isDue(lastCheck: t0, now: t0 + 3600), "an hour later is not")
        check(UpdateSchedule.isDue(lastCheck: t0, now: t0 + 86_400), "a day later is")
        check(UpdateSchedule.isDue(lastCheck: t0 + 100, now: t0), "a clock moved back checks again")
    }

    // Against the real signed, notarized release in /Applications, only read and copied into a temp dir.
    static func installer() {
        let real = URL(fileURLWithPath: "/Applications/SmartWindow.app")
        check(FileManager.default.fileExists(atPath: real.path), "needs the released SmartWindow.app in /Applications")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateProbe-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let info = UpdateInstaller.inspect(appURL: real)
        check(info.bundleID == "com.kevnnard.smartwindow" && info.version != nil, "reads bundle ID and version")
        check(info.teamID == "4ZXFP3445A", "reads the team")
        check(info.signatureValid, "the release signature is valid")
        check(info.notarized, "the release is notarized")

        // The release ZIP layout: SmartWindow.app at the root.
        let zip = work.appendingPathComponent("SmartWindow.zip")
        check(run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", real.path, zip.path]), "zip the app")
        let stage = work.appendingPathComponent("stage")
        let staged = try? UpdateInstaller.unpack(zip: zip, into: stage)
        check(staged?.lastPathComponent == "SmartWindow.app", "unpacks SmartWindow.app")
        check(UpdateInstaller.inspect(appURL: staged!).signatureValid, "unzipping keeps the signature")
        check((try? UpdateInstaller.unpack(zip: work.appendingPathComponent("missing.zip"), into: work.appendingPathComponent("s2"))) == nil,
              "a missing ZIP fails")

        // A tampered copy: same bundle and team on paper, broken signature.
        let tampered = work.appendingPathComponent("tampered/SmartWindow.app")
        try! FileManager.default.createDirectory(at: tampered.deletingLastPathComponent(), withIntermediateDirectories: true)
        check(run("/usr/bin/ditto", [real.path, tampered.path]), "copy the app")
        let res = tampered.appendingPathComponent("Contents/Resources/tampered.txt")
        try! Data("x".utf8).write(to: res)
        let bad = UpdateInstaller.inspect(appURL: tampered)
        check(bad.bundleID == "com.kevnnard.smartwindow" && !bad.signatureValid, "a changed bundle fails the signature")

        // Ad-hoc signed (no Developer ID): no team, not a valid signature.
        let adhoc = work.appendingPathComponent("adhoc/SmartWindow.app")
        try! FileManager.default.createDirectory(at: adhoc.deletingLastPathComponent(), withIntermediateDirectories: true)
        check(run("/usr/bin/ditto", [real.path, adhoc.path]), "copy the app")
        check(run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", adhoc.path]), "ad-hoc sign")
        let adhocInfo = UpdateInstaller.inspect(appURL: adhoc)
        check(adhocInfo.teamID == nil && !adhocInfo.signatureValid && !adhocInfo.notarized, "ad-hoc is not Developer ID")

        // The whole installer with a bad download leaves the installed app as it was.
        let installedVersion = AppVersion("0.0.1")!
        let target = work.appendingPathComponent("Installed/SmartWindow.app")
        try! FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try! Data("installed".utf8).write(to: target.appendingPathComponent("Contents/marker"))
        func installedUntouched() -> Bool {
            (try? Data(contentsOf: target.appendingPathComponent("Contents/marker"))) == Data("installed".utf8)
        }
        let release = UpdateRelease(version: info.version!, zipURL: URL(string: "https://example.com/z")!,
                                    pageURL: URL(string: "https://example.com")!)
        let tamperedZip = work.appendingPathComponent("tampered.zip")
        check(run("/usr/bin/ditto", ["-c", "-k", "--keepParent", tampered.path, tamperedZip.path]), "zip tampered")
        do {
            try UpdateInstaller.install(zip: tamperedZip, release: release, installed: installedVersion,
                                        runningTeam: "4ZXFP3445A", bundleURL: target)
            check(false, "a tampered download must be refused")
        } catch { check((error as? UpdateProblem) == .badSignature, "refused as a broken signature") }
        check(installedUntouched(), "tampered: installed app unchanged")
        let wrong = UpdateRelease(version: AppVersion("99.0.0")!, zipURL: release.zipURL, pageURL: release.pageURL)
        check((try? UpdateInstaller.install(zip: zip, release: wrong, installed: installedVersion,
                                            runningTeam: "4ZXFP3445A", bundleURL: target)) == nil, "not the version offered")
        check(installedUntouched(), "wrong version: installed app unchanged")
        check((try? UpdateInstaller.install(zip: zip, release: release, installed: installedVersion,
                                            runningTeam: "AAAAAAAAAA", bundleURL: target)) == nil, "another team")
        check(installedUntouched(), "wrong team: installed app unchanged")
        check((try? FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)) == ["SmartWindow.app"],
              "no staging left next to the app")

        // Replacing: the new app takes the old one's place and nothing else is left behind.
        let apps = work.appendingPathComponent("Apps")
        let old = apps.appendingPathComponent("SmartWindow.app")
        try! FileManager.default.createDirectory(at: old.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try! Data("old".utf8).write(to: old.appendingPathComponent("Contents/marker"))
        check((try? UpdateInstaller.replace(installed: old, with: staged!)) != nil, "replaces")
        check(!FileManager.default.fileExists(atPath: old.appendingPathComponent("Contents/marker").path), "old app gone")
        check(UpdateInstaller.inspect(appURL: old).signatureValid, "the new app in place, still valid")
        check((try? FileManager.default.contentsOfDirectory(atPath: apps.path)) == ["SmartWindow.app"], "no backup left")

        // A dev build (no bundle, no team) never updates itself.
        check(UpdateInstaller.unsupportedReason(bundleURL: URL(fileURLWithPath: "/tmp/.build/debug"), teamID: nil) != nil,
              "a dev build is unsupported")
        check(UpdateInstaller.unsupportedReason(bundleURL: real, teamID: "4ZXFP3445A") == nil, "the installed app is supported")
    }

    static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
