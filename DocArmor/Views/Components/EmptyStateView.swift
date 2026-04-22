import SwiftUI
import KatafractStyle

// MARK: - Branded empty state for DocArmor
struct DocArmorEmptyState: View {
    let title: String
    let description: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color.kataChampagne.opacity(0.7))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.kataNavy)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.kataNavy.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kataIce.opacity(0.3))
    }
}
