import Foundation

struct SavedCustomPack: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var isEnabled: Bool
    var encodedTypes: String

    init(
        id: UUID = UUID(),
        title: String,
        isEnabled: Bool = true,
        documentTypes: [DocumentType]
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.encodedTypes = DocumentType.encodePackSelection(documentTypes)
    }

    var documentTypes: [DocumentType] {
        DocumentType.decodePackSelection(from: encodedTypes)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Custom Pack" : trimmed
    }

    static func decodeList(from rawValue: String) -> [SavedCustomPack] {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedCustomPack].self, from: data) else {
            return []
        }
        return decoded
    }

    static func encodeList(_ packs: [SavedCustomPack]) -> String {
        guard let data = try? JSONEncoder().encode(packs),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

enum DocumentType: String, CaseIterable, Codable, Hashable {
    // Identity
    case driversLicense  = "Driver's License"
    case passport        = "Passport"
    case stateID         = "State ID"
    case socialSecurity  = "Social Security Card"
    case birthCertificate = "Birth Certificate"
    case militaryID      = "Military ID"
    case globalEntry     = "Global Entry / TSA PreCheck"
    case greenCard       = "Green Card"
    case workPermit      = "Work Permit / Visa"

    // Medical
    case insuranceHealth = "Health Insurance"
    case medicareCard    = "Medicare / Medicaid Card"
    case vaccineRecord   = "Vaccine Record"
    case prescriptionInfo = "Prescription Card"
    case bloodTypeCard   = "Blood Type / Donor Card"
    case emergencyContacts = "Emergency Contacts"

    // Financial
    case insuranceAuto   = "Auto Insurance"
    case insuranceHome   = "Home / Renters Insurance"
    case insuranceLife   = "Life Insurance"

    // Travel
    case hotelLoyalty    = "Hotel Loyalty Card"
    case airlineMembership = "Airline Membership"
    case rentalCarMembership = "Rental Car Membership"

    // Work
    case employeeID      = "Employee ID"
    case professionalLicense = "Professional License"

    // Other
    case custom          = "Custom"

    var defaultCategory: DocumentCategory {
        switch self {
        case .driversLicense, .passport, .stateID, .socialSecurity,
             .birthCertificate, .militaryID, .greenCard, .workPermit:
            return .identity
        case .globalEntry:
            return .travel
        case .insuranceHealth, .medicareCard, .vaccineRecord,
             .prescriptionInfo, .bloodTypeCard, .emergencyContacts:
            return .medical
        case .insuranceAuto, .insuranceHome, .insuranceLife:
            return .financial
        case .hotelLoyalty, .airlineMembership, .rentalCarMembership:
            return .travel
        case .employeeID, .professionalLicense:
            return .work
        case .custom:
            return .custom
        }
    }

    var requiresFrontBack: Bool {
        switch self {
        case .driversLicense, .stateID, .militaryID, .insuranceHealth,
             .medicareCard, .greenCard, .employeeID, .professionalLicense:
            return true
        default:
            return false
        }
    }

    var systemImage: String {
        switch self {
        case .driversLicense:        return "car.fill"
        case .passport:              return "globe"
        case .stateID:               return "person.crop.rectangle.fill"
        case .socialSecurity:        return "number.square.fill"
        case .birthCertificate:      return "doc.text.fill"
        case .militaryID:            return "shield.lefthalf.filled"
        case .globalEntry:           return "airplane.departure"
        case .greenCard:             return "creditcard.fill"
        case .workPermit:            return "briefcase.fill"
        case .insuranceHealth:       return "cross.fill"
        case .medicareCard:          return "staroflife.fill"
        case .vaccineRecord:         return "syringe.fill"
        case .prescriptionInfo:      return "pills.fill"
        case .bloodTypeCard:         return "drop.fill"
        case .emergencyContacts:     return "person.crop.circle.badge.exclamationmark.fill"
        case .insuranceAuto:         return "car.2.fill"
        case .insuranceHome:         return "house.fill"
        case .insuranceLife:         return "heart.text.square.fill"
        case .hotelLoyalty:          return "bed.double.fill"
        case .airlineMembership:     return "airplane"
        case .rentalCarMembership:   return "key.fill"
        case .employeeID:            return "person.badge.key.fill"
        case .professionalLicense:   return "rosette"
        case .custom:                return "doc.fill"
        }
    }

    static func decodePackSelection(from rawValueList: String) -> [DocumentType] {
        rawValueList
            .split(separator: "|")
            .compactMap { DocumentType(rawValue: String($0)) }
    }

    static func encodePackSelection(_ types: [DocumentType]) -> String {
        types
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
            .map(\.rawValue)
            .joined(separator: "|")
    }
}
