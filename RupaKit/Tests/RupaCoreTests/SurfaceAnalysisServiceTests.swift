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
        .analyze(document: document)

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
        .analyze(document: document)
    let high = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .high))
        .analyze(document: document)

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
    let topology = try TopologySummaryService().summarize(document: document)
    let faceEntry = try #require(topology.entries.first { $0.kind == .face })

    let result = try SurfaceFrameService().resolve(
        document: document,
        queries: [
            SurfaceFrameQuery(
                facePersistentName: faceEntry.persistentName,
                u: 0.5,
                v: 0.5
            ),
        ]
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
