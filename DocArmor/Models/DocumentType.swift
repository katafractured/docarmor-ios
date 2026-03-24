import Foundation

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
        case .employeeID:            return "person.badge.fill"
        case .professionalLicense:   return "rosette"
        case .custom:                return "doc.fill"
        }
    }
}
