import Foundation
import StoreKit
import SwiftUI

/// DocArmor entitlement model (as of 1.1.4 / 2026-04-20):
///
/// Three states:
///
///   • `.locked` — fresh install, no purchase, no Sovereign subscription.
///     Basic capabilities work (scan, view, basic folders, Face ID lock) but
///     premium surfaces (Present Mode, Travel Mode, Smart Packs, Custom
///     Packs, Household, Family Vault) show a paywall.
///
///   • `.unlocked` — the user paid the one-time `com.katafract.DocArmor.unlock`
///     IAP ($12.99, non-consumable). All local features unlocked. Cloud
///     backup still locked.
///
///   • `.sovereign` — the user has a Sovereign subscription in Vaultyx. Sigil
///     token lives in shared App Group `group.com.katafract.enclave`. DocArmor
///     reads the token, confirms plan == sovereign, unlocks everything AND
///     enables cloud backup / cross-device sync to Shards S3.
///
/// Either path (one-time unlock OR Sovereign) gets you premium local
/// features. Only Sovereign gets you cloud.
@Observable
@MainActor
final class EntitlementService {
    enum Plan: Int, Comparable {
        case locked    = 0
        case unlocked  = 1
        case sovereign = 2
        static func < (lhs: Plan, rhs: Plan) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var currentPlan: Plan = .locked
    private(set) var isLoading: Bool = false
    private(set) var unlockProduct: Product?
    var purchaseError: String?

    // MARK: - Feature gates

    /// Premium local features — unlocked either by one-time IAP or Sovereign.
    var hasPremiumLocal: Bool    { currentPlan >= .unlocked }
    var canUsePresentMode: Bool  { hasPremiumLocal }
    var canUseTravelMode: Bool   { hasPremiumLocal }
    var canUseCustomPacks: Bool  { hasPremiumLocal }
    var canManageHousehold: Bool { hasPremiumLocal }
    var hasFamilyVault: Bool     { hasPremiumLocal }
    var smartPackLimit: Int      { hasPremiumLocal ? .max : 1 }

    /// Cloud backup — Sovereign only.
    var hasCloudBackup: Bool { currentPlan == .sovereign }

    var isSovereign: Bool { currentPlan == .sovereign }

    // MARK: - Sovereign (App Group) detection

    private static let enclaveAppGroup = "group.com.katafract.enclave"
    private static let tokenKey        = "enclave.sigil.token"
    private static let planKey         = "enclave.sigil.plan"

    private var hasSovereignEntitlement: Bool {
        guard let defaults = UserDefaults(suiteName: Self.enclaveAppGroup) else { return false }
        let token = defaults.string(forKey: Self.tokenKey) ?? ""
        let plan  = (defaults.string(forKey: Self.planKey) ?? "").lowercased()
        return !token.isEmpty && (plan == "sovereign" || plan == "sovereign_annual")
    }

    // MARK: - StoreKit (one-time unlock)

    private var transactionListener: Task<Void, Never>?

    func startListening() {
        transactionListener?.cancel()
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let txn) = update {
                    await txn.finish()
                    await self.refreshEntitlements()
                }
            }
        }
        // Foreground refresh so Sovereign flips on/off without a relaunch.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshEntitlements() }
        }

        Task { await self.refreshEntitlements() }
    }

    func loadProduct() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [ProductID.unlock])
            unlockProduct = products.first
        } catch {
            // Product load failures aren't fatal — app just can't show price.
        }
    }

    func purchaseUnlock() async -> Bool {
        guard let product = unlockProduct else {
            purchaseError = "Unlock option is temporarily unavailable — please try again shortly."
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    await refreshEntitlements()
                    return currentPlan >= .unlocked
                }
                purchaseError = "Purchase could not be verified. Contact support if you were charged."
                return false
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Purchase is pending approval (parental, Ask to Buy, etc.)."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
        await refreshEntitlements()
    }

    /// Reconcile state across (a) current StoreKit entitlements and (b) the
    /// Enclave shared App Group. Highest wins.
    func refreshEntitlements() async {
        var newPlan: Plan = .locked

        // StoreKit: look for the non-consumable unlock
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == ProductID.unlock,
               txn.revocationDate == nil {
                newPlan = Self.max(newPlan, .unlocked)
            }
        }

        // Shared App Group: Sovereign from Vaultyx
        if hasSovereignEntitlement {
            newPlan = Self.max(newPlan, .sovereign)
        }

        currentPlan = newPlan
    }

    private static func max(_ a: Plan, _ b: Plan) -> Plan { a > b ? a : b }
}
