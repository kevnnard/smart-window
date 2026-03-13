import Foundation
import SwiftUI

// MARK: - AppSettings

/// User-configurable settings persisted via UserDefaults.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    /// Extra timezone identifiers to show in the bar (e.g. "America/New_York", "Europe/London").
    @Published var extraTimezones: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(extraTimezones) {
                UserDefaults.standard.set(data, forKey: "extraTimezones")
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "extraTimezones"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.extraTimezones = decoded
        } else {
            self.extraTimezones = []
        }
    }
}
