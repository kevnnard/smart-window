import Foundation
import SwiftUI

// MARK: - AppSettings

/// User-configurable settings persisted via UserDefaults.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    private init() {}
}
