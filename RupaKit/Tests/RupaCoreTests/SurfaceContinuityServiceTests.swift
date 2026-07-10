import Testing
import RupaCore
import SwiftCAD

@Test func surfaceContinuityServiceReportsPlanarUnmergedPolySplinePatchNetwork() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Planar Patch Network",
        sourceMesh: surfaceContinuityPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let summary = try SurfaceContinuityService().summarize(document: document, displayUnit: .millimeter)

    #expect(summary.counts.bSplineFaceCount == 2)
    #expect(summary.counts.sharedEdgeCount == 1)
    #expect(summary.counts.g0AdjacencyCount == 0)
    #expect(summary.counts.g1AdjacencyCount == 0)
    #expect(summary.counts.g2AdjacencyCount == 1)
    #expect(summary.counts.unresolvedG2AdjacencyCount == 0)
    let adjacency = try #require(summary.adjacencies.first)
    #expect(adjacency.continuity == .g2)
    #expect(adjacency.positionGap == 0.0)
    #expect(adjacency.requiresCurvatureContinuitySolve == false)
    let normalAngle = try #require(adjacency.normalAngle)
    #expect(normalAngle <= ModelingTolerance.standard.angle)
    let curvatureGap = try #require(adjacency.curvatureGap)
    #expect(curvatureGap <= 1.0e-6)
    let faceNames = [
        adjacency.firstFacePersistentName,
        adjacency.secondFacePersistentName,
    ]
    #expect(faceNames.contains { $0?.contains("subshape:patch:0:face") == true })
    #expect(faceNames.contains { $0?.contains("subshape:patch:2:face") == true })
    #expect(adjacency.edgePersistentNames.contains { $0.contains("subshape:patch:0:edge:uMax") })
    #expect(adjacency.edgePersistentNames.contains { $0.contains("subshape:patch:2:edge:uMin") })
    #expect(!summary.diagnostics.contains { $0.severity == .warning })
}

private func surfaceContinuityPolySplinePatchNetworkMesh(centerZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}
