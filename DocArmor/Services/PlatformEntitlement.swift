import Foundation

/// Checks if user has an active Enclave/Sovereign/Founder platform token from shared App Group.
/// Written by WraithVPN or Vaultyx on subscription purchase.
enum PlatformEntitlement {
    static let sharedGroup = "group.com.katafract.enclave"
    static let tokenKey = "enclave_token"
    static let planKey = "enclave_plan"

    /// Returns true if user has an active Enclave, Enclave Plus, or Sovereign token.
    static var isPlatformUnlocked: Bool {
        guard let defaults = UserDefaults(suiteName: sharedGroup),
              let plan = defaults.string(forKey: planKey) else { return false }
        return ["enclave", "enclave_annual", "enclave_plus", "enclave_plus_annual", "sovereign", "sovereign_annual"].contains(plan)
    }
}
