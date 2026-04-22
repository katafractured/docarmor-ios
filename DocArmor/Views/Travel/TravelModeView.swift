import SwiftUI
import KatafractStyle
import SwiftData

struct TravelModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementService.self) private var entitlementService
    @Query(sort: \Document.name) private var allDocuments: [Document]

    @State private var navigationPath = NavigationPath()
    @State private var showingQuickPresent = false
    @State private var quickPresentImages: [UIImage] = []
    @State private var quickPresentDocumentName = ""

    private let travelTypes: Set<DocumentType> = [
        .passport, .driversLicense, .stateID, .globalEntry,
        .hotelLoyalty, .airlineMembership, .rentalCarMembership
    ]

    private var travelDocuments: [Document] {
        allDocuments.filter { doc in
            doc.category == .travel || travelTypes.contains(doc.documentType)
        }
    }

    private var readyDocuments: [Document] {
        travelDocuments.filter { !$0.needsAttention }
    }

    private var attentionDocuments: [Document] {
        travelDocuments.filter { $0.needsAttention }
    }

    private var householdTravelGaps: [TravelGap] {
        HouseholdStore.loadMembers().compactMap { member in
            let docs = travelDocuments.filter { $0.ownerDisplayName == member }
            let presentTypes = Set(docs.map(\.documentType))
            let required: [DocumentType] = [.passport, .driversLicense]
            let missing = required.filter { !presentTypes.contains($0) }
            return missing.isEmpty ? nil : TravelGap(ownerName: member, missingTypes: missing)
        }
    }

    @State private var showingPaywall = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !entitlementService.canUseTravelMode {
                    PaywallLockedTravelView { showingPaywall = true }
                } else if travelDocuments.isEmpty {
                    ContentUnavailableView(
                        "No Travel Documents",
                        systemImage: "airplane",
                        description: Text("Add travel-category documents or types like passport, driver's license, and membership cards to see them here.")
                    )
                } else {
                    List {
                        Section("Travel Readiness") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    summaryCard(
                                        title: "Ready",
                                        value: "\(readyDocuments.count)",
                                        caption: "Travel docs without active issues",
                                        systemImage: "checkmark.shield.fill",
                                        color: .green
                                    )
                                    summaryCard(
                                        title: "Needs Attention",
                                        value: "\(attentionDocuments.count)",
                                        caption: "Expired, stale, or incomplete",
                                        systemImage: "exclamationmark.triangle.fill",
                                        color: .orange
                                    )
                                    summaryCard(
                                        title: "People Missing ID",
                                        value: "\(householdTravelGaps.count)",
                                        caption: "Passport or license still missing",
                                        systemImage: "person.crop.circle.badge.exclamationmark",
                                        color: .secondary
                                    )
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if !householdTravelGaps.isEmpty {
                            Section("Missing Travel Identity") {
                                ForEach(householdTravelGaps) { gap in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(gap.ownerName, systemImage: "person.crop.circle")
                                            .font(.subheadline.weight(.semibold))
                                        Text(gap.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        if !readyDocuments.isEmpty {
                            Section {
                                ForEach(readyDocuments) { doc in
                                    DocumentRow(document: doc)
                                        .contentShape(Rectangle())
                                        .onTapGesture { navigationPath.append(doc) }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            quickPresentAction(for: doc)
                                        }
                                }
                            } header: {
                                Label("Ready to Travel", systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                    .font(.footnote.bold())
                            }
                        }

                        if !attentionDocuments.isEmpty {
                            Section {
                                ForEach(attentionDocuments) { doc in
                                    DocumentRow(document: doc)
                                        .contentShape(Rectangle())
                                        .onTapGesture { navigationPath.append(doc) }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            quickPresentAction(for: doc)
                                        }
                                }
                            } header: {
                                Label("Needs Attention", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.kataChampagne.opacity(0.8))
                                    .font(.footnote.bold())
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Travel Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Document.self) { document in
                DocumentDetailView(document: document)
            }
            .fullScreenCover(isPresented: $showingQuickPresent) {
                PresentModeView(
                    images: quickPresentImages,
                    documentName: quickPresentDocumentName
                )
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(
                    reason: .travelMode,
                    entitlementService: entitlementService,
                    dismiss: { showingPaywall = false }
                )
            }
        }
    }

    /// Locked state when neither the one-time unlock nor Sovereign is active.
    private struct PaywallLockedTravelView: View {
        let showPaywall: () -> Void
        var body: some View {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange, Color.kataChampagne.opacity(0.18))
                Text("Travel Mode")
                    .font(.title2.bold())
                Text("Pull every travel document into one ready-to-present view. Unlock DocArmor or add Sovereign to enable it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showPaywall()
                } label: {
                    Text("See unlock options")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .background(Color.kataChampagne, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func quickPresentAction(for document: Document) -> some View {
        Button {
            Task { await showNow(document) }
        } label: {
            Label("Show Now", systemImage: "rectangle.on.rectangle.circle.fill")
        }
        .tint(.blue)
    }

    private func summaryCard(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 170, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            // Fall back to the standard detail view if present mode cannot be prepared.
        }
    }
}

private struct TravelGap: Identifiable {
    let ownerName: String
    let missingTypes: [DocumentType]

    var id: String { ownerName }

    var summary: String {
        "Missing \(missingTypes.map(\.rawValue).joined(separator: " and "))."
    }
}

#Preview {
    TravelModeView()
        .modelContainer(for: [Document.self, DocumentPage.self], inMemory: true)
}
