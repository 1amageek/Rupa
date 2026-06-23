import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func polySplineSurfaceVertexEditingServiceResolvesBoundaryVertexSourceIndex() throws {
    let service = PolySplineSurfaceVertexEditingService()
    let polySpline = PolySplineFeature(sourceMesh: polySplineEditingQuadMesh())
    let featureID = FeatureID()
    let target = PolySplineSurfaceVertexTarget(
        featureID: featureID,
        patchID: 0,
        boundaryRole: .uMaxVMin
    )

    let sourceVertexIndex = try service.sourceVertexIndex(
        for: target,
        in: polySpline,
        owner: "PolySpline surface vertex move"
    )

    #expect(sourceVertexIndex == 1)
}

@Test func polySplineSurfaceVertexEditingServiceUsesPatchHullForSlideDirections() throws {
    let service = PolySplineSurfaceVertexEditingService()
    let polySpline = PolySplineFeature(sourceMesh: polySplineEditingQuadMesh())
    let featureID = FeatureID()
    let target = PolySplineSurfaceVertexTarget(
        featureID: featureID,
        patchID: 0,
        boundaryRole: .uMaxVMin
    )

    let positiveV = try service.slideUnitVector(
        for: target,
        in: polySpline,
        direction: .positiveV
    )
    let negativeU = try service.slideUnitVector(
        for: target,
        in: polySpline,
        direction: .negativeU
    )
    let positiveVLength = sqrt((0.02 * 0.02) + (0.004 * 0.004))

    #expect(abs(positiveV.x) <= 1.0e-12)
    #expect(abs(positiveV.y - (0.02 / positiveVLength)) <= 1.0e-12)
    #expect(abs(positiveV.z - (0.004 / positiveVLength)) <= 1.0e-12)
    #expect(abs(negativeU.x + 1.0) <= 1.0e-12)
    #expect(abs(negativeU.y) <= 1.0e-12)
    #expect(abs(negativeU.z) <= 1.0e-12)
}

private func polySplineEditingQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.004),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}
