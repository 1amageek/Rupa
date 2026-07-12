import Foundation
import RupaGeometry

public enum GeometrySourceReference: Codable, Equatable, Sendable {
    case mesh(MeshSourceID)
    case external(providerID: String, sourceID: String, outputID: String?)

    public func validate() throws {
        switch self {
        case .mesh(let sourceID):
            try sourceID.validate()
        case .external(let providerID, let sourceID, let outputID):
            guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  outputID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "External geometry references require non-empty provider and source IDs; output IDs must be non-empty when present."
                )
            }
        }
    }

    public var providerID: String {
        switch self {
        case .mesh:
            "mesh"
        case .external(let providerID, _, _):
            providerID
        }
    }
}
