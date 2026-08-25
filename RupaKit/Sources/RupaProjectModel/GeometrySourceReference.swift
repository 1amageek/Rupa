import Foundation
import RupaCoreTypes
import RupaGeometry

public enum GeometrySourceReference: Codable, Equatable, Hashable, Sendable {
    public static let cadProviderID = "cad"
    public static let authoredMeshProviderID = "mesh"

    case cad(sourceID: String, outputID: String)
    case authoredMesh(GeometrySourceID)
    case external(providerID: String, sourceID: String, outputID: String?)

    public func validate() throws {
        switch self {
        case .authoredMesh(let sourceID):
            do {
                try sourceID.validate()
            } catch let error as EditorError {
                throw ProjectModelError(code: .invalidReference, message: error.message)
            }
        case .cad(let sourceID, let outputID):
            try Self.validateExternalIdentifier(
                sourceID,
                label: "CAD source IDs"
            )
            try Self.validateExternalIdentifier(
                outputID,
                label: "CAD output IDs"
            )
        case .external(let providerID, let sourceID, let outputID):
            try Self.validateExternalIdentifier(
                providerID,
                label: "External geometry provider IDs"
            )
            try Self.validateExternalIdentifier(
                sourceID,
                label: "External geometry source IDs"
            )
            if let outputID {
                try Self.validateExternalIdentifier(
                    outputID,
                    label: "External geometry output IDs"
                )
            }
        }
    }

    public var providerID: String {
        switch self {
        case .cad:
            Self.cadProviderID
        case .authoredMesh:
            Self.authoredMeshProviderID
        case .external(let providerID, _, _):
            providerID
        }
    }

    private static func validateExternalIdentifier(
        _ value: String,
        label: String
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed == value else {
            throw ProjectModelError(
                code: .invalidReference,
                message: "\(label) must be non-empty and must not contain surrounding whitespace."
            )
        }
    }
}
