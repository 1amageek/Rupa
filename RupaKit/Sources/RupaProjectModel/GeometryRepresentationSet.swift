import RupaCoreTypes

public struct GeometryRepresentationSet: Codable, Hashable, Sendable {
    public var representations: [GeometryRepresentationID: GeometryRepresentation]
    public var selection: GeometryRepresentationSelection?

    public init(
        representations: [GeometryRepresentationID: GeometryRepresentation] = [:],
        selection: GeometryRepresentationSelection? = nil
    ) {
        self.representations = representations
        self.selection = selection
    }

    public static let empty = GeometryRepresentationSet()

    public func representation(
        for purpose: GeometryRepresentationPurpose
    ) -> GeometryRepresentation? {
        guard let representationID = selection?.representationID(for: purpose) else {
            return nil
        }
        return representations[representationID]
    }

    public func source(
        for purpose: GeometryRepresentationPurpose
    ) -> GeometrySourceReference? {
        representation(for: purpose)?.source
    }

    public func validate(requiresSelection: Bool) throws {
        for (representationID, representation) in representations {
            guard representationID == representation.id else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "Geometry representation dictionary keys must match representation identities."
                )
            }
            try representation.validate()
        }
        guard Set(representations.values.map(\.source)).count == representations.count else {
            throw ProjectModelError(
                code: .invalidReference,
                message: "One object must not bind the same geometry source through multiple representation IDs."
            )
        }

        if requiresSelection {
            guard representations.isEmpty == false,
                  let selection else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "Geometry objects require retained representations and explicit modeling and presentation selections."
                )
            }
            guard representations[selection.modeling] != nil,
                  representations[selection.presentation] != nil else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "Geometry representation selections must reference retained representations."
                )
            }
        } else {
            guard representations.isEmpty,
                  selection == nil else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "Non-geometry objects must not retain geometry representations or selections."
                )
            }
        }
    }
}
