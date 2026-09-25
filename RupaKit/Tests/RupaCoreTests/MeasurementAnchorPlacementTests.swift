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
