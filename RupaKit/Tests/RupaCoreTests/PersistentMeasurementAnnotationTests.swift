import SwiftCAD
import Testing
@testable import RupaCore

/// Covers saving a measurement, following its placement, and reporting what no longer resolves.
@Suite struct PersistentMeasurementAnnotationTests {
    private let tolerance = 1.0e-9

    @MainActor
    private func boxSession() throws -> (EditorSession, SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(1, .meter), height: .length(1, .meter),
            depth: .length(1, .meter), direction: .normal
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let sceneNodeID = try #require(
            SceneNodeHierarchy(metadata: session.document.productMetadata)
                .presentingSceneNodeID(for: featureID)
        )
        return (session, sceneNodeID)
    }

    private func worldPoint(_ anchor: MeasurementAnchor, in document: DesignDocument) throws -> Point3D {
        try #require(try MeasurementAnchorWorldPointResolver().worldPoint(for: anchor, in: document))
    }

    @MainActor
    @Test func pickedAnchorsResolveBackToThePickedPointAndFollowTheirPlacement() throws {
        let (session, sceneNodeID) = try boxSession()
        var document = session.document
        try document.setSceneNodeTransform(
            id: sceneNodeID,
            localTransform: .translation(Vector3D(x: 2, y: 0, z: 0))
        )
        let definition = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [sceneNodeID])
        let instance = try document.createComponentInstance(
            name: "Instance", definitionID: definition,
            localTransform: .translation(Vector3D(x: 10, y: 0, z: 0))
        )
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrence = try #require(try hierarchy.resolvedOccurrences().first {
            $0.componentInstanceID == instance && $0.sourceSceneNodeID == sceneNodeID
        })
        let picked = Point3D(x: 12.5, y: 0.25, z: 0.5)

        let world = try MeasurementAnchor.picked(picked, under: .world, in: hierarchy, role: .start)
        let onNode = try MeasurementAnchor.picked(picked, under: .sceneNode(sceneNodeID), in: hierarchy)
        let onOccurrence = try MeasurementAnchor.picked(picked, under: .occurrence(occurrence.id), in: hierarchy)

        #expect(world.role == .start)
        for anchor in [world, onNode, onOccurrence] {
            #expect(try worldPoint(anchor, in: document).isApproximatelyEqual(to: picked, tolerance: tolerance))
        }

        try document.setComponentInstanceTransform(
            id: instance,
            localTransform: .translation(Vector3D(x: 13, y: 0, z: 0))
        )
        try document.setSceneNodeTransform(
            id: sceneNodeID,
            localTransform: .translation(Vector3D(x: 5, y: 0, z: 0))
        )

        #expect(try worldPoint(world, in: document) == picked)
        #expect(try worldPoint(onNode, in: document).isApproximatelyEqual(
            to: Point3D(x: 15.5, y: 0.25, z: 0.5), tolerance: tolerance
        ))
        // The occurrence composes the moved instance (13) with the moved definition root (5).
        #expect(try worldPoint(onOccurrence, in: document).isApproximatelyEqual(
            to: Point3D(x: 18.5, y: 0.25, z: 0.5), tolerance: tolerance
        ))
        #expect(throws: EditorError.self) {
            _ = try MeasurementAnchor.picked(picked, under: .occurrence(SceneOccurrenceID(rawValue: "scene.missing")), in: hierarchy)
        }
    }

    @MainActor
    @Test func savingIsUndoableAndDeletingTheAnnotationNodeRemovesTheMeasurement() throws {
        let (session, sceneNodeID) = try boxSession()
        let hierarchy = try SceneNodeHierarchy(metadata: session.document.productMetadata)
        let annotation = MeasurementAnnotation(
            name: "Distance 1",
            kind: .distance,
            anchors: [
                try .picked(Point3D(x: 0, y: 0, z: 1), under: .sceneNode(sceneNodeID), in: hierarchy, role: .start),
                try .picked(Point3D(x: 3, y: 4, z: 1), under: .world, in: hierarchy, role: .end),
            ]
        )

        _ = try session.execute(.addMeasurementAnnotation(annotation))
        let saved = try #require(session.document.productMetadata.measurements[annotation.id])
        let annotationNodeID = try #require(saved.sceneNodeID)
        #expect(session.document.productMetadata.sceneNodes[annotationNodeID]?.object?.category == .annotation)

        _ = try session.undo()
        #expect(session.document.productMetadata.measurements[annotation.id] == nil)
        #expect(session.document.productMetadata.sceneNodes[annotationNodeID] == nil)

        _ = try session.redo()
        #expect(session.document.productMetadata.measurements[annotation.id] != nil)
        _ = try session.execute(.deleteSceneNodes(ids: [annotationNodeID]))
        #expect(session.document.productMetadata.measurements[annotation.id] == nil)
    }

    @MainActor
    @Test func resolutionIsAllOrNothingAndReportsWhatFailed() throws {
        let (session, sceneNodeID) = try boxSession()
        var document = session.document
        let resolved = MeasurementAnnotation(
            name: "A Resolved",
            kind: .distance,
            anchors: [.worldPoint(.origin, role: .start), .sceneLocalPoint(.origin, in: sceneNodeID, role: .end)]
        )
        let staleTopology = MeasurementAnnotation(
            name: "B Stale",
            kind: .distance,
            anchors: [
                .worldPoint(.origin, role: .start),
                .topologyReference(
                    sceneNodeID: sceneNodeID,
                    component: .vertex(SelectionComponentID(rawValue: "missing.vertex")),
                    kind: .vertex,
                    subshapeID: "missing-subshape",
                    role: .end
                ),
            ]
        )
        try document.addMeasurementAnnotation(resolved)
        try document.addMeasurementAnnotation(staleTopology)
        let topology = try TopologySnapshotService().snapshot(document: document)
        let resolver = MeasurementAnnotationResolver()

        let withTopology = resolver.resolveAll(in: document) { topology }
        #expect(withTopology.map(\.name) == ["A Resolved", "B Stale"])
        guard case .resolved(let anchors) = withTopology[0].outcome else {
            Issue.record("The fully placed annotation must resolve.")
            return
        }
        #expect(anchors.map(\.role) == [.start, .end])
        guard case .unresolved(let error) = withTopology[1].outcome else {
            Issue.record("A missing topology anchor must be reported, not dropped.")
            return
        }
        #expect(error.code == .referenceUnresolved)
        #expect(error.message.contains("anchor 2"))

        // A topology failure is reported only for the annotations that need topology.
        let failingTopology = resolver.resolveAll(in: document) {
            throw EditorError(code: .evaluationFailed, message: "evaluation unavailable")
        }
        #expect({ if case .resolved = failingTopology[0].outcome { true } else { false } }())
        guard case .unresolved(let topologyError) = failingTopology[1].outcome else {
            Issue.record("A topology failure must be reported for the annotation that needs it.")
            return
        }
        #expect(topologyError.message.contains("evaluation unavailable"))
    }

    @MainActor
    @Test func drawingProjectionReportsAnUnresolvedAnnotationInsteadOfDroppingAnchors() throws {
        var document = DesignDocument.empty(named: "Unresolved Drawing Annotation")
        let rootID = try #require(document.productMetadata.rootSceneNodeIDs.first)
        try document.addMeasurementAnnotation(MeasurementAnnotation(
            name: "Stale",
            kind: .distance,
            anchors: [
                .worldPoint(.origin, role: .start),
                .topologyReference(
                    sceneNodeID: rootID,
                    component: .vertex(SelectionComponentID(rawValue: "gone.vertex")),
                    kind: .vertex,
                    subshapeID: "gone",
                    role: .end
                ),
            ]
        ))
        let savedView = SavedView(
            name: "Front",
            camera: SavedViewCamera(target: .origin, distanceMeters: 4, yawRadians: 0, pitchRadians: 0),
            projection: .orthographic(heightMeters: 4),
            displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
        )
        _ = try document.createSavedView(savedView, objectRegistry: .builtIn)

        let result = try DrawingProjectionService().generate(
            document: document,
            query: DrawingProjectionQuery(savedViewID: savedView.id)
        )

        #expect(result.annotations.isEmpty)
        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("\"Stale\" anchor 2")
        })
    }

    @MainActor
    @Test func topologySnapPointsFollowTheirMovedSceneNode() throws {
        let (session, sceneNodeID) = try boxSession()
        var document = session.document
        try document.setSceneNodeTransform(
            id: sceneNodeID,
            localTransform: .translation(Vector3D(x: 3, y: 0, z: 0))
        )
        let topology = try TopologySnapshotService().snapshot(document: document)
        let vertex = try #require(topology.entries.first { $0.kind == .vertex && $0.start != nil })
        let local = try #require(vertex.start)
        let placed = Point2D(x: local.x + 3, y: local.y)

        let result = try SnapResolver().resolve(
            point: Point2D(x: placed.x + 0.00001, y: placed.y + 0.00001),
            in: document,
            ruler: .standard(for: .millimeter),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            )
        )

        let world = try #require(result.selectedTopologyWorldPoint)
        #expect(result.selectedCandidate?.topologySource?.sceneNodeID == sceneNodeID)
        #expect(abs(world.x - (local.x + 3)) <= 1.0e-9)
        #expect(abs(world.y - local.y) <= 1.0e-9)
        #expect(abs(world.z - local.z) <= 1.0e-9)
    }

    @MainActor
    @Test func deletingTheMeasuredSourceNodeRemovesAnOccurrenceAnchoredMeasurement() throws {
        let (session, sceneNodeID) = try boxSession()
        var document = session.document
        let definition = try document.createComponentDefinition(name: "Part", rootSceneNodeIDs: [sceneNodeID])
        let instance = try document.createComponentInstance(
            name: "Instance", definitionID: definition,
            localTransform: .translation(Vector3D(x: 5, y: 0, z: 0))
        )
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrence = try #require(try hierarchy.resolvedOccurrences().first {
            $0.componentInstanceID == instance && $0.sourceSceneNodeID == sceneNodeID
        })
        let annotation = MeasurementAnnotation(
            name: "On Instance",
            kind: .distance,
            anchors: [
                try .picked(Point3D(x: 5, y: 0, z: 0), under: .occurrence(occurrence.id), in: hierarchy, role: .start),
                .worldPoint(Point3D(x: 9, y: 0, z: 0), role: .end),
            ]
        )
        try document.addMeasurementAnnotation(annotation)
        // The anchor names the instance node as its owner, not the deleted source node.
        #expect(annotation.anchors[0].sceneNodeID == occurrence.sceneNodeID)
        #expect(occurrence.sceneNodeID != sceneNodeID)

        let plan = try SceneNodeDeletionPlanner().plan(
            metadata: document.productMetadata,
            designGraph: document.cadDocument.designGraph,
            ids: [sceneNodeID]
        )

        #expect(plan.measurementIDs.contains(annotation.id))
    }

    @Test func snapPlacementNamesOneSceneNodeOrStaysInWorldSpace() throws {
        let metadata = ProductMetadata.empty()
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        let first = SceneNodeID()
        let second = SceneNodeID()
        func topology(_ sceneNodeID: SceneNodeID) -> SnapTopologyReference {
            SnapTopologyReference(
                sceneNodeID: sceneNodeID, component: .vertex(SelectionComponentID(rawValue: "vertex")), kind: .vertex,
                persistentName: "vertex", referenceID: "vertex"
            )
        }
        let single = SnapCandidate(
            kind: .lineEnd, point: .init(x: 0, y: 0), distanceMeters: 0, label: "Vertex",
            topologySource: topology(first)
        )
        let crossing = SnapCandidate(
            kind: .curveIntersection, point: .init(x: 0, y: 0), distanceMeters: 0, label: "Intersection",
            source: SnapSourceReference(sceneNodeID: second, featureID: FeatureID(), entityID: SketchEntityID()),
            topologySource: topology(first)
        )
        let unowned = SnapCandidate(kind: .grid, point: .init(x: 0, y: 0), distanceMeters: 0, label: "Grid")

        #expect(single.measurementPickPlacement(in: hierarchy) == .sceneNode(first))
        #expect(crossing.measurementPickPlacement(in: hierarchy) == .world)
        #expect(unowned.measurementPickPlacement(in: hierarchy) == .world)
    }
}
