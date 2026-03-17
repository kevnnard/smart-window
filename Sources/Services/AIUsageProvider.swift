import SwiftUI

protocol AIUsageProvider {
    var id: String { get }
    var displayName: String { get }
    func fetchUsage() async throws -> TokenUsage
    func settingsView() -> AnyView
    func usageView(for usage: TokenUsage) -> AnyView
}
