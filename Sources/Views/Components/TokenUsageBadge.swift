import SwiftUI

struct TokenUsageBadge: View {
    @ObservedObject var usageService: AIUsageService
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: usageService.error != nil ? "exclamationmark.triangle" : "sparkle")
                .font(.system(size: 11))
            
            if !usageService.usages.isEmpty {
                let total = usageService.usages.values.reduce(0) { $0 + $1.proTokens + $1.flashTokens + $1.flashLiteTokens }
                Text("\(total)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            } else {
                Text(usageService.error != nil ? "Error" : "---")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(usageService.error != nil ? Color.red.opacity(0.12) : Color.orange.opacity(0.12))
        )
        .foregroundStyle(usageService.error != nil ? .red : .orange)
    }
}
