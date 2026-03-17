import SwiftUI

struct TokenUsagePopover: View {
    @ObservedObject var usageService: AIUsageService
    @Binding var showPopover: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Token Usage")
                .font(.system(size: 12, weight: .bold))
                .padding(.bottom, 4)
            
            if !usageService.usages.isEmpty {
                VStack(spacing: 8) {
                    ForEach(usageService.usages.keys.sorted(), id: \.self) { key in
                        if let usage = usageService.usages[key],
                           let provider = AIUsageService.providerRegistry[key] {
                            Text(provider.displayName.capitalized)
                                .font(.system(size: 10, weight: .bold))
                            provider.usageView(for: usage)
                        }
                    }
                }
            } else if let error = usageService.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else {
                Text("Loading...")
                    .font(.system(size: 10))
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}
