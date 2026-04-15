import Foundation
import NaturalLanguage
import Vision
import UIKit

enum OCRService {
    enum SuggestionSource: String, Sendable {
        case deterministic
        case foundationModel

        nonisolated var displayLabel: String {
            switch self {
            case .deterministic:
                return "On-device OCR heuristics"
            case .foundationModel:
                return "Apple Intelligence refinement"
            }
        }
    }

    enum StructureHint: String, Sendable {
        case likelyFront
        case likelyBack
        case unclear

        nonisolated var warningText: String? {
            switch self {
            case .likelyFront:
                return "This scan looks like the front of a card-style document."
            case .likelyBack:
                return "This scan looks like the back of a card-style document."
            case .unclear:
                return nil
            }
        }
    }

    struct Suggestions: Sendable {
        var name: String?
        var issuerName: String?
        var documentNumber: String?
        var expirationDate: Date?
        var textCorpus: String
        var structureHint: StructureHint
        var confidenceScore: Double
        var qualityWarnings: [String]
        var source: SuggestionSource

        nonisolated init(
            name: String? = nil,
            issuerName: String? = nil,
            documentNumber: String? = nil,
            expirationDate: Date? = nil,
            textCorpus: String = "",
            structureHint: StructureHint = .unclear,
            confidenceScore: Double = 0,
            qualityWarnings: [String] = [],
            source: SuggestionSource = .deterministic
        ) {
            self.name = name
            self.issuerName = issuerName
            self.documentNumber = documentNumber
            self.expirationDate = expirationDate
            self.textCorpus = textCorpus
            self.structureHint = structureHint
            self.confidenceScore = confidenceScore
            self.qualityWarnings = qualityWarnings
            self.source = source
        }
    }

    /// Runs on-device text recognition plus barcode scanning on `image`.
    ///
    /// Vision's `VNImageRequestHandler.perform` is a synchronous blocking call
    /// that takes multiple seconds on detailed documents (passports, IDs).
    /// It MUST run off the main thread — callers are typically in SwiftUI
    /// `.task {}` blocks which inherit MainActor, and a scene-update watchdog
    /// will kill the app after 10 seconds. We use `Task.detached` to guarantee
    /// the Vision work runs on a background executor.
    nonisolated static func extractSuggestions(from image: UIImage) async -> Suggestions {
        guard let cgImage = image.cgImage else { return Suggestions() }
        let imageSize = image.size

        let (lines, barcodePayloads) = await Task.detached(priority: .userInitiated) {
            () -> ([String], [String]) in
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.customWords = [
                "Passport",
                "License",
                "Department",
                "Insurance",
                "Medicare",
                "Medicaid"
            ]

            let barcodeRequest = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([textRequest, barcodeRequest])

            let lines = (textRequest.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            let barcodePayloads = (barcodeRequest.results ?? [])
                .compactMap(\.payloadStringValue)
            return (lines, barcodePayloads)
        }.value

        let baseSuggestions = parse(
            lines,
            barcodePayloads: barcodePayloads,
            imageSize: imageSize
        )

        // Refine via FoundationModels if available. On iOS 26 the first access
        // to SystemLanguageModel.default is a synchronous blocking init — run
        // it off the main thread. On iOS 17/18 this short-circuits to the
        // deterministic fallback so the detached hop is cheap.
        return await Task.detached(priority: .userInitiated) {
            await FoundationModelExtractionService.refine(
                lines: lines,
                barcodePayloads: barcodePayloads,
                fallback: baseSuggestions
            )
        }.value
    }

    // MARK: - Parsing

    private nonisolated static func parse(
        _ lines: [String],
        barcodePayloads: [String],
        imageSize: CGSize
    ) -> Suggestions {
        var suggestions = parseEncodedMetadata(lines: lines, barcodePayloads: barcodePayloads)
        let entities = extractNamedEntities(from: lines)
        let letterSpaceSet = CharacterSet.letters.union(.whitespaces)
        let textCorpus = (lines + barcodePayloads).joined(separator: "\n")

        if suggestions.name == nil {
            suggestions.name = entities.personalNames.first
        }
        if suggestions.issuerName == nil {
            suggestions.issuerName = entities.organizations.first
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if suggestions.name == nil,
               (4...50).contains(trimmed.count),
               trimmed.unicodeScalars.allSatisfy({ letterSpaceSet.contains($0) }) {
                suggestions.name = trimmed.capitalized
            }

            if suggestions.documentNumber == nil,
               let range = trimmed.range(of: #"[A-Z0-9]{6,20}"#, options: .regularExpression) {
                suggestions.documentNumber = normalizedDocumentNumber(from: String(trimmed[range]))
            }

            if suggestions.issuerName == nil {
                let nextLine = lines.indices.contains(index + 1) ? lines[index + 1] : nil
                suggestions.issuerName = extractIssuer(from: trimmed, nextLine: nextLine)
            }

            if suggestions.expirationDate == nil {
                suggestions.expirationDate = extractDate(from: trimmed)
            }
        }

        if suggestions.documentNumber == nil {
            suggestions.documentNumber = barcodePayloads.lazy.compactMap(normalizedDocumentNumber(from:)).first
        }

        suggestions.structureHint = inferStructureHint(lines: lines, barcodePayloads: barcodePayloads)

        let extractedFieldCount = [
            suggestions.name,
            suggestions.issuerName,
            suggestions.documentNumber
        ].compactMap { $0 }.count + (suggestions.expirationDate == nil ? 0 : 1)
        let minDimension = min(imageSize.width, imageSize.height)
        let lineCount = lines.count
        var confidence = 0.15
        confidence += min(Double(lineCount) / 8.0, 0.25)
        confidence += min(Double(extractedFieldCount) * 0.15, 0.45)
        if barcodePayloads.contains(where: isLikelyStructuredBarcodePayload) {
            confidence += 0.12
        }
        if containsMachineReadableZone(lines) {
            confidence += 0.08
        }
        if minDimension >= 1400 { confidence += 0.15 }
        else if minDimension >= 1000 { confidence += 0.08 }
        confidence = min(confidence, 0.95)

        var warnings: [String] = []
        if minDimension < 900 {
            warnings.append("Scan resolution looks low. Retake if text is hard to read.")
        }
        if lineCount < 3 {
            warnings.append("Very little readable text was detected in this scan.")
        }
        if extractedFieldCount == 0 {
            warnings.append("DocArmor could not confidently extract fields from this scan yet.")
        } else if extractedFieldCount < 2 {
            warnings.append("Only a small amount of structured data was detected. Review suggestions carefully.")
        }

        suggestions.confidenceScore = confidence
        suggestions.qualityWarnings = warnings
        suggestions.textCorpus = textCorpus
        return suggestions
    }

    private nonisolated static func extractNamedEntities(from lines: [String]) -> NamedEntities {
        let text = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else { return NamedEntities() }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var personalNames: [String] = []
        var organizations: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag else { return true }
            let entity = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard entity.isEmpty == false else { return true }

            switch tag {
            case .personalName:
                if isLikelyHumanName(entity) {
                    personalNames.append(entity.capitalized)
                }
            case .organizationName:
                if isLikelyIssuerEntity(entity) {
                    organizations.append(entity)
                }
            default:
                break
            }
            return true
        }

        return NamedEntities(
            personalNames: uniqueEntities(personalNames),
            organizations: uniqueEntities(organizations)
        )
    }

    private nonisolated static func parseEncodedMetadata(
        lines: [String],
        barcodePayloads: [String]
    ) -> Suggestions {
        var suggestions = Suggestions()

        if let barcodeSuggestions = barcodePayloads.lazy.compactMap(parseAAMVAPayload).first {
            suggestions = merge(primary: barcodeSuggestions, fallback: suggestions)
        }

        if let mrzSuggestions = parseMRZ(lines: lines) {
            suggestions = merge(primary: suggestions, fallback: mrzSuggestions)
        }

        return suggestions
    }

    private nonisolated static func merge(primary: Suggestions, fallback: Suggestions) -> Suggestions {
        Suggestions(
            name: primary.name ?? fallback.name,
            issuerName: primary.issuerName ?? fallback.issuerName,
            documentNumber: primary.documentNumber ?? fallback.documentNumber,
            expirationDate: primary.expirationDate ?? fallback.expirationDate,
            textCorpus: primary.textCorpus.isEmpty ? fallback.textCorpus : primary.textCorpus,
            structureHint: primary.structureHint == .unclear ? fallback.structureHint : primary.structureHint,
            confidenceScore: max(primary.confidenceScore, fallback.confidenceScore),
            qualityWarnings: primary.qualityWarnings.isEmpty ? fallback.qualityWarnings : primary.qualityWarnings
        )
    }

    private struct NamedEntities {
        var personalNames: [String]
        var organizations: [String]

        nonisolated init(
            personalNames: [String] = [],
            organizations: [String] = []
        ) {
            self.personalNames = personalNames
            self.organizations = organizations
        }
    }

    private nonisolated static func inferStructureHint(
        lines: [String],
        barcodePayloads: [String]
    ) -> StructureHint {
        let upperLines = lines.map { $0.uppercased() }
        let frontKeywords = [
            "DOB", "EXP", "ISS", "SEX", "HEIGHT", "WEIGHT", "ADDRESS",
            "LICENSE", "PASSPORT", "NATIONALITY", "SURNAME", "GIVEN", "NAME"
        ]
        let backKeywords = [
            "RESTRICTIONS", "ENDORSEMENTS", "CLASS", "DONOR", "ORGAN",
            "SIGNATURE", "NOT VALID", "NOTICE", "REV", "DUPLICATE"
        ]

        var frontScore = 0
        var backScore = barcodePayloads.isEmpty ? 0 : 2

        for line in upperLines {
            if frontKeywords.contains(where: { line.contains($0) }) {
                frontScore += 1
            }
            if backKeywords.contains(where: { line.contains($0) }) {
                backScore += 1
            }
        }

        if barcodePayloads.isEmpty == false && upperLines.count <= 4 {
            backScore += 1
        }

        if frontScore >= backScore + 1 {
            return .likelyFront
        }
        if backScore >= frontScore + 1 {
            return .likelyBack
        }
        return .unclear
    }

    private nonisolated static func parseAAMVAPayload(_ payload: String) -> Suggestions? {
        let normalized = payload
            .replacingOccurrences(of: "\u{1E}", with: "\n")
            .replacingOccurrences(of: "\u{1D}", with: "\n")
            .replacingOccurrences(of: "\u{1C}", with: "\n")
        guard normalized.uppercased().contains("ANSI ") || normalized.contains("DAQ") else { return nil }

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var fields: [String: String] = [:]
        for line in lines {
            guard line.count >= 3 else { continue }
            let key = String(line.prefix(3)).uppercased()
            guard key.allSatisfy({ $0.isLetter }) else { continue }
            let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            fields[key] = value
        }

        guard fields.isEmpty == false else { return nil }

        let fullName = normalizedOCRName(fields["DAA"]) ??
            buildName(given: fields["DAC"], middle: fields["DAD"], family: fields["DCS"])
        let issuer = normalizedOCRSuggestionText(fields["DAJ"]) ?? normalizedOCRSuggestionText(fields["DAI"])
        let documentNumber = normalizedDocumentNumber(from: fields["DAQ"] ?? "")
        let expirationDate = parseAAMVADate(fields["DBA"])

        return Suggestions(
            name: fullName,
            issuerName: issuer,
            documentNumber: documentNumber,
            expirationDate: expirationDate,
            structureHint: .likelyBack,
            confidenceScore: 0.82
        )
    }

    private nonisolated static func parseMRZ(lines: [String]) -> Suggestions? {
        let candidates = lines
            .map { $0.uppercased().replacingOccurrences(of: " ", with: "") }
            .filter { $0.contains("<<") && $0.count >= 24 }

        guard candidates.count >= 2 else { return nil }
        let first = candidates[0]
        let second = candidates[1]
        guard first.first == "P" || first.first == "I" else { return nil }

        let nameChunk = first.dropFirst(5)
        let nameParts = nameChunk
            .components(separatedBy: "<<")
            .flatMap { $0.components(separatedBy: "<") }
            .filter { !$0.isEmpty }
            .map(\.capitalized)
        let name = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")

        let documentNumberSlice = safeSubstring(second, from: 0, length: 9)
        let expirySlice = safeSubstring(second, from: 13, length: 6)

        return Suggestions(
            name: name,
            issuerName: nil,
            documentNumber: normalizedDocumentNumber(from: documentNumberSlice),
            expirationDate: parseMRZDate(expirySlice),
            structureHint: .likelyFront,
            confidenceScore: 0.76
        )
    }

    private nonisolated static func buildName(
        given: String?,
        middle: String?,
        family: String?
    ) -> String? {
        let parts = [given, middle, family]
            .compactMap(normalizedOCRName)
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private nonisolated static func normalizedOCRName(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "<<", with: " ")
            .replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return nil }
        return cleaned.capitalized
    }

    private nonisolated static func normalizedOCRSuggestionText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func uniqueEntities(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let key = value.lowercased()
            return seen.insert(key).inserted
        }
    }

    private nonisolated static func isLikelyHumanName(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: " ")
        guard (1...4).contains(parts.count), cleaned.count >= 4 else { return false }
        return parts.allSatisfy { part in
            part.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
        }
    }

    private nonisolated static func isLikelyIssuerEntity(_ text: String) -> Bool {
        let upper = text.uppercased()
        let issuerKeywords = [
            "DEPARTMENT",
            "DMV",
            "BUREAU",
            "MINISTRY",
            "INSURANCE",
            "MEDICARE",
            "MEDICAID",
            "PASSPORT",
            "STATE",
            "COUNTY",
            "UNIVERSITY",
            "HOSPITAL"
        ]
        return issuerKeywords.contains(where: { upper.contains($0) })
    }

    private nonisolated static func parseAAMVADate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let digits = text.filter(\.isNumber)
        guard digits.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMddyyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: digits), date > Date.now else { return nil }
        return date
    }

    private nonisolated static func parseMRZDate(_ text: String) -> Date? {
        guard text.count == 6 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: text), date > Date.now else { return nil }
        return date
    }

    private nonisolated static func safeSubstring(_ text: String, from start: Int, length: Int) -> String {
        guard start >= 0, length > 0, text.count >= start + length else { return "" }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(startIndex, offsetBy: length)
        return String(text[startIndex..<endIndex]).replacingOccurrences(of: "<", with: "")
    }

    private nonisolated static func isLikelyStructuredBarcodePayload(_ payload: String) -> Bool {
        let upper = payload.uppercased()
        return upper.contains("ANSI ") || upper.contains("DAQ") || upper.contains("DBA")
    }

    private nonisolated static func containsMachineReadableZone(_ lines: [String]) -> Bool {
        lines.contains { line in
            let normalized = line.uppercased().replacingOccurrences(of: " ", with: "")
            return normalized.contains("<<") && normalized.count >= 24
        }
    }

    private nonisolated static func extractIssuer(from text: String, nextLine: String?) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = normalized.uppercased()
        let issuerHints = [
            "DEPARTMENT",
            "DMV",
            "BUREAU",
            "MINISTRY",
            "INSURANCE",
            "MEDICARE",
            "MEDICAID",
            "PASSPORT",
            "STATE OF",
            "REPUBLIC",
            "COUNTY"
        ]

        guard issuerHints.contains(where: { upper.contains($0) }) else { return nil }

        let candidate = [normalized, nextLine?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return candidate.isEmpty ? nil : candidate
    }

    private nonisolated static func normalizedDocumentNumber(from text: String) -> String? {
        let stripped = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (6...20).contains(stripped.count) else { return nil }
        return stripped
    }

    private nonisolated static func extractDate(from text: String) -> Date? {
        let candidates: [(pattern: String, formats: [String])] = [
            (#"\d{1,2}/\d{1,2}/\d{2,4}"#, ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy"]),
            (#"\d{4}-\d{2}-\d{2}"#, ["yyyy-MM-dd"]),
            (#"\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4}"#, ["dd MMM yyyy", "d MMM yyyy"]),
            (#"[A-Za-z]{3}\s+\d{1,2},\s+\d{4}"#, ["MMM d, yyyy"])
        ]

        for (pattern, formats) in candidates {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(text[range])
            for format in formats {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                if let date = formatter.date(from: match), date > Date.now {
                    return date
                }
            }
        }
        return nil
    }
}
