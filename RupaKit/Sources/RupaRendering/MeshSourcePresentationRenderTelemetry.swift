import Foundation
import RupaGeometry

/// Immutable counters emitted by one complete presentation-plan construction.
public struct MeshSourcePresentationRenderTelemetry: Equatable, Sendable {
    public let faceVisits: Int
    public let cornerVisits: Int
    public let indexedVertexLookups: Int
    public let positionReads: Int
    public let scratchPositionValues: Int
    public let nonConvexWorkUnits: Int
    public let globalIdentifierScans: Int
    public let sourcePositionMaterializations: Int

    public init() {
        faceVisits = 0
        cornerVisits = 0
        indexedVertexLookups = 0
        positionReads = 0
        scratchPositionValues = 0
        nonConvexWorkUnits = 0
        globalIdentifierScans = 0
        sourcePositionMaterializations = 0
    }

    init(_ telemetry: MeshTriangulationTelemetry) {
        faceVisits = telemetry.faceVisits
        cornerVisits = telemetry.cornerVisits
        indexedVertexLookups = telemetry.indexedVertexLookups
        positionReads = telemetry.positionReads
        scratchPositionValues = telemetry.scratchPositionValues
        nonConvexWorkUnits = telemetry.nonConvexWorkUnits
        globalIdentifierScans = telemetry.globalIdentifierScans
        sourcePositionMaterializations = telemetry.sourcePositionMaterializations
    }

    func adding(_ other: Self) throws -> Self {
        Self(
            faceVisits: try adding(faceVisits, other.faceVisits),
            cornerVisits: try adding(cornerVisits, other.cornerVisits),
            indexedVertexLookups: try adding(indexedVertexLookups, other.indexedVertexLookups),
            positionReads: try adding(positionReads, other.positionReads),
            scratchPositionValues: try adding(scratchPositionValues, other.scratchPositionValues),
            nonConvexWorkUnits: try adding(nonConvexWorkUnits, other.nonConvexWorkUnits),
            globalIdentifierScans: try adding(globalIdentifierScans, other.globalIdentifierScans),
            sourcePositionMaterializations: try adding(
                sourcePositionMaterializations,
                other.sourcePositionMaterializations
            )
        )
    }

    private init(
        faceVisits: Int,
        cornerVisits: Int,
        indexedVertexLookups: Int,
        positionReads: Int,
        scratchPositionValues: Int,
        nonConvexWorkUnits: Int,
        globalIdentifierScans: Int,
        sourcePositionMaterializations: Int
    ) {
        self.faceVisits = faceVisits
        self.cornerVisits = cornerVisits
        self.indexedVertexLookups = indexedVertexLookups
        self.positionReads = positionReads
        self.scratchPositionValues = scratchPositionValues
        self.nonConvexWorkUnits = nonConvexWorkUnits
        self.globalIdentifierScans = globalIdentifierScans
        self.sourcePositionMaterializations = sourcePositionMaterializations
    }

    private func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw MeshSourcePresentationRenderError(
                code: .sizeOverflow,
                message: "Presentation triangulation telemetry overflowed."
            )
        }
        return result.partialValue
    }
}
