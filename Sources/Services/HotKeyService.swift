import Carbon
import Cocoa
import Foundation

// MARK: - HotKeyService

/// Manages global keyboard shortcuts using Carbon APIs.
/// Provides toggle overlay, next/previous window shortcuts.
@MainActor
final class HotKeyService: ObservableObject {

    static let shared = HotKeyService()

    // MARK: - Callbacks

    var onToggleOverlay: (() -> Void)?
    var onNextWindow: (() -> Void)?
    var onPreviousWindow: (() -> Void)?
    var onSwitchToWindow: ((Int) -> Void)?  // index 0-8 for ⌥1-⌥9

    // MARK: - Hot Key References

    private var toggleHotKeyRef: EventHotKeyRef?
    private var nextHotKeyRef: EventHotKeyRef?
    private var prevHotKeyRef: EventHotKeyRef?
    private var numberHotKeyRefs: [EventHotKeyRef?] = Array(repeating: nil, count: 9)

    private init() {}

    // MARK: - Registration

    /// Registers all global hotkeys.
    func registerHotKeys() {
        // ⌥ + Esc → Toggle overlay
        registerHotKey(
            keyCode: UInt32(kVK_Escape),
            modifiers: UInt32(optionKey),
            id: 1,
            ref: &toggleHotKeyRef
        )

        // ⌥ + ] → Next window
        registerHotKey(
            keyCode: UInt32(kVK_ANSI_RightBracket),
            modifiers: UInt32(optionKey),
            id: 2,
            ref: &nextHotKeyRef
        )

        // ⌥ + [ → Previous window
        registerHotKey(
            keyCode: UInt32(kVK_ANSI_LeftBracket),
            modifiers: UInt32(optionKey),
            id: 3,
            ref: &prevHotKeyRef
        )

        // ⌥ + 1-9 → Switch to window by index
        let numberKeyCodes: [Int] = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
            kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
            kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
        for i in 0..<9 {
            registerHotKey(
                keyCode: UInt32(numberKeyCodes[i]),
                modifiers: UInt32(optionKey),
                id: UInt32(10 + i),  // ids 10-18
                ref: &numberHotKeyRefs[i]
            )
        }

        // Install event handler
        installEventHandler()
    }

    /// Unregisters all global hotkeys.
    func unregisterHotKeys() {
        if let ref = toggleHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = nextHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = prevHotKeyRef { UnregisterEventHotKey(ref) }
        for ref in numberHotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
    }

    // MARK: - Private

    private func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        ref: inout EventHotKeyRef?
    ) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x5357_494E), id: id) // "SWIN"
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status != noErr {
            print("⚠️ Failed to register hotkey id=\(id), status=\(status)")
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // We need to capture `self` via a pointer for the C callback
        let service = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()

                DispatchQueue.main.async {
                    switch hotKeyID.id {
                    case 1: service.onToggleOverlay?()
                    case 2: service.onNextWindow?()
                    case 3: service.onPreviousWindow?()
                    case 10...18:
                        // ⌥1-⌥9 → switch to window at index (0-based)
                        let windowIndex = Int(hotKeyID.id) - 10
                        service.onSwitchToWindow?(windowIndex)
                    default: break
                    }
                }

                return noErr
            },
            1,
            &eventType,
            service,
            nil
        )
    }
}
