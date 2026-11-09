import Foundation

/// A release version, `major.minor.patch` with numbers only. Pre-release tags ("0.8.0-beta") are not
/// versions here, so they are never offered.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy(\.isASCIIDigit), let n = Int(piece) else { return nil }
            parts.append(n)
        }
        self.parts = parts + Array(repeating: 0, count: 3 - parts.count)
    }

    /// The running app's version, from its Info.plist.
    static var installed: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (a: AppVersion, b: AppVersion) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// The latest GitHub release, as far as updating needs it.
struct UpdateRelease: Equatable {
    static let repository = "kevnnard/smart-window"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let assetName = "SmartWindow.zip"
    /// The ZIP must be an asset of this repository's releases, over https.
    static let downloadPrefix = "https://github.com/\(repository)/releases/download/"

    let version: AppVersion
    let zipURL: URL
    let pageURL: URL

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// A release that can be installed, or nil: drafts, pre-releases and releases without the app ZIP
    /// from this repository are not.
    static func parse(_ data: Data) -> UpdateRelease? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name),
              let asset = payload.assets.first(where: { $0.name == assetName }),
              asset.browser_download_url.hasPrefix(downloadPrefix),
              let zipURL = URL(string: asset.browser_download_url),
              let pageURL = URL(string: payload.html_url) else { return nil }
        return UpdateRelease(version: version, zipURL: zipURL, pageURL: pageURL)
    }

    /// The release if it is newer than the installed version.
    static func offer(_ release: UpdateRelease, installed: AppVersion) -> UpdateRelease? {
        release.version > installed ? release : nil
    }
}

/// Why a downloaded app was refused. Nothing is installed in any of these cases.
enum UpdateProblem: Error, Equatable {
    case wrongApp, wrongVersion, wrongSigner, badSignature, notNotarized

    var message: String {
        switch self {
        case .wrongApp: return "The download is not SmartWindow, so it was not installed."
        case .wrongVersion: return "The download is not the version offered, so it was not installed."
        case .wrongSigner: return "The download is not signed by the SmartWindow developer, so it was not installed."
        case .badSignature: return "The download's signature is broken, so it was not installed."
        case .notNotarized: return "The download is not notarized by Apple, so it was not installed."
        }
    }
}

/// What the downloaded app proves about itself, read from its bundle and code signature.
struct UpdateCandidate {
    var bundleID: String?
    var version: AppVersion?
    var teamID: String?
    var signatureValid: Bool
    var notarized: Bool

    /// The first reason to refuse it, or nil when it is the offered SmartWindow version, newer than the
    /// installed one, signed by the same team as the running app (`teamID`; nil for a dev build, which
    /// accepts nothing) and notarized.
    func problem(expected: AppVersion, installed: AppVersion, teamID runningTeam: String?) -> UpdateProblem? {
        guard bundleID == "com.kevnnard.smartwindow" else { return .wrongApp }
        guard let version, version == expected, version > installed else { return .wrongVersion }
        guard let runningTeam, let teamID, teamID == runningTeam else { return .wrongSigner }
        guard signatureValid else { return .badSignature }
        guard notarized else { return .notNotarized }
        return nil
    }
}

/// When to look for an update on its own: at launch and once a day.
enum UpdateSchedule {
    static let interval: TimeInterval = 86_400

    static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock moved back would otherwise wait until it caught up.
        return now < lastCheck || now.timeIntervalSince(lastCheck) >= interval
    }
}
