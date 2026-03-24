import SwiftUI
import SwiftData

@main
struct DocArmorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // Both services share the same AuthService instance so AutoLock can call lock().
    // They are initialised once in init() and stored as @State to survive re-renders.
    @State private var authService: AuthService
    @State private var autoLockService: AutoLockService

    // Deep-link state for Siri / widget → open a specific document type
    @State private var pendingDocumentType: DocumentType?

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

        // Provision vault key on first launch
        if !VaultKey.exists {
            _ = try? VaultKey.generate()
        }

        // Create a single AuthService and hand the same reference to AutoLockService.
        // Using _property = State(initialValue:) is the correct pattern for initialising
        // @State inside init() without creating a discarded duplicate instance.
        let auth = AuthService()
        _authService    = State(initialValue: auth)
        _autoLockService = State(initialValue: AutoLockService(authService: auth))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(autoLockService)
                .environment(\.pendingDocumentType, $pendingDocumentType)
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
}

// MARK: - Environment Key for deep-link state

private struct PendingDocumentTypeKey: EnvironmentKey {
    static let defaultValue: Binding<DocumentType?> = .constant(nil)
}

extension EnvironmentValues {
    var pendingDocumentType: Binding<DocumentType?> {
        get { self[PendingDocumentTypeKey.self] }
        set { self[PendingDocumentTypeKey.self] = newValue }
    }
}
