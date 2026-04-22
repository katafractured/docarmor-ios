import SwiftUI
import SwiftData
import KatafractStyle

struct VaultView: View {
    private enum BundleFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case readyNow = "Ready Now"
        case travel = "Travel & Identity"
        case vehicle = "Vehicle"
        case family = "Family Essentials"
        case medical = "Medical"
        case work = "Work"
        case custom = "Custom Packs"
        case attention = "Needs Attention"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .readyNow: return "bolt.shield.fill"
            case .travel: return "airplane.departure"
            case .vehicle: return "car.fill"
            case .family: return "person.3.sequence.fill"
            case .medical: return "cross.case.fill"
            case .work: return "briefcase.fill"
            case .custom: return "square.stack.3d.up.fill"
            case .attention: return "exclamationmark.triangle.fill"
            }
        }

        var caption: String {
            switch self {
            case .all: return "Every document in the vault"
            case .readyNow: return "Most-used documents kept ready"
            case .travel: return "Passports, IDs, memberships, and travel-ready documents"
            case .vehicle: return "License, registration-style, and auto insurance docs"
            case .family: return "Core household identity and health docs"
            case .medical: return "Health and medical records"
            case .work: return "Job and professional credentials"
            case .custom: return "Your user-defined fast-access document set"
            case .attention: return "Expired, incomplete, or stale docs"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.createdAt, order: .reverse) private var allDocuments: [Document]

    @State private var searchText = ""
    @State private var showingAddDocument = false
    @State private var navigationPath = NavigationPath()
    @State private var selectedBundleFilter: BundleFilter = .all
    @State private var selectedTypeFilter: DocumentType?
    @State private var selectedOwnerFilter: String?
    @State private var isBeingCaptured = false
    @State private var showingTravelMode = false
    @State private var showingImportInbox = false
    @State private var showingQuickPresent = false
    @State private var quickPresentImages: [UIImage] = []
    @State private var quickPresentDocumentName = ""
    @State private var pendingImportCount = ImportInboxService.pendingCount()
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

    @State private var showingReadinessReview = false

    var pendingDocumentType: Binding<DocumentType?>
    var pendingCategory: Binding<DocumentCategory?>

    // MARK: - Computed

    private let sharedOwnerToken = "__shared__"

    private var filteredDocuments: [Document] {
        allDocuments.filter { document in
            let matchesSearch = matchesSearch(for: document)

            let matchesType =
                selectedTypeFilter == nil ||
                document.documentType == selectedTypeFilter

            let matchesOwner: Bool
            if let selectedOwnerFilter {
                if selectedOwnerFilter == sharedOwnerToken {
                    matchesOwner = HouseholdStore.normalize(document.ownerName) == nil
                } else {
                    matchesOwner = document.ownerDisplayName == selectedOwnerFilter
                }
            } else {
                matchesOwner = true
            }

            let matchesBundle = matches(document: document, bundle: selectedBundleFilter)

            return matchesSearch && matchesType && matchesOwner && matchesBundle
        }
    }

    private var favorites: [Document] {
        filteredDocuments.filter { $0.isFavorite }
    }

    private var availableBundleFilters: [BundleFilter] {
        BundleFilter.allCases.filter(isBundleFilterEnabled)
    }

    private var documentsByCategory: [(DocumentCategory, [Document])] {
        let nonFavorites = filteredDocuments.filter { !$0.isFavorite }
        return DocumentCategory.allCases.compactMap { category in
            let docs = nonFavorites.filter { $0.category == category }
            return docs.isEmpty ? nil : (category, docs)
        }
    }

    private var ownerFilterOptions: [String] {
        var options = allDocuments.map(\.ownerDisplayName)
        if allDocuments.contains(where: { HouseholdStore.normalize($0.ownerName) == nil }) {
            options.append("Shared")
        }
        return Array(Set(options)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var snapshotFingerprint: String {
        allDocuments
            .map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    private var importInboxLabel: String {
        pendingImportCount > 0 ? "Inbox \(pendingImportCount)" : "Inbox"
    }

    private var packVisibilitySignature: String {
        [
            travelPackEnabled,
            vehiclePackEnabled,
            familyPackEnabled,
            medicalPackEnabled,
            workPackEnabled,
            !enabledCustomPacks.isEmpty,
            renewalPackEnabled
        ].map { $0 ? "1" : "0" }.joined()
    }

    private var expiringSoonDocuments: [Document] {
        allDocuments.filter(\.expiresSoon)
    }

    private var attentionDocuments: [Document] {
        allDocuments.filter(\.needsAttention)
    }

    private var recentlyAddedDocuments: [Document] {
        Array(allDocuments.prefix(3))
    }

    private var travelIdentityDocuments: [Document] {
        allDocuments
            .filter { matches(document: $0, bundle: .travel) }
            .sorted(by: sortForCounterAccess)
            .prefix(6)
            .map { $0 }
    }

    private var vehicleReadyDocuments: [Document] {
        allDocuments
            .filter { matches(document: $0, bundle: .vehicle) }
            .sorted(by: sortForVehicleAccess)
            .prefix(4)
            .map { $0 }
    }

    private var savedCustomPacks: [SavedCustomPack] {
        let decoded = SavedCustomPack.decodeList(from: customPacksRawStorage)
        if !decoded.isEmpty {
            return decoded
        }

        let legacyTypes = DocumentType.decodePackSelection(from: legacyCustomPackRawTypes)
        guard !legacyTypes.isEmpty else { return [] }

        return [
            SavedCustomPack(
                title: legacyCustomPackTitle,
                isEnabled: legacyCustomPackEnabled,
                documentTypes: legacyTypes
            )
        ]
    }

    private var enabledCustomPacks: [SavedCustomPack] {
        savedCustomPacks.filter { $0.isEnabled && !$0.documentTypes.isEmpty }
    }

    private func documents(for customPack: SavedCustomPack) -> [Document] {
        allDocuments
            .filter { customPack.documentTypes.contains($0.documentType) }
            .sorted(by: sortForCounterAccess)
            .prefix(8)
            .map { $0 }
    }

    private var familyPacketDocuments: [Document] {
        allDocuments
            .filter { matches(document: $0, bundle: .family) }
            .sorted(by: sortForFamilyPacket)
            .prefix(6)
            .map { $0 }
    }

    private var schoolPacketDocuments: [Document] {
        allDocuments
            .filter { schoolPacketTypes.contains($0.documentType) }
            .sorted(by: sortForSchoolPacket)
            .prefix(6)
            .map { $0 }
    }

    private var medicalVisitDocuments: [Document] {
        allDocuments
            .filter { medicalVisitTypes.contains($0.documentType) }
            .sorted(by: sortForMedicalVisit)
            .prefix(6)
            .map { $0 }
    }

    private var workPacketDocuments: [Document] {
        allDocuments
            .filter { workPacketTypes.contains($0.documentType) }
            .sorted(by: sortForWorkPacket)
            .prefix(6)
            .map { $0 }
    }

    private var propertyClaimDocuments: [Document] {
        allDocuments
            .filter { propertyClaimTypes.contains($0.documentType) }
            .sorted(by: sortForPropertyClaim)
            .prefix(6)
            .map { $0 }
    }

    private var disasterPacketDocuments: [Document] {
        allDocuments
            .filter { disasterPacketTypes.contains($0.documentType) }
            .sorted(by: sortForDisasterPacket)
            .prefix(8)
            .map { $0 }
    }

    private var dependentCareDocuments: [Document] {
        allDocuments
            .filter { dependentCareTypes.contains($0.documentType) }
            .sorted(by: sortForDependentCare)
            .prefix(8)
            .map { $0 }
    }

    private var petPacketDocuments: [Document] {
        allDocuments
            .filter { petPacketTypes.contains($0.documentType) || documentLooksPetRelated($0) }
            .sorted(by: sortForPetPacket)
            .prefix(8)
            .map { $0 }
    }

    private var membersMissingPrimaryIDCount: Int {
        householdGaps.filter { $0.missingTypes.contains(where: primaryIdentityTypes.contains) }.count
    }

    private var householdProfiles: [HouseholdMemberProfile] {
        HouseholdStore.loadProfiles()
    }

    private var humanProfiles: [HouseholdMemberProfile] {
        householdProfiles.filter { $0.role != .pet }
    }

    private var vehicleProfiles: [HouseholdMemberProfile] {
        householdProfiles.filter { [.adult, .senior].contains($0.role) }
    }

    private var schoolProfiles: [HouseholdMemberProfile] {
        householdProfiles.filter { $0.role == .child }
    }

    private var workProfiles: [HouseholdMemberProfile] {
        householdProfiles.filter { [.adult, .senior].contains($0.role) }
    }

    private var dependentProfiles: [HouseholdMemberProfile] {
        householdProfiles.filter { [.child, .senior].contains($0.role) }
    }

    private var petProfiles: [HouseholdMemberProfile] {
        householdProfiles.filter { $0.role == .pet }
    }

    private var householdGaps: [HouseholdGap] {
        return humanProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: householdEssentials)
            return missing.isEmpty ? nil : HouseholdGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var renewalCandidates: [Document] {
        allDocuments
            .filter { $0.needsAttention }
            .sorted(by: sortByUrgency)
            .prefix(6)
            .map { $0 }
    }

    private var expiredDocuments: [Document] {
        allDocuments.filter(\.isExpired).sorted(by: sortByUrgency)
    }

    private var incompleteDocuments: [Document] {
        allDocuments.filter(\.isMissingRequiredPages).sorted(by: sortByUrgency)
    }

    private var staleReviewDocuments: [Document] {
        allDocuments
            .filter { $0.needsVerificationReview && !$0.isExpired && !$0.expiresSoon && !$0.isMissingRequiredPages }
            .sorted(by: sortByUrgency)
    }

    private var renewalWorkflows: [RenewalWorkflowItem] {
        [
            RenewalWorkflowItem(
                title: "Renew Now",
                systemImage: "arrow.clockwise.circle.fill",
                count: expiredDocuments.count,
                caption: "Expired documents that need replacement or renewal",
                actionLabel: "Review expired"
            ),
            RenewalWorkflowItem(
                title: "Handle Soon",
                systemImage: "calendar.badge.exclamationmark",
                count: expiringSoonDocuments.count,
                caption: "Documents expiring within 30 days",
                actionLabel: "Review upcoming"
            ),
            RenewalWorkflowItem(
                title: "Finish Setup",
                systemImage: "doc.badge.plus",
                count: incompleteDocuments.count,
                caption: "Documents missing required back sides or supporting pages",
                actionLabel: "Review incomplete"
            ),
            RenewalWorkflowItem(
                title: "Verify",
                systemImage: "checkmark.seal.trianglebadge.exclamationmark",
                count: staleReviewDocuments.count,
                caption: "Documents that should be checked against the physical original",
                actionLabel: "Review stale"
            )
        ]
    }

    private var vehicleGaps: [VehicleGap] {
        return vehicleProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: vehicleEssentials)
            return missing.isEmpty ? nil : VehicleGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var schoolGaps: [SchoolGap] {
        return schoolProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: schoolEssentials)
            return missing.isEmpty ? nil : SchoolGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var medicalVisitGaps: [MedicalVisitGap] {
        return humanProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: medicalVisitEssentials)
            return missing.isEmpty ? nil : MedicalVisitGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var workPacketGaps: [WorkPacketGap] {
        return workProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: workPacketEssentials)
            return missing.isEmpty ? nil : WorkPacketGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var propertyClaimGaps: [PropertyClaimGap] {
        return vehicleProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: propertyClaimEssentials)
            return missing.isEmpty ? nil : PropertyClaimGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var disasterPacketGaps: [DisasterPacketGap] {
        return humanProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: disasterPacketEssentials)
            return missing.isEmpty ? nil : DisasterPacketGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var dependentCareGaps: [DependentCareGap] {
        return dependentProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: dependentCareEssentials)
            return missing.isEmpty ? nil : DependentCareGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private var petPacketGaps: [PetPacketGap] {
        return petProfiles.compactMap { profile in
            let missing = missingTypes(for: profile.name, essentials: petPacketEssentials)
            return missing.isEmpty ? nil : PetPacketGap(ownerName: profile.name, missingTypes: missing)
        }
    }

    private let primaryIdentityTypes: Set<DocumentType> = [.driversLicense, .passport, .stateID]
    private let householdEssentials: [DocumentType] = [.passport, .driversLicense, .insuranceHealth, .vaccineRecord]
    private let vehicleEssentials: [DocumentType] = [.driversLicense, .insuranceAuto]
    private let schoolPacketTypes: Set<DocumentType> = [.vaccineRecord, .insuranceHealth, .birthCertificate, .passport, .stateID]
    private let schoolEssentials: [DocumentType] = [.vaccineRecord, .insuranceHealth, .birthCertificate]
    private let medicalVisitTypes: Set<DocumentType> = [.insuranceHealth, .medicareCard, .prescriptionInfo, .bloodTypeCard, .emergencyContacts, .vaccineRecord]
    private let medicalVisitEssentials: [DocumentType] = [.insuranceHealth, .prescriptionInfo, .emergencyContacts]
    private let workPacketTypes: Set<DocumentType> = [.employeeID, .professionalLicense, .workPermit, .passport, .driversLicense, .stateID, .socialSecurity]
    private let workPacketEssentials: [DocumentType] = [.passport, .driversLicense, .employeeID]
    private let propertyClaimTypes: Set<DocumentType> = [.insuranceHome, .insuranceLife, .driversLicense, .passport, .stateID]
    private let propertyClaimEssentials: [DocumentType] = [.insuranceHome, .driversLicense]
    private let disasterPacketTypes: Set<DocumentType> = [.passport, .driversLicense, .stateID, .insuranceHealth, .insuranceHome, .insuranceLife, .prescriptionInfo, .emergencyContacts, .bloodTypeCard, .vaccineRecord]
    private let disasterPacketEssentials: [DocumentType] = [.passport, .insuranceHealth, .emergencyContacts]
    private let dependentCareTypes: Set<DocumentType> = [.insuranceHealth, .medicareCard, .prescriptionInfo, .emergencyContacts, .bloodTypeCard, .stateID, .driversLicense, .passport]
    private let dependentCareEssentials: [DocumentType] = [.insuranceHealth, .prescriptionInfo, .emergencyContacts]
    private let petPacketTypes: Set<DocumentType> = [.vaccineRecord, .prescriptionInfo, .emergencyContacts, .insuranceHealth, .custom]
    private let petPacketEssentials: [DocumentType] = [.vaccineRecord, .emergencyContacts]

    private var preparednessChecklist: [PreparednessChecklistItem] {
        [
            PreparednessChecklistItem(
                title: "Travel",
                systemImage: "airplane.departure",
                readyCount: allDocuments.filter { matches(document: $0, bundle: .travel) }.count,
                missingCount: householdGaps.reduce(0) { partialResult, gap in
                    partialResult + gap.missingTypes.filter { householdEssentials.contains($0) || $0 == .passport }.count
                },
                caption: "Passports, travel IDs, and household travel readiness"
            ),
            PreparednessChecklistItem(
                title: "Medical",
                systemImage: "cross.case.fill",
                readyCount: medicalVisitDocuments.count,
                missingCount: medicalVisitGaps.count,
                caption: "Insurance, prescriptions, and intake-ready records"
            ),
            PreparednessChecklistItem(
                title: "Disaster",
                systemImage: "bolt.shield.fill",
                readyCount: disasterPacketDocuments.count,
                missingCount: disasterPacketGaps.count,
                caption: "Grab-and-go identity, medical, and insurance docs"
            ),
            PreparednessChecklistItem(
                title: "Household",
                systemImage: "person.3.sequence.fill",
                readyCount: familyPacketDocuments.count,
                missingCount: householdGaps.count,
                caption: "Family essentials and dependent support coverage"
            ),
            PreparednessChecklistItem(
                title: "Property",
                systemImage: "house.fill",
                readyCount: propertyClaimDocuments.count,
                missingCount: propertyClaimGaps.count,
                caption: "Claim-ready housing and identity documents"
            )
        ]
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if !allDocuments.isEmpty {
                    filterBar
                }

                if allDocuments.isEmpty {
                    emptyStateView
                } else if filteredDocuments.isEmpty {
                    ContentUnavailableView(
                        "No Matching Documents",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try a different search, type filter, or person filter.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    documentList
                }
            }
            .navigationTitle("DocArmor")
            .navigationDestination(for: Document.self) { document in
                DocumentDetailView(document: document)
            }
            .searchable(text: $searchText, prompt: "Search documents")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        refreshImportInboxCount()
                        showingImportInbox = true
                    }) {
                        Label(importInboxLabel, systemImage: "tray.full")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddDocument = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Add Document")
                }
                ToolbarItem(placement: .secondaryAction) {
                    if travelPackEnabled {
                        Button(action: { showingTravelMode = true }) {
                            Label("Travel Mode", systemImage: "airplane.departure")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView()
            }
            .sheet(isPresented: $showingImportInbox, onDismiss: refreshImportInboxCount) {
                ImportInboxView()
            }
            .sheet(isPresented: $showingTravelMode) {
                TravelModeView()
            }
            .sheet(isPresented: $showingReadinessReview) {
                ReadinessReviewSheet(documents: allDocuments)
            }
            .fullScreenCover(isPresented: $showingQuickPresent) {
                PresentModeView(
                    images: quickPresentImages,
                    documentName: quickPresentDocumentName
                )
            }
            .onChange(of: pendingDocumentType.wrappedValue) { _, type in
                guard let type else { return }
                // VaultView is only in the hierarchy when auth.state == .unlocked,
                // so this onChange fires only after the user has authenticated.
                // Do NOT clear the pending value on the lock screen path — the
                // DocArmorApp.onOpenURL handler sets it; we consume it here.
                if let doc = allDocuments.first(where: { $0.documentType == type }) {
                    navigationPath.append(doc)
                }
                pendingDocumentType.wrappedValue = nil
            }
            .onChange(of: pendingCategory.wrappedValue) { _, category in
                guard let category else { return }
                if let doc = allDocuments.first(where: { $0.category == category }) {
                    navigationPath.append(doc)
                }
                pendingCategory.wrappedValue = nil
            }
            .task(id: snapshotFingerprint) {
                updateWidgetSnapshot()
                refreshImportInboxCount()
            }
            .onAppear {
                updateCaptureState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                updateCaptureState()
            }
            .onAppear {
                normalizeSelectedBundleFilter()
            }
            .onChange(of: packVisibilitySignature) { _, _ in
                normalizeSelectedBundleFilter()
            }
            .overlay {
                if isBeingCaptured { captureOverlay }
            }
        }
    }

    private func refreshImportInboxCount() {
        pendingImportCount = ImportInboxService.pendingCount()
    }

    private var captureOverlay: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                Text("Screen Recording Blocked")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("DocArmor hides vault content\nwhile screen recording is active.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Document List

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(availableBundleFilters) { bundle in
                        Button {
                            selectedBundleFilter = bundle
                        } label: {
                            Label(bundle.rawValue, systemImage: bundle.systemImage)
                        }
                    }
                } label: {
                    filterChip(
                        title: selectedBundleFilter.rawValue,
                        systemImage: selectedBundleFilter.systemImage
                    )
                }

                Menu {
                    Button {
                        selectedTypeFilter = nil
                    } label: {
                        Label("All Types", systemImage: "square.grid.2x2")
                    }

                    ForEach(DocumentType.allCases, id: \.self) { type in
                        Button {
                            selectedTypeFilter = type
                        } label: {
                            Label(type.rawValue, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    filterChip(
                        title: selectedTypeFilter?.rawValue ?? "All Types",
                        systemImage: selectedTypeFilter?.systemImage ?? "square.grid.2x2"
                    )
                }

                Menu {
                    Button {
                        selectedOwnerFilter = nil
                    } label: {
                        Label("All People", systemImage: "person.3.fill")
                    }

                    if ownerFilterOptions.contains("Shared") {
                        Button {
                            selectedOwnerFilter = sharedOwnerToken
                        } label: {
                            Label("Shared", systemImage: "person.2.fill")
                        }
                    }

                    ForEach(ownerFilterOptions.filter { $0 != "Shared" }, id: \.self) { owner in
                        Button {
                            selectedOwnerFilter = owner
                        } label: {
                            Label(owner, systemImage: "person.fill")
                        }
                    }
                } label: {
                    filterChip(
                        title: selectedOwnerFilterTitle,
                        systemImage: selectedOwnerFilter == sharedOwnerToken ? "person.2.fill" : "person.fill"
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var selectedOwnerFilterTitle: String {
        if selectedOwnerFilter == sharedOwnerToken {
            return "Shared"
        }
        return selectedOwnerFilter ?? "All People"
    }

    private func filterChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var documentList: some View {
        List {
            Section("Readiness") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        readinessCard(
                            title: "Needs Attention",
                            value: "\(attentionDocuments.count)",
                            caption: "Tap to review and fix",
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        ) {
                            showingReadinessReview = true
                        }

                        readinessCard(
                            title: "Expiring Soon",
                            value: "\(expiringSoonDocuments.count)",
                            caption: "Within 30 days",
                            systemImage: "calendar.badge.exclamationmark",
                            color: .red
                        ) {
                            showingReadinessReview = true
                        }

                        readinessCard(
                            title: "Ready Now",
                            value: "\(allDocuments.filter { matches(document: $0, bundle: .readyNow) }.count)",
                            caption: "Favorites and travel IDs",
                            systemImage: "bolt.shield.fill",
                            color: documentTone
                        ) {
                            selectedBundleFilter = .readyNow
                        }

                        readinessCard(
                            title: "People Missing ID",
                            value: "\(membersMissingPrimaryIDCount)",
                            caption: "No passport, DL, or state ID",
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            color: .secondary
                        ) {
                            selectedOwnerFilter = nil
                            selectedBundleFilter = .all
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if preparednessEnabled {
                Section("Preparedness Checklist") {
                    ForEach(preparednessChecklist) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(item.isReady ? .green : .orange)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(item.statusText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.isReady ? .green : .orange)
                                }

                                Text(item.caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if renewalPackEnabled {
                Section("Renewal Workflows") {
                    ForEach(renewalWorkflows) { workflow in
                        Button {
                            selectedBundleFilter = .attention
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: workflow.systemImage)
                                    .foregroundStyle(workflow.count > 0 ? .orange : .green)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(workflow.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(workflow.statusText)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(workflow.count > 0 ? .orange : .green)
                                    }

                                    Text(workflow.caption)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !enabledCustomPacks.isEmpty {
                ForEach(enabledCustomPacks) { pack in
                    let packDocuments = documents(for: pack)
                    if !packDocuments.isEmpty {
                        Section(pack.displayTitle) {
                            ForEach(packDocuments) { doc in
                                CounterReadyRow(
                                    document: doc,
                                    detailAction: { navigationPath.append(doc) },
                                    showNowAction: { Task { await showNow(doc) } }
                                )
                            }
                        }
                    }
                }
            }

            if travelPackEnabled && !travelIdentityDocuments.isEmpty {
                Section {
                    ForEach(travelIdentityDocuments) { document in
                        CounterReadyRow(
                            document: document,
                            detailAction: { navigationPath.append(document) },
                            showNowAction: { Task { await showNow(document) } }
                        )
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Travel & Identity")
                        Text("Fast access for passports, IDs, hotel desks, travel checkpoints, and public verification.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if vehiclePackEnabled && (!vehicleReadyDocuments.isEmpty || !vehicleGaps.isEmpty) {
                Section {
                    if !vehicleReadyDocuments.isEmpty {
                        ForEach(vehicleReadyDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !vehicleGaps.isEmpty {
                        ForEach(vehicleGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "car.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Roadside Ready")
                        Text("Keep license and auto insurance together for traffic stops, rentals, and roadside assistance.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if familyPackEnabled && !familyPacketDocuments.isEmpty {
                Section {
                    ForEach(familyPacketDocuments) { document in
                        CounterReadyRow(
                            document: document,
                            detailAction: { navigationPath.append(document) },
                            showNowAction: { Task { await showNow(document) } }
                        )
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Family Emergency Packet")
                        Text("Health cards, vaccine proof, and core identity documents kept together for urgent household use.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if schoolPackEnabled && (!schoolPacketDocuments.isEmpty || !schoolGaps.isEmpty) {
                Section {
                    if !schoolPacketDocuments.isEmpty {
                        ForEach(schoolPacketDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !schoolGaps.isEmpty {
                        ForEach(schoolGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "graduationcap.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("School Packet")
                        Text("Vaccination, insurance, and identity documents kept together for enrollment and school administration.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if medicalPackEnabled && (!medicalVisitDocuments.isEmpty || !medicalVisitGaps.isEmpty) {
                Section {
                    if !medicalVisitDocuments.isEmpty {
                        ForEach(medicalVisitDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !medicalVisitGaps.isEmpty {
                        ForEach(medicalVisitGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "cross.case.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Medical Visit Packet")
                        Text("Insurance, prescriptions, and emergency details kept together for appointments and intake.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if workPackEnabled && (!workPacketDocuments.isEmpty || !workPacketGaps.isEmpty) {
                Section {
                    if !workPacketDocuments.isEmpty {
                        ForEach(workPacketDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !workPacketGaps.isEmpty {
                        ForEach(workPacketGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "briefcase.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Work Credential Packet")
                        Text("Employee IDs, licenses, and identity documents kept together for onboarding and credential checks.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if propertyPackEnabled && (!propertyClaimDocuments.isEmpty || !propertyClaimGaps.isEmpty) {
                Section {
                    if !propertyClaimDocuments.isEmpty {
                        ForEach(propertyClaimDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !propertyClaimGaps.isEmpty {
                        ForEach(propertyClaimGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "house.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Property Claim Packet")
                        Text("Home insurance and identity documents kept together for claims, adjuster visits, and housing admin.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if disasterPackEnabled && (!disasterPacketDocuments.isEmpty || !disasterPacketGaps.isEmpty) {
                Section {
                    if !disasterPacketDocuments.isEmpty {
                        ForEach(disasterPacketDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !disasterPacketGaps.isEmpty {
                        ForEach(disasterPacketGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "bolt.shield.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Grab-and-Go Packet")
                        Text("Emergency identity, medical, and insurance documents kept together for evacuation and disaster response.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if dependentPackEnabled && (!dependentCareDocuments.isEmpty || !dependentCareGaps.isEmpty) {
                Section {
                    if !dependentCareDocuments.isEmpty {
                        ForEach(dependentCareDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !dependentCareGaps.isEmpty {
                        ForEach(dependentCareGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "person.2.crop.square.stack.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dependent Care Packet")
                        Text("Identity, insurance, prescriptions, and emergency contacts kept together for caregiver support.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if petPackEnabled && (!petPacketDocuments.isEmpty || !petPacketGaps.isEmpty) {
                Section {
                    if !petPacketDocuments.isEmpty {
                        ForEach(petPacketDocuments) { document in
                            CounterReadyRow(
                                document: document,
                                detailAction: { navigationPath.append(document) },
                                showNowAction: { Task { await showNow(document) } }
                            )
                        }
                    }

                    if !petPacketGaps.isEmpty {
                        ForEach(petPacketGaps) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "pawprint.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(gap.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pet & Boarding Packet")
                        Text("Vaccines, prescriptions, and emergency-style records kept together for boarding, vet visits, and pet travel.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !householdGaps.isEmpty {
                Section("Household Gaps") {
                    ForEach(householdGaps) { gap in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(HouseholdStore.displayLabel(for: gap.ownerName), systemImage: "person.crop.circle")
                                .font(.subheadline.weight(.semibold))
                            Text(gap.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !renewalCandidates.isEmpty {
                Section("Renewal Center") {
                    ForEach(renewalCandidates) { document in
                        Button {
                            navigationPath.append(document)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(renewalReason(for: document))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !recentlyAddedDocuments.isEmpty {
                Section("Recently Added") {
                    ForEach(recentlyAddedDocuments) { doc in
                        DocumentRow(document: doc)
                            .contentShape(Rectangle())
                            .onTapGesture { navigationPath.append(doc) }
                    }
                }
            }

            // Favorites section
            if !favorites.isEmpty {
                Section {
                    ForEach(favorites) { doc in
                        DocumentRow(document: doc)
                            .contentShape(Rectangle())
                            .onTapGesture { navigationPath.append(doc) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                quickPresentAction(for: doc)
                            }
                    }
                    .onDelete { indexSet in
                        deleteDocuments(from: favorites, at: indexSet)
                    }
                } header: {
                    Label("Favorites", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            // Category sections
            ForEach(documentsByCategory, id: \.0) { category, docs in
                Section {
                    ForEach(docs) { doc in
                        DocumentRow(document: doc)
                            .contentShape(Rectangle())
                            .onTapGesture { navigationPath.append(doc) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                quickPresentAction(for: doc)
                            }
                    }
                    .onDelete { indexSet in
                        deleteDocuments(from: docs, at: indexSet)
                    }
                } header: {
                    CategoryHeader(category: category)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 72))
                .foregroundStyle(.tint.opacity(0.7))

            VStack(spacing: 8) {
                Text("Your Vault is Empty")
                    .font(.title2.bold())
                Text("Add your important documents — driver's license,\npassport, insurance cards, and more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showingAddDocument = true }) {
                Label("Add First Document", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Delete

    private func deleteDocuments(from docs: [Document], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(docs[index])
        }
    }

    private var documentTone: Color {
        Color(red: 0.26, green: 0.39, blue: 0.45)
    }

    private func readinessCard(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value). \(caption).")
    }

    @ViewBuilder
    private func quickPresentAction(for document: Document) -> some View {
        Button {
            Task { await showNow(document) }
        } label: {
            Label("Show Now", systemImage: "rectangle.on.rectangle.circle.fill")
        }
        .tint(documentTone)
    }

    private func matches(document: Document, bundle: BundleFilter) -> Bool {
        switch bundle {
        case .all:
            return true
        case .readyNow:
            return document.isFavorite || document.category == .identity || document.category == .travel
        case .travel:
            return document.category == .travel || [.passport, .globalEntry, .driversLicense, .stateID, .hotelLoyalty, .airlineMembership, .rentalCarMembership].contains(document.documentType)
        case .vehicle:
            return [.driversLicense, .insuranceAuto].contains(document.documentType)
        case .family:
            return [.passport, .driversLicense, .stateID, .insuranceHealth, .medicareCard, .vaccineRecord].contains(document.documentType)
        case .medical:
            return document.category == .medical
        case .work:
            return document.category == .work
        case .custom:
            return enabledCustomPacks.contains { $0.documentTypes.contains(document.documentType) }
        case .attention:
            return document.needsAttention
        }
    }

    private func isBundleFilterEnabled(_ bundle: BundleFilter) -> Bool {
        switch bundle {
        case .all, .readyNow:
            return true
        case .travel:
            return travelPackEnabled
        case .vehicle:
            return vehiclePackEnabled
        case .family:
            return familyPackEnabled
        case .medical:
            return medicalPackEnabled
        case .work:
            return workPackEnabled
        case .custom:
            return !enabledCustomPacks.isEmpty
        case .attention:
            return renewalPackEnabled
        }
    }

    private func normalizeSelectedBundleFilter() {
        if !isBundleFilterEnabled(selectedBundleFilter) {
            selectedBundleFilter = .all
        }
    }

    private func missingTypes(for ownerName: String, essentials: [DocumentType]) -> [DocumentType] {
        let docs = allDocuments.filter { $0.ownerDisplayName == ownerName }
        let presentTypes = Set(docs.map(\.documentType))
        return essentials.filter { !presentTypes.contains($0) }
    }

    private func matchesSearch(for document: Document) -> Bool {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let queryTerms = semanticQueryTerms(from: trimmedQuery)

        let searchCorpus = searchableTerms(for: document)
        return queryTerms.allSatisfy { term in
            searchCorpus.contains { $0.contains(term) }
        }
    }

    private func searchableTerms(for document: Document) -> [String] {
        var terms = [
            document.name,
            document.documentType.rawValue,
            document.category.rawValue,
            document.ownerDisplayName,
            document.issuerName,
            document.identifierSuffix,
            document.ocrSuggestedIssuerName ?? "",
            document.ocrSuggestedIdentifier ?? "",
            document.notes,
            document.renewalNotes
        ]

        terms.append(contentsOf: documentTypeAliases(for: document.documentType))
        terms.append(contentsOf: ocrSearchTerms(for: document))
        terms.append(contentsOf: scenarioTerms(for: document))
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func semanticQueryTerms(from query: String) -> [String] {
        let baseTerms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !baseTerms.isEmpty else { return [] }

        var expandedTerms: [String] = []
        for term in baseTerms {
            expandedTerms.append(term)
            expandedTerms.append(contentsOf: semanticAlternates(for: term))
        }

        return Array(NSOrderedSet(array: expandedTerms)) as? [String] ?? expandedTerms
    }

    private func semanticAlternates(for term: String) -> [String] {
        switch term {
        case "id", "identity":
            return ["license", "licence", "passport", "state", "identification"]
        case "passport", "travel":
            return ["airport", "hotel", "tsa", "global", "entry", "identity"]
        case "vehicle", "car", "auto":
            return ["roadside", "license", "insurance", "registration", "driving"]
        case "medical", "doctor", "clinic":
            return ["health", "insurance", "medicare", "medicaid", "vaccine", "prescription"]
        case "renew", "renewal", "expired":
            return ["expires", "expiry", "attention", "verification"]
        case "work", "job", "employment":
            return ["credential", "employee", "permit", "license"]
        case "school", "student":
            return ["enrollment", "vaccine", "birth", "insurance"]
        case "family", "household":
            return ["shared", "child", "senior", "pet"]
        case "pet", "boarding", "vet":
            return ["vaccine", "prescription", "medical", "animal"]
        case "tax", "duty", "store":
            return ["travel", "passport", "identity", "airport"]
        default:
            return []
        }
    }

    private func documentTypeAliases(for type: DocumentType) -> [String] {
        switch type {
        case .driversLicense:
            return ["driver license", "license", "dl", "id card"]
        case .stateID:
            return ["state id", "identification", "identity card"]
        case .passport:
            return ["travel document", "international id", "passport book"]
        case .insuranceHealth:
            return ["health insurance", "medical insurance", "insurance card"]
        case .insuranceAuto:
            return ["auto insurance", "car insurance", "proof of insurance"]
        case .medicareCard:
            return ["medicare", "medicaid", "medical card", "benefits card", "health card"]
        case .vaccineRecord:
            return ["vaccination", "immunization", "shot record"]
        case .globalEntry:
            return ["trusted traveler", "tsa", "border", "travel"]
        default:
            return []
        }
    }

    private func ocrSearchTerms(for document: Document) -> [String] {
        var terms: [String] = []
        if let date = document.ocrSuggestedExpirationDate {
            terms.append(date.formatted(date: .abbreviated, time: .omitted))
            terms.append(date.formatted(.dateTime.year().month().day()))
        }
        if let ocrStructureHintsRaw = document.ocrStructureHintsRaw {
            terms.append(contentsOf: ocrStructureHintsRaw.map {
                switch $0 {
                case "likelyFront": return "front side"
                case "likelyBack": return "back side barcode"
                default: return $0
                }
            })
        }
        if let score = document.ocrConfidenceScore, score < 0.5 {
            terms.append(contentsOf: ["low confidence", "review scan", "ocr warning"])
        }
        return terms
    }

    private func scenarioTerms(for document: Document) -> [String] {
        var terms: [String] = []

        if matches(document: document, bundle: .travel) {
            terms.append(contentsOf: ["travel", "airport", "hotel", "tsa", "passport", "identity", "tax free", "store"])
        }
        if matches(document: document, bundle: .vehicle) {
            terms.append(contentsOf: ["vehicle", "driving", "car", "roadside"])
        }
        if matches(document: document, bundle: .family) {
            terms.append(contentsOf: ["family", "household", "essentials"])
        }
        if document.needsAttention {
            terms.append(contentsOf: ["renew", "renewal", "expired", "attention"])
        }

        return terms
    }

    private func updateWidgetSnapshot() {
        let snapshot = VaultReadinessSnapshot(
            updatedAt: .now,
            totalDocuments: allDocuments.count,
            needsAttentionCount: attentionDocuments.count,
            expiringSoonCount: expiringSoonDocuments.count,
            readyNowCount: allDocuments.filter { matches(document: $0, bundle: .readyNow) }.count
        )
        VaultSnapshotStore.save(snapshot: snapshot)
    }

    private func updateCaptureState() {
        let activeScreen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        isBeingCaptured = activeScreen?.isCaptured ?? false
    }

    private func sortByUrgency(lhs: Document, rhs: Document) -> Bool {
        urgencyRank(for: lhs) < urgencyRank(for: rhs)
    }

    private func sortForCounterAccess(lhs: Document, rhs: Document) -> Bool {
        let leftRank = counterAccessRank(for: lhs)
        let rightRank = counterAccessRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForVehicleAccess(lhs: Document, rhs: Document) -> Bool {
        let leftRank = vehicleAccessRank(for: lhs)
        let rightRank = vehicleAccessRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForFamilyPacket(lhs: Document, rhs: Document) -> Bool {
        let leftRank = familyPacketRank(for: lhs)
        let rightRank = familyPacketRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForSchoolPacket(lhs: Document, rhs: Document) -> Bool {
        let leftRank = schoolPacketRank(for: lhs)
        let rightRank = schoolPacketRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForMedicalVisit(lhs: Document, rhs: Document) -> Bool {
        let leftRank = medicalVisitRank(for: lhs)
        let rightRank = medicalVisitRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForWorkPacket(lhs: Document, rhs: Document) -> Bool {
        let leftRank = workPacketRank(for: lhs)
        let rightRank = workPacketRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForPropertyClaim(lhs: Document, rhs: Document) -> Bool {
        let leftRank = propertyClaimRank(for: lhs)
        let rightRank = propertyClaimRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForDisasterPacket(lhs: Document, rhs: Document) -> Bool {
        let leftRank = disasterPacketRank(for: lhs)
        let rightRank = disasterPacketRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForDependentCare(lhs: Document, rhs: Document) -> Bool {
        let leftRank = dependentCareRank(for: lhs)
        let rightRank = dependentCareRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForPetPacket(lhs: Document, rhs: Document) -> Bool {
        let leftRank = petPacketRank(for: lhs)
        let rightRank = petPacketRank(for: rhs)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func counterAccessRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        if document.documentType == .passport { return 1 }
        if document.documentType == .driversLicense || document.documentType == .stateID { return 2 }
        if document.documentType == .globalEntry { return 3 }
        return 4
    }

    private func vehicleAccessRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        if document.documentType == .driversLicense { return 1 }
        if document.documentType == .insuranceAuto { return 2 }
        return 3
    }

    private func familyPacketRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .insuranceHealth, .medicareCard:
            return 1
        case .emergencyContacts, .bloodTypeCard:
            return 2
        case .passport, .driversLicense, .stateID:
            return 3
        case .vaccineRecord:
            return 4
        default:
            return 5
        }
    }

    private func schoolPacketRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .vaccineRecord:
            return 1
        case .insuranceHealth:
            return 2
        case .birthCertificate:
            return 3
        case .passport, .stateID:
            return 4
        default:
            return 5
        }
    }

    private func medicalVisitRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .insuranceHealth, .medicareCard:
            return 1
        case .prescriptionInfo:
            return 2
        case .emergencyContacts, .bloodTypeCard:
            return 3
        case .vaccineRecord:
            return 4
        default:
            return 5
        }
    }

    private func workPacketRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .employeeID, .professionalLicense:
            return 1
        case .workPermit:
            return 2
        case .passport, .driversLicense, .stateID:
            return 3
        case .socialSecurity:
            return 4
        default:
            return 5
        }
    }

    private func propertyClaimRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .insuranceHome:
            return 1
        case .insuranceLife:
            return 2
        case .driversLicense, .stateID, .passport:
            return 3
        default:
            return 4
        }
    }

    private func disasterPacketRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .passport, .driversLicense, .stateID:
            return 1
        case .insuranceHealth, .insuranceHome, .insuranceLife:
            return 2
        case .emergencyContacts, .bloodTypeCard:
            return 3
        case .prescriptionInfo, .vaccineRecord:
            return 4
        default:
            return 5
        }
    }

    private func dependentCareRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .insuranceHealth, .medicareCard:
            return 1
        case .prescriptionInfo:
            return 2
        case .emergencyContacts, .bloodTypeCard:
            return 3
        case .stateID, .driversLicense, .passport:
            return 4
        default:
            return 5
        }
    }

    private func petPacketRank(for document: Document) -> Int {
        if document.isFavorite { return 0 }
        switch document.documentType {
        case .vaccineRecord:
            return 1
        case .prescriptionInfo:
            return 2
        case .emergencyContacts:
            return 3
        case .insuranceHealth:
            return 4
        default:
            return 5
        }
    }

    private func documentLooksPetRelated(_ document: Document) -> Bool {
        let petTerms = ["pet", "dog", "cat", "vet", "boarding", "rabies"]
        let corpus = [
            document.name,
            document.notes,
            document.issuerName,
            document.ownerDisplayName
        ].map { $0.lowercased() }
        return petTerms.contains { term in
            corpus.contains(where: { $0.contains(term) })
        }
    }

    private func urgencyRank(for document: Document) -> Int {
        if document.isExpired { return 0 }
        if document.expiresSoon { return 1 }
        if document.isMissingRequiredPages { return 2 }
        if document.needsVerificationReview { return 3 }
        return 4
    }

    private func renewalReason(for document: Document) -> String {
        if document.isExpired {
            return "Expired. Renew or replace this document."
        }
        if let days = document.daysUntilExpiry, document.expiresSoon {
            return "Expires in \(days) day\(days == 1 ? "" : "s")."
        }
        if document.isMissingRequiredPages {
            return "Missing a required back side or supporting page."
        }
        if document.needsVerificationReview {
            return "Needs review because it has not been verified recently."
        }
        return "Needs attention."
    }

    @MainActor
    private func showNow(_ document: Document) async {
        guard !document.sortedPages.isEmpty else { return }

        do {
            let key = try VaultKey.load()
            var orderedImages = [Int: UIImage]()

            try await withThrowingTaskGroup(of: (Int, UIImage?).self) { group in
                for page in document.sortedPages {
                    let encryptedData = page.encryptedImageData
                    let nonce = page.nonce
                    let index = page.pageIndex
                    group.addTask(priority: .userInitiated) {
                        let data = try EncryptionService.decrypt(
                            encryptedData: encryptedData,
                            nonce: nonce,
                            using: key
                        )
                        return (index, UIImage(data: data))
                    }
                }

                for try await (index, image) in group {
                    if let image {
                        orderedImages[index] = image
                    }
                }
            }

            quickPresentImages = document.sortedPages.compactMap { orderedImages[$0.pageIndex] }
            guard !quickPresentImages.isEmpty else { return }
            quickPresentDocumentName = document.name
            showingQuickPresent = true
        } catch {
            // Ignore failed quick-present attempts; the detail view remains available.
        }
    }
}

private struct HouseholdGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.prefix(3).map(\.rawValue)
        let remainder = missingTypes.count - labels.count
        if remainder > 0 {
            return "Missing \(labels.joined(separator: ", ")) and \(remainder) more."
        }
        return "Missing \(labels.joined(separator: ", "))."
    }
}

private struct VehicleGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct SchoolGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct MedicalVisitGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct WorkPacketGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct PropertyClaimGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct DisasterPacketGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct DependentCareGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct PetPacketGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        let labels = missingTypes.map(\.rawValue)
        return "Missing \(labels.joined(separator: " and "))."
    }
}

private struct PreparednessChecklistItem: Identifiable {
    let title: String
    let systemImage: String
    let readyCount: Int
    let missingCount: Int
    let caption: String

    var id: String { title }

    var isReady: Bool {
        readyCount > 0 && missingCount == 0
    }

    var statusText: String {
        if missingCount == 0 {
            return readyCount > 0 ? "Ready" : "Needs Setup"
        }
        return "\(missingCount) gap\(missingCount == 1 ? "" : "s")"
    }
}

private struct RenewalWorkflowItem: Identifiable {
    let title: String
    let systemImage: String
    let count: Int
    let caption: String
    let actionLabel: String

    var id: String { title }

    var statusText: String {
        count == 0 ? "Clear" : "\(count) \(actionLabel.lowercased())"
    }
}

// MARK: - Supporting Views

struct CategoryHeader: View {
    let category: DocumentCategory

    var body: some View {
        Label(category.rawValue, systemImage: category.systemImage)
            .foregroundStyle(category.color)
            .font(.footnote.bold())
    }
}

private struct CounterReadyRow: View {
    let document: Document
    let detailAction: () -> Void
    let showNowAction: () -> Void

    private var ownerLabel: String {
        HouseholdStore.displayLabel(for: document.ownerName)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.body.weight(.semibold))
                Text("\(document.documentType.rawValue) • \(ownerLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !document.identifierSuffix.isEmpty {
                    Text("ID ending \(document.identifierSuffix)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button("Details", action: detailAction)
                .buttonStyle(.borderless)

            Button(action: showNowAction) {
                Label("Show", systemImage: "rectangle.on.rectangle.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.26, green: 0.39, blue: 0.45))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(document.name), \(document.documentType.rawValue), \(ownerLabel), quick access")
    }
}

struct DocumentRow: View {
    let document: Document

    private var ownerLabel: String {
        HouseholdStore.displayLabel(for: document.ownerName)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Monochrome sealed chip — no rainbow by type
            ZStack {
                Capsule()
                    .fill(Color.kataNavy.opacity(0.6))
                    .overlay(Capsule().stroke(Color.kataGold, lineWidth: 0.5))
                    .frame(width: 38, height: 38)
                Image(systemName: document.documentType.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.kataGold.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(document.name)
                        .font(.kataDisplay(15))
                        .foregroundStyle(Color.kataIce)
                    if document.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.kataGold)
                    }
                }
                Text(document.documentType.rawValue)
                    .font(.kataCaption(11))
                    .foregroundStyle(Color.kataIce.opacity(0.5))
                Label(ownerLabel, systemImage: document.ownerName == nil ? "person.2.fill" : "person.fill")
                    .font(.kataCaption(11))
                    .foregroundStyle(Color.kataIce.opacity(0.35))
                if document.isMissingRequiredPages {
                    Label("Missing page", systemImage: "doc.badge.plus")
                        .font(.kataCaption(11))
                        .foregroundStyle(Color.kataChampagne.opacity(0.8))
                } else if document.needsVerificationReview {
                    Label("Review recommended", systemImage: "checkmark.seal.trianglebadge.exclamationmark")
                        .font(.kataCaption(11))
                        .foregroundStyle(Color.kataChampagne.opacity(0.8))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let days = document.daysUntilExpiry {
                    ExpirationBadge(daysUntilExpiry: days, isExpired: document.isExpired)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.kataGold.opacity(0.4))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.kataSapphire.opacity(0.04))
        )
        .overlay(
            Group {
                if document.needsAttention {
                    RoundedRectangle(cornerRadius: 4).stroke(Color.kataChampagne.opacity(0.6), lineWidth: 0.5)
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(documentRowAccessibilityLabel)
    }

    private var documentRowAccessibilityLabel: String {
        var parts = [document.name, document.documentType.rawValue, ownerLabel]
        if document.isExpired {
            parts.append("Expired")
        } else if document.expiresSoon, let days = document.daysUntilExpiry {
            parts.append("Expires in \(days) days")
        }
        if document.needsAttention { parts.append("Needs attention") }
        return parts.joined(separator: ", ")
    }
}

struct ExpirationBadge: View {
    let daysUntilExpiry: Int
    let isExpired: Bool

    private var label: String {
        if isExpired              { return "Expired" }
        if daysUntilExpiry <= 30  { return "\(daysUntilExpiry)d" }
        return "Valid"
    }

    /// Urgent = expired/expiring → kataChampagne (warm amber warning); healthy → kataGold faded.
    private var labelColor: Color {
        isExpired || daysUntilExpiry <= 30 ? Color.kataChampagne : Color.kataGold.opacity(0.5)
    }

    var body: some View {
        Text(label)
            .font(.kataMono(10))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(labelColor.opacity(0.12))
            .foregroundStyle(labelColor)
            .clipShape(Capsule())
            .accessibilityLabel(isExpired ? "Expired" : "\(daysUntilExpiry) days until expiry")
    }
}

#Preview {
    VaultView(pendingDocumentType: .constant(nil), pendingCategory: .constant(nil))
        .modelContainer(for: [Document.self, DocumentPage.self], inMemory: true)
}
