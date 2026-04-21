import Foundation
import SwiftUI

/// A specific reason a document needs user attention. Each case carries the
/// data the UI needs to build a human-readable row: how many days ago, how
/// many pages missing, etc. One Document can produce multiple reasons.
enum AttentionReason: Hashable, Identifiable {
    case expired(daysAgo: Int)
    case expiringSoon(daysRemaining: Int)
    case missingBackPage
    case neverVerified
    case staleVerification(daysAgo: Int)

    var id: String {
        switch self {
        case .expired(let d):            return "expired-\(d)"
        case .expiringSoon(let d):       return "expiring-\(d)"
        case .missingBackPage:           return "missing-page"
        case .neverVerified:             return "never-verified"
        case .staleVerification(let d):  return "stale-verified-\(d)"
        }
    }

    var shortLabel: String {
        switch self {
        case .expired(let d):
            if d == 0 { return "Expired today" }
            if d == 1 { return "Expired yesterday" }
            return "Expired \(d) days ago"
        case .expiringSoon(let d):
            if d == 0 { return "Expires today" }
            if d == 1 { return "Expires tomorrow" }
            return "Expires in \(d) days"
        case .missingBackPage:
            return "Back side or supporting page is missing"
        case .neverVerified:
            return "Not yet verified — confirm the details are accurate"
        case .staleVerification(let d):
            return "Last checked \(d) days ago — re-confirm the details"
        }
    }

    var systemImage: String {
        switch self {
        case .expired:            return "calendar.badge.exclamationmark"
        case .expiringSoon:       return "calendar.badge.clock"
        case .missingBackPage:    return "doc.badge.plus"
        case .neverVerified:      return "checkmark.seal.trianglebadge.exclamationmark"
        case .staleVerification:  return "checkmark.seal.trianglebadge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .expired:                       return .red
        case .expiringSoon:                  return .orange
        case .missingBackPage:               return .orange
        case .neverVerified, .staleVerification: return Color(red: 0.26, green: 0.39, blue: 0.45)
        }
    }

    /// Groups reasons into ordered sections on the review sheet.
    var groupOrder: Int {
        switch self {
        case .expired:           return 0
        case .expiringSoon:      return 1
        case .missingBackPage:   return 2
        case .neverVerified:     return 3
        case .staleVerification: return 4
        }
    }

    var groupTitle: String {
        switch self {
        case .expired:           return "Expired"
        case .expiringSoon:      return "Expiring soon"
        case .missingBackPage:   return "Missing pages"
        case .neverVerified:     return "Never verified"
        case .staleVerification: return "Verification is stale"
        }
    }
}

extension Document {
    /// Every specific reason this document appears under "Needs Attention".
    /// Empty when `needsAttention` is false.
    var attentionReasons: [AttentionReason] {
        var out: [AttentionReason] = []

        if isExpired, let daysUntil = daysUntilExpiry {
            out.append(.expired(daysAgo: max(0, -daysUntil)))
        } else if expiresSoon, let daysUntil = daysUntilExpiry {
            out.append(.expiringSoon(daysRemaining: max(0, daysUntil)))
        }

        if isMissingRequiredPages {
            out.append(.missingBackPage)
        }

        if lastVerifiedAt == nil {
            out.append(.neverVerified)
        } else if needsVerificationReview, let last = lastVerifiedAt {
            let days = Int(Date.now.timeIntervalSince(last) / 86_400)
            out.append(.staleVerification(daysAgo: max(0, days)))
        }

        return out
    }
}
