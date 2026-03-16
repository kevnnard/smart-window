import Foundation
import SwiftUI

// MARK: - AppSettings

/// User-configurable settings persisted via UserDefaults.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    static let localTimezoneIdentifier = "Local"

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("previewTimezone") var previewTimezone: String = ""
    @AppStorage("temperatureUnit") var temperatureUnit: String = "C"
    
    @AppStorage("geminiPath") var geminiPath: String = "/opt/homebrew/bin/gemini"
    @AppStorage("isAIMonitoringEnabled") var isAIMonitoringEnabled: Bool = false
    
    @AppStorage("claudeProTokens") var claudeProTokens: Int = 0
    @AppStorage("claudeFlashTokens") var claudeFlashTokens: Int = 0
    @AppStorage("claudeFlashLiteTokens") var claudeFlashLiteTokens: Int = 0
    @AppStorage("claudeProLimit") var claudeProLimit: Int = 1000000
    @AppStorage("claudeFlashLimit") var claudeFlashLimit: Int = 1000000
    @AppStorage("claudeFlashLiteLimit") var claudeFlashLiteLimit: Int = 1000000
    
    @AppStorage("claudeDailyUsage") var claudeDailyUsage: Int = 0
    @AppStorage("claudeDailyLimit") var claudeDailyLimit: Int = 1000
    @AppStorage("claudeWeeklyUsage") var claudeWeeklyUsage: Int = 0
    @AppStorage("claudeWeeklyLimit") var claudeWeeklyLimit: Int = 7000

    var geminiApiKey: String? {
        get { KeychainManager.shared.load(key: "geminiApiKey") }
        set {
            if let value = newValue {
                KeychainManager.shared.save(key: "geminiApiKey", value: value)
            } else {
                KeychainManager.shared.delete(key: "geminiApiKey")
            }
        }
    }

    /// Extra timezone identifiers to show in the bar (e.g. "America/New_York", "Europe/London").
    @Published var extraTimezones: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(extraTimezones) {
                UserDefaults.standard.set(data, forKey: "extraTimezones")
            }
        }
    }

    /// Order of widgets in the bar.
    @Published var widgetOrder: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(widgetOrder) {
                UserDefaults.standard.set(data, forKey: "widgetOrder")
            }
        }
    }

    /// Visibility of widgets in the bar.
    @Published var widgetVisibility: [String: Bool] {
        didSet {
            if let data = try? JSONEncoder().encode(widgetVisibility) {
                UserDefaults.standard.set(data, forKey: "widgetVisibility")
            }
        }
    }

    /// Separator positions in the bar.
    @Published var separatorPositions: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(separatorPositions) {
                UserDefaults.standard.set(data, forKey: "separatorPositions")
            }
        }
    }

    /// Enabled AI providers.
    @Published var enabledProviders: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(enabledProviders) {
                UserDefaults.standard.set(data, forKey: "enabledProviders")
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

        if let data = UserDefaults.standard.data(forKey: "widgetOrder"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.widgetOrder = decoded
        } else {
            self.widgetOrder = ["RAM", "CPU", "Temperature", "GPU", "Battery"]
        }
        
        if let data = UserDefaults.standard.data(forKey: "widgetVisibility"),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.widgetVisibility = decoded
        } else {
            self.widgetVisibility = ["RAM": true, "CPU": true, "Temperature": true, "GPU": true, "Battery": true]
        }
        
        if let data = UserDefaults.standard.data(forKey: "separatorPositions"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.separatorPositions = decoded
        } else {
            self.separatorPositions = ["Battery"]
        }
        
        if let data = UserDefaults.standard.data(forKey: "enabledProviders"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.enabledProviders = decoded
        } else {
            self.enabledProviders = ["gemini"]
        }
    }
}
