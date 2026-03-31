import CryptoKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddDocumentView: View {
    private enum SaveMode {
        case normal
        case appendToExisting(Document)
        case replaceExisting(Document)
    }

    private struct DuplicateMatch: Identifiable {
        let document: Document
        let summary: String
        let score: Int

        var id: UUID { document.id }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allDocuments: [Document]

    // Edit mode: pass an existing document
    var editingDocument: Document?
    var initialImportedImages: [UIImage] = []
    var initialDocumentName: String? = nil
    var pendingImportItemsToConsume: [PendingImportItem] = []

    // MARK: - Form State

    @State private var name = ""
    @State private var selectedOwnerName: String?
    @State private var selectedType: DocumentType = .driversLicense
    @State private var selectedCategory: DocumentCategory = .identity
    @State private var notes = ""
    @State private var issuerName = ""
    @State private var identifierSuffix = ""
    @State private var hasLastVerified = false
    @State private var lastVerifiedAt = Date.now
    @State private var renewalNotes = ""
    @State private var hasExpiration = false
    @State private var expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var selectedReminderDays: Set<Int> = [30]

    // Pages captured/imported (raw, not yet encrypted)
    @State private var capturedImages: [UIImage] = []
    @State private var pageLabels: [String] = []

    // Existing page thumbnails shown in edit mode (decrypted for preview)
    @State private var existingPageThumbnails: [UIImage] = []
    @State private var isLoadingExistingPages = false

    // OCR suggestions shown as tappable chips after image capture
    @State private var suggestedName: String?
    @State private var suggestedIssuer: String?
    @State private var suggestedDocNumber: String?
    @State private var suggestedExpiry: Date?
    @State private var suggestedType: DocumentType?
    @State private var suggestedCategory: DocumentCategory?
    @State private var suggestedOwnerName: String?
    @State private var ocrConfidenceScore: Double?
    @State private var ocrQualityWarnings: [String] = []
    @State private var pageStructureHints: [OCRService.StructureHint] = []
    @State private var ocrSuggestionSource: OCRService.SuggestionSource = .deterministic

    // Sheet presentation
    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var duplicateMatches: [DuplicateMatch] = []
    @State private var showingDuplicateResolution = false
    @State private var hasConfirmedDuplicateSave = false
    @State private var scannerError: String?
    @State private var importError: String?
    @State private var householdMembers = HouseholdStore.loadMembers()
    @State private var householdProfiles = HouseholdStore.loadProfiles()
    @State private var pendingInboxItems: [PendingImportItem] = ImportInboxService.pendingItems()
    @State private var hasAppliedInitialImport = false
    @State private var cropImageIndex: Int? = nil

    private var isEditing: Bool { editingDocument != nil }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Document Info
                Section("Document Info") {
                    TextField("Name (e.g. John's Passport)", text: $name)
                        .autocorrectionDisabled()

                    if let suggested = suggestedName, name.isEmpty {
                        suggestionChip(label: "Use \"\(suggested)\"") {
                            name = suggested
                            suggestedName = nil
                        }
                    }

                    Picker(selection: $selectedOwnerName) {
                        Label("Shared", systemImage: "person.2.fill").tag(Optional<String>.none)
                        ForEach(availableHouseholdMembers, id: \.self) { member in
                            Label(member, systemImage: "person.fill").tag(Optional(member))
                        }
                    } label: {
                        Label("Person", systemImage: selectedOwnerName == nil ? "person.2.fill" : "person.fill")
                    }
                    .pickerStyle(.menu)

                    if let suggestedOwnerName, suggestedOwnerName != selectedOwnerName {
                        suggestionChip(label: "Assign to \(suggestedOwnerName)") {
                            selectedOwnerName = suggestedOwnerName
                            self.suggestedOwnerName = nil
                        }
                    }

                    Picker(selection: $selectedCategory) {
                        ForEach(DocumentCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                        }
                    } label: {
                        Label("Category", systemImage: selectedCategory.systemImage)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedCategory) { _, newCategory in
                        // Reset type to first valid option for the new category if needed
                        if selectedType.defaultCategory != newCategory {
                            let validTypes = DocumentType.allCases.filter { $0.defaultCategory == newCategory }
                            selectedType = validTypes.first ?? .custom
                            updatePageLabels()
                        }
                    }

                    if let suggestedCategory, suggestedType == nil, suggestedCategory != selectedCategory {
                        suggestionChip(label: "Use \(suggestedCategory.rawValue)") {
                            selectedCategory = suggestedCategory
                            self.suggestedCategory = nil
                        }
                    }

                    Picker(selection: $selectedType) {
                        ForEach(typesForSelectedCategory, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemImage).tag(type)
                        }
                    } label: {
                        Label("Type", systemImage: selectedType.systemImage)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) { _, newType in
                        updatePageLabels()
                    }

                    if let suggestedType, suggestedType != selectedType {
                        suggestionChip(label: "Use \(suggestedType.rawValue)") {
                            selectedType = suggestedType
                            selectedCategory = suggestedType.defaultCategory
                            self.suggestedType = nil
                            self.suggestedCategory = nil
                            updatePageLabels()
                        }
                    }
                }

                Section("Reference Details") {
                    if !capturedImages.isEmpty {
                        Label(ocrSuggestionSource.displayLabel, systemImage: ocrSuggestionSource == .foundationModel ? "sparkles" : "text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Issuing authority", text: $issuerName)
                        .autocorrectionDisabled()

                    if let suggested = suggestedIssuer, issuerName.isEmpty {
                        suggestionChip(label: "Use issuer: \(suggested)") {
                            issuerName = suggested
                            suggestedIssuer = nil
                        }
                    }

                    TextField("ID or policy suffix", text: $identifierSuffix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    if let suggested = suggestedDocNumber, identifierSuffix.isEmpty {
                        suggestionChip(label: "Use doc number: \(suggested)") {
                            identifierSuffix = suggested
                            suggestedDocNumber = nil
                        }
                    }

                    Toggle("Track last verification", isOn: $hasLastVerified)

                    if hasLastVerified {
                        DatePicker("Last Verified", selection: $lastVerifiedAt, displayedComponents: .date)
                    }

                    TextField("Renewal notes", text: $renewalNotes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // MARK: Expiration
                Section("Expiration") {
                    Toggle("Has Expiration Date", isOn: $hasExpiration)

                    if !hasExpiration, let suggested = suggestedExpiry {
                        suggestionChip(label: "Set expiry: \(suggested.formatted(date: .abbreviated, time: .omitted))") {
                            hasExpiration = true
                            expirationDate = suggested
                            suggestedExpiry = nil
                        }
                    }

                    if hasExpiration {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)

                        ForEach([30, 60, 90], id: \.self) { days in
                            Toggle("\(days) days before", isOn: Binding(
                                get: { selectedReminderDays.contains(days) },
                                set: { on in
                                    if on { selectedReminderDays.insert(days) }
                                    else  { selectedReminderDays.remove(days) }
                                }
                            ))
                        }
                    }
                }

                // MARK: Notes
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // MARK: Pages
                Section("Document Pages") {
                    if isEditing {
                        // Existing pages (decrypted thumbnails)
                        if isLoadingExistingPages {
                            ProgressView("Loading pages…")
                        } else if !existingPageThumbnails.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(existingPageThumbnails.indices, id: \.self) { i in
                                        Image(uiImage: existingPageThumbnails[i])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.separator, lineWidth: 1)
                                            )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // New pages to append
                        if !capturedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(capturedImages.indices, id: \.self) { i in
                                        VStack(spacing: 4) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: capturedImages[i])
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 80, height: 60)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(.tint.opacity(0.6), lineWidth: 2)
                                                    )
                                                Button {
                                                    cropImageIndex = i
                                                } label: {
                                                    Image(systemName: "crop")
                                                        .font(.caption2.bold())
                                                        .padding(4)
                                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                                }
                                                .buttonStyle(.plain)
                                                .padding(4)
                                            }
                                            Text("New")
                                                .font(.caption2)
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            Button(role: .destructive) {
                                capturedImages.removeAll()
                            } label: {
                                Label("Clear New Pages", systemImage: "trash")
                            }
                        }

                        Button(action: { showingScanner = true }) {
                            Label("Add Pages via Scan", systemImage: "camera.viewfinder")
                        }
                        Button(action: { showingPhotoPicker = true }) {
                            Label("Add Pages from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button(action: { showingFileImporter = true }) {
                            Label("Add Pages from Files", systemImage: "doc.badge.plus")
                        }
                        if !pendingInboxItems.isEmpty {
                            Button(action: {
                                Task { await importPendingInboxItems() }
                            }) {
                                Label("Import Shared Items (\(pendingInboxItems.count))", systemImage: "square.and.arrow.down")
                            }
                        }
                    } else {
                        if capturedImages.isEmpty {
                            VStack(spacing: 12) {
                                Button(action: { showingScanner = true }) {
                                    Label("Scan Document", systemImage: "camera.viewfinder")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button(action: { showingPhotoPicker = true }) {
                                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button(action: { showingFileImporter = true }) {
                                    Label("Import from Files", systemImage: "doc.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                if !pendingInboxItems.isEmpty {
                                    Button(action: {
                                        Task { await importPendingInboxItems() }
                                    }) {
                                        Label("Import Shared Items (\(pendingInboxItems.count))", systemImage: "square.and.arrow.down")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(capturedImages.indices, id: \.self) { i in
                                        VStack(spacing: 4) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: capturedImages[i])
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 80, height: 60)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(.separator, lineWidth: 1)
                                                    )
                                                Button {
                                                    cropImageIndex = i
                                                } label: {
                                                    Image(systemName: "crop")
                                                        .font(.caption2.bold())
                                                        .padding(4)
                                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                                }
                                                .buttonStyle(.plain)
                                                .padding(4)
                                            }
                                            if i < pageLabels.count {
                                                Text(pageLabels[i])
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            Button(role: .destructive) {
                                capturedImages.removeAll()
                            } label: {
                                Label("Clear Pages", systemImage: "trash")
                            }

                            Button(action: { showingScanner = true }) {
                                Label("Rescan", systemImage: "camera.viewfinder")
                            }
                            Button(action: { showingFileImporter = true }) {
                                Label("Add from Files", systemImage: "doc.badge.plus")
                            }
                        }
                    }

                    if !scanWarnings.isEmpty {
                        ForEach(scanWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // MARK: Save Error
                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Document" : "Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await attemptSaveDocument() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerWrapperView(
                    onCompletion: { images in
                        capturedImages = images
                        updatePageLabels()
                        showingScanner = false
                        Task { await runOCR(on: images) }
                    },
                    onCancel: { showingScanner = false },
                    onError: { error in
                        showingScanner = false
                        scannerError = error.localizedDescription
                    }
                )
                .ignoresSafeArea()
            }
            .alert("Camera Unavailable", isPresented: .init(
                get: { scannerError != nil },
                set: { if !$0 { scannerError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scannerError ?? "The document scanner could not start. Check that camera access is allowed in Settings.")
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPickerView(
                    onCompletion: { images in
                        capturedImages = images
                        updatePageLabels()
                        showingPhotoPicker = false
                        Task { await runOCR(on: images) }
                    },
                    onCancel: { showingPhotoPicker = false }
                )
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await importFiles(from: urls) }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { cropImageIndex != nil },
                set: { if !$0 { cropImageIndex = nil } }
            )) {
                if let index = cropImageIndex, capturedImages.indices.contains(index) {
                    ImageCropView(
                        image: capturedImages[index],
                        documentType: selectedType
                    ) { cropped in
                        capturedImages[index] = cropped
                        cropImageIndex = nil
                    } onCancel: {
                        cropImageIndex = nil
                    }
                }
            }
            .onAppear {
                householdProfiles = HouseholdStore.loadProfiles()
                refreshPendingInboxItems()
                if let doc = editingDocument {
                    name = doc.name
                    selectedOwnerName = HouseholdStore.normalize(doc.ownerName)
                    selectedType = doc.documentType
                    selectedCategory = doc.category
                    notes = doc.notes
                    issuerName = doc.issuerName
                    identifierSuffix = doc.identifierSuffix
                    hasLastVerified = doc.lastVerifiedAt != nil
                    if let lastVerified = doc.lastVerifiedAt {
                        lastVerifiedAt = lastVerified
                    }
                    renewalNotes = doc.renewalNotes
                    hasExpiration = doc.expirationDate != nil
                    if let expiry = doc.expirationDate { expirationDate = expiry }
                    selectedReminderDays = Set(doc.expirationReminderDays ?? [])
                    applyInitialImportIfNeeded()
                    Task { await loadExistingPageThumbnails() }
                } else {
                    selectedOwnerName = availableHouseholdMembers.first
                    updatePageLabels()
                    applyInitialImportIfNeeded()
                }
            }
            .alert("Import Failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "The file could not be imported.")
            }
            .confirmationDialog(
                "Possible Duplicate",
                isPresented: $showingDuplicateResolution,
                titleVisibility: .visible
            ) {
                if let bestDuplicateMatch {
                    Button("Replace Existing") {
                        Task { await saveDocument(mode: .replaceExisting(bestDuplicateMatch.document)) }
                    }
                    Button("Append Pages to Existing") {
                        Task { await saveDocument(mode: .appendToExisting(bestDuplicateMatch.document)) }
                    }
                }
                Button("Keep Both") {
                    hasConfirmedDuplicateSave = true
                    Task { await saveDocument(mode: .normal) }
                }
                Button("Cancel", role: .cancel) {
                    hasConfirmedDuplicateSave = false
                }
            } message: {
                Text(duplicateResolutionMessage)
            }
        }
    }

    private var bestDuplicateMatch: DuplicateMatch? {
        duplicateMatches.first
    }

    private var duplicateResolutionMessage: String {
        guard let bestDuplicateMatch else { return "A similar document already exists in the vault." }
        return "Closest match:\n\(bestDuplicateMatch.summary)"
    }

    // MARK: - Validation

    private var reminderArrayOrNil: [Int]? {
        let sorted = selectedReminderDays.sorted()
        return sorted.isEmpty ? nil : sorted
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isEditing || !capturedImages.isEmpty)
    }

    private var typesForSelectedCategory: [DocumentType] {
        let filtered = DocumentType.allCases.filter { $0.defaultCategory == selectedCategory }
        guard !filtered.isEmpty else { return DocumentType.allCases }
        // Always keep the current selection visible even if the category was overridden
        if !filtered.contains(selectedType) {
            return [selectedType] + filtered
        }
        return filtered
    }

    private var availableHouseholdMembers: [String] {
        var members = householdMembers
        if let selectedOwnerName, !members.contains(selectedOwnerName) {
            members.append(selectedOwnerName)
        }
        return members.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var scanWarnings: [String] {
        guard !capturedImages.isEmpty else { return [] }

        var warnings: [String] = []
        let existingCount = editingDocument?.pages.count ?? 0
        let totalPageCount = existingCount + capturedImages.count

        if selectedType.requiresFrontBack && totalPageCount < 2 {
            warnings.append("This document usually needs both front and back images.")
        }

        if capturedImages.contains(where: { min($0.size.width, $0.size.height) < 900 }) {
            warnings.append("One or more pages look low resolution. Retake if text is not crisp.")
        }

        if selectedType.requiresFrontBack, capturedImages.count == 1, let hint = pageStructureHints.first?.warningText {
            warnings.append("\(hint) Capture the other side before saving.")
        }

        if selectedType.requiresFrontBack,
           pageStructureHints.count >= 2,
           pageStructureHints[0] != .unclear,
           pageStructureHints[0] == pageStructureHints[1] {
            warnings.append("The first two scans look like the same side of the document. Confirm that both front and back are included.")
        }

        if let ocrConfidenceScore {
            let percent = Int((ocrConfidenceScore * 100).rounded())
            warnings.append("OCR confidence: \(percent)%")
        }

        warnings.append(contentsOf: ocrQualityWarnings)
        return warnings
    }

    // MARK: - Page Labels

    private func updatePageLabels() {
        if selectedType.requiresFrontBack && capturedImages.count >= 2 {
            pageLabels = ["Front", "Back"] + (2..<capturedImages.count).map { "Page \($0 + 1)" }
        } else {
            pageLabels = capturedImages.indices.map { i in
                capturedImages.count == 1 ? "" : "Page \(i + 1)"
            }
        }
    }

    // MARK: - OCR

    private func runOCR(on images: [UIImage]) async {
        guard !images.isEmpty else { return }

        var structureHints: [OCRService.StructureHint] = []
        for (index, image) in images.prefix(2).enumerated() {
            let suggestions = await OCRService.extractSuggestions(from: image)
            structureHints.append(suggestions.structureHint)

            if index == 0 {
                if let n = suggestions.name, !n.isEmpty { suggestedName = n }
                if let issuer = suggestions.issuerName, !issuer.isEmpty { suggestedIssuer = issuer }
                if let d = suggestions.documentNumber { suggestedDocNumber = d }
                if let e = suggestions.expirationDate { suggestedExpiry = e }
                ocrConfidenceScore = suggestions.confidenceScore
                ocrQualityWarnings = suggestions.qualityWarnings
                ocrSuggestionSource = suggestions.source

                let classification = LocalDocumentClassificationService.suggest(
                    from: suggestions,
                    householdProfiles: householdProfiles
                )
                suggestedType = classification.documentType
                suggestedCategory = classification.category
                suggestedOwnerName = classification.ownerName
            }
        }

        pageStructureHints = structureHints
    }

    private func importFiles(from urls: [URL]) async {
        do {
            let result = try DocumentImportNormalizationService.normalize(urls: urls)
            applyImportedImages(result.images, suggestedDocumentName: result.suggestedName)
            await runOCR(on: result.images)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importPendingInboxItems() async {
        let items = pendingInboxItems
        guard !items.isEmpty else { return }

        do {
            let result = try DocumentImportNormalizationService.normalize(urls: items.map(\.fileURL))
            applyImportedImages(result.images, suggestedDocumentName: result.suggestedName)
            for item in items {
                try ImportInboxService.consume(item)
            }
            refreshPendingInboxItems()
            await runOCR(on: result.images)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func applyImportedImages(_ images: [UIImage], suggestedDocumentName: String?) {
        if isEditing {
            capturedImages.append(contentsOf: images)
        } else {
            capturedImages = images
        }

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggestedDocumentName,
           !suggestedDocumentName.isEmpty {
            name = suggestedDocumentName
        }

        updatePageLabels()
    }

    private func refreshPendingInboxItems() {
        pendingInboxItems = ImportInboxService.pendingItems()
    }

    private func applyInitialImportIfNeeded() {
        guard !hasAppliedInitialImport else { return }
        hasAppliedInitialImport = true
        guard !initialImportedImages.isEmpty else { return }

        if isEditing {
            capturedImages.append(contentsOf: initialImportedImages)
        } else {
            capturedImages = initialImportedImages
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let initialDocumentName,
           !initialDocumentName.isEmpty {
            name = initialDocumentName
        }
        updatePageLabels()
        Task { await runOCR(on: initialImportedImages) }
    }

    private func suggestionChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: "sparkles")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(.tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load Existing Page Thumbnails

    private func loadExistingPageThumbnails() async {
        guard let doc = editingDocument else { return }
        isLoadingExistingPages = true
        do {
            let key = try VaultKey.load()
            let pages = doc.sortedPages
            var ordered = [Int: UIImage](minimumCapacity: pages.count)
            try await withThrowingTaskGroup(of: (Int, UIImage?).self) { group in
                for (idx, page) in pages.enumerated() {
                    let encData = page.encryptedImageData
                    let nonce   = page.nonce
                    group.addTask(priority: .userInitiated) {
                        let jpeg = try EncryptionService.decrypt(
                            encryptedData: encData, nonce: nonce, using: key)
                        return (idx, UIImage(data: jpeg))
                    }
                }
                for try await (idx, image) in group {
                    ordered[idx] = image
                }
            }
            existingPageThumbnails = (0..<pages.count).compactMap { ordered[$0] }
        } catch {
            // Thumbnails unavailable — edit still works; pages won't be shown
        }
        isLoadingExistingPages = false
    }

    // MARK: - Save

    private func attemptSaveDocument() async {
        hasConfirmedDuplicateSave = false
        duplicateMatches = probableDuplicateMatches()
        guard duplicateMatches.isEmpty else {
            showingDuplicateResolution = true
            return
        }

        await saveDocument(mode: .normal)
    }

    private func saveDocument(mode: SaveMode) async {
        isSaving = true
        saveError = nil

        do {
            let key = try VaultKey.load()

            if let doc = editingDocument {
                // Update existing document metadata
                applyFormMetadata(to: doc)

                // Append any newly captured pages to the existing document
                if !capturedImages.isEmpty {
                    try await appendCapturedPages(to: doc, using: key)
                }

                ExpirationService.updateReminder(for: doc)
            } else if case .appendToExisting(let existingDocument) = mode {
                applyFormMetadata(to: existingDocument)
                try await appendCapturedPages(to: existingDocument, using: key)
                ExpirationService.updateReminder(for: existingDocument)
            } else if case .replaceExisting(let existingDocument) = mode {
                applyFormMetadata(to: existingDocument)
                replacePages(in: existingDocument)
                try await addCapturedPages(to: existingDocument, startingAt: 0, using: key)
                ExpirationService.updateReminder(for: existingDocument)
            } else {
                // Create new document + encrypt pages
                let document = Document(
                    name: name.trimmingCharacters(in: .whitespaces),
                    ownerName: HouseholdStore.normalize(selectedOwnerName),
                    documentType: selectedType,
                    category: selectedCategory,
                    notes: notes,
                    issuerName: issuerName.trimmingCharacters(in: .whitespacesAndNewlines),
                    identifierSuffix: identifierSuffix.trimmingCharacters(in: .whitespacesAndNewlines),
                    ocrSuggestedIssuerName: normalizedOCRSuggestion(suggestedIssuer),
                    ocrSuggestedIdentifier: normalizedOCRSuggestion(suggestedDocNumber),
                    ocrSuggestedExpirationDate: suggestedExpiry,
                    ocrConfidenceScore: ocrConfidenceScore,
                    ocrExtractedAt: ocrMetadataTimestamp,
                    ocrStructureHintsRaw: normalizedStructureHints,
                    lastVerifiedAt: hasLastVerified ? lastVerifiedAt : nil,
                    renewalNotes: renewalNotes,
                    expirationDate: hasExpiration ? expirationDate : nil,
                    expirationReminderDays: hasExpiration ? reminderArrayOrNil : nil
                )
                modelContext.insert(document)

                try await addCapturedPages(to: document, startingAt: 0, using: key)

                ExpirationService.scheduleReminder(for: document)
            }

            // Reset flag before dismiss so re-presentation doesn't flash "Saving…"
            if !pendingImportItemsToConsume.isEmpty {
                for item in pendingImportItemsToConsume {
                    try? ImportInboxService.consume(item)
                }
            }
            try modelContext.save()
            isSaving = false
            dismiss()
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
        }
    }

    private func persistOCRMetadata(into document: Document) {
        document.ocrSuggestedIssuerName = normalizedOCRSuggestion(suggestedIssuer)
        document.ocrSuggestedIdentifier = normalizedOCRSuggestion(suggestedDocNumber)
        document.ocrSuggestedExpirationDate = suggestedExpiry
        document.ocrConfidenceScore = ocrConfidenceScore
        document.ocrExtractedAt = ocrMetadataTimestamp
        document.ocrStructureHintsRaw = normalizedStructureHints
    }

    private func normalizedOCRSuggestion(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedStructureHints: [String]? {
        let values = pageStructureHints
            .filter { $0 != .unclear }
            .map(\.rawValue)
        return values.isEmpty ? nil : values
    }

    private var ocrMetadataTimestamp: Date? {
        let hasOCRPayload = normalizedOCRSuggestion(suggestedIssuer) != nil ||
            normalizedOCRSuggestion(suggestedDocNumber) != nil ||
            suggestedExpiry != nil ||
            ocrConfidenceScore != nil ||
            normalizedStructureHints != nil
        return hasOCRPayload ? .now : nil
    }

    private func probableDuplicateMatches() -> [DuplicateMatch] {
        guard !hasConfirmedDuplicateSave else { return [] }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedOwner = HouseholdStore.normalize(selectedOwnerName)?.lowercased()
        let normalizedSuffix = identifierSuffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedExpiration = hasExpiration ? expirationDate : nil

        return allDocuments.compactMap { existing -> DuplicateMatch? in
            if let editingDocument, existing.id == editingDocument.id {
                return nil
            }

            guard existing.documentType == selectedType else { return nil }

            let existingOwner = HouseholdStore.normalize(existing.ownerName)?.lowercased()
            let ownerMatches = existingOwner == normalizedOwner

            let existingName = existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let nameMatches = !normalizedName.isEmpty && existingName == normalizedName

            let existingSuffix = existing.identifierSuffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let suffixMatches = !normalizedSuffix.isEmpty && existingSuffix == normalizedSuffix

            let expiryMatches: Bool
            if let selectedExpiration, let existingExpiration = existing.expirationDate {
                expiryMatches = Calendar.current.isDate(existingExpiration, inSameDayAs: selectedExpiration)
            } else {
                expiryMatches = false
            }

            let strongMatchCount = [nameMatches, suffixMatches, expiryMatches].filter { $0 }.count
            guard ownerMatches && strongMatchCount >= 2 else { return nil }

            var parts = [existing.name, existing.documentType.rawValue]
            if !existing.identifierSuffix.isEmpty {
                parts.append("suffix \(existing.identifierSuffix)")
            }
            if let expiry = existing.expirationDate {
                parts.append("expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
            }
            return DuplicateMatch(
                document: existing,
                summary: parts.joined(separator: " • "),
                score: strongMatchCount
            )
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.summary < rhs.summary
        }
    }

    private func applyFormMetadata(to document: Document) {
        document.name = name.trimmingCharacters(in: .whitespaces)
        document.ownerName = HouseholdStore.normalize(selectedOwnerName)
        document.documentTypeRaw = selectedType.rawValue
        document.categoryRaw = selectedCategory.rawValue
        document.notes = notes
        document.issuerName = issuerName.trimmingCharacters(in: .whitespacesAndNewlines)
        document.identifierSuffix = identifierSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        document.lastVerifiedAt = hasLastVerified ? lastVerifiedAt : nil
        document.renewalNotes = renewalNotes
        document.expirationDate = hasExpiration ? expirationDate : nil
        document.expirationReminderDays = hasExpiration ? reminderArrayOrNil : nil
        persistOCRMetadata(into: document)
        document.updatedAt = .now
    }

    private func appendCapturedPages(to document: Document, using key: SymmetricKey) async throws {
        try await addCapturedPages(to: document, startingAt: document.pages.count, using: key)
    }

    private func addCapturedPages(to document: Document, startingAt startIndex: Int, using key: SymmetricKey) async throws {
        for (offset, image) in capturedImages.enumerated() {
            let jpegData = image.jpegData(compressionQuality: 0.85) ?? Data()
            let (encrypted, nonce) = try await Task.detached(priority: .userInitiated) {
                try EncryptionService.encrypt(jpegData, using: key)
            }.value

            let labelIndex = startIndex + offset
            let label: String?
            if offset < pageLabels.count {
                label = pageLabels[offset].isEmpty ? nil : pageLabels[offset]
            } else {
                label = nil
            }

            let page = DocumentPage(
                pageIndex: labelIndex,
                encryptedImageData: encrypted,
                nonce: nonce,
                label: label
            )
            page.document = document
            modelContext.insert(page)
        }
    }

    private func replacePages(in document: Document) {
        for page in document.pages {
            modelContext.delete(page)
        }
    }
}

#Preview {
    AddDocumentView()
        .modelContainer(for: [Document.self, DocumentPage.self], inMemory: true)
}
