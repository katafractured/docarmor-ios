import SwiftUI
import SwiftData
import KatafractStyle

@main
struct DocArmorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // Both services share the same AuthService instance so AutoLock can call lock().
    // They are initialised once in init() and stored as @State to survive re-renders.
    @State private var authService: AuthService
    @State private var autoLockService: AutoLockService
    @State private var entitlementService: EntitlementService

    // Deep-link state for Siri / widget → open a specific document type or category
    @State private var pendingDocumentType: DocumentType?
    @State private var pendingCategory: DocumentCategory?

    private let modelContainer: ModelContainer

    init() {
        // Configure SwiftData with explicit no-CloudKit to ensure local-only storage
        let config = ModelConfiguration(
            schema: Schema([Document.self, DocumentPage.self]),
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(for: Document.self, DocumentPage.self, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }

        // Provision vault key on first launch.
        // `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` requires the device
        // to have a passcode. If it doesn't, generate() throws and we surface a
        // flag so the UI can explain the situation instead of failing silently later.
        if !VaultKey.exists {
            do {
                try VaultKey.generate()
            } catch {
                // VaultKey.noPasscode is checked by LockScreenView to show
                // an actionable "Set a device passcode to use DocArmor" message.
                UserDefaults.standard.set(true, forKey: "vaultKeyProvisioningFailed")
            }
        }

        // Create a single AuthService and hand the same reference to AutoLockService.
        // Using _property = State(initialValue:) is the correct pattern for initialising
        // @State inside init() without creating a discarded duplicate instance.
        let auth = AuthService()
        _authService    = State(initialValue: auth)
        _autoLockService = State(initialValue: AutoLockService(authService: auth))

        // Initialize EntitlementService for StoreKit 2 monetization
        _entitlementService = State(initialValue: EntitlementService())

        excludeVaultFromBackup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(autoLockService)
                .environment(entitlementService)
                .environment(\.pendingDocumentType, $pendingDocumentType)
                .environment(\.pendingCategory, $pendingCategory)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        authService.lock()
                        autoLockService.stopMonitoring()
                    case .active:
                        autoLockService.startMonitoring()
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .showDocumentIntent)) { notification in
                    guard
                        let typeValue = notification.userInfo?["documentType"] as? String,
                        let docType = DocumentType(rawValue: typeValue)
                    else { return }
                    pendingDocumentType = docType
                }
                .onReceive(NotificationCenter.default.publisher(for: .openCategoryIntent)) { notification in
                    guard
                        let categoryValue = notification.userInfo?["category"] as? String,
                        let category = DocumentCategory(rawValue: categoryValue)
                    else { return }
                    pendingCategory = category
                }
                .task {
                    entitlementService.startListening()
                }
                .tint(KataAccent.gold)
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Deep Link

    /// Handles `docarmor://open?type=driversLicense` URLs from widgets and Siri.
    private func handleDeepLink(_ url: URL) {
        guard
            url.scheme == "docarmor",
            url.host == "open",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let typeValue = components.queryItems?.first(where: { $0.name == "type" })?.value,
            let docType = DocumentType(rawValue: typeValue)
        else { return }
        pendingDocumentType = docType
    }

    private func excludeVaultFromBackup() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        for filename in ["default.store", "default.store-wal", "default.store-shm"] {
            var url = appSupport.appendingPathComponent(filename)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        }
    }
}

// MARK: - Environment Keys for deep-link state

private struct PendingDocumentTypeKey: EnvironmentKey {
    static let defaultValue: Binding<DocumentType?> = .constant(nil)
}

private struct PendingCategoryKey: EnvironmentKey {
    static let defaultValue: Binding<DocumentCategory?> = .constant(nil)
}

extension EnvironmentValues {
    var pendingDocumentType: Binding<DocumentType?> {
        get { self[PendingDocumentTypeKey.self] }
        set { self[PendingDocumentTypeKey.self] = newValue }
    }

    var pendingCategory: Binding<DocumentCategory?> {
        get { self[PendingCategoryKey.self] }
        set { self[PendingCategoryKey.self] = newValue }
    }
}
