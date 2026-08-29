import Foundation

/// Representation labels accepted by the sphere oracle.
///
/// The non-sphere labels are explicit so an approximation cannot be promoted
/// to an analytic sphere merely because its bounds have the same radius.
enum CADSphereRepresentationKind: String, Codable, Equatable, Hashable, Sendable {
    case analyticSphere
    case box
    case cylinder
    case circle
    case polyhedron
    case extrudedDisc
    case mesh
    case unknown
}

/// Immutable source/B-rep facts supplied to the exact sphere oracle.
struct CADSphereObservedGeometry: Equatable, Sendable {
    let representation: CADSphereRepresentationKind
    let center: CADPoint3D
    let radiusMeters: Double
    let bodyCount: Int
    let faceCount: Int
    let edgeCount: Int
    let vertexCount: Int
    let analyticSurfaceCount: Int
    let featureCount: Int
    let volumeCubicMeters: Double
    let isClosed: Bool
    let sourceIsAuthoritative: Bool

    init(
        representation: CADSphereRepresentationKind,
        center: CADPoint3D,
        radiusMeters: Double,
        bodyCount: Int,
        faceCount: Int,
        edgeCount: Int,
        vertexCount: Int,
        analyticSurfaceCount: Int,
        featureCount: Int,
        volumeCubicMeters: Double,
        isClosed: Bool,
        sourceIsAuthoritative: Bool
    ) {
        self.representation = representation
        self.center = center
        self.radiusMeters = radiusMeters
        self.bodyCount = bodyCount
        self.faceCount = faceCount
        self.edgeCount = edgeCount
        self.vertexCount = vertexCount
        self.analyticSurfaceCount = analyticSurfaceCount
        self.featureCount = featureCount
        self.volumeCubicMeters = volumeCubicMeters
        self.isClosed = isClosed
        self.sourceIsAuthoritative = sourceIsAuthoritative
    }
}
