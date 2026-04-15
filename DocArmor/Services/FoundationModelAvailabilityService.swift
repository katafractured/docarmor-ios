import Foundation

#if canImport(FoundationModels)
@_weakLinked import FoundationModels
#endif

enum FoundationModelAvailabilityService {

    enum Status: Equatable, Sendable {
        case unavailable(FallbackReason)
        case available
    }

    enum FallbackReason: String, Equatable, Sendable {
        case frameworkUnavailable
        case osVersionUnsupported
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unsupportedLanguage
        case unknown

        var userFacingDescription: String {
            switch self {
            case .frameworkUnavailable:
                return "Foundation Models is unavailable in this build environment."
            case .osVersionUnsupported:
                return "This OS version does not support Apple Intelligence."
            case .deviceNotEligible:
                return "This device does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off on this device."
            case .modelNotReady:
                return "The on-device model is still preparing."
            case .unsupportedLanguage:
                return "The current app language is not supported by the on-device model."
            case .unknown:
                return "DocArmor is using its deterministic local fallback path."
            }
        }
    }

    nonisolated static var currentStatus: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.supportsLocale() else {
                return .unavailable(.unsupportedLanguage)
            }

            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(.deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(.appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady):
                return .unavailable(.modelNotReady)
            case .unavailable:
                return .unavailable(.unknown)
            @unknown default:
                return .unavailable(.unknown)
            }
        } else {
            return .unavailable(.osVersionUnsupported)
        }
        #else
        return .unavailable(.frameworkUnavailable)
        #endif
    }

    nonisolated static var isAvailable: Bool {
        if case .available = currentStatus {
            return true
        }
        return false
    }

    nonisolated static var fallbackReason: FallbackReason? {
        guard case let .unavailable(reason) = currentStatus else { return nil }
        return reason
    }
}
