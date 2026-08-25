import Foundation
import RupaCoreTypes

public struct ObjectDefinition: Codable, Equatable, Sendable {
    public var id: ObjectDefinitionID
    public var name: String
    public var representations: GeometryRepresentationSet

    public init(
        id: ObjectDefinitionID,
        name: String,
        representations: GeometryRepresentationSet = .empty
    ) {
        self.id = id
        self.name = name
        self.representations = representations
    }

    public func validate() throws {
        do {
            try id.validate()
        } catch let error as EditorError {
            throw ProjectModelError(code: .invalidIdentity, message: error.message)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectModelError(code: .invalidIdentity, message: "Object definition names must not be empty.")
        }
        try representations.validate(
            requiresSelection: representations.representations.isEmpty == false
        )
    }
}
