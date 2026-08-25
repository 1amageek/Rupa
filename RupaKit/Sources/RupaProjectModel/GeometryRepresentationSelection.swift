import RupaCoreTypes

public struct GeometryRepresentationSelection: Codable, Hashable, Sendable {
    public var modeling: GeometryRepresentationID
    public var presentation: GeometryRepresentationID

    public init(
        modeling: GeometryRepresentationID,
        presentation: GeometryRepresentationID
    ) {
        self.modeling = modeling
        self.presentation = presentation
    }

    public func representationID(
        for purpose: GeometryRepresentationPurpose
    ) -> GeometryRepresentationID {
        switch purpose {
        case .modeling:
            modeling
        case .presentation:
            presentation
        }
    }
}
