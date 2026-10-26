import Foundation
import Combine

/// A global view filter, not a rewrite of widget/display visibility preferences.
final class FocusMode: ObservableObject {
    static let shared = FocusMode()
    private let defaults: UserDefaults
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "focusModeEnabled") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "focusModeEnabled")
    }
    func visibleWidgets(in order: [String], isVisible: (String) -> Bool) -> [String] {
        isEnabled ? [] : order.filter(isVisible)
    }
}
