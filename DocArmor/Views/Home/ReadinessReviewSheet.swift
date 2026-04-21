import SwiftUI
import SwiftData

/// Shown when the user taps "Needs Attention" (or similar) on the home screen.
/// Presents one row per (document, reason) pair so the user sees WHICH document
/// needs work AND WHAT specifically is wrong, and can fix it inline when the
/// fix is one-tap (e.g. mark as verified).
struct ReadinessReviewSheet: View {
    let documents: [Document]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var editingDocument: Document?
    @State private var openingDetailFor: Document?

    fileprivate struct Row: Identifiable, Hashable {
        let id: String
        let document: Document
        let reason: AttentionReason

        static func == (lhs: Row, rhs: Row) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var rows: [Row] {
        documents
            .filter(\.needsAttention)
            .flatMap { doc in
                doc.attentionReasons.map { reason in
                    Row(id: "\(doc.id.uuidString)-\(reason.id)", document: doc, reason: reason)
                }
            }
    }

    private var groupedRows: [(reasonOrder: Int, title: String, rows: [Row])] {
        let grouped = Dictionary(grouping: rows) { $0.reason.groupOrder }
        return grouped
            .map { (order, rows) in
                let title = rows.first?.reason.groupTitle ?? ""
                let sorted = rows.sorted { lhs, rhs in
                    lhs.document.name.localizedCaseInsensitiveCompare(rhs.document.name) == .orderedAscending
                }
                return (order, title, sorted)
            }
            .sorted { $0.reasonOrder < $1.reasonOrder }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "Everything looks ready",
                        systemImage: "checkmark.seal.fill",
                        description: Text("No documents currently need your attention.")
                    )
                } else {
                    List {
                        summaryBanner
                        ForEach(groupedRows, id: \.reasonOrder) { group in
                            Section {
                                ForEach(group.rows) { row in
                                    ReadinessRow(
                                        row: row,
                                        onVerify: { markVerified(row.document) },
                                        onOpenDetail: { openingDetailFor = row.document },
                                        onOpenEditor: { editingDocument = row.document }
                                    )
                                }
                            } header: {
                                Text(group.title)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Needs Attention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingDocument) { doc in
                NavigationStack {
                    AddDocumentView(editingDocument: doc)
                }
            }
            .sheet(item: $openingDetailFor) { doc in
                NavigationStack {
                    DocumentDetailView(document: doc)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryBanner: some View {
        let uniqueDocs = Set(rows.map(\.document.id)).count
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(uniqueDocs) document\(uniqueDocs == 1 ? "" : "s") need attention")
                    .font(.subheadline.weight(.semibold))
                Text("Tap a row to fix it, or use the inline action when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
    }

    private func markVerified(_ document: Document) {
        document.lastVerifiedAt = .now
        document.updatedAt = .now
        try? modelContext.save()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

private struct ReadinessRow: View {
    let row: ReadinessReviewSheet.Row
    let onVerify: () -> Void
    let onOpenDetail: () -> Void
    let onOpenEditor: () -> Void

    var body: some View {
        Button(action: onOpenDetail) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.reason.systemImage)
                    .font(.title3)
                    .foregroundStyle(row.reason.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.document.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(row.document.ownerDisplayName)
                        Text("•")
                        Text(row.reason.shortLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                    actionButton
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch row.reason {
        case .neverVerified, .staleVerification:
            Button(action: onVerify) {
                Label("Mark verified", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)

        case .missingBackPage:
            Button(action: onOpenEditor) {
                Label("Add page", systemImage: "doc.badge.plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)

        case .expired, .expiringSoon:
            Button(action: onOpenEditor) {
                Label("Update date", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(row.reason.tint)
        }
    }
}
