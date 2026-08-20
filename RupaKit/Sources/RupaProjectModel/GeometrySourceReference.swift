import Foundation
import RupaGeometry

public enum GeometrySourceReference: Codable, Equatable, Hashable, Sendable {
    public static let meshProviderID = "mesh"

    case mesh(MeshSourceID)
    case external(providerID: String, sourceID: String, outputID: String?)

    public func validate() throws {
        switch self {
        case .mesh(let sourceID):
            try sourceID.validate()
        case .external(let providerID, let sourceID, let outputID):
            let trimmedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSourceID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOutputID = outputID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasValidOutputID = outputID == nil
                || (trimmedOutputID?.isEmpty == false && outputID == trimmedOutputID)
            guard !trimmedProviderID.isEmpty,
                  providerID == trimmedProviderID,
                  !trimmedSourceID.isEmpty,
                  sourceID == trimmedSourceID,
                  hasValidOutputID else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "External geometry references require non-empty provider, source, and optional output IDs without surrounding whitespace."
                )
            }
        }
    }

    public var providerID: String {
        switch self {
        case .mesh:
            Self.meshProviderID
        case .external(let providerID, _, _):
            providerID
        }
    }
}
