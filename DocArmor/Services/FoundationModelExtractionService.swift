import Foundation

#if canImport(FoundationModels)
@_weakLinked import FoundationModels
#endif

enum FoundationModelExtractionService {
    static func refine(
        lines: [String],
        barcodePayloads: [String],
        fallback: OCRService.Suggestions
    ) async -> OCRService.Suggestions {
        guard FoundationModelAvailabilityService.isAvailable else { return fallback }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let prompt = buildPrompt(lines: lines, barcodePayloads: barcodePayloads, fallback: fallback)
            let instructions = """
            Extract document fields from local OCR text. Prefer exact values already visible in the text or barcode payload. Return empty strings when unknown. Use ISO dates in yyyy-MM-dd format when you can infer a future expiration date. Choose the card side based on the available evidence.
            """

            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedDocumentFields.self
                )
                return merge(generated: response.content, into: fallback)
            } catch {
                return fallback
            }
        }
        #endif
        return fallback
    }

    private static func buildPrompt(
        lines: [String],
        barcodePayloads: [String],
        fallback: OCRService.Suggestions
    ) -> String {
        let joinedLines = lines.joined(separator: "\n")
        let joinedBarcodes = barcodePayloads.isEmpty ? "None" : barcodePayloads.joined(separator: "\n")
        return """
        OCR lines:
        \(joinedLines)

        Barcode payloads:
        \(joinedBarcodes)

        Deterministic fallback:
        name: \(fallback.name ?? "")
        issuer: \(fallback.issuerName ?? "")
        document number: \(fallback.documentNumber ?? "")
        expiration: \(fallback.expirationDate?.formatted(.iso8601.year().month().day()) ?? "")
        structure hint: \(fallback.structureHint.rawValue)
        """
    }

    private static func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parsedDate(_ value: String) -> Date? {
        guard let text = cleaned(value) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: text)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func merge(
        generated: GeneratedDocumentFields,
        into fallback: OCRService.Suggestions
    ) -> OCRService.Suggestions {
        OCRService.Suggestions(
            name: cleaned(generated.name) ?? fallback.name,
            issuerName: cleaned(generated.issuerName) ?? fallback.issuerName,
            documentNumber: cleaned(generated.documentNumber) ?? fallback.documentNumber,
            expirationDate: parsedDate(generated.expirationDateText) ?? fallback.expirationDate,
            textCorpus: fallback.textCorpus,
            structureHint: structureHint(from: generated.structureHint) ?? fallback.structureHint,
            confidenceScore: max(fallback.confidenceScore, 0.88),
            qualityWarnings: fallback.qualityWarnings,
            source: .foundationModel
        )
    }

    @available(iOS 26.0, *)
    private static func structureHint(from value: GeneratedStructureHint) -> OCRService.StructureHint? {
        switch value {
        case .front:
            return .likelyFront
        case .back:
            return .likelyBack
        case .unclear:
            return .unclear
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Structured document fields extracted from local OCR and barcode text.")
private struct GeneratedDocumentFields {
    @Guide(description: "The holder or person name if present. Empty when unknown.")
    var name: String

    @Guide(description: "The issuing organization or authority. Empty when unknown.")
    var issuerName: String

    @Guide(description: "The strongest document number or suffix candidate. Empty when unknown.")
    var documentNumber: String

    @Guide(description: "A future expiration date in yyyy-MM-dd format. Empty when unknown.")
    var expirationDateText: String

    @Guide(description: "Whether the scan looks like the front side, back side, or remains unclear.")
    var structureHint: GeneratedStructureHint
}

@available(iOS 26.0, *)
@Generable(description: "The likely side of a scanned card-style document.")
private enum GeneratedStructureHint: String {
    case front
    case back
    case unclear
}
#endif
