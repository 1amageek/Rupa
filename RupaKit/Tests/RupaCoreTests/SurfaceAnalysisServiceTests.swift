import Foundation
import Testing
import RupaCore
import SwiftCAD

@Test func surfaceAnalysisServiceSamplesPlanarUnmergedPolySplinePatchNetwork() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Planar Surface Analysis",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let result = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .standard))
        .analyze(document: document, displayUnit: .millimeter)

    #expect(result.counts.bSplineFaceCount == 2)
    #expect(result.counts.sampleCount == 50)
    #expect(result.counts.uCurvatureCombCount == 50)
    #expect(result.counts.vCurvatureCombCount == 50)
    #expect(result.counts.trimBoundaryCount == 2)
    #expect(result.counts.innerTrimBoundaryCount == 0)
    #expect(result.counts.openTrimBoundaryCount == 0)
    #expect(result.counts.trimBoundaryEdgeCount == 8)
    #expect(result.faces.count == 2)
    let firstFace = try #require(result.faces.first)
    #expect(firstFace.uDegree == 3)
    #expect(firstFace.vDegree == 3)
    #expect(firstFace.uControlPointCount == 4)
    #expect(firstFace.vControlPointCount == 4)
    #expect(firstFace.samples.count == 25)
    #expect(firstFace.curvatureCombs.count == 50)
    #expect(firstFace.maxUNormalChangePerLength <= 1.0e-8)
    #expect(firstFace.maxVNormalChangePerLength <= 1.0e-8)
    #expect(firstFace.maxNormalAngle <= ModelingTolerance.standard.angle)
    #expect(firstFace.maxAbsUNormalCurvature <= 1.0e-8)
    #expect(firstFace.maxAbsVNormalCurvature <= 1.0e-8)
    #expect(firstFace.maxAbsPrincipalCurvature <= 1.0e-8)
    #expect(firstFace.maxAbsGaussianCurvature <= 1.0e-8)
    let sample = try #require(firstFace.samples.first)
    #expect(abs(sample.normalCurvatureU) <= 1.0e-8)
    #expect(abs(sample.normalCurvatureV) <= 1.0e-8)
    #expect(abs(sample.meanCurvature) <= 1.0e-8)
    #expect(abs(sample.gaussianCurvature) <= 1.0e-8)
    #expect(abs(sample.minimumPrincipalCurvature) <= 1.0e-8)
    #expect(abs(sample.maximumPrincipalCurvature) <= 1.0e-8)
    #expect(abs(vectorLength(sample.minimumPrincipalDirection) - 1.0) <= 1.0e-8)
    #expect(abs(vectorLength(sample.maximumPrincipalDirection) - 1.0) <= 1.0e-8)
    #expect(firstFace.facePersistentNames.contains { $0.contains("subshape:patch") })
    #expect(firstFace.edgePersistentNames.contains { $0.contains("subshape:patch") })
    #expect(firstFace.trimBoundaries.count == 1)
    let trimBoundary = try #require(firstFace.trimBoundaries.first)
    #expect(trimBoundary.role == .outer)
    #expect(trimBoundary.edgeCount == 4)
    #expect(trimBoundary.vertexCount == 4)
    #expect(trimBoundary.points.count == 4)
    #expect(trimBoundary.isClosed)
    #expect(trimBoundary.estimatedLength > 0.0)
    #expect(trimBoundary.edgePersistentNames.contains { $0.contains("subshape:patch") })
    #expect(trimBoundary.points.contains { abs($0.x - 0.0) <= 1.0e-12 && abs($0.y - 0.0) <= 1.0e-12 })
    #expect(!result.diagnostics.contains { $0.severity == .warning })
}

@Test func surfaceAnalysisServiceRespectsSampleDensityOptions() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Density Surface Analysis",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let low = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .low))
        .analyze(document: document, displayUnit: .millimeter)
    let high = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .high))
        .analyze(document: document, displayUnit: .millimeter)

    #expect(low.counts.bSplineFaceCount == 2)
    #expect(low.counts.sampleCount == 18)
    #expect(low.counts.uCurvatureCombCount == 18)
    #expect(low.counts.vCurvatureCombCount == 18)
    #expect(low.counts.trimBoundaryCount == 2)
    #expect(low.counts.trimBoundaryEdgeCount == 8)
    #expect(low.faces.allSatisfy { $0.samples.count == 9 })
    #expect(low.faces.allSatisfy { $0.curvatureCombs.count == 18 })
    #expect(low.faces.allSatisfy { $0.trimBoundaries.count == 1 })

    #expect(high.counts.bSplineFaceCount == 2)
    #expect(high.counts.sampleCount == 162)
    #expect(high.counts.uCurvatureCombCount == 162)
    #expect(high.counts.vCurvatureCombCount == 162)
    #expect(high.counts.trimBoundaryCount == 2)
    #expect(high.counts.trimBoundaryEdgeCount == 8)
    #expect(high.faces.allSatisfy { $0.samples.count == 81 })
    #expect(high.faces.allSatisfy { $0.curvatureCombs.count == 162 })
    #expect(high.faces.allSatisfy { $0.trimBoundaries.count == 1 })
}

@Test func surfaceFrameServiceResolvesOrientedUVNFrameByPersistentName() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Frame Surface Analysis",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let topology = try TopologySnapshotService().snapshot(document: document)
    let faceEntry = try #require(topology.entries.first { $0.kind == .face })

    let result = try SurfaceFrameService().resolve(
        document: document,
        queries: [
            SurfaceFrameQuery(
                facePersistentName: faceEntry.persistentName,
                u: 0.5,
                v: 0.5
            ),
        ],
        displayUnit: .millimeter
    )

    #expect(result.frames.count == 1)
    let frame = try #require(result.frames.first)
    #expect(frame.facePersistentNames.contains(faceEntry.persistentName))
    #expect(frame.u == 0.5)
    #expect(frame.v == 0.5)
    #expect(frame.uDomain.lowerBound == 0.0)
    #expect(frame.uDomain.upperBound == 1.0)
    #expect(frame.vDomain.lowerBound == 0.0)
    #expect(frame.vDomain.upperBound == 1.0)
    #expect(abs(vectorLength(frame.uAxis) - 1.0) <= 1.0e-8)
    #expect(abs(vectorLength(frame.vAxis) - 1.0) <= 1.0e-8)
    #expect(abs(vectorLength(frame.normal) - 1.0) <= 1.0e-8)
    #expect(abs(dot(cross(frame.uAxis, frame.vAxis), frame.normal) - 1.0) <= 1.0e-8)
    #expect(frame.handedness > 0.999_999)
    #expect(abs(frame.normalCurvatureU) <= 1.0e-8)
    #expect(abs(frame.normalCurvatureV) <= 1.0e-8)
    #expect(!result.diagnostics.contains { $0.severity == .warning })
}

@Test func surfaceFrameServiceResolvesFrameFromFaceSelectionReference() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Frame Face Selection Surface",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let source = try #require(surfaceSummary.sources.first)
    let patch = try #require(source.patches.first)
    let faceSelectionReference = try #require(patch.faceSelectionReference)
    let facePersistentName = try #require(patch.facePersistentName)

    let result = try SurfaceFrameService().resolve(
        document: document,
        queries: [
            SurfaceFrameQuery(
                selectionReference: faceSelectionReference,
                u: 0.25,
                v: 0.75
            ),
        ],
        displayUnit: .millimeter
    )

    let frame = try #require(result.frames.first)
    #expect(frame.facePersistentNames.contains(facePersistentName))
    #expect(abs(frame.u - 0.25) <= 1.0e-12)
    #expect(abs(frame.v - 0.75) <= 1.0e-12)
    #expect(abs(vectorLength(frame.uAxis) - 1.0) <= 1.0e-8)
    #expect(abs(vectorLength(frame.vAxis) - 1.0) <= 1.0e-8)
    #expect(abs(dot(cross(frame.uAxis, frame.vAxis), frame.normal) - 1.0) <= 1.0e-8)
}

@Test func surfaceFrameServiceResolvesFrameFromSurfaceParameterSelectionReference() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Frame Parameter Selection Surface",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let source = try #require(surfaceSummary.sources.first)
    let patch = try #require(source.patches.first)
    let facePersistentName = try #require(patch.facePersistentName)
    let surfaceReference = try #require(patch.faceSelectionReference)
    guard case .surface(.whole(let wholeSurfaceReference)) = surfaceReference else {
        Issue.record("Expected a whole surface selection reference.")
        return
    }

    let result = try SurfaceFrameService().resolve(
        document: document,
        queries: [
            SurfaceFrameQuery(
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: wholeSurfaceReference,
                    u: 0.25,
                    v: 0.75
                )))
            ),
        ],
        displayUnit: .millimeter
    )

    let frame = try #require(result.frames.first)
    #expect(frame.facePersistentNames.contains(facePersistentName))
    #expect(abs(frame.u - 0.25) <= 1.0e-12)
    #expect(abs(frame.v - 0.75) <= 1.0e-12)
    #expect(abs(vectorLength(frame.normal) - 1.0) <= 1.0e-8)
}

@Test func surfaceFrameServiceResolvesGrevilleFrameFromSurfaceControlPointReference() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Frame Surface CV Selection Surface",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let source = try #require(surfaceSummary.sources.first)
    let patch = try #require(source.patches.first)
    let facePersistentName = try #require(patch.facePersistentName)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })

    let result = try SurfaceFrameService().resolve(
        document: document,
        queries: [
            SurfaceFrameQuery(selectionReference: controlPoint.selectionReference),
        ],
        displayUnit: .millimeter
    )

    let frame = try #require(result.frames.first)
    #expect(frame.facePersistentNames.contains(facePersistentName))
    #expect(abs(frame.u - (2.0 / 3.0)) <= 1.0e-12)
    #expect(abs(frame.v - (1.0 / 3.0)) <= 1.0e-12)
    #expect(abs(vectorLength(frame.uAxis) - 1.0) <= 1.0e-8)
    #expect(abs(vectorLength(frame.vAxis) - 1.0) <= 1.0e-8)
    #expect(abs(dot(cross(frame.uAxis, frame.vAxis), frame.normal) - 1.0) <= 1.0e-8)
}

@Test func surfaceFrameServiceResolvesFrameFromTrimParameterCurveReferences() async throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Frame Trim Parameter Surface",
        surface: surfaceAnalysisDirectBSplineSurface()
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [surfaceAnalysisAuthoredTrimLoop()]
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let trimEdge = try #require(summary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let spanSelection = try #require(trimEdge.parameterCurve.spans.first?.selectionReference)
    let knotSelection = try #require(trimEdge.parameterCurve.knotVector.first?.selectionReference)
    let result = try SurfaceFrameService().resolve(
        document: document,
        queries: [
            SurfaceFrameQuery(selectionReference: spanSelection),
            SurfaceFrameQuery(selectionReference: knotSelection),
        ],
        displayUnit: .millimeter
    )

    #expect(result.frames.count == 2)
    let spanFrame = try #require(result.frames.first)
    let knotFrame = try #require(result.frames.dropFirst().first)
    #expect(abs(spanFrame.u - 0.51) <= 1.0e-12)
    #expect(abs(spanFrame.v - 0.3225) <= 1.0e-12)
    #expect(abs(knotFrame.u - 0.2) <= 1.0e-12)
    #expect(abs(knotFrame.v - 0.2) <= 1.0e-12)
    #expect(abs(vectorLength(spanFrame.uAxis) - 1.0) <= 1.0e-8)
    #expect(abs(vectorLength(spanFrame.vAxis) - 1.0) <= 1.0e-8)
    #expect(abs(dot(cross(spanFrame.uAxis, spanFrame.vAxis), spanFrame.normal) - 1.0) <= 1.0e-8)
    _ = try SurfaceFrameDisplayID(query: SurfaceFrameQuery(selectionReference: spanSelection))
    _ = try SurfaceFrameDisplayID(query: SurfaceFrameQuery(selectionReference: knotSelection))
}

@Test func surfaceFrameServiceRejectsAmbiguousSurfaceParameterInput() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Frame Ambiguous Parameter Surface",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let source = try #require(surfaceSummary.sources.first)
    let patch = try #require(source.patches.first)
    let surfaceReference = try #require(patch.faceSelectionReference)
    guard case .surface(.whole(let wholeSurfaceReference)) = surfaceReference else {
        Issue.record("Expected a whole surface selection reference.")
        return
    }

    #expect(throws: EditorError.self) {
        try SurfaceFrameService().resolve(
            document: document,
            queries: [
                SurfaceFrameQuery(
                    selectionReference: .surface(.parameter(SurfaceParameterReference(
                        surface: wholeSurfaceReference,
                        u: 0.25,
                        v: 0.75
                    ))),
                    u: 0.5,
                    v: 0.5
                ),
            ],
            displayUnit: .millimeter
        )
    }
}

@Test func surfaceFrameServiceRejectsTrimSelectionReferences() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Frame Trim Rejection Surface",
        sourceMesh: surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let source = try #require(surfaceSummary.sources.first)
    let patch = try #require(source.patches.first)
    let trimLoop = try #require(patch.trimLoops.first)
    let trimReference = try #require(trimLoop.selectionReferences.first)

    #expect(throws: EditorError.self) {
        try SurfaceFrameService().resolve(
            document: document,
            queries: [
                SurfaceFrameQuery(selectionReference: trimReference),
            ],
            displayUnit: .millimeter
        )
    }
}

private func vectorLength(_ vector: SurfaceAnalysisResult.Vector) -> Double {
    hypot(hypot(vector.x, vector.y), vector.z)
}

private func dot(
    _ lhs: SurfaceAnalysisResult.Vector,
    _ rhs: SurfaceAnalysisResult.Vector
) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

private func cross(
    _ lhs: SurfaceAnalysisResult.Vector,
    _ rhs: SurfaceAnalysisResult.Vector
) -> SurfaceAnalysisResult.Vector {
    SurfaceAnalysisResult.Vector(
        x: lhs.y * rhs.z - lhs.z * rhs.y,
        y: lhs.z * rhs.x - lhs.x * rhs.z,
        z: lhs.x * rhs.y - lhs.y * rhs.x
    )
}

private func surfaceAnalysisPolySplinePatchNetworkMesh(centerZ: Double) -> Mesh {
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

private func surfaceAnalysisDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
        topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
    )
}

private func surfaceAnalysisAuthoredTrimLoop() -> BSplineSurfaceTrimLoop {
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
    )
}
