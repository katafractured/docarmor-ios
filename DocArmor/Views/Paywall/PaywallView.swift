import SwiftUI
import StoreKit

/// Why the user landed on the paywall. Tunes the headline copy.
enum PaywallReason {
    case presentMode, travelMode, smartPacks, household, familyVault, cloudBackup

    var headline: String {
        switch self {
        case .presentMode:  "Present Mode"
        case .travelMode:   "Travel Mode"
        case .smartPacks:   "Smart Packs"
        case .household:    "Household"
        case .familyVault:  "Family Vault"
        case .cloudBackup:  "Cloud Backup"
        }
    }

    var subhead: String {
        switch self {
        case .presentMode:
            "Hand the phone to an agent with your passport full-screen, bright, and landscape-locked. No scrolling, no camera roll fumbling."
        case .travelMode:
            "Pull every travel document — passports, boarding passes, vaccine cards — into one ready-to-present space."
        case .smartPacks:
            "Organize documents by the moment you'll need them: Travel, Roadside, Medical, School, Family Emergency."
        case .household:
            "Track every family member's documents and see at a glance who's missing what."
        case .familyVault:
            "Each person in the household gets their own organized vault, all encrypted together."
        case .cloudBackup:
            "Keep an encrypted backup of your vault in Katafract Shards and sync across every device."
        }
    }

    /// Cloud backup is Sovereign-only — no one-time unlock path.
    var isSovereignOnly: Bool { self == .cloudBackup }
}

/// Three paths to unlock:
///   1. One-time DocArmor unlock IAP ($12.99) — full local features.
///   2. Enclave/Sovereign/Founder bundle token (via shared App Group) — full local features.
///   3. Sovereign subscription (sold in Vaultyx) — local features + cloud backup.
///
/// Cloud Backup reason shows only path #2 (Sovereign).
struct PaywallView: View {
    let reason: PaywallReason
    let entitlementService: EntitlementService
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showingError = false

    /// Vaultyx App Store URL — where Sovereign is sold.
    private static let vaultyxAppStoreURL = URL(string: "https://apps.apple.com/app/id6762418528")!

    var body: some View {
        ZStack {
            Color.kataBackgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // MARK: Header
                VStack(spacing: 14) {
                    Image(systemName: reason.isSovereignOnly ? "icloud.and.arrow.up.fill" : "lock.shield.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.kataChampagne.opacity(0.9), Color.white.opacity(0.9))

                    Text(reason.headline)
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Text(reason.subhead)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer().frame(height: 4)

                // MARK: Two paths
                VStack(spacing: 14) {
                    if !reason.isSovereignOnly {
                        unlockCard
                    }
                    sovereignCard
                }
                .padding(.horizontal, 16)

                Spacer()

                // MARK: Footer
                VStack(spacing: 10) {
                    Button {
                        Task { await entitlementService.restorePurchases() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }

                    Button(action: dismiss) {
                        Text("Not now")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .task {
            await entitlementService.loadProduct()
        }
        .alert("Purchase Error", isPresented: $showingError) {
            Button("OK") { entitlementService.purchaseError = nil }
        } message: {
            Text(entitlementService.purchaseError ?? "")
        }
        .onChange(of: entitlementService.purchaseError) { _, new in
            showingError = new != nil
        }
    }

    // MARK: - Option cards

    private var unlockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock DocArmor")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("One-time · keep forever")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                Text(entitlementService.unlockProduct?.displayPrice ?? "$12.99")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            bulletList([
                "Present Mode, Travel Mode, Smart Packs",
                "Custom Packs + Household members",
                "OCR auto-fill + all scenario surfaces",
                "Stays on-device — no account, no server",
            ])

            Button {
                Task {
                    if await entitlementService.purchaseUnlock() {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if entitlementService.isLoading {
                        ProgressView().tint(Color.kataNavy)
                    } else {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock for \(entitlementService.unlockProduct?.displayPrice ?? "$12.99")")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Color.kataNavy)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(entitlementService.isLoading)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var sovereignCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Get Sovereign")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("BONUS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.kataNavy)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.kataChampagne, in: Capsule())
                    }
                    Text("$18/mo or $144/yr · bundled with Vaultyx")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
            }

            bulletList([
                "Everything in the one-time unlock",
                "Encrypted cloud backup of your vault",
                "Cross-device sync — iPhone, iPad, Mac",
                "Vaultyx 1 TB storage + Wraith VPN + Haven DNS",
            ])

            Button {
                openURL(Self.vaultyxAppStoreURL)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Get Sovereign in Vaultyx")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Color.kataNavy)
                .background(Color.kataPremiumGradient, in: RoundedRectangle(cornerRadius: 12))
            }

            if !reason.isSovereignOnly {
                Button {
                    Task {
                        await entitlementService.refreshEntitlements()
                        if entitlementService.isSovereign { dismiss() }
                    }
                } label: {
                    Text("Already subscribed? Refresh entitlement")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.kataGold.opacity(0.16), Color.kataBronze.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.kataGold.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.kataChampagne.opacity(0.95))
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    PaywallView(
        reason: .presentMode,
        entitlementService: EntitlementService(),
        dismiss: { }
    )
}
