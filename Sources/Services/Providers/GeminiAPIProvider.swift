import SwiftUI

struct GeminiAPIProvider: AIUsageProvider {
    var id: String { "gemini" }
    var displayName: String { "Gemini" }
    
    func fetchUsage() async throws -> TokenUsage {
        guard let apiKey = AppSettings.shared.geminiApiKey, !apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPIProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gemini API Key not set"])
        }
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/usage") else {
            throw NSError(domain: "GeminiAPIProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GeminiAPIProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "Server returned error"])
        }
        
        return try JSONDecoder().decode(TokenUsage.self, from: data)
    }
    
    func settingsView() -> AnyView {
        AnyView(GeminiSettingsView())
    }
    
    func usageView(for usage: TokenUsage) -> AnyView {
        AnyView(GeminiUsageView(usage: usage))
    }
}

struct GeminiSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Section(header: Label("Gemini Configuration", systemImage: "key")) {
            Toggle("Enable AI usage tracking", isOn: $settings.isAIMonitoringEnabled)
            SecureField("Gemini API Key", text: Binding(
                get: { settings.geminiApiKey ?? "" },
                set: { settings.geminiApiKey = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(!settings.isAIMonitoringEnabled)
            
            Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                Label("Get API Key", systemImage: "link")
            }
            .foregroundStyle(.blue)
            
            TextField("Gemini CLI Path", text: $settings.geminiPath)
                .textFieldStyle(.roundedBorder)
                .disabled(!settings.isAIMonitoringEnabled)
        }
    }
}

struct GeminiUsageView: View {
    let usage: TokenUsage
    
    var body: some View {
        VStack(spacing: 8) {
            progressRow(label: "Pro", value: Double(usage.proTokens), color: .purple)
            progressRow(label: "Flash", value: Double(usage.flashTokens), color: .blue)
            progressRow(label: "Flash Lite", value: Double(usage.flashLiteTokens), color: .green)
        }
    }
    
    private func progressRow(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            ProgressView(value: value, total: 1000000) // Assuming 1M limit
                .tint(color)
        }
    }
}
