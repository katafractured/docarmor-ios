import SwiftUI
import KatafractStyle

enum DocumentCategory: String, CaseIterable, Codable, Hashable {
    case identity  = "Identity"
    case medical   = "Medical"
    case financial = "Financial"
    case travel    = "Travel"
    case work      = "Work"
    case custom    = "Custom"

    var systemImage: String {
        switch self {
        case .identity:  return "person.text.rectangle.fill"
        case .medical:   return "cross.case.fill"
        case .financial: return "creditcard.fill"
        case .travel:    return "airplane"
        case .work:      return "briefcase.fill"
        case .custom:    return "folder.fill"
        }
    }

    /// All categories use kataGold-family tones — no rainbow.
    var color: Color {
        switch self {
        case .identity:  return Color.kataGold
        case .medical:   return Color.kataGold.opacity(0.75)
        case .financial: return Color.kataGold.opacity(0.85)
        case .travel:    return Color.kataChampagne
        case .work:      return Color.kataGold.opacity(0.65)
        case .custom:    return Color.kataGold.opacity(0.55)
        }
    }
}
