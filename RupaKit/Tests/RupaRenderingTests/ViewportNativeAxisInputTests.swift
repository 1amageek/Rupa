import Foundation
import RupaCore
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test
func nativeAxisInputMapsAllEightRoutesAndRetainsWorldAxis() throws {
    let axis = ViewportSpatialPreparedInteractionTarget.Axis(
        origin: .init(x: 2, y: 3, z: 4),
        direction: .init(x: 0, y: 0, z: 2),
        baseValue: 0.25
    )
    let targets: [ViewportSpatialPreparedInteractionTarget] = [
        .splineControlPointSlide(
            featureID: .init(), entityID: .init(), target: .init(sceneNodeID: .init(), component: .object),
            controlPointIndexes: [1, 3], direction: .positiveU, axis: axis
        ),
        .polySplineSurfaceVertexSlide(
            targets: [.init(sceneNodeID: .init(), component: .object)], direction: .positiveU, axis: axis
        ),
        .surfaceControlPointSlide(
            targets: [], direction: .positiveV, axis: axis
        ),
        .surfaceFrame(
            targets: [], query: .init(), displayID: .init(rawValue: "surface-frame"), axis: .u, geometry: axis
        ),
        .regionOffset(
            featureID: .init(), componentID: SelectionComponentID(rawValue: "test-component"),
            target: .init(sceneNodeID: .init(), component: .object), axis: axis
        ),
        .edgeOffset(
            featureID: .init(), edge: .leftBottom,
            target: .init(sceneNodeID: .init(), component: .object),
            edgeStart: .origin, edgeEnd: .init(x: 1, y: 0, z: 0), axis: axis
        ),
        .slotWidth(
            featureID: .init(), entityID: .init(),
            target: .init(sceneNodeID: .init(), component: .object), axis: axis
        ),
        .sketchVertexOffset(
            featureID: .init(), entityID: .init(),
            target: .init(sceneNodeID: .init(), component: .object),
            handle: .lineStart, axis: axis
        )
    ]

    for target in targets {
        let record = try ViewportSpatialInteractionRecord(target: target)
        let input = try #require(try ViewportNativeAxisInput(record: record))
        #expect(input.record.identity == record.identity)
        #expect(input.axis.origin == axis.origin)
        #expect(input.axis.direction == axis.direction)
        let value = try input.value(forWorldDelta: 0.5)
        #expect(value.isFinite)
        let commit = try #require(try input.commit(value: value))
        switch (target, commit) {
        case let (
            .splineControlPointSlide(_, _, target, indexes, direction, _),
            .splineControlPointSlide(payload)
        ):
            #expect(payload.target == target)
            #expect(payload.controlPointIndexes == indexes)
            #expect(payload.direction == direction)
            #expect(payload.distance == value)
        case let (
            .polySplineSurfaceVertexSlide(targets, direction, _),
            .polySplineSurfaceVertexSlide(payload)
        ):
            #expect(payload.targets == targets)
            #expect(payload.direction == direction)
            #expect(payload.distance == value)
        case let (
            .surfaceControlPointSlide(targets, direction, _),
            .surfaceControlPointSlide(payload)
        ):
            #expect(payload.targets == targets)
            #expect(payload.direction == direction)
            #expect(payload.distance == value)
        case let (
            .surfaceFrame(targets, query, _, axis, _),
            .surfaceFrame(payload)
        ):
            #expect(payload.targets == targets)
            #expect(payload.query == query)
            #expect(payload.axis == axis)
            #expect(payload.distance == value)
        case let (
            .regionOffset(_, _, target, _),
            .regionOffset(payload)
        ):
            #expect(payload.target == target)
            #expect(payload.distance == value)
        case let (
            .edgeOffset(_, _, target, _, _, _),
            .edgeOffset(payload)
        ):
            #expect(payload.target == target)
            #expect(payload.distance == value)
        case let (
            .slotWidth(_, _, target, _),
            .slotWidth(payload)
        ):
            #expect(payload.target == target)
            #expect(payload.width == value)
        case let (
            .sketchVertexOffset(_, _, target, handle, _),
            .sketchVertexOffset(payload)
        ):
            #expect(payload.target == target)
            #expect(payload.handle == handle)
            #expect(payload.distance == value)
        default:
            Issue.record("The prepared route produced the wrong callback payload.")
        }
    }
}

@Test
func nativeAxisInputAppliesRouteSpecificScalarRulesAndSuppressesUnchangedCommit() throws {
    let baseAxis = ViewportSpatialPreparedInteractionTarget.Axis(
        origin: .origin, direction: .unitX, baseValue: 2.0
    )
    let edgeTarget = ViewportSpatialPreparedInteractionTarget.edgeOffset(
        featureID: .init(), edge: .leftBottom,
        target: .init(sceneNodeID: .init(), component: .object),
        edgeStart: .origin, edgeEnd: .init(x: 1, y: 0, z: 0), axis: baseAxis
    )
    let slotTarget = ViewportSpatialPreparedInteractionTarget.slotWidth(
        featureID: .init(), entityID: .init(),
        target: .init(sceneNodeID: .init(), component: .object), axis: baseAxis
    )
    let regionTarget = ViewportSpatialPreparedInteractionTarget.regionOffset(
        featureID: .init(), componentID: SelectionComponentID(rawValue: "test-component"),
        target: .init(sceneNodeID: .init(), component: .object), axis: baseAxis
    )

    let edgeRecord = try ViewportSpatialInteractionRecord(target: edgeTarget)
    let slotRecord = try ViewportSpatialInteractionRecord(target: slotTarget)
    let regionRecord = try ViewportSpatialInteractionRecord(target: regionTarget)
    let edge = try #require(try ViewportNativeAxisInput(record: edgeRecord))
    let slot = try #require(try ViewportNativeAxisInput(record: slotRecord))
    let region = try #require(try ViewportNativeAxisInput(record: regionRecord))
    #expect(try edge.value(forWorldDelta: -3) == 1.0e-9)
    #expect(try slot.value(forWorldDelta: 0.5) == 3.0)
    #expect(try region.value(forWorldDelta: -0.5) == -0.5)
    #expect(try edge.commit(value: 2.0) == nil)
    #expect(try slot.commit(value: 2.0) == nil)
    #expect(try region.commit(value: 0.0) == nil)

    guard case .edgeOffset(let edgeCommit) = try edge.commit(value: 2.5) else {
        Issue.record("The edge-offset callback payload was not produced.")
        return
    }
    #expect(edgeCommit.distance == 2.5)
    guard case .slotWidth(let slotCommit) = try slot.commit(value: 3.0) else {
        Issue.record("The slot-width callback payload was not produced.")
        return
    }
    #expect(slotCommit.width == 3.0)
}

@Test
func nativeAxisInputRejectsInvalidAxesAndNonAxisRecords() throws {
    let invalidAxis = ViewportSpatialPreparedInteractionTarget.Axis(
        origin: .origin, direction: .zero, baseValue: 1
    )
    let invalidTarget = ViewportSpatialPreparedInteractionTarget.regionOffset(
        featureID: .init(), componentID: SelectionComponentID(rawValue: "test-component"),
        target: .init(sceneNodeID: .init(), component: .object), axis: invalidAxis
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativeAxisInput(record: ViewportSpatialInteractionRecord(target: invalidTarget))
    }

    let featureID = FeatureID()
    let reference = SelectionReference.surface(.controlPoint(.init(
        surface: .init(subshape: .init(subshapeID: .init(featureID: featureID, role: "surface", ordinal: 0),
                                      geometrySignature: .vertex(point: .origin))), uIndex: 1, vIndex: 2)))
    let nonAxis = ViewportSpatialPreparedInteractionTarget.surfaceControlPoint(
        .init(featureID: featureID, target: reference,
              point: .origin, modelTransform: .identity, dragMode: .planar)
    )
    let record = try ViewportSpatialInteractionRecord(target: nonAxis)
    #expect(try ViewportNativeAxisInput(record: record) == nil)
}

@Test
func nativeAxisInputConvertsWorldDeltaToSourceUnitsUsingRecordTransform() throws {
    let axis = ViewportSpatialPreparedInteractionTarget.Axis(
        origin: .origin, direction: .unitX, baseValue: 2.0
    )
    let target = ViewportSpatialPreparedInteractionTarget.edgeOffset(
        featureID: .init(), edge: .leftBottom,
        target: .init(sceneNodeID: .init(), component: .object),
        edgeStart: .origin, edgeEnd: .init(x: 1, y: 0, z: 0), axis: axis
    )
    let transform = try Transform3D(matrix: Matrix4x4(values: [
        2.0, 0.0, 0.0, 0.0,
        0.0, 2.0, 0.0, 0.0,
        0.0, 0.0, 2.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]))
    let record = try ViewportSpatialInteractionRecord(target: target, modelTransform: transform)
    let input = try #require(try ViewportNativeAxisInput(record: record))
    #expect(abs(input.sourceUnitsPerWorldMetre - 0.5) < 1.0e-12)
    #expect(abs(try input.value(forWorldDelta: 1.0) - 2.5) < 1.0e-12)
}

@Test
func nativeAxisInputRejectsIncompatibleGroupedSourceScales() throws {
    let scale2 = try Transform3D(matrix: Matrix4x4(values: [
        2.0, 0.0, 0.0, 0.0,
        0.0, 2.0, 0.0, 0.0,
        0.0, 0.0, 2.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]))
    let scale3 = try Transform3D(matrix: Matrix4x4(values: [
        3.0, 0.0, 0.0, 0.0,
        0.0, 3.0, 0.0, 0.0,
        0.0, 0.0, 3.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativeAxisInput.commonSourceScale([scale2, scale3].map {
            try ViewportNativeAxisInput.sourceUnitsPerWorldMetre(for: .unitX, in: $0)
        })
    }
}

@Test
func nativeAxisInputPreservesCorrespondingRotatedGroupMetric() throws {
    let first = try Transform3D(matrix: Matrix4x4(values: [
        2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
    ]))
    let second = try Transform3D(matrix: Matrix4x4(values: [
        0, -1, 0, 0, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
    ]))
    let factors = try [first, second].map { transform in
        try ViewportNativeAxisInput.sourceUnitsPerWorldMetre(
            for: transform.viewportTransformedVector(.unitX), in: transform
        )
    }
    let factor = try ViewportNativeAxisInput.commonSourceScale(factors)
    #expect(abs(factor - 0.5) < 1e-12)
    let record = try ViewportSpatialInteractionRecord(target: .surfaceControlPointSlide(
        targets: [], direction: .positiveU,
        axis: .init(origin: .origin, direction: .init(x: 1, y: 1, z: 0),
                    baseValue: 0, sourceUnitsPerWorldMetre: factor)
    ))
    let input = try #require(try ViewportNativeAxisInput(record: record))
    #expect(abs(try input.value(forWorldDelta: 1) - 0.5) < 1e-12)
}
