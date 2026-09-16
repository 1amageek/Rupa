import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func spatialInteractionRecordRetainsBaselineAndRejectsDuplicateAuthority() throws {
    let featureID = FeatureID()
    let reference = SelectionReference.surface(.controlPoint(.init(
        surface: .init(subshape: .init(subshapeID: .init(featureID: featureID, role: "surface", ordinal: 0),
                                      geometrySignature: .vertex(point: .origin))), uIndex: 1, vIndex: 2)))
    var target = ViewportSurfaceControlPointHandleTarget(featureID: featureID, target: reference,
        point: .init(x: 1, y: 2, z: 3), modelTransform: .identity, dragMode: .planar)
    var table: [ViewportSpatialInteractionRecord] = []
    let index = try ViewportSpatialOverlayProducer.handleIndex(for: .surfaceControlPoint(target), in: &table)
    #expect(index == 0)
    let identity = table[0].identity
    target.point = .init(x: 10, y: 20, z: 30)
    if case .surfaceControlPoint(let retained) = table[0].target {
        #expect(retained.point == .init(x: 1, y: 2, z: 3))
        #expect(retained.target == reference)
    } else { Issue.record("The prepared operation changed its route.") }
    #expect(try ViewportSpatialOverlayProducer.handleIndex(for: identity, in: table) == index)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.handleIndex(for: .surfaceControlPoint(target), in: &table)
    }
    #expect(table.count == 1)
    target.dragMode = .axis(.x)
    #expect(try ViewportSpatialOverlayProducer.handleIndex(for: .surfaceControlPoint(target), in: &table) == 1)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.handleIndex(
            for: .surfaceControlPoint(.init(reference), role: .axis(.y)), in: table)
    }
}

@Test func spatialInteractionRecordRetainsWorldCurveWithoutProjectedGeometry() throws {
    var points: [RupaCore.Point3D] = [.origin, .init(x: 2, y: 3, z: 4)]
    let target = ViewportPatternAffordanceSource.CurveExtentHandle(
        sourceID: .init(), title: "Extent", pathPoints: points,
        distanceMeters: 2, displayDistanceMeters: 3, extentMode: .distance, state: .normal)
    let record = try ViewportSpatialInteractionRecord(target: .patternArrayCurveExtent(target))
    points[1] = .init(x: 10, y: 10, z: 10)
    if case .patternArrayCurveExtent(let retained) = record.target {
        #expect(retained.pathPoints[1] == .init(x: 2, y: 3, z: 4))
        #expect(retained.distanceMeters == 2)
        #expect(retained.displayDistanceMeters == 3)
    } else { Issue.record("The world-space curve baseline was lost.") }
    #expect(record.identity == .patternArrayCurveExtent(.init(sourceID: target.sourceID)))
}

@Test func spatialInteractionRecordSeparatesOccurrenceAuthority() throws {
    let featureID = FeatureID()
    let target = recordTestBody(featureID: featureID, occurrenceID: "source.first")
    var table: [ViewportSpatialInteractionRecord] = []
    let first = try ViewportSpatialOverlayProducer.handleIndex(
        for: target, occurrenceID: "source.first", in: &table
    )
    let second = try ViewportSpatialOverlayProducer.handleIndex(
        for: recordTestBody(featureID: featureID, occurrenceID: "source.second"),
        occurrenceID: "source.second", in: &table
    )
    #expect(first != second)
    #expect(table[Int(first)].identity == table[Int(second)].identity)
    #expect(try ViewportSpatialOverlayProducer.handleIndex(
        for: target.spatialIdentity, occurrenceID: "source.second", in: table
    ) == second)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.handleIndex(for: target.spatialIdentity, in: table)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.handleIndex(
            for: target, occurrenceID: "source.first", in: &table
        )
    }
    #expect(table.count == 2)
}

@Test func spatialInteractionRecordAdmitsOwnedPayloadAndCapacity() throws {
    let points: [RupaCore.Point3D] = Array(repeating: .origin, count: 32)
    let target = ViewportPatternAffordanceSource.CurveExtentHandle(
        sourceID: .init(), title: String(repeating: "a", count: 256), pathPoints: points,
        distanceMeters: 2, displayDistanceMeters: nil, extentMode: .distance, state: .normal)
    let table = [try ViewportSpatialInteractionRecord(target: .patternArrayCurveExtent(target))]
    let bytes = try ViewportSpatialInteractionRecord.retainedByteCount(for: table)
    #expect(bytes >= MemoryLayout<ViewportSpatialInteractionRecord>.stride + points.capacity * MemoryLayout<RupaCore.Point3D>.stride)
    func limits(bytes: Int, positions: Int = 32) -> MeshSourcePresentationPlanLimits {
        .init(maxItemCount: 1, maxPositionCount: positions, maxTriangleCount: 0, maxRetainedByteCount: bytes)
    }
    #expect(try ViewportSpatialInteractionRecord.retainedByteCount(for: table, limits: limits(bytes: bytes)) == bytes)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialInteractionRecord.retainedByteCount(for: table, limits: limits(bytes: bytes - 1))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialInteractionRecord.retainedByteCount(for: table, limits: limits(bytes: bytes, positions: 31))
    }
    #expect(try ViewportSpatialInteractionRecord.retainedByteCount(for: []) == 0)
}

@Test func semanticWorkerKeepsRepeatedSketchesAndBodyEdgesWithTheirOwners() throws {
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let nodes = (0..<4).map { _ in SceneNodeID() }
    var translated = Transform3D.identity
    translated.matrix.values[3] = 4
    let sketch = ViewportSceneItem(
        id: "sketch.first", featureID: featureID, sceneNodeID: nodes[0],
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        kind: .sketch(primitives: [.line(entityID: entityID, start: .zero, end: CGPoint(x: 1, y: 0))])
    )
    var repeated = sketch
    repeated.id = "sketch.second"
    repeated.sceneNodeID = nodes[1]
    repeated.modelTransform = translated
    let bodies = (2..<4).map { index in
        ViewportSceneItem(
            id: "body.\(index)", featureID: FeatureID(), sceneNodeID: nodes[index],
            modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            kind: .body(component: .init(sizeXMeters: 1, sizeYMeters: 1, sizeZMeters: 1,
                                         yMinMeters: 0, yMaxMeters: 1))
        )
    }
    let selection = SelectionModel(selectedTargets: nodes.enumerated().map { index, node in
        SelectionTarget(sceneNodeID: node, component: index < 2
            ? .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))
            : .edge(index == 2 ? .bodyEdgeLeftBottom : .bodyEdgeRightTop))
    })
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var lines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var records: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: .init(document: .empty(), scene: .init(items: [sketch, repeated] + bodies),
                    selection: selection, ruler: .standard(for: .meter),
                    enabledRoutes: [.curvePointControl, .edgeOffset]),
        meshes: &meshes, paths: &paths, labels: &labels, markers: &markers,
        cameraLines: &lines, cameraPaths: &cameraPaths, interactionRecords: &records,
        activeFamilies: &families, checkpoint: { _, _, _ in }
    )
    #expect(records.count == 6)
    for record in records {
        switch record.target {
        case .sketchPointHandle(let target):
            let second = record.occurrenceID == repeated.id
            #expect(target.target.sceneNodeID == nodes[second ? 1 : 0])
            #expect(record.modelTransform == (second ? translated : .identity))
        case .edgeOffset(let feature, let edge, let target, _, _, _):
            let first = record.occurrenceID == bodies[0].id
            #expect(feature == bodies[first ? 0 : 1].featureID)
            #expect(target.sceneNodeID == nodes[first ? 2 : 3])
            #expect(edge == (first ? .leftBottom : .rightTop))
        default: Issue.record("Unexpected interaction route in the occurrence fixture.")
        }
    }
    let interactiveFragmentHandles = markers.compactMap(\.value.handleIndex)
        + cameraPaths.compactMap(\.value.handleIndex)
    #expect(Set(interactiveFragmentHandles).count == records.count)
}

@Test func spatialInteractionRecordCancellationDoesNotRegisterAuthority() async throws {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        var table: [ViewportSpatialInteractionRecord] = []
        #expect(throws: CancellationError.self) {
            try ViewportSpatialOverlayProducer.handleIndex(
                for: recordTestBody(), occurrenceID: "body.first", in: &table)
        }
        #expect(table.isEmpty)
    }
    await task.value
}

@Test func spatialInteractionRecordsShareTheNativeAggregateBudget() throws {
    let records = [try ViewportSpatialInteractionRecord(
        target: recordTestBody(),
        occurrenceID: "body.first")]
    let input = ViewportSpatialOverlayInput(
        markers: [.init(family: .transform, value: .init(
            shape: .sphere, anchor: .origin, diameterPoints: 8,
            color: [1, 0, 0, 1], handleIndex: 0, hitTolerancePoints: 14))],
        interactionRecords: records, renderOrigin: .origin,
        retainedSurfaceByteCount: 128, topologyRevision: 1)
    let batch = try ViewportSpatialOverlayProducer.makeBatch(from: input)
    #expect(batch.handleCount == 1)
    #expect(batch.retainedSemanticByteCount == (try ViewportSpatialInteractionRecord.retainedByteCount(for: records)))
    let standard = MeshSourcePresentationPlanLimits.standard
    let limits = MeshSourcePresentationPlanLimits(
        maxItemCount: standard.maxItemCount, maxPositionCount: standard.maxPositionCount,
        maxTriangleCount: standard.maxTriangleCount, maxRetainedByteCount: batch.admittedByteCount - 1)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.makeBatch(from: input, limits: limits)
    }
    let empty = try ViewportSpatialOverlayProducer.makeBuilder(from: .init(
        renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 2))(.origin, 0)
    #expect(empty.interactionRecords.isEmpty)
    #expect(empty.spatialBatch.handleCount == 0)
    #expect(empty.spatialBatch.retainedSemanticByteCount == 0)
}

private func recordTestBody(
    featureID: FeatureID = .init(), occurrenceID: String = "body.first"
) -> ViewportSpatialPreparedInteractionTarget {
    .affordance(target: .init(featureID: featureID, action: .translate(.x)), members: [
        .init(occurrenceID: occurrenceID, featureID: featureID, sceneNodeID: nil,
              modelTransform: .identity,
              edit: .init(xMin: 0, xMax: 1, yMin: 0, yMax: 1, zMin: 0, zMax: 1))
    ], groupEdit: nil, placement: nil)
}

@Test func spatialBodyBaselineRejectsIncompleteGroupsAndChargesMembers() throws {
    let featureID = FeatureID()
    let target = ViewportAffordanceTarget(featureID: featureID, action: .translate(.x))
    let first = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
        occurrenceID: "body.first", featureID: featureID, sceneNodeID: .init(),
        modelTransform: .identity, edit: .init(xMin: 0, xMax: 1, yMin: 0, yMax: 1, zMin: 0, zMax: 1))
    let second = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
        occurrenceID: "body.second", featureID: featureID, sceneNodeID: .init(),
        modelTransform: .identity, edit: .init(xMin: 2, xMax: 3, yMin: 0, yMax: 1, zMin: 0, zMax: 1))
    let group = ViewportObjectEditState(xMin: 0, xMax: 3, yMin: 0, yMax: 1, zMin: 0, zMax: 1)
    let record = try ViewportSpatialInteractionRecord(target: .affordance(
        target: target, members: [first, second], groupEdit: group, placement: nil))
    let bytes = try ViewportSpatialInteractionRecord.retainedByteCount(for: [record])
    #expect(bytes >= MemoryLayout<ViewportSpatialInteractionRecord>.stride
        + 2 * MemoryLayout<ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember>.stride)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialInteractionRecord.retainedByteCount(for: [record], limits: .init(
            maxItemCount: 1, maxPositionCount: 1, maxTriangleCount: 0, maxRetainedByteCount: bytes))
    }
    for (members, groupEdit): ([ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember], ViewportObjectEditState?) in [
        ([], nil), ([first], group), ([first, second], nil), ([first, first], group)
    ] {
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try ViewportSpatialInteractionRecord(target: .affordance(
                target: target, members: members, groupEdit: groupEdit, placement: nil))
        }
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialInteractionRecord(target: .affordance(
            target: target, members: [first], groupEdit: nil, placement: nil), occurrenceID: "body.other")
    }
}

/// A placement baseline names the one scene node a released translate commits
/// into. The record refuses a baseline that names anything the drawn gizmo's
/// own member does not, because the gesture would then measure from one frame
/// and commit onto another.
@Test func spatialBodyPlacementBaselineMustNameTheDrawnMemberSceneNode() throws {
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let target = ViewportAffordanceTarget(featureID: featureID, action: .translate(.y))
    let member = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
        occurrenceID: "body.first", featureID: featureID, sceneNodeID: sceneNodeID,
        modelTransform: .identity, edit: .init(xMin: 0, xMax: 1, yMin: 0, yMax: 1, zMin: 0, zMax: 1))
    let second = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
        occurrenceID: "body.second", featureID: featureID, sceneNodeID: .init(),
        modelTransform: .identity, edit: .init(xMin: 2, xMax: 3, yMin: 0, yMax: 1, zMin: 0, zMax: 1))
    let group = ViewportObjectEditState(xMin: 0, xMax: 3, yMin: 0, yMax: 1, zMin: 0, zMax: 1)
    func baseline(_ node: SceneNodeID) -> ViewportBodyPlacementBaseline {
        .init(featureID: featureID, sceneNodeID: node,
              baseLocalTransform: .identity, parentWorldTransform: .identity)
    }
    let accepted = try ViewportSpatialInteractionRecord(target: .affordance(
        target: target, members: [member], groupEdit: nil, placement: baseline(sceneNodeID)))
    guard case .affordance(_, _, _, let placement) = accepted.target else {
        Issue.record("The affordance baseline was not retained.")
        return
    }
    #expect(placement?.sceneNodeID == sceneNodeID)
    // Both frames are heap matrix storage this table now owns.
    let withBaseline = try ViewportSpatialInteractionRecord.retainedByteCount(for: [accepted])
    let withoutBaseline = try ViewportSpatialInteractionRecord.retainedByteCount(for: [
        try ViewportSpatialInteractionRecord(target: .affordance(
            target: target, members: [member], groupEdit: nil, placement: nil))
    ])
    #expect(withBaseline > withoutBaseline)
    // A node the drawn member does not name, and a group gizmo that names no
    // single node at all, are both refusals rather than a chosen winner.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialInteractionRecord(target: .affordance(
            target: target, members: [member], groupEdit: nil, placement: baseline(.init())))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialInteractionRecord(target: .affordance(
            target: target, members: [member, second], groupEdit: group,
            placement: baseline(sceneNodeID)))
    }
}
