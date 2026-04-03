import CryptoKit
import CommonCrypto
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let docarmorBackup = UTType(exportedAs: "com.katafract.docarmor.backup")
}

struct EncryptedBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.docarmorBackup, .data] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupService.BackupError.invalidBackup
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    struct BackupArchive: Codable {
        let version: Int
        let exportedAt: Date
        let salt: Data
        let nonce: Data
        let ciphertext: Data
    }

    struct BackupPayload: Codable {
        let exportedAt: Date
        let householdMembers: [String]
        let vaultKeyData: Data
        let documents: [BackupDocument]
    }

    struct BackupDocument: Codable {
        let id: UUID
        let name: String
        let ownerName: String?
        let documentTypeRaw: String
        let categoryRaw: String
        let notes: String
        let issuerName: String
        let identifierSuffix: String
        let lastVerifiedAt: Date?
        let renewalNotes: String
        let expirationDate: Date?
        let expirationReminderDays: [Int]?
        let createdAt: Date
        let updatedAt: Date
        let isFavorite: Bool
        let pages: [BackupPage]
    }

    struct BackupPage: Codable {
        let id: UUID
        let pageIndex: Int
        let encryptedImageData: Data
        let nonce: Data
        let label: String?
    }

    enum BackupError: LocalizedError {
        case invalidPassphrase
        case invalidBackup
        case unsupportedVersion
        case missingVaultKey

        var errorDescription: String? {
            switch self {
            case .invalidPassphrase:
                return "Enter a passphrase with at least 8 characters."
            case .invalidBackup:
                return "The selected backup file is invalid or corrupted."
            case .unsupportedVersion:
                return "This backup was created by a newer version of DocArmor."
            case .missingVaultKey:
                return "The vault key could not be loaded for backup."
            }
        }
    }

    private static let version = 2

    static func exportBackup(
        documents: [Document],
        householdMembers: [String],
        passphrase: String
    ) throws -> EncryptedBackupDocument {
        let payload = try BackupPayload(
            exportedAt: .now,
            householdMembers: householdMembers,
            vaultKeyData: VaultKey.exportKeyData(),
            documents: documents.map(makeBackupDocument(document:))
        )

        return EncryptedBackupDocument(data: try encryptPayload(payload, passphrase: passphrase))
    }

    @MainActor
    static func restoreBackup(
        from data: Data,
        passphrase: String,
        into modelContext: ModelContext
    ) throws {
        let payload = try decryptPayload(from: data, passphrase: passphrase)

        ExpirationService.cancelAllReminders()

        let existingDocuments = try modelContext.fetch(FetchDescriptor<Document>())
        for document in existingDocuments {
            modelContext.delete(document)
        }
        try modelContext.save()

        try VaultKey.replace(with: payload.vaultKeyData)
        HouseholdStore.saveMembers(payload.householdMembers)

        for backupDocument in payload.documents {
            let document = Document(
                id: backupDocument.id,
                name: backupDocument.name,
                ownerName: backupDocument.ownerName,
                documentType: DocumentType(rawValue: backupDocument.documentTypeRaw) ?? .custom,
                category: DocumentCategory(rawValue: backupDocument.categoryRaw) ?? .identity,
                notes: backupDocument.notes,
                issuerName: backupDocument.issuerName,
                identifierSuffix: backupDocument.identifierSuffix,
                lastVerifiedAt: backupDocument.lastVerifiedAt,
                renewalNotes: backupDocument.renewalNotes,
                expirationDate: backupDocument.expirationDate,
                expirationReminderDays: backupDocument.expirationReminderDays,
                isFavorite: backupDocument.isFavorite
            )
            document.createdAt = backupDocument.createdAt
            document.updatedAt = backupDocument.updatedAt
            modelContext.insert(document)

            for backupPage in backupDocument.pages {
                let page = DocumentPage(
                    id: backupPage.id,
                    pageIndex: backupPage.pageIndex,
                    encryptedImageData: backupPage.encryptedImageData,
                    nonce: backupPage.nonce,
                    label: backupPage.label
                )
                page.document = document
                modelContext.insert(page)
            }

            ExpirationService.scheduleReminder(for: document)
        }

        try modelContext.save()
    }

    nonisolated static func defaultFilename() -> String {
        let timestamp = Date.now.formatted(.iso8601.year().month().day())
        return "DocArmor-Backup-\(timestamp).docarmorbackup"
    }

    nonisolated private static func makeBackupDocument(document: Document) -> BackupDocument {
        BackupDocument(
            id: document.id,
            name: document.name,
            ownerName: document.ownerName,
            documentTypeRaw: document.documentTypeRaw,
            categoryRaw: document.categoryRaw,
            notes: document.notes,
            issuerName: document.issuerName,
            identifierSuffix: document.identifierSuffix,
            lastVerifiedAt: document.lastVerifiedAt,
            renewalNotes: document.renewalNotes,
            expirationDate: document.expirationDate,
            expirationReminderDays: document.expirationReminderDays,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            isFavorite: document.isFavorite,
            pages: document.sortedPages.map {
                BackupPage(
                    id: $0.id,
                    pageIndex: $0.pageIndex,
                    encryptedImageData: $0.encryptedImageData,
                    nonce: $0.nonce,
                    label: $0.label
                )
            }
        )
    }

    private static func encryptPayload(_ payload: BackupPayload, passphrase: String) throws -> Data {
        guard passphrase.count >= 8 else {
            throw BackupError.invalidPassphrase
        }

        let payloadData = try JSONEncoder().encode(payload)
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = try derivedKey(from: passphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(payloadData, using: key)

        let archive = BackupArchive(
            version: version,
            exportedAt: payload.exportedAt,
            salt: salt,
            nonce: Data(sealedBox.nonce),
            ciphertext: sealedBox.ciphertext + sealedBox.tag
        )

        return try JSONEncoder().encode(archive)
    }

    private static func decryptPayload(from data: Data, passphrase: String) throws -> BackupPayload {
        guard passphrase.count >= 8 else {
            throw BackupError.invalidPassphrase
        }

        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        guard archive.version <= version else {
            throw BackupError.unsupportedVersion
        }

        guard archive.ciphertext.count > 16 else {
            throw BackupError.invalidBackup
        }

        let key: SymmetricKey
        if archive.version == 1 {
            key = try legacyDerivedKey(from: passphrase, salt: archive.salt)
        } else {
            key = try derivedKey(from: passphrase, salt: archive.salt)
        }
        let nonce = try AES.GCM.Nonce(data: archive.nonce)
        let ciphertext = archive.ciphertext.dropLast(16)
        let tag = archive.ciphertext.suffix(16)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let payloadData = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(BackupPayload.self, from: payloadData)
    }

    private static func derivedKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        guard let passphraseData = passphrase.data(using: .utf8), !passphraseData.isEmpty else {
            throw BackupError.invalidPassphrase
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let result = passphraseData.withUnsafeBytes { passphrasePointer in
            salt.withUnsafeBytes { saltPointer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrasePointer.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passphraseData.count,
                    saltPointer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    310_000,
                    &keyBytes,
                    32
                )
            }
        }

        guard result == kCCSuccess else {
            throw BackupError.invalidPassphrase
        }
        return SymmetricKey(data: Data(keyBytes))
    }

    // Legacy v1 KDF — only used when restoring old backups.
    private static func legacyDerivedKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        guard let passphraseData = passphrase.data(using: .utf8), !passphraseData.isEmpty else {
            throw BackupError.invalidPassphrase
        }

        var material = Data(SHA256.hash(data: passphraseData + salt))
        for _ in 0..<100_000 {
            material = Data(SHA256.hash(data: material + passphraseData + salt))
        }
        return SymmetricKey(data: material)
    }
}
