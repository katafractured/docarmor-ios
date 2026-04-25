import Foundation
import SwiftData

/// ScreenshotMode provides seed data for fastlane snapshot captures.
/// Activated via launch argument: -ScreenshotMode seedData
public class ScreenshotMode {
    static let isEnabled = CommandLine.arguments.contains("-ScreenshotMode") &&
                          CommandLine.arguments.contains("seedData")

    static func seedDocuments() -> [Document] {
        [
            Document(
                id: UUID(),
                name: "Driver License - California",
                ownerName: nil,
                documentType: .driversLicense,
                category: .identity,
                notes: "Primary ID",
                issuerName: "California DMV",
                identifierSuffix: "4829",
                ocrSuggestedIssuerName: "California DMV",
                ocrSuggestedIdentifier: "D1234567",
                ocrSuggestedExpirationDate: Date(timeIntervalSinceNow: 365 * 86400),
                ocrConfidenceScore: 0.98,
                ocrExtractedAt: Date(timeIntervalSinceNow: -3600),
                ocrStructureHintsRaw: ["expiration", "number", "name"],
                lastVerifiedAt: Date(timeIntervalSinceNow: -86400),
                renewalNotes: "Renew in 2025",
                expirationDate: Date(timeIntervalSinceNow: 365 * 86400),
                expirationReminderDays: [90, 30],
                isFavorite: true
            ),
            Document(
                id: UUID(),
                name: "Passport - United States",
                ownerName: nil,
                documentType: .passport,
                category: .travel,
                notes: "Primary travel document",
                issuerName: "U.S. Department of State",
                identifierSuffix: "2849",
                ocrSuggestedIssuerName: "U.S. Department of State",
                ocrSuggestedIdentifier: "C02840293",
                ocrSuggestedExpirationDate: Date(timeIntervalSinceNow: 5 * 365 * 86400),
                ocrConfidenceScore: 0.95,
                ocrExtractedAt: Date(timeIntervalSinceNow: -7200),
                ocrStructureHintsRaw: ["passport_number", "expiration", "nationality"],
                lastVerifiedAt: Date(timeIntervalSinceNow: -172800),
                renewalNotes: "Valid until 2029",
                expirationDate: Date(timeIntervalSinceNow: 5 * 365 * 86400),
                expirationReminderDays: [180],
                isFavorite: false
            ),
            Document(
                id: UUID(),
                name: "Tax Return 2024",
                ownerName: nil,
                documentType: .custom,
                category: .financial,
                notes: "Filed with IRS",
                issuerName: "Internal Revenue Service",
                identifierSuffix: "2024",
                ocrSuggestedIssuerName: "Internal Revenue Service",
                ocrSuggestedIdentifier: "1040",
                ocrSuggestedExpirationDate: Date(timeIntervalSinceNow: 7 * 365 * 86400),
                ocrConfidenceScore: 0.92,
                ocrExtractedAt: Date(timeIntervalSinceNow: -10800),
                ocrStructureHintsRaw: ["filing_date", "tax_year"],
                lastVerifiedAt: Date(timeIntervalSinceNow: -259200),
                renewalNotes: "Keep 7 years",
                expirationDate: nil,
                expirationReminderDays: nil,
                isFavorite: false
            ),
            Document(
                id: UUID(),
                name: "Mortgage Statement - Primary Residence",
                ownerName: nil,
                documentType: .custom,
                category: .financial,
                notes: "Current loan balance",
                issuerName: "Chase Bank",
                identifierSuffix: "5829",
                ocrSuggestedIssuerName: "Chase Bank",
                ocrSuggestedIdentifier: "Loan #3728",
                ocrSuggestedExpirationDate: Date(timeIntervalSinceNow: 30 * 365 * 86400),
                ocrConfidenceScore: 0.89,
                ocrExtractedAt: Date(timeIntervalSinceNow: -14400),
                ocrStructureHintsRaw: ["balance", "payment_amount", "rate"],
                lastVerifiedAt: Date(timeIntervalSinceNow: -345600),
                renewalNotes: "30-year fixed at 3.875%",
                expirationDate: Date(timeIntervalSinceNow: 30 * 365 * 86400),
                expirationReminderDays: nil,
                isFavorite: false
            ),
            Document(
                id: UUID(),
                name: "Vehicle Title - 2021 Tesla Model 3",
                ownerName: nil,
                documentType: .custom,
                category: .custom,
                notes: "Clear title on file",
                issuerName: "California DMV",
                identifierSuffix: "7392",
                ocrSuggestedIssuerName: "California DMV",
                ocrSuggestedIdentifier: "VIN last 8: 4KL9Z3TQ",
                ocrSuggestedExpirationDate: nil,
                ocrConfidenceScore: 0.91,
                ocrExtractedAt: Date(timeIntervalSinceNow: -18000),
                ocrStructureHintsRaw: ["vin", "odometer", "owner_name"],
                lastVerifiedAt: Date(timeIntervalSinceNow: -432000),
                renewalNotes: "Owned free and clear",
                expirationDate: nil,
                expirationReminderDays: nil,
                isFavorite: false
            )
        ]
    }

    static func makeSovereignEntitlementOverride() -> Bool {
        true
    }
}
