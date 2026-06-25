import SwiftCAD

public enum BodySourceSectionReference: Codable, Hashable, Sendable {
    case profile(ProfileReference)
    case curve(FeatureID)

    public var featureID: FeatureID {
        switch self {
        case .profile(let profile):
            return profile.featureID
        case .curve(let featureID):
            return featureID
        }
    }

    public var profileReference: ProfileReference? {
        guard case .profile(let profile) = self else {
            return nil
        }
        return profile
    }

    public var requiredOutputRole: FeaturePort {
        switch self {
        case .profile:
            return .profile
        case .curve:
            return .curve
        }
    }

    public init(sweepSection: SweepSectionReference) {
        switch sweepSection {
        case .profile(let profile):
            self = .profile(profile)
        case .curve(let curve):
            self = .curve(curve.featureID)
        }
    }

    private enum Kind: String, Codable {
        case profile
        case curve
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case featureID
        case profileIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let featureID = try container.decode(FeatureID.self, forKey: .featureID)
        switch kind {
        case .profile:
            let profileIndex = try container.decodeIfPresent(Int.self, forKey: .profileIndex) ?? 0
            self = .profile(ProfileReference(featureID: featureID, profileIndex: profileIndex))
        case .curve:
            if container.contains(.profileIndex) {
                throw DecodingError.dataCorruptedError(
                    forKey: .profileIndex,
                    in: container,
                    debugDescription: "Body curve source sections must not contain a profile index."
                )
            }
            self = .curve(featureID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profile(let profile):
            try container.encode(Kind.profile, forKey: .kind)
            try container.encode(profile.featureID, forKey: .featureID)
            try container.encode(profile.profileIndex, forKey: .profileIndex)
        case .curve(let featureID):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(featureID, forKey: .featureID)
        }
    }
}
