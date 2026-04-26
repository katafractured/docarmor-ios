import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Shield logo
                ZStack {
                    Circle()
                        .fill(.tint.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                }

                VStack(spacing: 8) {
                    Text("DocArmor")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Your documents, encrypted on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Auth error message
                if let error = auth.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Unlock button
                Button(action: { Task { await auth.authenticate() } }) {
                    Label(unlockLabel, systemImage: biometryIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .disabled(auth.state == .authenticating)
                .accessibilityLabel(unlockLabel)

                Spacer().frame(height: 16)
            }
        }
    }

    private var biometryIcon: String {
        switch auth.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.open.fill"
        }
    }

    private var unlockLabel: String {
        if auth.state == .authenticating {
            return "Authenticating…"
        }
        switch auth.biometryType {
        case .faceID:  return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default:       return "Unlock with Passcode"
        }
    }
}

#Preview {
    LockScreenView()
        .environment(AuthService())
}
