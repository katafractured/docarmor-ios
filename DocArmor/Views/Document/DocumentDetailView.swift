import SwiftUI
import SwiftData
import KatafractStyle

struct DocumentDetailView: View {
    let document: Document

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var decryptedImages: [UIImage] = []
    @State private var currentPageIndex = 0
    @State private var isLoading = true
    @State private var decryptError: String?
    @State private var showingPresentMode = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var showingShareOptions = false
    @State private var showingShareWarning = false   // pre-share privacy confirmation
    @State private var shareItems: [Any] = []
    @State private var isBeingCaptured = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: Page Carousel
                pageCarousel
                    .frame(height: 280)

                // MARK: Metadata
                VStack(alignment: .leading, spacing: 20) {
                    // Type + Category
                    HStack {
                        Label(document.documentType.rawValue, systemImage: document.documentType.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(document.category.rawValue, systemImage: document.category.systemImage)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(document.category.color.opacity(0.12))
                            .foregroundStyle(document.category.color)
                            .clipShape(Capsule())
                    }

                    Label(document.ownerDisplayName, systemImage: document.ownerName == nil ? "person.2.fill" : "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if document.needsAttention {
                        VStack(alignment: .leading, spacing: 8) {
                            if document.isMissingRequiredPages {
                                Label("Back side or supporting page is missing.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.kataChampagne.opacity(0.8))
                            }
                            if document.needsVerificationReview {
                                Label("Review this document for accuracy. It has not been verified recently.", systemImage: "checkmark.seal.trianglebadge.exclamationmark")
                                    .foregroundStyle(Color.kataChampagne.opacity(0.8))
                            }
                        }
                        .font(.caption)
                    }

                    // Expiration
                    if let expiry = document.expirationDate {
                        ExpirationRow(expirationDate: expiry, isExpired: document.isExpired, daysUntilExpiry: document.daysUntilExpiry)
                    }

                    if !document.issuerName.isEmpty || !document.identifierSuffix.isEmpty || document.lastVerifiedAt != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if !document.issuerName.isEmpty {
                                detailLine(title: "Issuer", value: document.issuerName)
                            }
                            if !document.identifierSuffix.isEmpty {
                                detailLine(title: "ID Suffix", value: document.identifierSuffix)
                            }
                            if let lastVerifiedAt = document.lastVerifiedAt {
                                detailLine(
                                    title: "Last Verified",
                                    value: lastVerifiedAt.formatted(date: .abbreviated, time: .omitted)
                                )
                            }
                        }
                    }

                    // Notes
                    if !document.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(document.notes)
                                .font(.body)
                        }
                    }

                    if !document.renewalNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Renewal Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(document.renewalNotes)
                                .font(.body)
                        }
                    }

                    // Added date
                    Text("Added \(document.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }
        }
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Present Mode
                Button(action: { showingPresentMode = true }) {
                    Image(systemName: "rectangle.expand.vertical")
                }
                .disabled(decryptedImages.isEmpty)
                .accessibilityLabel("Present Mode")

                Menu {
                    Button(action: { showingEditSheet = true }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(action: { showingShareOptions = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(decryptedImages.isEmpty)
                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Document Actions")
            }
        }
        .task {
            await decryptPages()
        }
        .onAppear {
            updateCaptureState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            updateCaptureState()
        }
        .overlay {
            if isBeingCaptured { captureOverlay }
        }
        .fullScreenCover(isPresented: $showingPresentMode) {
            PresentModeView(images: decryptedImages, initialIndex: currentPageIndex, documentName: document.name)
        }
        .sheet(isPresented: $showingEditSheet) {
            AddDocumentView(editingDocument: document)
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityViewController(activityItems: shareItems)
        }
        .confirmationDialog("Choose Export Copy", isPresented: $showingShareOptions, titleVisibility: .visible) {
            Button("Current Page") {
                stageShare(items: [decryptedImages[currentPageIndex]])
            }

            if document.documentType.requiresFrontBack, let firstImage = decryptedImages.first {
                Button("Front Only") {
                    stageShare(items: [firstImage])
                }
            }

            if decryptedImages.count > 1 {
                Button("Entire Document") {
                    stageShare(items: decryptedImages)
                }
            }

            Button("Watermarked Current Page") {
                stageShare(items: [watermarked(image: decryptedImages[currentPageIndex], label: "DocArmor Preview")])
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the narrowest export that gets the job done. Shared copies leave DocArmor unencrypted.")
        }
        // Privacy gate before sharing — exporting leaves the encrypted vault
        .alert("Export Unencrypted Image?", isPresented: $showingShareWarning) {
            Button("Export Anyway", role: .destructive) {
                showingShareSheet = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sharing will export a plain, unencrypted image outside DocArmor. Only share with people or apps you trust.")
        }
        .alert("Delete Document?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) { deleteDocument() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(document.name)\" and all its pages. This cannot be undone.")
        }
    }

    private func detailLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: - Page Carousel

    private var pageCarousel: some View {
        ZStack {
            Color(.systemGroupedBackground)

            if isLoading {
                KataProgressRing(size: 24)
            } else if let error = decryptError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.kataCrimson)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if decryptedImages.isEmpty {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tertiary)
            } else {
                TabView(selection: $currentPageIndex) {
                    ForEach(decryptedImages.indices, id: \.self) { i in
                        Image(uiImage: decryptedImages[i])
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
    }

    // MARK: - Decrypt

    private func decryptPages() async {
        isLoading = true
        decryptError = nil

        do {
            let key   = try VaultKey.load()
            let pages = document.sortedPages

            // Decrypt all pages concurrently so a 10-page document takes
            // max(individual decrypt time) rather than sum(all decrypt times).
            var ordered = [Int: UIImage](minimumCapacity: pages.count)
            try await withThrowingTaskGroup(of: (Int, UIImage?).self) { group in
                for (idx, page) in pages.enumerated() {
                    let encData = page.encryptedImageData
                    let nonce   = page.nonce
                    group.addTask(priority: .userInitiated) {
                        let jpeg = try EncryptionService.decrypt(
                            encryptedData: encData,
                            nonce: nonce,
                            using: key
                        )
                        return (idx, UIImage(data: jpeg))
                    }
                }
                for try await (idx, image) in group {
                    ordered[idx] = image
                }
            }
            // Restore page order from the index map
            decryptedImages = (0..<pages.count).compactMap { ordered[$0] }
        } catch {
            decryptError = "Could not decrypt document: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Share

    private func shareCurrentPage() {
        guard currentPageIndex < decryptedImages.count else { return }
        // Show a privacy warning before handing the decrypted image to the
        // system share sheet, where it could be sent outside the encrypted vault.
        showingShareOptions = true
    }

    private func stageShare(items: [Any]) {
        guard !items.isEmpty else { return }
        shareItems = items
        showingShareWarning = true
    }

    private func watermarked(image: UIImage, label: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(at: .zero)

            let inset: CGFloat = 24
            let bannerHeight = max(44, image.size.height * 0.1)
            let bannerRect = CGRect(
                x: inset,
                y: image.size.height - bannerHeight - inset,
                width: image.size.width - (inset * 2),
                height: bannerHeight
            )

            UIColor.black.withAlphaComponent(0.58).setFill()
            UIBezierPath(roundedRect: bannerRect, cornerRadius: 18).fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: max(18, image.size.width * 0.035)),
                .foregroundColor: UIColor.white
            ]

            let textSize = label.size(withAttributes: attributes)
            let textRect = CGRect(
                x: bannerRect.minX + 18,
                y: bannerRect.midY - (textSize.height / 2),
                width: bannerRect.width - 36,
                height: textSize.height
            )
            label.draw(in: textRect, withAttributes: attributes)
        }
    }

    private func updateCaptureState() {
        let activeScreen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        isBeingCaptured = activeScreen?.isCaptured ?? false
    }

    // MARK: - Delete

    private func deleteDocument() {
        ExpirationService.cancelReminder(for: document)
        modelContext.delete(document)
        dismiss()
    }

    // MARK: - Capture Overlay

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
                Text("DocArmor hides document content\nwhile screen recording is active.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Supporting Views

struct ExpirationRow: View {
    let expirationDate: Date
    let isExpired: Bool
    let daysUntilExpiry: Int?

    private var color: Color {
        if isExpired { return .red }
        if let days = daysUntilExpiry, days <= 30 { return .orange }
        return .green
    }

    private var label: String {
        if isExpired { return "Expired \(expirationDate.formatted(date: .abbreviated, time: .omitted))" }
        guard let days = daysUntilExpiry else { return "Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))" }
        if days == 0 { return "Expires today" }
        return "Expires in \(days) days (\(expirationDate.formatted(date: .abbreviated, time: .omitted)))"
    }

    var body: some View {
        Label(label, systemImage: isExpired ? "exclamationmark.circle.fill" : "calendar")
            .font(.subheadline)
            .foregroundStyle(color)
    }
}

/// UIKit share sheet wrapper
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        DocumentDetailView(document: {
            let doc = Document(name: "John's License", documentType: .driversLicense)
            return doc
        }())
    }
    .modelContainer(for: [Document.self, DocumentPage.self], inMemory: true)
}
