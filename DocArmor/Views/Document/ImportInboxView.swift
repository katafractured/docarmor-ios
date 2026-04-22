// MARK: - EmptyStateView imported for empty states
import SwiftUI
import SwiftData

struct ImportInboxView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pendingItems: [PendingImportItem] = ImportInboxService.pendingItems()
    @State private var selectedImportPayload: ImportPayload?
    @State private var queuedImportPayloads: [ImportPayload] = []
    @State private var appendImportPayload: ImportPayload?
    @State private var importError: String?
    @State private var selectedItemIDs: Set<String> = []
    @State private var previewImages: [String: UIImage] = [:]
    @State private var structureHints: [String: OCRService.StructureHint] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if pendingItems.isEmpty {
                    DocArmorEmptyState(
                        title: "No Shared Items",
                        description: "Items shared to DocArmor will appear here before you save them into the vault.",
                        systemImage: "tray"
                    )
                } else {
                    List {
                        if !selectedItems.isEmpty {
                            Section("Batch Actions") {
                                Button {
                                    reviewSelectedAsSingleDocument()
                                } label: {
                                    Label("Merge Selected into One Document", systemImage: "square.stack.3d.up.fill")
                                }

                                Button {
                                    processSelectedOneByOne()
                                } label: {
                                    Label("Review Selected One by One", systemImage: "list.bullet.rectangle.portrait")
                                }

                                Button {
                                    appendSelectedToExisting()
                                } label: {
                                    Label("Append Selected to Existing", systemImage: "plus.rectangle.on.rectangle")
                                }

                                Button(role: .destructive) {
                                    discardSelected()
                                } label: {
                                    Label("Discard Selected", systemImage: "trash")
                                }
                            }
                        }

                        Section("Pending Imports") {
                            ForEach(pendingItems) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Button {
                                            toggleSelection(for: item)
                                        } label: {
                                            Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                                        }
                                        .buttonStyle(.plain)

                                        if let previewImage = previewImages[item.id] {
                                            Image(uiImage: previewImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 52, height: 40)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.secondary.opacity(0.12))
                                                .frame(width: 52, height: 40)
                                                .overlay(
                                                    Image(systemName: item.kind.systemImage)
                                                        .foregroundStyle(.tint)
                                                )
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.filename)
                                                .font(.body.weight(.medium))
                                                .lineLimit(2)
                                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if let pairHint = pairHint(for: item) {
                                                Text(pairHint)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                        Spacer()
                                    }

                                    HStack {
                                        Button("Review") {
                                            review(item)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button("Append…") {
                                            append(item)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Discard", role: .destructive) {
                                            discard(item)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Inbox")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !pendingItems.isEmpty {
                        Button(selectedItems.count == pendingItems.count ? "Clear Selection" : "Select All") {
                            toggleSelectAll()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !pendingItems.isEmpty {
                        Button("Clear All", role: .destructive) {
                            clearAll()
                        }
                    }
                }
            }
            .sheet(item: $selectedImportPayload, onDismiss: handleImportDismiss) { payload in
                AddDocumentView(
                    initialImportedImages: payload.images,
                    initialDocumentName: payload.suggestedName,
                    pendingImportItemsToConsume: payload.pendingItems
                )
            }
            .sheet(item: $appendImportPayload, onDismiss: refreshItems) { payload in
                AppendToDocumentPickerView(payload: payload)
            }
            .alert("Import Failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "The shared item could not be prepared.")
            }
            .task(id: pendingItems.map(\.id).joined(separator: "|")) {
                await loadPreviewsAndHints()
            }
        }
    }

    private func review(_ item: PendingImportItem) {
        do {
            selectedImportPayload = try payload(for: [item])
        } catch {
            importError = error.localizedDescription
        }
    }

    private func append(_ item: PendingImportItem) {
        do {
            appendImportPayload = try payload(for: [item])
        } catch {
            importError = error.localizedDescription
        }
    }

    private func discard(_ item: PendingImportItem) {
        do {
            try ImportInboxService.consume(item)
            refreshItems()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try ImportInboxService.clearInbox()
            refreshItems()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func refreshItems() {
        pendingItems = ImportInboxService.pendingItems()
        selectedItemIDs = selectedItemIDs.intersection(Set(pendingItems.map(\.id)))
    }

    private var selectedItems: [PendingImportItem] {
        pendingItems.filter { selectedItemIDs.contains($0.id) }
    }

    private func toggleSelection(for item: PendingImportItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    private func toggleSelectAll() {
        if selectedItems.count == pendingItems.count {
            selectedItemIDs.removeAll()
        } else {
            selectedItemIDs = Set(pendingItems.map(\.id))
        }
    }

    private func reviewSelectedAsSingleDocument() {
        guard !selectedItems.isEmpty else { return }
        do {
            selectedImportPayload = try payload(for: selectedItems)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func processSelectedOneByOne() {
        guard !selectedItems.isEmpty else { return }
        do {
            queuedImportPayloads = try selectedItems.map { try payload(for: [$0]) }
            selectedImportPayload = queuedImportPayloads.removeFirst()
        } catch {
            queuedImportPayloads.removeAll()
            importError = error.localizedDescription
        }
    }

    private func appendSelectedToExisting() {
        guard !selectedItems.isEmpty else { return }
        do {
            appendImportPayload = try payload(for: selectedItems)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func discardSelected() {
        guard !selectedItems.isEmpty else { return }
        do {
            for item in selectedItems {
                try ImportInboxService.consume(item)
            }
            refreshItems()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleImportDismiss() {
        refreshItems()
        if !queuedImportPayloads.isEmpty {
            selectedImportPayload = queuedImportPayloads.removeFirst()
        }
    }

    private func pairHint(for item: PendingImportItem) -> String? {
        guard let index = pendingItems.firstIndex(where: { $0.id == item.id }) else { return nil }
        let currentHint = structureHints[item.id] ?? .unclear

        if currentHint == .likelyFront, pendingItems.indices.contains(index + 1) {
            let next = pendingItems[index + 1]
            if structureHints[next.id] == .likelyBack {
                return "Likely front/back pair with \(next.filename)"
            }
        }

        if currentHint == .likelyBack, pendingItems.indices.contains(index - 1) {
            let previous = pendingItems[index - 1]
            if structureHints[previous.id] == .likelyFront {
                return "Likely paired with \(previous.filename)"
            }
        }

        return nil
    }

    private func loadPreviewsAndHints() async {
        var newPreviews: [String: UIImage] = [:]
        var newHints: [String: OCRService.StructureHint] = [:]

        for item in pendingItems {
            guard let preview = DocumentImportNormalizationService.previewImage(for: item.fileURL) else { continue }
            newPreviews[item.id] = preview
            let suggestions = await OCRService.extractSuggestions(from: preview)
            newHints[item.id] = suggestions.structureHint
        }

        previewImages = newPreviews
        structureHints = newHints
    }

    private func payload(for items: [PendingImportItem]) throws -> ImportPayload {
        let normalized = try DocumentImportNormalizationService.normalize(urls: items.map(\.fileURL))
        let suggestedName: String?
        if items.count == 1 {
            suggestedName = normalized.suggestedName
        } else {
            suggestedName = "Imported Batch"
        }
        return ImportPayload(
            images: normalized.images,
            suggestedName: suggestedName,
            pendingItems: items
        )
    }
}

private struct ImportPayload: Identifiable {
    let id = UUID()
    let images: [UIImage]
    let suggestedName: String?
    let pendingItems: [PendingImportItem]
}

private struct AppendToDocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Document.updatedAt, order: .reverse) private var allDocuments: [Document]

    let payload: ImportPayload

    var body: some View {
        NavigationStack {
            List(allDocuments) { document in
                Button {
                    selectedDocument = document
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.name)
                            .font(.body.weight(.medium))
                        Text("\(document.documentType.rawValue) • \(HouseholdStore.displayLabel(for: document.ownerName))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Append to Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedDocument) { document in
                AddDocumentView(
                    editingDocument: document,
                    initialImportedImages: payload.images,
                    initialDocumentName: payload.suggestedName,
                    pendingImportItemsToConsume: payload.pendingItems
                )
            }
        }
    }

    @State private var selectedDocument: Document?
}

#Preview {
    ImportInboxView()
}
