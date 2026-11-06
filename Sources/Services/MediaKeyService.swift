import AppKit

/// Posts system media keys. They reach the app macOS treats as now playing,
/// which is normally the app that last started playback.
enum MediaKeyService {

    enum MediaKeyError: LocalizedError {
        case permissionDenied, failed
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Allow SmartWindow in System Settings > Privacy & Security > Accessibility to control this source."
            case .failed:
                return "Could not send the media key to this source."
            }
        }
    }

    /// NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT and NX_KEYTYPE_PREVIOUS from IOKit's ev_keymap.h.
    static func keyCode(for action: NowPlayingService.TransportAction) -> Int32 {
        switch action {
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    static func post(_ action: NowPlayingService.TransportAction) throws {
        guard CGPreflightPostEventAccess() else {
            _ = CGRequestPostEventAccess()
            throw MediaKeyError.permissionDenied
        }
        let key = Int(keyCode(for: action))
        for (state, flags) in [(0xA, 0xA00), (0xB, 0xB00)] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (key << 16) | (state << 8), data2: -1
            ), let cgEvent = event.cgEvent else { throw MediaKeyError.failed }
            cgEvent.post(tap: .cghidEventTap)
        }
    }
}
