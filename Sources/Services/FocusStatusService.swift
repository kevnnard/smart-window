import Foundation
import Intents

/// Shows Focus changes in the notch wings. Reads which Focus is on from ~/Library/DoNotDisturb/DB,
/// which needs Full Disk Access. Without it, falls back to the public Focus status, which only
/// tells whether some Focus is on, and shows it as a generic Focus.
@MainActor
final class FocusStatusService {
    private let state: SystemHUDState
    private var tracker = FocusChangeTracker()
    private var timer: Timer?
    /// Modification dates of the last database reading, and what it said.
    private var lastStamp: [Date?]?
    private var databaseActive: FocusModeDescriptor?
    private var requestedAuthorization = false

    init(state: SystemHUDState? = nil) {
        self.state = state ?? .shared
    }

    func start() {
        guard timer == nil else { return }
        poll()
        // The database has no change notification; checking its date once a second is cheap.
        // Common modes: also runs while a menu is open.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        // Dates first: a write after this reading changes them again, so it is never skipped.
        let stamp = [FocusDatabase.assertionsURL, FocusDatabase.configurationsURL].map(modificationDate)
        if let assertions = try? Data(contentsOf: FocusDatabase.assertionsURL) {
            // Parse only when either file changed (or a date is unknown).
            if stamp != lastStamp || stamp.contains(nil) {
                lastStamp = stamp
                let configurations = (try? Data(contentsOf: FocusDatabase.configurationsURL)) ?? Data()
                databaseActive = FocusDatabase.active(assertions: assertions, configurations: configurations)
            }
            report(FocusDatabase.resolve(database: databaseActive, publicFocused: publicFocusStatus()))
        } else if let focused = publicFocusStatus() {
            report(FocusDatabase.resolve(database: nil, publicFocused: focused))
        }
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func report(_ active: FocusModeDescriptor?) {
        if let event = tracker.update(active) {
            state.show(event)
        }
    }

    /// Whether some Focus is on, from the public API; nil when unavailable or not authorized.
    private func publicFocusStatus() -> Bool? {
        // Asking without a usage description terminates the app (a debug build has no Info.plist).
        guard Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") != nil else { return nil }
        let center = INFocusStatusCenter.default
        switch center.authorizationStatus {
        case .authorized:
            return center.focusStatus.isFocused
        case .notDetermined:
            if !requestedAuthorization {
                requestedAuthorization = true
                center.requestAuthorization { _ in }
            }
            return nil
        default:
            return nil
        }
    }
}
