import SwiftUI
import KatafractStyle

struct BackupPassphraseSheet: View {
    let operation: SettingsView.BackupOperation
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)

                    if operation == .export {
                        SecureField("Confirm passphrase", text: $confirmation)
                    }
                } header: {
                    Text(operation == .export ? "Create Backup Passphrase" : "Unlock Backup")
                } footer: {
                    Text(footerText)
                }

                if operation == .export && !confirmation.isEmpty && confirmation != passphrase {
                    Section {
                        Text("Passphrases do not match.")
                            .font(.caption)
                            .foregroundStyle(Color.kataCrimson)
                    }
                }
            }
            .navigationTitle(operation == .export ? "Encrypted Backup" : "Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(operation == .export ? "Continue" : "Restore") {
                        onSubmit(passphrase)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard passphrase.count >= 8 else { return false }
        if operation == .export {
            return passphrase == confirmation
        }
        return true
    }

    private var footerText: String {
        switch operation {
        case .export:
            return "Use a passphrase you will remember. The backup is encrypted before it leaves the app."
        case .restore:
            return "Enter the passphrase used when the backup was created. Restoring replaces the current vault."
        }
    }
}
