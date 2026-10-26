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

    // MARK: Appearance

    /// Opacity of the bar background (0.6-1.0). Lower values let the wallpaper show through.
    @AppStorage("barOpacity") var barOpacity: Double = 0.94
    /// When true the notch badge uses the bar color; otherwise pure black.
    @AppStorage("notchBadgeMatchesBar") var notchBadgeMatchesBar: Bool = false

    /// Every widget the bar knows how to render, in default order.
    static let knownWidgets: [String] = ["RAM", "CPU", "Temperature", "GPU", "MIC", "VOL", "Tailscale", "Keyboard", "Battery"]

    /// Human-readable name for a widget identifier.
    static func widgetDisplayName(_ id: String) -> String {
        switch id {
        case "RAM": return "Memory"
        case "CPU": return "CPU"
        case "GPU": return "GPU"
        case "MIC": return "Microphone"
        case "VOL": return "Volume"
        case "Tailscale": return "Tailscale VPN"
        case "Keyboard": return "Keyboard input"
        default: return id
        }
    }

    /// Drops widgets the bar no longer renders and appends known widgets missing from the
    /// stored order as hidden, so they can be enabled.
    func reconcileWidgets() {
        let known = Set(Self.knownWidgets)
        let cleaned = widgetOrder.filter { known.contains($0) }
        let missing = Self.knownWidgets.filter { !cleaned.contains($0) }
        guard cleaned != widgetOrder || !missing.isEmpty else { return }
        widgetOrder = cleaned + missing
        for id in missing where widgetVisibility[id] == nil {
            widgetVisibility[id] = false
        }
    }
    
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
