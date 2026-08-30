import Foundation

/// Deterministic counters for one source-order triangulation operation.
public struct MeshTriangulationTelemetry: Equatable, Sendable {
    public private(set) var faceVisits: Int
    public private(set) var cornerVisits: Int
    public private(set) var indexedVertexLookups: Int
    public private(set) var positionReads: Int
    public private(set) var scratchPositionValues: Int
    public private(set) var nonConvexWorkUnits: Int
    public private(set) var globalIdentifierScans: Int
    /// Counts replacement GeometryBuffer materializations, not bounded scratch values.
    public private(set) var sourcePositionMaterializations: Int

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

    mutating func recordFaceVisit() throws {
        faceVisits = try addingOne(to: faceVisits)
    }

    mutating func recordCornerVisit() throws {
        cornerVisits = try addingOne(to: cornerVisits)
    }

    mutating func recordIndexedVertexLookup() throws {
        indexedVertexLookups = try addingOne(to: indexedVertexLookups)
    }

    mutating func recordPositionRead() throws {
        positionReads = try addingOne(to: positionReads)
    }

    mutating func recordScratchPositionValue() throws {
        scratchPositionValues = try addingOne(to: scratchPositionValues)
    }

    mutating func recordGlobalIdentifierScan() throws {
        globalIdentifierScans = try addingOne(to: globalIdentifierScans)
    }

    mutating func recordNonConvexWork(
        limit: Int
    ) throws {
        guard limit >= 0 else {
            throw MeshTriangulationError(
                code: .invalidLimits,
                message: "Mesh triangulation work limits cannot be negative."
            )
        }
        let next = nonConvexWorkUnits.addingReportingOverflow(1)
        guard !next.overflow else {
            throw MeshTriangulationError(
                code: .sizeOverflow,
                message: "Mesh triangulation work counter overflowed."
            )
        }
        guard next.partialValue <= limit else {
            throw MeshTriangulationError(
                code: .budgetExceeded,
                message: "Mesh non-convex triangulation exceeded its work budget."
            )
        }
        nonConvexWorkUnits = next.partialValue
    }

    private func addingOne(to value: Int) throws -> Int {
        let next = value.addingReportingOverflow(1)
        guard !next.overflow else {
            throw MeshTriangulationError(
                code: .sizeOverflow,
                message: "Mesh triangulation telemetry counter overflowed."
            )
        }
        return next.partialValue
    }
}
