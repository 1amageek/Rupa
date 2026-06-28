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
    #expect(result.counts.controlPointCount == 32)
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
    #expect(patch.basis.uKnotVector.map(\.id) == [
        "uKnot:0",
        "uKnot:1",
        "uKnot:2",
        "uKnot:3",
        "uKnot:4",
        "uKnot:5",
        "uKnot:6",
        "uKnot:7",
    ])
    #expect(patch.basis.uKnotVector.map(\.multiplicity) == [4, 4, 4, 4, 4, 4, 4, 4])
    #expect(patch.basis.vKnotVector.map(\.id) == [
        "vKnot:0",
        "vKnot:1",
        "vKnot:2",
        "vKnot:3",
        "vKnot:4",
        "vKnot:5",
        "vKnot:6",
        "vKnot:7",
    ])
    #expect(patch.basis.uSpans.count == 1)
    #expect(patch.basis.uSpans.first?.id == "uSpan:0")
    #expect(patch.basis.uSpans.first?.startKnotIndex == 3)
    #expect(patch.basis.uSpans.first?.endKnotIndex == 4)
    #expect(patch.basis.vSpans.count == 1)
    #expect(patch.basis.vSpans.first?.id == "vSpan:0")
    #expect(patch.basis.vSpans.first?.startKnotIndex == 3)
    #expect(patch.basis.vSpans.first?.endKnotIndex == 4)
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
    #expect(patch.controlPoints.count == 16)
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
    let interiorControlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(interiorControlPoint.isBoundary == false)
    #expect(interiorControlPoint.isEditable)
    #expect(interiorControlPoint.weight == 1.0)
    guard case .surface(.controlPoint(let interiorReference)) = interiorControlPoint.selectionReference else {
        Issue.record("Surface source control point must expose a kernel surface control-point reference.")
        return
    }
    #expect(interiorReference.uIndex == 1)
    #expect(interiorReference.vIndex == 1)
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

@MainActor
@Test func surfaceControlPointDisplayStateRoundTripsThroughSurfaceSourceSummary() async throws {
    let session = EditorSession()
    let createResult = try #require(session.createPolySplineSurface(
        name: "Surface CV Display State",
        sourceMesh: surfaceSourceSummaryPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))
    #expect(createResult.commandName == "createPolySplineSurface")

    let initialSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let initialPatch = try #require(initialSummary.sources.first?.patches.first)
    let interiorControlPoint = try #require(initialPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(interiorControlPoint.isPointDisplayVisible == false)

    let displayResult = try #require(session.setSurfaceControlPointDisplay(
        target: interiorControlPoint.selectionReference,
        isVisible: true
    ))
    #expect(displayResult.commandName == "setSurfaceControlPointDisplay")
    #expect(displayResult.didMutate)

    let displayID = try SurfaceControlPointDisplayID(selectionReference: interiorControlPoint.selectionReference)
    #expect(session.document.productMetadata.surfaceControlPointDisplays[displayID]?.isVisible == true)
    let visibleSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let visiblePatch = try #require(visibleSummary.sources.first?.patches.first)
    let visibleControlPoint = try #require(visiblePatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let visibleControlVertex = try #require(visiblePatch.controlVertices.first { $0.role == "uMin:vMin" })
    #expect(visibleControlPoint.isPointDisplayVisible)
    #expect(visibleControlVertex.isPointDisplayVisible == false)

    _ = try session.undo()
    #expect(session.document.productMetadata.surfaceControlPointDisplays[displayID] == nil)

    _ = try session.redo()
    #expect(session.document.productMetadata.surfaceControlPointDisplays[displayID]?.isVisible == true)

    let hiddenResult = try #require(session.setSurfaceControlPointDisplay(
        target: interiorControlPoint.selectionReference,
        isVisible: false
    ))
    #expect(hiddenResult.commandName == "setSurfaceControlPointDisplay")

    let hiddenSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let hiddenPatch = try #require(hiddenSummary.sources.first?.patches.first)
    let hiddenControlPoint = try #require(hiddenPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(hiddenControlPoint.isPointDisplayVisible == false)
}

@MainActor
@Test func surfaceFrameDisplayStateRoundTripsThroughDocumentMetadata() async throws {
    let session = EditorSession()
    let createResult = try #require(session.createPolySplineSurface(
        name: "Surface Frame Display State",
        sourceMesh: surfaceSourceSummaryPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))
    #expect(createResult.commandName == "createPolySplineSurface")

    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })
    let query = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)

    let displayResult = try #require(session.setSurfaceFrameDisplay(
        query: query,
        isVisible: true
    ))
    #expect(displayResult.commandName == "setSurfaceFrameDisplay")
    #expect(displayResult.didMutate)

    let displayID = try SurfaceFrameDisplayID(query: query)
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID]?.isVisible == true)
    let frameResult = try SurfaceFrameService().resolve(
        document: session.document,
        queries: [query]
    )
    let frame = try #require(frameResult.frames.first)
    #expect(abs(frame.u - (2.0 / 3.0)) <= 1.0e-12)
    #expect(abs(frame.v - (1.0 / 3.0)) <= 1.0e-12)

    _ = try session.undo()
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID] == nil)

    _ = try session.redo()
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID]?.isVisible == true)

    let hiddenResult = try #require(session.setSurfaceFrameDisplay(
        query: query,
        isVisible: false
    ))
    #expect(hiddenResult.commandName == "setSurfaceFrameDisplay")
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID] == nil)

    let staleQuery = SurfaceFrameQuery(
        faceID: "00000000-0000-0000-0000-000000000001",
        u: 0.5,
        v: 0.5
    )
    var staleDocument = DesignDocument.empty()
    try staleDocument.setSurfaceFrameDisplay(query: staleQuery, isVisible: false)
    let staleDisplayID = try SurfaceFrameDisplayID(query: staleQuery)
    #expect(staleDocument.productMetadata.surfaceFrameDisplays[staleDisplayID] == nil)
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
