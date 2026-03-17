import Foundation
import Combine
import SwiftUI

@MainActor
final class AIUsageService: ObservableObject {
    @Published private(set) var usages: [String: TokenUsage] = [:]
    @Published private(set) var error: String?

    private var refreshTimer: Timer?
    private var lastRefreshDate: Date?
    private let cacheInterval: TimeInterval = 5 * 60 // 5 minutes
    
    // Registry of all available providers
    static let providerRegistry: [String: AIUsageProvider] = [
        "gemini": GeminiAPIProvider(),
        "claude": ClaudeSubscriptionProvider()
    ]
    
    // Enabled providers (derived from settings)
    private var activeProviders: [(String, AIUsageProvider)] {
        AppSettings.shared.enabledProviders.compactMap { key in
            if let provider = AIUsageService.providerRegistry[key] {
                return (key, provider)
            }
            return nil
        }
    }

    init() {
        Task { @MainActor in
            await refresh()
            startMonitoring()
        }
    }

    private func startMonitoring() {
        // Poll every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    private func refresh() async {
        // Cache check
        if let last = lastRefreshDate, Date().timeIntervalSince(last) < cacheInterval {
            return
        }

        do {
            if !AppSettings.shared.isAIMonitoringEnabled {
                throw NSError(domain: "AIUsageService", code: 0, userInfo: [NSLocalizedDescriptionKey: "AI Monitoring is disabled"])
            }
            
            var newUsages: [String: TokenUsage] = [:]
            for (key, provider) in activeProviders {
                let usage = try await provider.fetchUsage()
                newUsages[key] = usage
            }
            
            self.usages = newUsages
            self.lastRefreshDate = Date()
            self.error = nil
        } catch {
            print("AIUsageService: Error fetching usage: \(error)")
            self.error = "Failed to fetch usage: \(error.localizedDescription)"
        }
    }
}
