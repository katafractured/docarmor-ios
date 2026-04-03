import Foundation

enum HouseholdRole: String, CaseIterable, Codable, Identifiable {
    case adult
    case child
    case senior
    case pet

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .adult: return "Adult"
        case .child: return "Child"
        case .senior: return "Senior"
        case .pet: return "Pet"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .adult: return "person.fill"
        case .child: return "figure.and.child.holdinghands"
        case .senior: return "figure.seated.side"
        case .pet: return "pawprint.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "adult":
            self = .adult
        case "child", "dependent":
            self = .child
        case "senior":
            self = .senior
        case "pet":
            self = .pet
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown household role: \(rawValue)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct HouseholdMemberProfile: Codable, Equatable, Identifiable {
    var name: String
    var role: HouseholdRole

    nonisolated var id: String { name }
}

enum HouseholdStore {
    nonisolated private static let membersKey = "householdMembers"
    nonisolated private static let profilesKey = "householdMemberProfiles"

    nonisolated static func loadProfiles() -> [HouseholdMemberProfile] {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([HouseholdMemberProfile].self, from: data) {
            let sanitized = sanitizeProfiles(decoded)
            saveProfiles(sanitized)
            return sanitized
        }

        let migrated = sanitizeProfiles(
            loadLegacyMembers().map { HouseholdMemberProfile(name: $0, role: defaultRole(for: $0)) }
        )
        saveProfiles(migrated)
        return migrated
    }

    nonisolated static func loadMembers() -> [String] {
        loadProfiles().map(\.name)
    }

    nonisolated static func primaryMemberName(from profiles: [HouseholdMemberProfile]? = nil) -> String? {
        let profiles = profiles ?? loadProfiles()

        if let me = profiles.first(where: { $0.name.localizedCaseInsensitiveCompare("Me") == .orderedSame }) {
            return me.name
        }

        if let adult = profiles.first(where: { $0.role == .adult }) {
            return adult.name
        }

        return profiles.first?.name
    }

    nonisolated static func saveMembers(_ members: [String]) {
        saveProfiles(sanitize(members).map { HouseholdMemberProfile(name: $0, role: defaultRole(for: $0)) })
    }

    nonisolated static func saveProfiles(_ profiles: [HouseholdMemberProfile]) {
        let sanitized = sanitizeProfiles(profiles)
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        UserDefaults.standard.set(sanitized.map(\.name), forKey: membersKey)
    }

    @discardableResult
    nonisolated static func addMember(named name: String) -> [String] {
        addMember(named: name, role: defaultRole(for: name)).map(\.name)
    }

    @discardableResult
    nonisolated static func addMember(named name: String, role: HouseholdRole) -> [HouseholdMemberProfile] {
        var profiles = loadProfiles()
        guard let normalized = normalize(name), !profiles.contains(where: { $0.name == normalized }) else {
            return profiles
        }
        profiles.append(HouseholdMemberProfile(name: normalized, role: role))
        saveProfiles(profiles)
        return loadProfiles()
    }

    @discardableResult
    nonisolated static func updateRole(for memberName: String, role: HouseholdRole) -> [HouseholdMemberProfile] {
        let profiles = loadProfiles().map { profile in
            guard profile.name == memberName else { return profile }
            return HouseholdMemberProfile(name: profile.name, role: role)
        }
        saveProfiles(profiles)
        return loadProfiles()
    }

    nonisolated static func role(for memberName: String?) -> HouseholdRole? {
        guard let normalized = normalize(memberName) else { return nil }
        return loadProfiles().first { $0.name == normalized }?.role
    }

    nonisolated static func profile(for memberName: String?) -> HouseholdMemberProfile? {
        guard let normalized = normalize(memberName) else { return nil }
        return loadProfiles().first { $0.name == normalized }
    }

    nonisolated static func displayLabel(for memberName: String?) -> String {
        guard let profile = profile(for: memberName) else {
            return normalize(memberName) ?? "Shared"
        }
        return "\(profile.name) • \(profile.role.displayName)"
    }

    @discardableResult
    nonisolated static func removeMember(named name: String) -> [String] {
        removeProfile(named: name).map(\.name)
    }

    @discardableResult
    nonisolated static func removeProfile(named name: String) -> [HouseholdMemberProfile] {
        let profiles = loadProfiles().filter { $0.name != name }
        saveProfiles(profiles)
        return loadProfiles()
    }

    nonisolated static func normalize(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func defaultRole(for name: String?) -> HouseholdRole {
        normalize(name)?.localizedCaseInsensitiveCompare("Me") == .orderedSame ? .adult : .child
    }

    nonisolated private static func loadLegacyMembers() -> [String] {
        let members = UserDefaults.standard.stringArray(forKey: membersKey) ?? ["Me"]
        return sanitize(members)
    }

    nonisolated private static func sanitizeProfiles(_ profiles: [HouseholdMemberProfile]) -> [HouseholdMemberProfile] {
        let deduped = profiles.reduce(into: [String: HouseholdMemberProfile]()) { partialResult, profile in
            guard let normalized = normalize(profile.name) else { return }
            partialResult[normalized] = HouseholdMemberProfile(name: normalized, role: profile.role)
        }
        let fallback = deduped.isEmpty ? ["Me": HouseholdMemberProfile(name: "Me", role: .adult)] : deduped
        return fallback.values.sorted(by: profileSort)
    }

    nonisolated private static func sanitize(_ members: [String]) -> [String] {
        Array(Set(members.compactMap(normalize(_:))))
            .sorted(by: memberSort)
    }

    nonisolated private static func profileSort(_ lhs: HouseholdMemberProfile, _ rhs: HouseholdMemberProfile) -> Bool {
        memberSort(lhs.name, rhs.name)
    }

    nonisolated private static func memberSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsIsMe = lhs.localizedCaseInsensitiveCompare("Me") == .orderedSame
        let rhsIsMe = rhs.localizedCaseInsensitiveCompare("Me") == .orderedSame

        if lhsIsMe != rhsIsMe {
            return lhsIsMe
        }

        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
