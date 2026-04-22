import Foundation
import KatafractStyle

// MARK: - Branded haptic actions for DocArmor
struct DocArmorHaptic {
    static func documentSaved() {
        KataHaptic.saved()
    }
    
    static func syncComplete() {
        KataHaptic.committed()
    }
    
    static func documentVerified() {
        KataHaptic.unlocked()
    }
    
    static func scanCaptured() {
        KataHaptic.tap()
    }
    
    static func deleteWarning() {
        KataHaptic.denied()
    }
}
