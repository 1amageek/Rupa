import RupaCoreTypes
import RupaGeometry

public struct AuthoredMeshAsset: Codable, Equatable, Sendable {
    public var source: MeshSource
    public var provenance: AuthoredMeshProvenance

    public var id: GeometrySourceID {
        source.identity
    }

    public init(
        source: MeshSource,
        provenance: AuthoredMeshProvenance
    ) throws {
        self.source = source
        self.provenance = provenance
        try validate()
    }

    public func validate() throws {
        try source.validate()
        try provenance.validate()
    }
}
