import SwiftCAD

struct GeneratedBodyIdentityResolver: Sendable {
    struct Identity: Equatable, Sendable {
        var bodyID: BodyID
        var sourceFeatureID: FeatureID
        var persistentName: String
    }

    func bodyFeatureIDs(
        in generatedNames: [PersistentName: TopologyReference]
    ) -> [FeatureID] {
        var seen: Set<FeatureID> = []
        return bodyIdentities(in: generatedNames).compactMap { identity in
            guard seen.insert(identity.sourceFeatureID).inserted else {
                return nil
            }
            return identity.sourceFeatureID
        }
    }

    func firstBodyIdentity(
        for featureID: FeatureID,
        in generatedNames: [PersistentName: TopologyReference]
    ) -> Identity? {
        bodyIdentities(in: generatedNames).first {
            $0.sourceFeatureID == featureID
        }
    }

    func bodyIdentityByBodyID(
        in generatedNames: [PersistentName: TopologyReference]
    ) -> [BodyID: Identity] {
        var identitiesByBodyID: [BodyID: Identity] = [:]
        for identity in bodyIdentities(in: generatedNames) {
            if identitiesByBodyID[identity.bodyID] == nil {
                identitiesByBodyID[identity.bodyID] = identity
            }
        }
        return identitiesByBodyID
    }

    func bodyIdentities(
        in generatedNames: [PersistentName: TopologyReference]
    ) -> [Identity] {
        generatedNames
            .sorted { persistentNameString($0.key) < persistentNameString($1.key) }
            .compactMap { name, reference -> Identity? in
                guard case .body(let bodyID) = reference,
                      let sourceFeatureID = sourceFeatureID(name) else {
                    return nil
                }
                return Identity(
                    bodyID: bodyID,
                    sourceFeatureID: sourceFeatureID,
                    persistentName: persistentNameString(name)
                )
            }
    }

    func sourceFeatureID(_ name: PersistentName) -> FeatureID? {
        for component in name.components {
            if case .feature(let featureID) = component {
                return featureID
            }
        }
        return nil
    }

    func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }
}
