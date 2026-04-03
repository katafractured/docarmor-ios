import SwiftUI
import SwiftData
import LocalAuthentication
import UniformTypeIdentifiers

struct SettingsView: View {
    private enum FocusedField: Hashable {
        case newMemberName
    }

    enum BackupOperation: String, Identifiable {
        case export
        case restore

        var id: String { rawValue }
    }

    enum SuggestedPackKind: String, CaseIterable, Identifiable {
        case travel
        case vehicle
        case family
        case school
        case medical
        case work
        case property
        case disaster
        case dependent
        case pet

        var id: String { rawValue }

        var title: String {
            switch self {
            case .travel: return "Travel & Identity Pack"
            case .vehicle: return "Vehicle & Roadside Pack"
            case .family: return "Family Emergency Pack"
            case .school: return "School Pack"
            case .medical: return "Medical Visit Pack"
            case .work: return "Work Credential Pack"
            case .property: return "Property Claim Pack"
            case .disaster: return "Grab-and-Go Pack"
            case .dependent: return "Dependent Care Pack"
            case .pet: return "Pet & Boarding Pack"
            }
        }

        var systemImage: String {
            switch self {
            case .travel: return "airplane.departure"
            case .vehicle: return "car.fill"
            case .family: return "person.3.sequence.fill"
            case .school: return "graduationcap.fill"
            case .medical: return "cross.case.fill"
            case .work: return "briefcase.fill"
            case .property: return "house.fill"
            case .disaster: return "bolt.shield.fill"
            case .dependent: return "person.2.crop.square.stack.fill"
            case .pet: return "pawprint.fill"
            }
        }

        var recommendationCaption: String {
            switch self {
            case .travel: return "Recommended because you already store travel, passport, or identity documents."
            case .vehicle: return "Recommended for adult household members and roadside-ready access."
            case .family: return "Recommended because your household spans multiple people."
            case .school: return "Recommended because your household includes a child."
            case .medical: return "Recommended because medical or insurance records are already present."
            case .work: return "Recommended because work or credential records are already present."
            case .property: return "Recommended because property or insurance records are already present."
            case .disaster: return "Recommended to keep emergency documents together."
            case .dependent: return "Recommended because your household includes a child or senior profile."
            case .pet: return "Recommended because your household includes a pet profile."
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AuthService.self) private var auth
    @Environment(AutoLockService.self) private var autoLock
    @Query private var allDocuments: [Document]

    @State private var showingResetAlert = false
    @State private var showingResetConfirm = false
    @State private var isResetting = false
    @State private var householdProfiles: [HouseholdMemberProfile] = []
    @State private var newMemberName = ""
    @State private var newMemberRole: HouseholdRole = .adult
    @State private var showingRestoreConfirm = false
    @State private var showingFileImporter = false
    @State private var showingFileExporter = false
    @State private var activeBackupOperation: BackupOperation?
    @State private var pendingImportURL: URL?
    @State private var backupDocument = EncryptedBackupDocument()
    @State private var backupFilename = ""
    @State private var backupError: String?
    @State private var backupSuccessMessage: String?
    @State private var emergencyCard = EmergencyCardData()
    @AppStorage("smartPack.travelEnabled") private var travelPackEnabled = true
    @AppStorage("smartPack.vehicleEnabled") private var vehiclePackEnabled = true
    @AppStorage("smartPack.familyEnabled") private var familyPackEnabled = true
    @AppStorage("smartPack.schoolEnabled") private var schoolPackEnabled = true
    @AppStorage("smartPack.medicalEnabled") private var medicalPackEnabled = true
    @AppStorage("smartPack.workEnabled") private var workPackEnabled = true
    @AppStorage("smartPack.propertyEnabled") private var propertyPackEnabled = true
    @AppStorage("smartPack.disasterEnabled") private var disasterPackEnabled = true
    @AppStorage("smartPack.dependentEnabled") private var dependentPackEnabled = true
    @AppStorage("smartPack.petEnabled") private var petPackEnabled = true
    @AppStorage("smartPack.preparednessEnabled") private var preparednessEnabled = true
    @AppStorage("smartPack.renewalEnabled") private var renewalPackEnabled = true
    @AppStorage("smartPack.customPacks") private var customPacksRawStorage = ""
    @AppStorage("smartPack.customEnabled") private var legacyCustomPackEnabled = false
    @AppStorage("smartPack.customTitle") private var legacyCustomPackTitle = "My Fast Pack"
    @AppStorage("smartPack.customTypes") private var legacyCustomPackRawTypes =
        DocumentType.encodePackSelection([.passport, .driversLicense, .insuranceHealth])
    @State private var customPacks: [SavedCustomPack] = []
    @State private var foundationModelStatus: FoundationModelAvailabilityService.Status = .unavailable(.frameworkUnavailable)
    @State private var vaultKeyExists: Bool = false
    @State private var hasLoadedInitialState = false
    @FocusState private var focusedField: FocusedField?

    // Cached derived state — recomputed only when inputs change, not on every render
    @State private var cachedPackRecommendations: [LocalIntelligenceRecommendationService.PackRecommendation] = []
    @State private var cachedReadinessRecommendations: [LocalIntelligenceRecommendationService.ReadinessRecommendation] = []
    @State private var cachedAttentionCount: Int = 0
    @State private var cachedRemindersCount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Security
                Section("Security") {
                    Picker("Auto-Lock", selection: autoLockTimeoutBinding) {
                        ForEach(AutoLockService.Timeout.allCases) { timeout in
                            Text(timeout.displayName).tag(timeout)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Label("Biometrics", systemImage: biometryIcon)
                        Spacer()
                        Text(biometryName)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Vault
                Section("Vault") {
                    HStack {
                        Label("Documents", systemImage: "doc.fill")
                        Spacer()
                        Text("\(allDocuments.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset Vault", systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
                    .disabled(isResetting)
                }

                Section("Encrypted Backup") {
                    Button {
                        activeBackupOperation = .export
                    } label: {
                        Label("Export Encrypted Backup", systemImage: "square.and.arrow.up.fill")
                    }

                    Button {
                        showingRestoreConfirm = true
                    } label: {
                        Label("Restore Encrypted Backup", systemImage: "square.and.arrow.down.fill")
                    }

                    Text("Backups are encrypted with a passphrase you choose. DocArmor cannot recover that passphrase for you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Household") {
                    if householdProfiles.isEmpty {
                        Text("No family members added yet. Add one to organize documents per person.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(householdProfiles) { profile in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 10) {
                                    Label(profile.name, systemImage: profile.role.systemImage)
                                    Spacer()
                                    Text("\(documentCount(for: profile.name))")
                                        .foregroundStyle(.secondary)
                                    Button {
                                        removeHouseholdProfile(named: profile.name)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Picker("Role", selection: householdRoleBinding(for: profile.name)) {
                                    ForEach(HouseholdRole.allCases) { role in
                                        Text(role.displayName).tag(role)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Add family member", text: $newMemberName)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .newMemberName)

                        Picker("New member role", selection: $newMemberRole) {
                            ForEach(HouseholdRole.allCases) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .pickerStyle(.menu)

                        Button("Add") {
                            addHouseholdMember()
                            newMemberName = ""
                            newMemberRole = .adult
                            focusedField = nil
                        }
                        .disabled(HouseholdStore.normalize(newMemberName) == nil)
                    }

                    Label("Documents can also stay shared for the whole household.", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Security Status") {
                    statusRow(
                        title: "Vault Key",
                        systemImage: vaultKeyExists ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        value: vaultKeyExists ? "Stored in Keychain" : "Not provisioned"
                    )

                    statusRow(
                        title: "Storage",
                        systemImage: "iphone",
                        value: "Local-only"
                    )

                    statusRow(
                        title: "Network Activity",
                        systemImage: "network.slash",
                        value: "None by design"
                    )

                    statusRow(
                        title: "Auto-Lock",
                        systemImage: "lock.badge.clock",
                        value: autoLock.selectedTimeout.displayName
                    )

                    statusRow(
                        title: "Reminder Coverage",
                        systemImage: "bell.badge.fill",
                        value: "\(documentsWithRemindersCount) configured"
                    )

                    statusRow(
                        title: "Attention Queue",
                        systemImage: "exclamationmark.triangle.fill",
                        value: "\(attentionDocumentsCount) document(s)"
                    )

                    statusRow(
                        title: "Backup Format",
                        systemImage: "archivebox.fill",
                        value: ".docarmorbackup"
                    )
                }

                Section("On-Device Intelligence") {
                    statusRow(
                        title: "Apple Intelligence",
                        systemImage: foundationModelStatusSystemImage,
                        value: foundationModelStatusText
                    )

                    if let foundationModelFallbackDescription {
                        Text(foundationModelFallbackDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Smart Packs") {
                    smartPackToggle(
                        title: "Travel & Identity Pack",
                        caption: "Travel mode, passports, IDs, and public verification shortcuts.",
                        isOn: $travelPackEnabled
                    )
                    smartPackToggle(
                        title: "Vehicle & Roadside Pack",
                        caption: "Roadside-ready license and auto-insurance access.",
                        isOn: $vehiclePackEnabled
                    )
                    smartPackToggle(
                        title: "Family Emergency Pack",
                        caption: "Household identity and medical essentials for urgent use.",
                        isOn: $familyPackEnabled
                    )
                    smartPackToggle(
                        title: "School Pack",
                        caption: "Enrollment and school administration documents.",
                        isOn: $schoolPackEnabled
                    )
                    smartPackToggle(
                        title: "Medical Visit Pack",
                        caption: "Insurance, prescriptions, and intake-ready records.",
                        isOn: $medicalPackEnabled
                    )
                    smartPackToggle(
                        title: "Work Credential Pack",
                        caption: "Onboarding and professional credential documents.",
                        isOn: $workPackEnabled
                    )
                    smartPackToggle(
                        title: "Property Claim Pack",
                        caption: "Home-claim and housing-admin documents.",
                        isOn: $propertyPackEnabled
                    )
                    smartPackToggle(
                        title: "Grab-and-Go Pack",
                        caption: "Disaster-response identity, medical, and insurance records.",
                        isOn: $disasterPackEnabled
                    )
                    smartPackToggle(
                        title: "Dependent Care Pack",
                        caption: "Caregiver-ready identity, prescription, and emergency-contact records.",
                        isOn: $dependentPackEnabled
                    )
                    smartPackToggle(
                        title: "Pet & Boarding Pack",
                        caption: "Pet boarding, vaccine, and emergency-style records.",
                        isOn: $petPackEnabled
                    )
                    smartPackToggle(
                        title: "Preparedness Checklist",
                        caption: "Top-level dashboard summarizing readiness across scenarios.",
                        isOn: $preparednessEnabled
                    )
                    smartPackToggle(
                        title: "Renewal Workflows",
                        caption: "Grouped renewal and attention workflows near the top of the vault.",
                        isOn: $renewalPackEnabled
                    )
                }

                if !packRecommendations.isEmpty {
                    Section("Suggested Packs") {
                        ForEach(packRecommendations) { pack in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: pack.systemImage)
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pack.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(pack.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Turn On") {
                                    enableSuggestedPack(pack.key)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !readinessRecommendations.isEmpty {
                    Section("Readiness Suggestions") {
                        ForEach(readinessRecommendations) { recommendation in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(recommendation.title, systemImage: recommendation.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                Text(recommendation.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Custom Packs") {
                    if customPacks.isEmpty {
                        Text("Create reusable fast-access packs for your own scenarios.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customPacks.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Enabled", isOn: customPackEnabledBinding(for: index))
                                TextField("Pack title", text: customPackTitleBinding(for: index))
                                    .autocorrectionDisabled()

                                Text("Choose the document types that should appear together in this pack.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ForEach(DocumentType.allCases, id: \.self) { type in
                                    Toggle(type.rawValue, isOn: customPackTypeBinding(for: index, type: type))
                                }

                                Button("Delete Pack", role: .destructive) {
                                    removeCustomPack(at: index)
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button {
                        addCustomPack()
                    } label: {
                        Label("Add Custom Pack", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Toggle("Show Emergency Card on Lock Screen", isOn: $emergencyCard.isEnabled)
                        .onChange(of: emergencyCard.isEnabled) { _, _ in
                            EmergencyCardStore.save(emergencyCard)
                        }

                    if emergencyCard.isEnabled {
                        Label(
                            "This data is visible without unlocking DocArmor. Only add what you want emergency responders to see.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)

                        emergencyField("Blood Type", text: $emergencyCard.bloodType, placeholder: "e.g. O+")
                        emergencyField(
                            "Allergies",
                            text: $emergencyCard.allergies,
                            placeholder: "e.g. Penicillin, Peanuts"
                        )
                        emergencyField(
                            "Medical Notes",
                            text: $emergencyCard.medicalNotes,
                            placeholder: "e.g. Diabetic, Pacemaker"
                        )
                        emergencyField(
                            "Emergency Contact 1 Name",
                            text: $emergencyCard.contact1Name,
                            placeholder: "Name"
                        )
                        emergencyField(
                            "Emergency Contact 1 Phone",
                            text: $emergencyCard.contact1Phone,
                            placeholder: "+1 555 000 0000"
                        )
                        emergencyField(
                            "Emergency Contact 2 Name",
                            text: $emergencyCard.contact2Name,
                            placeholder: "Name"
                        )
                        emergencyField(
                            "Emergency Contact 2 Phone",
                            text: $emergencyCard.contact2Phone,
                            placeholder: "+1 555 000 0000"
                        )
                    }
                } header: {
                    Label("Emergency Card", systemImage: "cross.case.fill")
                        .foregroundStyle(.red)
                } footer: {
                    Text("Visible on the lock screen to emergency responders when the widget is added.")
                }

                // MARK: About
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Developer", systemImage: "person.fill")
                        Spacer()
                        Text("Katafract LLC")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Support & Legal") {
                    externalLinkRow(
                        title: "App Page",
                        systemImage: "app.badge",
                        urlString: "https://katafract.com/apps/docarmor"
                    )

                    externalLinkRow(
                        title: "Support",
                        systemImage: "questionmark.circle",
                        urlString: "https://katafract.com/support/docarmor"
                    )

                    externalLinkRow(
                        title: "Privacy Policy",
                        systemImage: "hand.raised.fill",
                        urlString: "https://katafract.com/privacy/docarmor"
                    )

                    externalLinkRow(
                        title: "Terms of Use",
                        systemImage: "doc.text",
                        urlString: "https://katafract.com/terms/docarmor"
                    )
                }

                // MARK: Privacy Statement
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("100% Local Storage", systemImage: "iphone")
                            .font(.caption.bold())
                        Text("Your documents never leave this device. DocArmor makes zero network connections and has no server infrastructure.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField = nil
                }
            )
            .navigationTitle("Settings")
            .alert("Reset Vault?", isPresented: $showingResetAlert) {
                Button("Reset Everything", role: .destructive) {
                    showingResetConfirm = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete ALL documents and the encryption key. Your data will be unrecoverable. This cannot be undone.")
            }
            .confirmationDialog("Are you absolutely sure?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
                Button("Delete Everything Forever", role: .destructive) {
                    Task { await resetVault() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(allDocuments.count) document(s) will be permanently destroyed.")
            }
            .confirmationDialog("Restore Backup?", isPresented: $showingRestoreConfirm, titleVisibility: .visible) {
                Button("Choose Backup File", role: .destructive) {
                    showingFileImporter = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restoring replaces the current vault, its encryption key, and reminders with the contents of the backup file.")
            }
            .sheet(item: $activeBackupOperation) { operation in
                BackupPassphraseSheet(operation: operation) { passphrase in
                    Task { await handleBackupPassphrase(passphrase, operation: operation) }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.docarmorBackup, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    pendingImportURL = urls.first
                    activeBackupOperation = .restore
                case .failure(let error):
                    backupError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $showingFileExporter,
                document: backupDocument,
                contentType: .docarmorBackup,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success:
                    backupSuccessMessage = "Encrypted backup exported successfully."
                case .failure(let error):
                    backupError = error.localizedDescription
                }
            }
            .alert("Backup Error", isPresented: backupErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupError ?? "The encrypted backup operation failed.")
            }
            .alert("Backup Complete", isPresented: backupSuccessBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupSuccessMessage ?? "Done.")
            }
            .task {
                guard !hasLoadedInitialState else { return }
                hasLoadedInitialState = true

                async let profiles: [HouseholdMemberProfile] = Task.detached(priority: .userInitiated) {
                    HouseholdStore.loadProfiles()
                }.value
                async let defaultBackupFilename: String = Task.detached(priority: .utility) {
                    BackupService.defaultFilename()
                }.value

                householdProfiles = await profiles
                emergencyCard = EmergencyCardStore.load()
                backupFilename = await defaultBackupFilename

                migrateLegacyCustomPacksIfNeeded()
                refreshDerivedState()

                // VaultKey.exists (Keychain) and SystemLanguageModel.default
                // (FoundationModels framework init) are synchronous blocking calls.
                // Running them on the main actor — even inside .task — hangs the UI
                // immediately after Face ID when the tab is first tapped.
                // Offload both to background threads; update @State on MainActor after.
                async let keyExists: Bool = Task.detached(priority: .userInitiated) {
                    VaultKey.exists
                }.value
                async let modelStatus: FoundationModelAvailabilityService.Status = Task.detached(priority: .userInitiated) {
                    FoundationModelAvailabilityService.currentStatus
                }.value

                let (key, model) = await (keyExists, modelStatus)
                vaultKeyExists = key
                foundationModelStatus = model
            }
            .onChange(of: allDocuments) { refreshDerivedState() }
            .onChange(of: householdProfiles) { refreshDerivedState() }
            .onChange(of: packEnabledFingerprint) { refreshDerivedState() }
        }
    }

    // MARK: - Derived state cache

    private func refreshDerivedState() {
        cachedPackRecommendations = LocalIntelligenceRecommendationService.packRecommendations(
            documents: allDocuments,
            householdProfiles: householdProfiles,
            enabledPacks: enabledPackKeys
        )
        cachedReadinessRecommendations = LocalIntelligenceRecommendationService.readinessRecommendations(
            documents: allDocuments,
            householdProfiles: householdProfiles
        )
        cachedAttentionCount = allDocuments.filter(\.needsAttention).count
        cachedRemindersCount = allDocuments.filter { !($0.expirationReminderDays ?? []).isEmpty }.count
    }

    // MARK: - Reset Vault

    private func resetVault() async {
        isResetting = true
        ExpirationService.cancelAllReminders()

        // Delete all SwiftData records
        for doc in allDocuments {
            modelContext.delete(doc)
        }

        // Explicitly save before touching the Keychain. SwiftData batches deletes
        // and may not flush until the next auto-save window; if the app crashes
        // after VaultKey.delete() but before the context saves, stale encrypted
        // records remain — now undecryptable with the new key.
        try? modelContext.save()

        // Delete vault encryption key — encrypted data is now unrecoverable garbage
        try? VaultKey.delete()

        // Generate a fresh key for any future use
        _ = try? VaultKey.generate()

        auth.lock()
        isResetting = false
    }

    @MainActor
    private func handleBackupPassphrase(_ passphrase: String, operation: BackupOperation) async {
        do {
            switch operation {
            case .export:
                backupDocument = try BackupService.exportBackup(
                    documents: allDocuments,
                    householdMembers: householdProfiles.map(\.name),
                    passphrase: passphrase
                )
                backupFilename = BackupService.defaultFilename()
                showingFileExporter = true
            case .restore:
                guard let importURL = pendingImportURL else {
                    backupError = "Choose a backup file to restore."
                    return
                }
                let didAccess = importURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        importURL.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: importURL)
                try BackupService.restoreBackup(from: data, passphrase: passphrase, into: modelContext)
                householdProfiles = HouseholdStore.loadProfiles()
                pendingImportURL = nil
                backupSuccessMessage = "Encrypted backup restored successfully."
            }
        } catch {
            backupError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var biometryIcon: String {
        switch auth.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.fill"
        }
    }

    private var autoLockTimeoutBinding: Binding<AutoLockService.Timeout> {
        Binding(
            get: { autoLock.selectedTimeout },
            set: { autoLock.selectedTimeout = $0 }
        )
    }

    private var biometryName: String {
        switch auth.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Passcode"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var backupErrorBinding: Binding<Bool> {
        Binding(
            get: { backupError != nil },
            set: { if !$0 { backupError = nil } }
        )
    }

    private var backupSuccessBinding: Binding<Bool> {
        Binding(
            get: { backupSuccessMessage != nil },
            set: { if !$0 { backupSuccessMessage = nil } }
        )
    }

    private func documentCount(for member: String) -> Int {
        allDocuments.filter { $0.ownerDisplayName == member }.count
    }

    private func householdRoleBinding(for memberName: String) -> Binding<HouseholdRole> {
        Binding(
            get: { householdProfiles.first(where: { $0.name == memberName })?.role ?? .adult },
            set: { newRole in
                updateHouseholdRole(for: memberName, role: newRole)
            }
        )
    }

    private func addHouseholdMember() {
        guard let normalized = HouseholdStore.normalize(newMemberName),
              !householdProfiles.contains(where: { $0.name == normalized }) else {
            return
        }

        householdProfiles.append(HouseholdMemberProfile(name: normalized, role: newMemberRole))
        householdProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        HouseholdStore.saveProfiles(householdProfiles)
    }

    private func removeHouseholdProfile(named name: String) {
        householdProfiles.removeAll { $0.name == name }
        HouseholdStore.saveProfiles(householdProfiles)
    }

    private func updateHouseholdRole(for memberName: String, role: HouseholdRole) {
        householdProfiles = householdProfiles.map { profile in
            guard profile.name == memberName else { return profile }
            return HouseholdMemberProfile(name: profile.name, role: role)
        }
        HouseholdStore.saveProfiles(householdProfiles)
    }

    private var documentsWithRemindersCount: Int { cachedRemindersCount }

    private var enabledPackKeys: Set<LocalIntelligenceRecommendationService.SmartPackKey> {
        var keys: Set<LocalIntelligenceRecommendationService.SmartPackKey> = []
        if travelPackEnabled { keys.insert(.travel) }
        if vehiclePackEnabled { keys.insert(.vehicle) }
        if familyPackEnabled { keys.insert(.family) }
        if schoolPackEnabled { keys.insert(.school) }
        if medicalPackEnabled { keys.insert(.medical) }
        if workPackEnabled { keys.insert(.work) }
        if propertyPackEnabled { keys.insert(.property) }
        if disasterPackEnabled { keys.insert(.disaster) }
        if dependentPackEnabled { keys.insert(.dependent) }
        if petPackEnabled { keys.insert(.pet) }
        return keys
    }

    private var packRecommendations: [LocalIntelligenceRecommendationService.PackRecommendation] {
        cachedPackRecommendations
    }

    private var readinessRecommendations: [LocalIntelligenceRecommendationService.ReadinessRecommendation] {
        cachedReadinessRecommendations
    }

    /// Cheap fingerprint of all pack-enabled toggles — used as onChange trigger.
    private var packEnabledFingerprint: Int {
        [travelPackEnabled, vehiclePackEnabled, familyPackEnabled, schoolPackEnabled,
         medicalPackEnabled, workPackEnabled, propertyPackEnabled, disasterPackEnabled,
         dependentPackEnabled, petPackEnabled]
            .enumerated()
            .reduce(0) { acc, pair in pair.element ? acc | (1 << pair.offset) : acc }
    }

    private var attentionDocumentsCount: Int { cachedAttentionCount }

    private var foundationModelStatusText: String {
        switch foundationModelStatus {
        case .available:
            return "Available"
        case .unavailable:
            return "Fallback Mode"
        }
    }

    private var foundationModelStatusSystemImage: String {
        switch foundationModelStatus {
        case .available:
            return "sparkles.rectangle.stack.fill"
        case .unavailable:
            return "cpu"
        }
    }

    private var foundationModelFallbackDescription: String? {
        guard case let .unavailable(reason) = foundationModelStatus else { return nil }
        return reason.userFacingDescription
    }

    private func statusRow(title: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func enableSuggestedPack(_ pack: LocalIntelligenceRecommendationService.SmartPackKey) {
        switch pack {
        case .travel:
            travelPackEnabled = true
        case .vehicle:
            vehiclePackEnabled = true
        case .family:
            familyPackEnabled = true
        case .school:
            schoolPackEnabled = true
        case .medical:
            medicalPackEnabled = true
        case .work:
            workPackEnabled = true
        case .property:
            propertyPackEnabled = true
        case .disaster:
            disasterPackEnabled = true
        case .dependent:
            dependentPackEnabled = true
        case .pet:
            petPackEnabled = true
        }
    }

    private func migrateLegacyCustomPacksIfNeeded() {
        if !customPacks.isEmpty {
            return
        }

        let decoded = SavedCustomPack.decodeList(from: customPacksRawStorage)
        if !decoded.isEmpty {
            customPacks = decoded
            return
        }

        let legacyTypes = DocumentType.decodePackSelection(from: legacyCustomPackRawTypes)
        guard !legacyTypes.isEmpty else { return }

        let migrated = [
            SavedCustomPack(
                title: legacyCustomPackTitle,
                isEnabled: legacyCustomPackEnabled,
                documentTypes: legacyTypes
            )
        ]
        persistCustomPacks(migrated)
    }

    private func persistCustomPacks(_ packs: [SavedCustomPack]) {
        customPacks = packs
        customPacksRawStorage = SavedCustomPack.encodeList(packs)
    }

    private func addCustomPack() {
        var packs = customPacks
        packs.append(SavedCustomPack(title: "My Fast Pack", isEnabled: true, documentTypes: [.passport, .driversLicense]))
        persistCustomPacks(packs)
    }

    private func removeCustomPack(at index: Int) {
        guard customPacks.indices.contains(index) else { return }
        var packs = customPacks
        packs.remove(at: index)
        persistCustomPacks(packs)
    }

    private func customPackTitleBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { customPacks.indices.contains(index) ? customPacks[index].title : "" },
            set: { title in
                guard customPacks.indices.contains(index) else { return }
                var packs = customPacks
                packs[index].title = title
                persistCustomPacks(packs)
            }
        )
    }

    private func customPackEnabledBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { customPacks.indices.contains(index) ? customPacks[index].isEnabled : false },
            set: { isEnabled in
                guard customPacks.indices.contains(index) else { return }
                var packs = customPacks
                packs[index].isEnabled = isEnabled
                persistCustomPacks(packs)
            }
        )
    }

    private func customPackTypeBinding(for index: Int, type: DocumentType) -> Binding<Bool> {
        Binding(
            get: {
                guard customPacks.indices.contains(index) else { return false }
                return customPacks[index].documentTypes.contains(type)
            },
            set: { isSelected in
                guard customPacks.indices.contains(index) else { return }
                var packs = customPacks
                var updatedTypes = packs[index].documentTypes
                if isSelected {
                    if !updatedTypes.contains(type) {
                        updatedTypes.append(type)
                    }
                } else {
                    updatedTypes.removeAll { $0 == type }
                }
                packs[index].encodedTypes = DocumentType.encodePackSelection(updatedTypes)
                persistCustomPacks(packs)
            }
        )
    }

    @ViewBuilder
    private func externalLinkRow(title: String, systemImage: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Button {
                openURL(url)
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func emergencyField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { _, _ in
                    EmergencyCardStore.save(emergencyCard)
                }
        }
    }

    @ViewBuilder
    private func smartPackToggle(title: String, caption: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Document.self, DocumentPage.self], inMemory: true)
        .environment(AuthService())
        .environment(AutoLockService(authService: AuthService()))
}
