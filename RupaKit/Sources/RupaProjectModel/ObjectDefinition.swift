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

    @available(*, deprecated, message: "Use the representations initializer and explicit purpose selection.")
    public init(
        id: ObjectDefinitionID,
        name: String,
        geometry: GeometrySourceReference?
    ) {
        self.id = id
        self.name = name
        guard let geometry else {
            self.representations = .empty
            return
        }
        let representationID = GeometryRepresentationID(
            rawValue: "representation.\(id.rawValue)"
        )
        self.representations = GeometryRepresentationSet(
            representations: [
                representationID: GeometryRepresentation(
                    id: representationID,
                    source: geometry
                ),
            ],
            selection: GeometryRepresentationSelection(
                modeling: representationID,
                presentation: representationID
            )
        )
    }

    @available(*, deprecated, message: "Use representations.source(for:) with an explicit purpose.")
    public var geometry: GeometrySourceReference? {
        representations.source(for: .presentation)
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
