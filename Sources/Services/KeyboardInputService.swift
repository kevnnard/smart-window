import Carbon
import Combine
import Foundation

/// Uses the same enabled keyboard input sources as the macOS Input menu.
@MainActor
final class KeyboardInputService: ObservableObject {
    static let shared = KeyboardInputService()

    struct Source: Identifiable, Equatable {
        let id: String
        let name: String

        var shortLabel: String {
            switch id {
            case "com.apple.keylayout.US": return "US"
            case "com.apple.keylayout.LatinAmerican": return "LAT"
            case "com.apple.keylayout.ABC": return "ABC"
            default: return String(name.prefix(5))
            }
        }
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var selectionError: String?

    var selectedSource: Source? { sources.first { $0.id == selectedID } }
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged!, kTISNotifyEnabledKeyboardInputSourcesChanged!] {
            observers.append(center.addObserver(forName: Notification.Name(name as String), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    deinit {
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    func refresh() {
        sources = Self.enabledSources().compactMap(Self.describe)
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        selectedID = Self.string(current, kTISPropertyInputSourceID)
    }

    /// Only selects an already enabled source; never enables or installs a layout.
    @discardableResult
    func select(id: String) -> Bool {
        guard let source = Self.enabledSources().first(where: { Self.string($0, kTISPropertyInputSourceID) == id }) else {
            selectionError = "This input source is no longer available."
            refresh()
            return false
        }
        let result = TISSelectInputSource(source)
        refresh()
        guard result == noErr, selectedID == id else {
            selectionError = "macOS could not select this input source. Try again from the system Input menu."
            return false
        }
        selectionError = nil
        return true
    }

    private static func enabledSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource!] as CFDictionary
        let all = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        return all.filter { flag($0, kTISPropertyInputSourceIsEnabled) && flag($0, kTISPropertyInputSourceIsSelectCapable) }
    }

    private static func describe(_ source: TISInputSource) -> Source? {
        guard let id = string(source, kTISPropertyInputSourceID),
              let name = string(source, kTISPropertyLocalizedName) else { return nil }
        return Source(id: id, name: name)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
