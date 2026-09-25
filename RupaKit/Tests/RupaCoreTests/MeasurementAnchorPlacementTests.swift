import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func sceneLocalMeasurementAnchorFollowsItsSceneNode() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Measurement Placement",
            plane: .xy,
            width: .length(1.0, .meter),
            height: .length(1.0, .meter),
            depth: .length(1.0, .meter),
            direction: .normal
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(session.document.productMetadata.sceneNodes.first { _, node in
        node.reference?.kind == .body && node.reference?.featureID == featureID
    }?.key)
    let anchor = MeasurementAnchor.sceneLocalPoint(.origin, in: sceneNodeID)
    let resolver = MeasurementAnchorWorldPointResolver()

    let initial = try #require(try resolver.worldPoint(for: anchor, in: session.document))
    var movedDocument = session.document
    try movedDocument.setSceneNodeTransform(
        id: sceneNodeID,
        localTransform: try Transform3D.translation(Vector3D(x: 3.0, y: 0.0, z: 0.0))
    )
    let moved = try #require(try resolver.worldPoint(for: anchor, in: movedDocument))

    #expect(initial == .origin)
    #expect(moved == Point3D(x: 3.0, y: 0.0, z: 0.0))
}

@Test func sceneLocalMeasurementAnchorRejectsMissingOccurrence() throws {
    let document = DesignDocument.empty(named: "Stale Measurement Placement")
    let anchor = MeasurementAnchor.sceneLocalPoint(.origin, in: SceneNodeID())

    #expect(throws: EditorError.self) {
        _ = try MeasurementAnchorWorldPointResolver().worldPoint(for: anchor, in: document)
    }
}

@MainActor
@Test func componentTopologyMeasurementResolvesSourceThenOccurrencePlacement() throws {
    let session = EditorSession()
    _ = try session.execute(.createExtrudedRectangle(name: "Box", plane: .xy,
        width: .length(1, .meter), height: .length(1, .meter),
        depth: .length(1, .meter), direction: .normal))
    var document = session.document
    let topology = try TopologySnapshotService().snapshot(document: document)
    let entry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(entry.selectionTarget())
    let definition = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [target.sceneNodeID])
    let instance = try document.createComponentInstance(name: "Instance", definitionID: definition,
        localTransform: .translation(Vector3D(x: 5, y: 0, z: 0)))
    let occurrence = try #require(try SceneNodeHierarchy(metadata: document.productMetadata)
        .resolvedOccurrences().first { $0.componentInstanceID == instance && $0.sourceSceneNodeID == target.sceneNodeID })
    let source = MeasurementAnchor.topologyReference(sceneNodeID: target.sceneNodeID,
        component: target.component, kind: .vertex, subshapeID: entry.subshapeID)
    var placed = MeasurementAnchor.topologyReference(sceneNodeID: occurrence.sceneNodeID,
        component: target.component, kind: .vertex, subshapeID: entry.subshapeID)
    let resolver = MeasurementAnchorWorldPointResolver()
    #expect(throws: EditorError.self) {
        try resolver.worldPoint(for: placed, in: document, topology: topology)
    }
    placed.occurrenceID = occurrence.id
    let local = try #require(try resolver.worldPoint(for: source, in: document, topology: topology))
    let world = try #require(try resolver.worldPoint(for: placed, in: document, topology: topology))
    #expect(world == local + Vector3D(x: 5, y: 0, z: 0))
    try document.setComponentInstanceTransform(id: instance,
        localTransform: .translation(Vector3D(x: 8, y: 0, z: 0)))
    #expect(try resolver.worldPoint(for: placed, in: document, topology: topology) == local + Vector3D(x: 8, y: 0, z: 0))
    placed.sceneNodeID = target.sceneNodeID
    placed.topologyReference?.sceneNodeID = target.sceneNodeID
    #expect(throws: EditorError.self) {
        try resolver.worldPoint(for: placed, in: document, topology: topology)
    }
}

/// Edge midpoints and edge-parameter anchors lie on the evaluated curve, not on the chord.
@Test func curvedEdgeAnchorsLieOnTheEvaluatedCircle() throws {
    var document = DesignDocument.empty(named: "Curved Edge Anchors")
    let radius = 1.0
    _ = try document.createExtrudedCircle(
        name: "Cylinder",
        plane: .xy,
        center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        radius: .length(radius, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let topology = try TopologySnapshotService().snapshot(document: document)
    let circularEdges = topology.entries.filter { entry in
        guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
        return abs(start.z - end.z) < 1.0e-9
    }
    try #require(!circularEdges.isEmpty)
    let resolver = MeasurementAnchorWorldPointResolver()
    func radialDistance(_ point: Point3D) -> Double { (point.x * point.x + point.y * point.y).squareRoot() }

    for entry in circularEdges {
        let start = try #require(entry.start)
        let target = try #require(entry.selectionTarget())
        let midpoint = try #require(try resolver.worldPoint(
            for: .topologyReference(sceneNodeID: target.sceneNodeID, component: target.component,
                kind: .edge, subshapeID: entry.subshapeID, role: .center),
            in: document, topology: topology
        ))
        #expect(abs(radialDistance(midpoint) - radius) < 1.0e-9)
        #expect(abs(midpoint.z - start.z) < 1.0e-9)

        let quarter = try #require(try resolver.worldPoint(
            for: .topologyEdgeParameter(sceneNodeID: target.sceneNodeID, component: target.component,
                subshapeID: entry.subshapeID, parameter: 0.25),
            in: document, topology: topology
        ))
        #expect(abs(radialDistance(quarter) - radius) < 1.0e-9)
        #expect(abs(quarter.z - start.z) < 1.0e-9)
        let offset = (quarter.x - start.x, quarter.y - start.y)
        #expect((offset.0 * offset.0 + offset.1 * offset.1).squareRoot() > 0.1)
    }
}

/// A component-occurrence edge anchor is measured as its occurrence places it.
@MainActor
@Test func occurrenceEdgeLengthIsMeasuredThroughTheOccurrencePlacement() throws {
    let session = EditorSession()
    _ = try session.execute(.createExtrudedRectangle(name: "Box", plane: .xy,
        width: .length(1, .meter), height: .length(1, .meter),
        depth: .length(2, .meter), direction: .normal))
    var document = session.document
    let topology = try TopologySnapshotService().snapshot(document: document)
    let entry = try #require(topology.entries.first {
        $0.kind == .edge && abs(($0.lengthMeters ?? -1) - 2) <= 1.0e-9
    })
    let target = try #require(entry.selectionTarget())
    let definition = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [target.sceneNodeID])
    let instance = try document.createComponentInstance(name: "Instance", definitionID: definition,
        localTransform: Transform3D(matrix: try Matrix4x4(values: [
            1, 0, 0, 5,
            0, 1, 0, 0,
            0, 0, 1.5, 0,
            0, 0, 0, 1,
        ])))
    let occurrence = try #require(try SceneNodeHierarchy(metadata: document.productMetadata)
        .resolvedOccurrences().first { $0.componentInstanceID == instance && $0.sourceSceneNodeID == target.sceneNodeID })
    var anchor = MeasurementAnchor.topologyReference(sceneNodeID: occurrence.sceneNodeID,
        component: target.component, kind: .edge, subshapeID: entry.subshapeID)
    anchor.occurrenceID = occurrence.id
    let resolver = MeasurementAnchorWorldPointResolver()

    let length = try #require(try resolver.placedEdgeLengthMeters(for: anchor, in: document, topology: topology))
    #expect(abs(length - 3) <= 1.0e-9)
}
