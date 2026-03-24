import Foundation
import LocalAuthentication
import Observation

@Observable
@MainActor
final class AuthService {

    enum AuthState: Equatable {
        case locked
        case authenticating
        case unlocked
    }

    var state: AuthState = .locked
    var biometryType: LABiometryType = .none
    var authError: String?

    init() {
        checkBiometryAvailability()
    }

    // MARK: - Biometry

    func checkBiometryAvailability() {
#if targetEnvironment(simulator)
        biometryType = .none
#else
        // Use a fresh context just for capability detection; LAContext is not reusable
        // across evaluate calls so we never cache the instance.
        let probeContext = LAContext()
        var error: NSError?
        probeContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        biometryType = probeContext.biometryType
#endif
    }

    // MARK: - Authenticate

    func authenticate() async {
        guard state != .unlocked else { return }

#if targetEnvironment(simulator)
        authError = nil
        state = .unlocked
#else
        state = .authenticating
        authError = nil

        let reason = "Unlock DocArmor to access your documents."
        let freshContext = LAContext()

        do {
            let success = try await freshContext.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if success {
                state = .unlocked
            } else {
                state = .locked
            }
        } catch let laError as LAError {
            state = .locked
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                // User dismissed — stay locked, no error shown
                break
            case .biometryNotAvailable, .biometryNotEnrolled:
                authError = "Biometrics unavailable. Use your device passcode."
            case .biometryLockout:
                authError = "Too many failed attempts. Use your device passcode."
            default:
                authError = laError.localizedDescription
            }
        } catch {
            state = .locked
            authError = error.localizedDescription
        }
#endif
    }

    // MARK: - Lock

    func lock() {
        guard state == .unlocked else { return }
        state = .locked
        authError = nil
    }
}
