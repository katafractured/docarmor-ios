import Foundation

/// DocArmor sells a single non-consumable unlock IAP. That IAP plus a
/// Sovereign subscription (purchased in Vaultyx, detected through the shared
/// App Group `group.com.katafract.enclave`) are the only two paths to
/// premium-local features — see `EntitlementService`.
enum ProductID {
    static let unlock = "com.katafract.DocArmor.unlock"
    static let all: Set<String> = [unlock]
}
