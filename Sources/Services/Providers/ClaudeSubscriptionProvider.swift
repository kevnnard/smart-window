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
        Section(header: Label("Claude Configuration", systemImage: "brain.head.profile")) {
            TextField("Pro Tokens", value: $settings.claudeProTokens, format: .number)
            TextField("Flash Tokens", value: $settings.claudeFlashTokens, format: .number)
            TextField("Flash Lite Tokens", value: $settings.claudeFlashLiteTokens, format: .number)
        }
    }
}

struct ClaudeUsageView: View {
    let usage: TokenUsage
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            ProgressView("Pro Usage", value: Double(usage.proTokens), total: Double(settings.claudeProLimit))
            ProgressView("Flash Usage", value: Double(usage.flashTokens), total: Double(settings.claudeFlashLimit))
            ProgressView("Flash Lite Usage", value: Double(usage.flashLiteTokens), total: Double(settings.claudeFlashLiteLimit))
        }
    }
}
