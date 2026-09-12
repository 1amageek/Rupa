import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test @MainActor
func materializationUsesCurveLengthAndRequestedExtent() throws {
    let points: [Point3D] = [.origin, .init(x: 1, y: 0, z: 0), .init(x: 1, y: 0, z: 3)]
    let extent = ViewportSpatialPreparedInteractionTarget.patternArrayCurveExtent(.init(
        sourceID: .init(), title: "Extent", pathPoints: points, distanceMeters: 2,
        displayDistanceMeters: nil, extentMode: .distance, state: .normal))
    let input = try extent.materialize { CGPoint(x: $0.x * 10, y: $0.z * 10) }
    guard case .patternArrayCurveExtent(_, let projection) = input else {
        Issue.record("Missing curve extent input"); return
    }
    #expect(projection.totalLengthMeters == 4)
    #expect(projection.baseDistanceMeters == 2)
    #expect(projection.distanceSamplesMeters == [0, 1, 4])
    #expect(projection.projectedPathPoints.count == projection.distanceSamplesMeters.count)
    let copies = ViewportSpatialPreparedInteractionTarget.patternArrayCopyCount(.init(
        sourceID: .init(), slot: .curve, title: "Copies",
        guide: .curve(pathPoints: points, extentDistanceMeters: 2),
        copyCount: 4, displayCopyCount: nil, state: .normal))
    let copyInput = try copies.materialize { CGPoint(x: $0.x * 10, y: $0.z * 10) }
    guard case .patternArrayCopyCountCurve(_, let copy) = copyInput else {
        Issue.record("Missing curve copy input"); return
    }
    #expect(copy.anchorPoint == CGPoint(x: -14, y: 10))
    #expect(copy.projectedDirection == CGVector(dx: 0, dy: 1))
}

@Test @MainActor
func materializationRejectsCollinearAngularBasis() throws {
    let source = ViewportPatternAffordanceSource.CopyCountHandle(
        sourceID: .init(), slot: .radialAngular, title: "Copies",
        guide: .radial(center: .origin, axis: .unitY, referencePoint: .init(x: 1, y: 0, z: 0),
                       angleRadians: 0.5, angleMode: .spacing),
        copyCount: 4, displayCopyCount: nil, state: .normal)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialPreparedInteractionTarget.patternArrayCopyCount(source).materialize {
            CGPoint(x: $0.x + $0.z, y: 0)
        }
    }
}

@Test @MainActor
func materializationKeepsProjectionFreeBodyBaselineAndOccurrences() throws {
    let featureID = FeatureID()
    let first = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
        occurrenceID: "body.first", featureID: featureID, sceneNodeID: .init(),
        modelTransform: .identity,
        edit: .init(xMin: 0, xMax: 1, yMin: 0, yMax: 1, zMin: 0, zMax: 1)
    )
    let second = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
        occurrenceID: "body.second", featureID: featureID, sceneNodeID: .init(),
        modelTransform: .identity,
        edit: .init(xMin: 2, xMax: 3, yMin: 0, yMax: 1, zMin: 0, zMax: 1)
    )
    let target = ViewportSpatialPreparedInteractionTarget.affordance(
        target: .init(featureID: featureID, action: .translate(.x)),
        members: [first, second],
        groupEdit: .init(xMin: 0, xMax: 3, yMin: 0, yMax: 1, zMin: 0, zMax: 1)
    )

    let record = try ViewportSpatialInteractionRecord(target: target)
    let materialized = try record.materialize { point in
        CGPoint(x: point.x, y: point.z)
    }
    guard case .projectionFree(.affordance(_, let members, let groupEdit)) = materialized else {
        Issue.record("The projection-free body route was not retained.")
        return
    }
    #expect(members.map(\.occurrenceID) == ["body.first", "body.second"])
    #expect(groupEdit?.xMax == 3)
}

@Test @MainActor
func materializationBuildsRadialProjectionFromNativeSamples() throws {
    let source = ViewportPatternAffordanceSource.RadialAngleHandle(
        sourceID: .init(), title: "Angle", center: .origin, axis: .unitY,
        referencePoint: .init(x: 2, y: 0, z: 0), angleRadians: 0.2,
        displayAngleRadians: nil, angleMode: .spacing, state: .normal
    )
    var projectedPoints: [Point3D] = []
    let target = ViewportSpatialPreparedInteractionTarget.patternArrayRadialAngle(source)
    let materialized = try target.materialize { point in
        projectedPoints.append(point)
        return CGPoint(x: point.x * 10, y: point.z * 10)
    }
    guard case .patternArrayRadialAngle(_, let projection) = materialized else {
        Issue.record("The radial route did not produce a closed projected input.")
        return
    }
    #expect(projectedPoints.count == 3)
    #expect(projection.center == .zero)
    #expect(abs(projection.radialVector.dx - 20) < 1.0e-9)
    #expect(abs(projection.radialVector.dy) < 1.0e-9)
    #expect(abs(projection.tangentVector.dx) < 1.0e-9)
    #expect(abs(projection.tangentVector.dy + 20) < 1.0e-9)
    #expect(projection.baseAngleRadians == 0.2)
    #expect(projection.minimumAngleRadians > 0)
}

@Test @MainActor
func materializationBuildsAngularDensityWithoutRetainingLayout() throws {
    let source = ViewportPatternAffordanceSource.CopyCountHandle(
        sourceID: .init(), slot: .radialAngular, title: "Density",
        guide: .radial(
            center: .origin, axis: .unitY,
            referencePoint: .init(x: 2, y: 0, z: 0),
            angleRadians: .pi / 2, angleMode: .extent
        ),
        copyCount: 4, displayCopyCount: nil, state: .normal
    )
    let target = ViewportSpatialPreparedInteractionTarget.patternArrayCopyCount(source)
    let materialized = try target.materialize { point in
        CGPoint(x: point.x * 20, y: point.z * 20)
    }
    guard case .patternArrayCopyCountAngularDensity(_, let projection) = materialized else {
        Issue.record("The angular-density route did not produce a closed input.")
        return
    }
    #expect(projection.baseCopyCount == 4)
    #expect(projection.pointsPerCopy == 28)
    #expect(projection.anchorPoint.x.isFinite)
    #expect(projection.anchorPoint.y.isFinite)
    #expect(projection.projectedDirection.dx.isFinite)
    #expect(projection.projectedDirection.dy.isFinite)
}

@Test @MainActor
func materializationRejectsDegenerateOrNonfiniteNativeProjection() throws {
    let source = ViewportPatternAffordanceSource.RadialAngleHandle(
        sourceID: .init(), title: "Angle", center: .origin, axis: .unitY,
        referencePoint: .init(x: 1, y: 0, z: 0), angleRadians: 0.4,
        displayAngleRadians: nil, angleMode: .spacing, state: .normal
    )
    let target = ViewportSpatialPreparedInteractionTarget.patternArrayRadialAngle(source)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try target.materialize { _ in .zero }
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try target.materialize { _ in CGPoint(x: CGFloat.nan, y: 0) }
    }
}

@Test @MainActor
func materializationLeavesAxisOwnedRoutesProjectionFree() throws {
    let linear = ViewportSpatialPreparedInteractionTarget.patternArrayLinearAxis(.init(
        sourceID: .init(), axisSlot: .first, title: "Axis",
        basePoint: .origin, direction: .unitX, distanceMeters: 0.5,
        displayDistanceMeters: nil, distanceMode: .spacing, state: .normal
    ))
    var projectedPoints: [Point3D] = []
    let materialized = try linear.materialize { point in
        projectedPoints.append(point)
        return CGPoint(x: point.x * 100, y: point.z * 100)
    }
    guard case .projectionFree(.patternArrayLinearAxis) = materialized else {
        Issue.record("The axis-owned linear route must not be answered by the materialized owner.")
        return
    }
    #expect(projectedPoints.isEmpty)
}

@Test @MainActor
func materializationRefusesCollinearRadialBasisAtPress() throws {
    let source = ViewportPatternAffordanceSource.RadialAngleHandle(
        sourceID: .init(), title: "Angle", center: .origin, axis: .unitY,
        referencePoint: .init(x: 2, y: 0, z: 0), angleRadians: 0.2,
        displayAngleRadians: nil, angleMode: .spacing, state: .normal
    )
    let target = ViewportSpatialPreparedInteractionTarget.patternArrayRadialAngle(source)
    // This camera collapses the radial and tangent samples onto one screen line,
    // which cannot recover a rotation about the CAD axis.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try target.materialize { CGPoint(x: $0.x + $0.z, y: 0) }
    }
}
