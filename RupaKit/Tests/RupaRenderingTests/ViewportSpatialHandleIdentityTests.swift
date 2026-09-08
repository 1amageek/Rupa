import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func spatialHandleIdentityPreservesOperationRoleWithoutGeometryPayload() throws {
    let featureID = FeatureID()
    let subshapeID = SubshapeID(featureID: featureID, role: "surface", ordinal: 0)
    func reference(point: SwiftCAD.Point3D, uIndex: Int) -> SelectionReference {
        .surface(.controlPoint(.init(surface: .init(subshape: .init(
            subshapeID: subshapeID, geometrySignature: .vertex(point: point))), uIndex: uIndex, vIndex: 2)))
    }
    var target = ViewportSurfaceControlPointHandleTarget(
        featureID: featureID, target: reference(point: .origin, uIndex: 1),
        point: .origin, modelTransform: .identity, dragMode: .planar)
    let planar = try ViewportInteractionTarget.surfaceControlPoint(target).spatialIdentity
    target.target = reference(point: .init(x: 10, y: 20, z: 30), uIndex: 1)
    target.point = .init(x: 4, y: 5, z: 6)
    #expect(try ViewportInteractionTarget.surfaceControlPoint(target).spatialIdentity == planar)
    target.dragMode = .axis(.x)
    let xAxis = try ViewportInteractionTarget.surfaceControlPoint(target).spatialIdentity
    #expect(xAxis != planar)
    target.dragMode = .localAxis(.u, direction: .unitX)
    let localU = try ViewportInteractionTarget.surfaceControlPoint(target).spatialIdentity
    #expect(localU != xAxis)
    target.dragMode = .localAxis(.u, direction: .unitZ)
    #expect(try ViewportInteractionTarget.surfaceControlPoint(target).spatialIdentity == localU)
    target.target = reference(point: .origin, uIndex: 3)
    #expect(try ViewportInteractionTarget.surfaceControlPoint(target).spatialIdentity != localU)

    target.target = reference(point: .origin, uIndex: 1)
    var table: [ViewportSpatialInteractionRecord] = []
    for role: ViewportPolySplineSurfaceVertexDragMode in [.planar, .axis(.x), .localAxis(.u, direction: .unitX)] {
        target.dragMode = role
        _ = try ViewportSpatialOverlayProducer.handleIndex(for: .surfaceControlPoint(target), in: &table)
    }
    #expect(try ViewportSpatialOverlayProducer.handleIndex(for: planar, in: table) == 0)
    #expect(table.map(\.identity) == [planar, xAxis, localU])
    let input = ViewportSpatialOverlayInput(
        interactionRecords: table, renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 1)
    let output = try ViewportSpatialOverlayProducer.makeBuilder(from: input)(.origin, 0)
    #expect(output.interactionRecords.map(\.identity) == table.map(\.identity))
    #expect(output.spatialBatch.handleCount == 3)
    #expect(output.spatialBatch.retainedSemanticByteCount == (try ViewportSpatialInteractionRecord.retainedByteCount(for: table)))
}

@Test func spatialHandleIdentityAdmitsVariableLengthIDsBeforeNativePreparation() throws {
    let value = ViewportSpatialHandleIdentity.polySplineSurfaceVertex(
        featureID: FeatureID(), componentID: .init(rawValue: String(repeating: "a", count: 4_096)), role: .planar)
    let limits = MeshSourcePresentationPlanLimits(maxItemCount: 10, maxPositionCount: 100,
                                                 maxTriangleCount: 100, maxRetainedByteCount: 2_048)
    do {
        _ = try ViewportSpatialHandleIdentity.retainedByteCount(for: [value], limits: limits)
        Issue.record("Variable-length handle identity escaped admission.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    }
    let reference = SelectionReference.sketchPoint(.init(featureID: FeatureID(), entityID: SketchEntityID()))
    let oversized = Array(repeating: reference, count: MeshSourcePresentationPlanLimits.standard.maxPositionCount + 1)
    do {
        _ = try ViewportSpatialReferenceAddress.project(oversized)
        Issue.record("An oversized group was copied before identity admission.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    }
}

@Test func nativeHandleTableChargeUsesTheAggregateAdmission() throws {
    let empty = try RealityViewportSpatialBatch(renderOrigin: .origin, retainedSurfaceByteCount: 0)
    let charged = try RealityViewportSpatialBatch(retainedSemanticByteCount: 512,
                                                 renderOrigin: .origin, retainedSurfaceByteCount: 0)
    #expect(charged.admittedByteCount == empty.admittedByteCount + 512)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try RealityViewportSpatialBatch(retainedSemanticByteCount: -1,
                                        renderOrigin: .origin, retainedSurfaceByteCount: 0)
    }
    do {
        _ = try RealityViewportSpatialBatch(retainedSemanticByteCount: MeshSourcePresentationPlanLimits.standard.maxRetainedByteCount + 1,
                                            renderOrigin: .origin, retainedSurfaceByteCount: 0)
        Issue.record("An over-budget identity table was admitted.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    }
}
