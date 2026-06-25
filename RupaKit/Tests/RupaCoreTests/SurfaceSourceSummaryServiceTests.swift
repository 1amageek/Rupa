import Testing
import RupaCore
import SwiftCAD

@Test func surfaceSourceSummaryReportsPolySplineSourceContract() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Source Contract Surface",
        sourceMesh: surfaceSourceSummaryPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let result = try SurfaceSourceSummaryService().summarize(document: document)

    #expect(result.counts.sourceCount == 1)
    #expect(result.counts.patchCount == 2)
    #expect(result.counts.controlVertexCount == 8)
    #expect(result.counts.trimLoopCount == 2)
    #expect(result.counts.adjacencyCount == 1)
    let source = try #require(result.sources.first)
    #expect(source.featureID == featureID.description)
    #expect(source.kind == "polySpline")
    #expect(source.sceneNodeID != nil)
    #expect(source.meshCounts.vertexCount == 6)
    #expect(source.meshCounts.triangleCount == 4)
    #expect(source.options.mergePatches == false)
    #expect(source.options.interpolateBoundaryExactly)
    #expect(source.support.isSupported)
    #expect(source.support.candidateKind == "quadPatchGraph")
    #expect(source.support.supportedPatchCount == 2)
    #expect(source.patches.map(\.patchID) == [0, 2])
    #expect(source.adjacencies.count == 1)
    let adjacency = try #require(source.adjacencies.first)
    #expect(adjacency.firstPatchID == 0)
    #expect(adjacency.secondPatchID == 2)
    #expect(adjacency.continuityLevel == "tangentPlane")
    #expect(adjacency.requiresCurvatureContinuitySolve == false)
    #expect(adjacency.sharedVertexIndices == [1, 4])
    #expect(adjacency.sharedEdgePersistentName?.contains("subshape:patch:0:edge:uMax") == true)

    let patch = try #require(source.patches.first)
    #expect(patch.facePersistentName?.contains("subshape:patch:0:face") == true)
    #expect(patch.faceSelectionComponentID?.hasPrefix(SelectionComponentID.generatedTopologyPrefix) == true)
    guard case .surface(.whole(let faceReference)) = patch.faceSelectionReference else {
        Issue.record("Patch must expose a kernel surface selection reference.")
        return
    }
    #expect(faceReference.faceName.components.count == 3)
    #expect(patch.basis.kind == "cubicBezierBSpline")
    #expect(patch.basis.uDegree == 3)
    #expect(patch.basis.vDegree == 3)
    #expect(patch.basis.uKnots == [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
    #expect(patch.basis.vKnots == [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
    #expect(patch.basis.isRational == false)
    #expect(patch.uDomain.lowerBound == 0.0)
    #expect(patch.uDomain.upperBound == 1.0)
    #expect(patch.vDomain.lowerBound == 0.0)
    #expect(patch.vDomain.upperBound == 1.0)
    #expect(patch.parameterAddresses.map(\.id) == ["uMin:vMin", "uMax:vMin", "uMax:vMax", "uMin:vMax", "center"])
    #expect(patch.parameterAddresses.allSatisfy { $0.selectionReference != nil })
    #expect(patch.trimLoops.count == 1)
    let trimLoop = try #require(patch.trimLoops.first)
    #expect(trimLoop.role == "outer")
    #expect(trimLoop.sourceVertexIndices == [0, 1, 4, 3])
    #expect(trimLoop.edgePersistentNames.count == 4)
    #expect(trimLoop.selectionReferences.count == 4)
    #expect(trimLoop.parameterAddresses.map(\.id) == ["uMin:vMin", "uMax:vMin", "uMax:vMax", "uMin:vMax"])
    #expect(trimLoop.parameterAddresses.allSatisfy { $0.selectionReference != nil })
    #expect(patch.controlVertices.count == 4)
    let controlVertex = try #require(patch.controlVertices.first)
    #expect(controlVertex.role == "uMin:vMin")
    #expect(controlVertex.sourceVertexIndex == 0)
    #expect(controlVertex.generatedVertexPersistentName.contains("subshape:patch:0:vertex:uMin:vMin"))
    #expect(controlVertex.selectionComponentID.hasPrefix(SelectionComponentID.generatedTopologyPrefix))
    guard case .surface(.controlPoint(let controlPointReference)) = controlVertex.selectionReference else {
        Issue.record("Surface source control vertex must expose a kernel surface control-point reference.")
        return
    }
    #expect(controlPointReference.uIndex == 0)
    #expect(controlPointReference.vIndex == 0)
    let measurement = try SelectionMeasurementService().measure(
        query: CADAgentMeasurementQuery(kind: .point, first: controlVertex.selectionReference),
        document: document
    )
    guard case .point(let measuredPoint) = measurement else {
        Issue.record("Surface control-point measurement must return a point result.")
        return
    }
    #expect(abs(measuredPoint.point.x - controlVertex.point.x) <= 1.0e-12)
    #expect(abs(measuredPoint.point.y - controlVertex.point.y) <= 1.0e-12)
    #expect(abs(measuredPoint.point.z - controlVertex.point.z) <= 1.0e-12)
}

private func surfaceSourceSummaryPatchNetworkMesh(centerZ: Double) -> Mesh {
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
