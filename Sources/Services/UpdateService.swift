import AppKit
import Foundation
import Security

/// The file and code-signature work of an update: unpack the release ZIP, read what the new app proves
/// about itself, and swap it in for the installed one. Runs off the main thread.
enum UpdateInstaller {
    struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Why this copy cannot update itself, or nil: only a signed `.app` bundle can.
    static func unsupportedReason(bundleURL: URL, teamID: String?) -> String? {
        if bundleURL.pathExtension != "app" {
            return "This is a development build. Updates are for the installed app."
        }
        if teamID == nil {
            return "This copy of SmartWindow is not signed, so it cannot update itself."
        }
        return nil
    }

    /// The team that signed the running app, nil when it is not signed by a developer (a dev build).
    static func runningTeamID() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return teamID(of: staticCode)
    }

    /// Bundle ID, version, signing team, whether the signature is a valid Developer ID one (every
    /// architecture and nested code), and whether Apple notarized it.
    static func inspect(appURL: URL) -> UpdateCandidate {
        let bundle = Bundle(url: appURL)
        let version = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
        var candidate = UpdateCandidate(bundleID: bundle?.bundleIdentifier, version: version,
                                        teamID: nil, signatureValid: false, notarized: false)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return candidate
        }
        candidate.teamID = teamID(of: staticCode)
        candidate.signatureValid = satisfies(staticCode, developerIDRequirement)
        candidate.notarized = candidate.signatureValid && satisfies(staticCode, "notarized")
        return candidate
    }

    /// Unzips the release ZIP into `directory` (created fresh) and returns the SmartWindow.app inside.
    static func unpack(zip: URL, into directory: URL) throws -> URL {
        let files = FileManager.default
        try? files.removeItem(at: directory)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, directory.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        let app = directory.appendingPathComponent("SmartWindow.app")
        guard ditto.terminationStatus == 0, files.fileExists(atPath: app.path) else {
            throw InstallError(message: "The download could not be unpacked, so nothing was installed.")
        }
        return app
    }

    /// Puts `newApp` where `installed` is, in one step, keeping no backup. `newApp` is moved.
    static func replace(installed: URL, with newApp: URL) throws {
        _ = try FileManager.default.replaceItemAt(installed, withItemAt: newApp, backupItemName: nil,
                                                  options: .usingNewMetadataOnly)
    }

    /// Unpacks, checks and installs a downloaded release ZIP over the running app. Any refusal leaves the
    /// installed app as it was; the staging folder is always removed.
    static func install(zip: URL, release: UpdateRelease, installed: AppVersion, runningTeam: String?,
                        bundleURL: URL) throws {
        let files = FileManager.default
        guard files.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path),
              files.isWritableFile(atPath: bundleURL.path) else {
            throw InstallError(message: "SmartWindow cannot write to \(bundleURL.deletingLastPathComponent().path), so nothing was installed. Update with Homebrew instead.")
        }
        // On the same volume as the app, so the swap is a rename.
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: bundleURL, create: true)
        defer { try? files.removeItem(at: staging) }
        let app = try unpack(zip: zip, into: staging.appendingPathComponent("unpacked"))
        if let problem = inspect(appURL: app).problem(expected: release.version, installed: installed, teamID: runningTeam) {
            throw problem
        }
        try replace(installed: bundleURL, with: app)
    }

    /// A Developer ID Application signature: Apple's chain with the Developer ID intermediate
    /// (1.2.840.113635.100.6.2.6) and the Developer ID Application leaf (1.2.840.113635.100.6.1.13).
    static let developerIDRequirement = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"

    private static func teamID(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func satisfies(_ code: SecStaticCode, _ requirementText: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil) == errSecSuccess
    }
}

/// Looks for a newer SmartWindow release at launch and once a day, and installs it when the user clicks
/// Update: download, verify, swap the app, relaunch. It never installs on its own.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case installing(UpdateRelease)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?
    @Published var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: Keys.auto)
            if checksAutomatically { checkIfDue() }
        }
    }

    /// Why this copy cannot update itself (a dev build), or nil.
    let unsupportedReason: String?

    var available: UpdateRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    private enum Keys {
        static let auto = "updates.checkAutomatically"
        static let lastCheck = "updates.lastCheck"
    }

    private let defaults = UserDefaults.standard
    private let runningTeam: String?
    private var timer: Timer?

    private init() {
        checksAutomatically = defaults.object(forKey: Keys.auto) as? Bool ?? true
        lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date
        runningTeam = UpdateInstaller.runningTeamID()
        unsupportedReason = UpdateInstaller.unsupportedReason(bundleURL: Bundle.main.bundleURL, teamID: runningTeam)
    }

    func start() {
        guard unsupportedReason == nil, timer == nil else { return }
        checkIfDue()
        // Hourly look at whether a day has passed, so sleep and long uptimes are covered.
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in UpdateService.shared.checkIfDue() }
        }
    }

    func checkIfDue() {
        guard checksAutomatically, UpdateSchedule.isDue(lastCheck: lastCheck, now: Date()) else { return }
        check()
    }

    func check() {
        guard unsupportedReason == nil, let installed = AppVersion.installed else { return }
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        Task {
            var request = URLRequest(url: UpdateRelease.latestURL, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SmartWindow/\(installed)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    state = .failed("Could not check for updates (HTTP \(status)).")
                    return
                }
                lastCheck = Date()
                defaults.set(lastCheck, forKey: Keys.lastCheck)
                if let release = UpdateRelease.parse(data).flatMap({ UpdateRelease.offer($0, installed: installed) }) {
                    state = .available(release)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed("Could not check for updates: \(error.localizedDescription)")
            }
        }
    }

    /// Downloads, verifies and installs `release`, then relaunches. Only from the user's click.
    func install(_ release: UpdateRelease) {
        guard unsupportedReason == nil, let installed = AppVersion.installed else { return }
        if case .installing = state { return }
        state = .installing(release)
        let team = runningTeam
        let bundleURL = Bundle.main.bundleURL
        Task {
            do {
                let (zip, response) = try await URLSession.shared.download(from: release.zipURL)
                defer { try? FileManager.default.removeItem(at: zip) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateInstaller.InstallError(message: "The download failed, so nothing was installed.")
                }
                try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.install(zip: zip, release: release, installed: installed,
                                                runningTeam: team, bundleURL: bundleURL)
                }.value
                relaunch(bundleURL)
            } catch let problem as UpdateProblem {
                state = .failed(problem.message)
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? "The update failed, so nothing was installed.")
            }
        }
    }

    /// Opens the new app once this one has quit.
    private func relaunch(_ bundleURL: URL) {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        shell.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                           bundleURL.path]
        do {
            try shell.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed("SmartWindow was updated. Quit and open it again to finish.")
        }
    }
}
