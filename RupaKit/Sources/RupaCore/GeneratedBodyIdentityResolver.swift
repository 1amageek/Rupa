import SwiftCAD

struct GeneratedBodyIdentityResolver: Sendable {
    struct Identity: Equatable, Sendable {
        var bodyID: BodyID
        var sourceFeatureID: FeatureID
        var subshapeID: SubshapeID
    }

    func bodyFeatureIDs(
        in subshapes: SubshapeIndex
    ) -> [FeatureID] {
        var seen: Set<FeatureID> = []
        return bodyIdentities(in: subshapes).compactMap { identity in
            guard seen.insert(identity.sourceFeatureID).inserted else {
                return nil
            }
            return identity.sourceFeatureID
        }
    }

    func firstBodyIdentity(
        for featureID: FeatureID,
        in subshapes: SubshapeIndex
    ) -> Identity? {
        bodyIdentities(in: subshapes).first {
            $0.sourceFeatureID == featureID
        }
    }

    func bodyIdentityByBodyID(
        in subshapes: SubshapeIndex
    ) -> [BodyID: Identity] {
        var identitiesByBodyID: [BodyID: Identity] = [:]
        for identity in bodyIdentities(in: subshapes) {
            if identitiesByBodyID[identity.bodyID] == nil {
                identitiesByBodyID[identity.bodyID] = identity
            }
        }
        return identitiesByBodyID
    }

    func bodyIdentities(
        in subshapes: SubshapeIndex
    ) -> [Identity] {
        subshapes.entries
            .sorted { $0.key < $1.key }
            .compactMap { subshapeID, reference -> Identity? in
                guard case .body(let bodyID) = reference else {
                    return nil
                }
                return Identity(
                    bodyID: bodyID,
                    sourceFeatureID: subshapeID.featureID,
                    subshapeID: subshapeID
                )
            }
    }
}
