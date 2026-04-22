import Foundation
import KatafractStyle

// MARK: - Branded haptic actions for DocArmor
struct DocArmorHaptic {
    static func documentSaved() {
        KataHaptic.saved.fire()
    }
    
    static func syncComplete() {
        KataHaptic.saved.fire()
    }
    
    static func documentVerified() {
        KataHaptic.unlocked.fire()
    }
    
    static func scanCaptured() {
        KataHaptic.tap.fire()
    }
    
    static func deleteWarning() {
        KataHaptic.denied.fire()
    }
}
