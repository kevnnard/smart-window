import SwiftUI

struct ClaudeSubscriptionProvider: AIUsageProvider {
    var id: String { "claude" }
    var displayName: String { "Claude" }
    
    func fetchUsage() async throws -> TokenUsage {
        let settings = AppSettings.shared
        return TokenUsage(
            proTokens: settings.claudeProTokens,
            flashTokens: settings.claudeFlashTokens,
            flashLiteTokens: settings.claudeFlashLiteTokens
        )
    }
    
    func settingsView() -> AnyView {
        AnyView(ClaudeSettingsView())
    }
    
    func usageView(for usage: TokenUsage) -> AnyView {
        AnyView(ClaudeUsageView(usage: usage))
    }
}

struct ClaudeSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section(header: Label("Claude Usage Limits", systemImage: "gauge.medium")) {
                TextField("Daily Limit", value: $settings.claudeDailyLimit, format: .number)
                TextField("Weekly Limit", value: $settings.claudeWeeklyLimit, format: .number)
            }
            
            Section(header: Label("Claude Tokens", systemImage: "cpu")) {
                TextField("Pro Tokens", value: $settings.claudeProTokens, format: .number)
                TextField("Flash Tokens", value: $settings.claudeFlashTokens, format: .number)
                TextField("Flash Lite Tokens", value: $settings.claudeFlashLiteTokens, format: .number)
            }
        }
        .formStyle(.grouped)
    }
}

struct ClaudeUsageView: View {
    let usage: TokenUsage
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Daily Usage").font(.caption).foregroundColor(.secondary)
                ProgressView(value: Double(settings.claudeDailyUsage), total: Double(settings.claudeDailyLimit))
            }
            VStack(alignment: .leading) {
                Text("Weekly Usage").font(.caption).foregroundColor(.secondary)
                ProgressView(value: Double(settings.claudeWeeklyUsage), total: Double(settings.claudeWeeklyLimit))
            }
        }
        .padding()
    }
}
