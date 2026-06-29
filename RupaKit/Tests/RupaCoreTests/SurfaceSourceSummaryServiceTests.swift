import Foundation
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
    #expect(result.counts.frameSampleCount == 2)
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
    #expect(patch.frameSamples.count == 1)
    let frameSample = try #require(patch.frameSamples.first)
    #expect(frameSample.id == "feature:\(featureID.description)/patch:0/frame:uSpan0:vSpan0")
    #expect(frameSample.uSpanID == "uSpan:0")
    #expect(frameSample.vSpanID == "vSpan:0")
    #expect(abs(frameSample.u - 0.5) <= 1.0e-12)
    #expect(abs(frameSample.v - 0.5) <= 1.0e-12)
    #expect(frameSample.isFrameDisplayVisible == false)
    expectSurfaceSourceVector(frameSample.uAxis, x: 1.0, y: 0.0, z: 0.0)
    expectSurfaceSourceVector(frameSample.vAxis, x: 0.0, y: 1.0, z: 0.0)
    expectSurfaceSourceVector(frameSample.normal, x: 0.0, y: 0.0, z: 1.0)
    #expect(abs(frameSample.handedness - 1.0) <= 1.0e-12)
    guard case .surface(.parameter(let frameParameterReference)) = frameSample.selectionReference else {
        Issue.record("Surface source frame sample must expose a surface parameter reference.")
        return
    }
    #expect(abs(frameParameterReference.u - 0.5) <= 1.0e-12)
    #expect(abs(frameParameterReference.v - 0.5) <= 1.0e-12)
    let resolvedFrame = try SurfaceFrameService().resolve(
        document: document,
        queries: [SurfaceFrameQuery(selectionReference: frameSample.selectionReference)]
    )
    let resolvedFrameSample = try #require(resolvedFrame.frames.first)
    #expect(abs(resolvedFrameSample.u - frameSample.u) <= 1.0e-12)
    #expect(abs(resolvedFrameSample.v - frameSample.v) <= 1.0e-12)
    #expect(abs(resolvedFrameSample.normal.z - frameSample.normal.z) <= 1.0e-12)
    #expect(patch.trimLoops.count == 1)
    let trimLoop = try #require(patch.trimLoops.first)
    #expect(trimLoop.role == "outer")
    #expect(trimLoop.sourceVertexIndices == [0, 1, 4, 3])
    #expect(trimLoop.edgePersistentNames.count == 4)
    #expect(trimLoop.selectionReferences.count == 4)
    #expect(trimLoop.edges.map(\.role) == ["vMin", "uMax", "vMax", "uMin"])
    #expect(trimLoop.edges.allSatisfy { $0.supportedBoundaryContinuityLevels.isEmpty })
    #expect(trimLoop.edges.allSatisfy { $0.supportsBoundaryContinuityMatching == false })
    #expect(trimLoop.edges.allSatisfy { $0.unsupportedReason?.contains("PolySpline") == true })
    let polySplineBoundaryEdge = try #require(trimLoop.edges.first)
    #expect(polySplineBoundaryEdge.boundaryDirection == .u)
    #expect(polySplineBoundaryEdge.inwardDirection == .v)
    #expect(polySplineBoundaryEdge.boundaryControlPointReferences.count == 4)
    #expect(polySplineBoundaryEdge.firstInwardControlPointReferences.count == 4)
    #expect(polySplineBoundaryEdge.secondInwardControlPointReferences.count == 4)
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

@Test func surfaceSourceSummaryReportsDirectBSplineSurfaceSourceContract() async throws {
    var document = DesignDocument.empty()
    let surface = surfaceSourceSummaryDirectBSplineSurface()
    let featureID = try document.createBSplineSurface(
        name: "Direct Surface Source",
        surface: surface
    )

    let result = try SurfaceSourceSummaryService().summarize(document: document)

    #expect(result.counts.sourceCount == 1)
    #expect(result.counts.patchCount == 1)
    #expect(result.counts.controlVertexCount == 0)
    #expect(result.counts.controlPointCount == 16)
    #expect(result.counts.frameSampleCount == 1)
    #expect(result.counts.trimLoopCount == 1)
    let source = try #require(result.sources.first)
    #expect(source.featureID == featureID.description)
    #expect(source.kind == "bSplineSurface")
    #expect(source.support.isSupported)
    #expect(source.support.candidateKind == "directBSplineSurface")
    let patch = try #require(source.patches.first)
    #expect(patch.facePersistentName?.contains("generated:bSplineSurface/subshape:patch:0:face") == true)
    #expect(patch.faceSelectionComponentID?.hasPrefix(SelectionComponentID.generatedTopologyPrefix) == true)
    #expect(patch.basis.kind == "bSplineSurface")
    #expect(patch.basis.uDegree == 3)
    #expect(patch.basis.vDegree == 3)
    #expect(patch.basis.uKnots == surface.uKnots)
    #expect(patch.basis.vKnots == surface.vKnots)
    #expect(patch.basis.isRational)
    let firstUKnot = try #require(patch.basis.uKnotVector.first)
    #expect(firstUKnot.selectionReference != nil)
    #expect(firstUKnot.isEditable == false)
    let firstUSpan = try #require(patch.basis.uSpans.first)
    #expect(firstUSpan.isEditable)
    guard case .surface(.span(let spanReference)) = firstUSpan.selectionReference else {
        Issue.record("Direct B-spline span must expose a surface span reference.")
        return
    }
    #expect(spanReference.direction == .u)
    #expect(spanReference.spanIndex == firstUSpan.index)
    let trimLoop = try #require(patch.trimLoops.first)
    #expect(trimLoop.edgePersistentNames.count == 4)
    #expect(trimLoop.selectionReferences.count == 4)
    #expect(trimLoop.edges.map(\.role) == ["vMin", "uMax", "vMax", "uMin"])
    #expect(trimLoop.edges.allSatisfy { $0.supportsBoundaryContinuityMatching })
    #expect(trimLoop.edges.allSatisfy { $0.supportedBoundaryContinuityLevels == [.g0, .g1, .g2] })
    #expect(trimLoop.edges.allSatisfy { $0.unsupportedReason == nil })
    let vMinEdge = try #require(trimLoop.edges.first)
    #expect(vMinEdge.index == 0)
    #expect(vMinEdge.startParameter.id == "uMin:vMin")
    #expect(vMinEdge.endParameter.id == "uMax:vMin")
    #expect(vMinEdge.boundaryDirection == .u)
    #expect(vMinEdge.inwardDirection == .v)
    #expect(vMinEdge.parameterCurveControlPoints.isEmpty)
    #expect(vMinEdge.boundaryControlPointReferences.count == surface.uControlPointCount)
    #expect(vMinEdge.firstInwardControlPointReferences.count == surface.uControlPointCount)
    #expect(vMinEdge.secondInwardControlPointReferences.count == surface.uControlPointCount)
    let firstBoundaryReference = try surfaceSourceControlPointReference(
        from: vMinEdge.boundaryControlPointReferences[0]
    )
    #expect(firstBoundaryReference.uIndex == 0)
    #expect(firstBoundaryReference.vIndex == 0)
    let firstInwardReference = try surfaceSourceControlPointReference(
        from: vMinEdge.firstInwardControlPointReferences[0]
    )
    #expect(firstInwardReference.uIndex == 0)
    #expect(firstInwardReference.vIndex == 1)
    let vMaxEdge = try #require(trimLoop.edges.first { $0.role == "vMax" })
    #expect(vMaxEdge.startParameter.id == "uMax:vMax")
    #expect(vMaxEdge.endParameter.id == "uMin:vMax")
    let vMaxFirstBoundaryReference = try surfaceSourceControlPointReference(
        from: vMaxEdge.boundaryControlPointReferences[0]
    )
    #expect(vMaxFirstBoundaryReference.uIndex == surface.uControlPointCount - 1)
    #expect(vMaxFirstBoundaryReference.vIndex == surface.vControlPointCount - 1)
    let frameSample = try #require(patch.frameSamples.first)
    #expect(frameSample.uSpanID == firstUSpan.id)
    #expect(frameSample.vSpanID == patch.basis.vSpans.first?.id)
    #expect(abs(frameSample.u - 0.5) <= 1.0e-12)
    #expect(abs(frameSample.v - 0.5) <= 1.0e-12)
    expectUnitSurfaceSourceVector(frameSample.uAxis)
    expectUnitSurfaceSourceVector(frameSample.vAxis)
    expectSurfaceSourceVector(frameSample.normal, x: 0.0, y: 0.0, z: 1.0)
    #expect(abs(surfaceSourceDot(frameSample.uAxis, frameSample.vAxis)) <= 1.0e-12)
    #expect(abs(surfaceSourceDot(frameSample.uAxis, frameSample.normal)) <= 1.0e-12)
    #expect(abs(surfaceSourceDot(frameSample.vAxis, frameSample.normal)) <= 1.0e-12)
    #expect(abs(frameSample.handedness - 1.0) <= 1.0e-12)
    let weightedControlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(weightedControlPoint.weight == 2.0)
    #expect(weightedControlPoint.isEditable)
    guard case .surface(.controlPoint(let controlPointReference)) = weightedControlPoint.selectionReference else {
        Issue.record("Direct B-spline control point must expose a surface control-point reference.")
        return
    }
    #expect(controlPointReference.uIndex == 1)
    #expect(controlPointReference.vIndex == 1)
    let measurement = try SelectionMeasurementService().measure(
        query: CADAgentMeasurementQuery(kind: .point, first: weightedControlPoint.selectionReference),
        document: document
    )
    guard case .point(let measuredPoint) = measurement else {
        Issue.record("Direct B-spline control point measurement must return a point result.")
        return
    }
    #expect(abs(measuredPoint.point.x - weightedControlPoint.point.x) <= 1.0e-12)
    #expect(abs(measuredPoint.point.y - weightedControlPoint.point.y) <= 1.0e-12)
    #expect(abs(measuredPoint.point.z - weightedControlPoint.point.z) <= 1.0e-12)
}

@Test func surfaceSourceSummaryReportsAuthoredTrimParameterCurveControlPoints() async throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Direct Authored Trim Surface",
        surface: surfaceSourceSummaryDirectBSplineSurface()
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [
            BSplineSurfaceTrimLoop(
                role: .outer,
                edges: [
                    BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                        degree: 2,
                        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                        controlPoints: [
                            Point2D(x: 0.2, y: 0.2),
                            Point2D(x: 0.52, y: 0.42),
                            Point2D(x: 0.8, y: 0.25),
                        ]
                    ))),
                    BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                        SurfaceParameter(u: 0.8, v: 0.25),
                        SurfaceParameter(u: 0.45, v: 0.8),
                    ])),
                    BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                        SurfaceParameter(u: 0.45, v: 0.8),
                        SurfaceParameter(u: 0.2, v: 0.2),
                    ])),
                ]
            ),
        ]
    )

    let result = try SurfaceSourceSummaryService().summarize(document: document)

    let loop = try #require(result.sources.first?.patches.first?.trimLoops.first)
    let bSplineEdge = try #require(loop.edges.first)
    #expect(bSplineEdge.parameterCurveControlPoints.map(\.index) == [0, 1, 2])
    #expect(bSplineEdge.parameterCurveControlPoints.map(\.isEndpoint) == [true, false, true])
    #expect(bSplineEdge.parameterCurveControlPoints.map(\.isEditable) == [false, true, false])
    let startPoint = try #require(bSplineEdge.parameterCurveControlPoints.first)
    #expect(startPoint.unsupportedReason?.contains("moveSurfaceTrimEndpoint") == true)
    let interiorPoint = try #require(bSplineEdge.parameterCurveControlPoints.first { $0.isEditable })
    #expect(interiorPoint.index == 1)
    #expect(interiorPoint.parameter.id == "loop:0:edge:0:parameterCurveControlPoint:1")
    #expect(abs(interiorPoint.parameter.u - 0.52) <= 1.0e-12)
    #expect(abs(interiorPoint.parameter.v - 0.42) <= 1.0e-12)
    #expect(interiorPoint.parameter.selectionReference != nil)
    let endPoint = try #require(bSplineEdge.parameterCurveControlPoints.last)
    #expect(endPoint.unsupportedReason?.contains("moveSurfaceTrimEndpoint") == true)
    let polylineEdge = try #require(loop.edges.dropFirst().first)
    #expect(polylineEdge.parameterCurveControlPoints.map(\.index) == [0, 1])
    #expect(polylineEdge.parameterCurveControlPoints.allSatisfy { $0.isEndpoint })
    #expect(polylineEdge.parameterCurveControlPoints.allSatisfy { $0.isEditable == false })
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

    let sourceFrameSample = try #require(patch.frameSamples.first)
    let sampleQuery = SurfaceFrameQuery(selectionReference: sourceFrameSample.selectionReference)
    let sampleDisplayResult = try #require(session.setSurfaceFrameDisplay(
        query: sampleQuery,
        isVisible: true
    ))
    #expect(sampleDisplayResult.commandName == "setSurfaceFrameDisplay")
    let sampleSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let visibleSample = try #require(sampleSummary.sources.first?.patches.first?.frameSamples.first)
    #expect(visibleSample.isFrameDisplayVisible)

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

private func expectSurfaceSourceVector(
    _ vector: SurfaceSourceSummaryResult.Vector,
    x: Double,
    y: Double,
    z: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(abs(vector.x - x) <= tolerance)
    #expect(abs(vector.y - y) <= tolerance)
    #expect(abs(vector.z - z) <= tolerance)
}

private func expectUnitSurfaceSourceVector(
    _ vector: SurfaceSourceSummaryResult.Vector,
    tolerance: Double = 1.0e-12
) {
    #expect(abs(surfaceSourceLength(vector) - 1.0) <= tolerance)
}

private func surfaceSourceControlPointReference(
    from selectionReference: SelectionReference
) throws -> SurfaceControlPointReference {
    guard case .surface(.controlPoint(let reference)) = selectionReference else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a surface control-point selection reference."
        )
    }
    return reference
}

private func surfaceSourceDot(
    _ lhs: SurfaceSourceSummaryResult.Vector,
    _ rhs: SurfaceSourceSummaryResult.Vector
) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

private func surfaceSourceLength(_ vector: SurfaceSourceSummaryResult.Vector) -> Double {
    sqrt(surfaceSourceDot(vector, vector))
}

private func surfaceSourceSummaryDirectBSplineSurface() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.015, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.015, z: 0.0)
    )
    var weights = base.weights
    weights[1][1] = 2.0
    return BSplineSurface3D(
        uDegree: base.uDegree,
        vDegree: base.vDegree,
        uKnots: base.uKnots,
        vKnots: base.vKnots,
        controlPoints: base.controlPoints,
        weights: weights
    )
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
