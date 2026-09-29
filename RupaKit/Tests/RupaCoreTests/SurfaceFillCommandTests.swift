import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite("Boundary surface commands", .timeLimit(.minutes(1)))
struct SurfaceFillCommandTests {
    @Test
    func deletedSolidFaceOpeningCreatesRetainedFillSheetAndSupportsUndoRedo() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let solidFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let solidSceneNodeID = try #require(sceneNodeID(for: solidFeatureID, in: session.document))
        let solidTopology = try TopologySnapshotService().snapshot(document: session.document)
        let topFace = try #require(solidTopology.entries.first {
            $0.kind == .face
                && $0.sceneNodeID == solidSceneNodeID.description
                && $0.generatedRole == "startFace"
        }?.selectionTarget())
        _ = try session.execute(.deleteBodyFaces(targets: [topFace]))

        let sourceFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let sourceNodeID = try #require(sceneNodeID(for: sourceFeatureID, in: session.document))
        let sourceNode = try #require(session.document.productMetadata.sceneNodes[sourceNodeID])
        let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let snapshot = try #require(
            BodyDisplaySnapshotService().snapshots(evaluatedDocument: evaluation)[sourceFeatureID]
        )
        let openingEdges = snapshot.topology.edges.filter { $0.openBoundaryLoopID != nil }
        let loopIDs = Set(openingEdges.compactMap(\.openBoundaryLoopID))
        #expect(openingEdges.count == 4)
        #expect(loopIDs.count == 1)
        #expect(snapshot.topology.edges.count == 12)
        #expect(evaluation.brep.faces.count == 5)
        let edge = try #require(openingEdges.first)
        let target = SelectionTarget(
            sceneNodeID: sourceNodeID,
            component: .edge(edge.componentID)
        )
        let original = session.document

        _ = try session.execute(.createSurfaceFill(name: "Fill", target: target))

        let fillFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let fillFeature = try #require(session.document.cadDocument.designGraph.nodes[fillFeatureID])
        guard case .surfaceFill = fillFeature.operation else {
            Issue.record("Surface Fill command did not append the persistent surface-fill feature.")
            return
        }
        let updatedSourceNode = try #require(session.document.productMetadata.sceneNodes[sourceNodeID])
        #expect(updatedSourceNode.reference == sourceNode.reference)
        #expect(updatedSourceNode.object == sourceNode.object)
        #expect(updatedSourceNode.childIDs.count == sourceNode.childIDs.count + 1)
        #expect(session.document.cadDocument.designGraph.nodes[sourceFeatureID]
            == original.cadDocument.designGraph.nodes[sourceFeatureID])
        let fillNodeID = try #require(updatedSourceNode.childIDs.last)
        let fillNode = try #require(session.document.productMetadata.sceneNodes[fillNodeID])
        #expect(fillNode.reference?.featureID == fillFeatureID)
        #expect(fillNode.object?.geometryRole == .surface)
        #expect(fillNode.object?.typeID == .bSplineSurface)

        let filled = try DocumentEvaluator.modelingDefault(for: session.document)
            .evaluateExact(session.document.cadDocument)
        try filled.brep.validate(level: .exact, tolerance: session.document.modelingSettings.tolerance)
        #expect(filled.brep.bodies.count == 2)
        #expect(filled.brep.faces.count == 6)
        #expect(evaluation.brep.faces.allSatisfy { filled.brep.faces[$0.key] == $0.value })
        let measurement = try MeasurementService().measure(
            document: session.document,
            ruler: .standard(for: .meter)
        )
        #expect(measurement.counts.sheets >= 1)
        #expect(measurement.sheets.contains { $0.featureID == fillFeatureID.description })

        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph.nodes[fillFeatureID] == nil)
        #expect(session.document.productMetadata.sceneNodes[sourceNodeID]?.childIDs == sourceNode.childIDs)
        _ = try session.redo()
        #expect(session.document.cadDocument.designGraph.nodes[fillFeatureID] == fillFeature)
        let redone = try DocumentEvaluator.modelingDefault(for: session.document)
            .evaluateExact(session.document.cadDocument)
        #expect(redone.brep == filled.brep)
    }

    @Test
    func boundaryBridgeConnectsTwoLiveOpenBoundariesWithoutReplacingSourceAndSupportsUndoRedo() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let solidFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let solidSceneNodeID = try #require(sceneNodeID(for: solidFeatureID, in: session.document))
        let solidTopology = try TopologySnapshotService().snapshot(document: session.document)
        let endFaces = solidTopology.entries.filter {
            $0.kind == .face
                && $0.sceneNodeID == solidSceneNodeID.description
                && ["startFace", "endFace"].contains($0.generatedRole)
        }
        #expect(endFaces.count == 2)
        _ = try session.execute(.deleteBodyFaces(targets: try endFaces.map {
            try #require($0.selectionTarget())
        }))

        let sourceFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let sourceSceneNodeID = try #require(sceneNodeID(for: sourceFeatureID, in: session.document))
        let sourceNode = try #require(session.document.productMetadata.sceneNodes[sourceSceneNodeID])
        let sourceEvaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let sourceSnapshot = try #require(
            BodyDisplaySnapshotService().snapshots(evaluatedDocument: sourceEvaluation)[sourceFeatureID]
        )
        let boundaryEdges = sourceSnapshot.topology.edges.filter { $0.openBoundaryLoopID != nil }
        let loopIDs = Array(Set(boundaryEdges.compactMap(\.openBoundaryLoopID))).sorted()
        #expect(loopIDs.count == 2)
        let reversedParallelPair = boundaryEdges.flatMap { first in
            boundaryEdges.compactMap { second -> (BodyDisplaySnapshot.Topology.Edge, BodyDisplaySnapshot.Topology.Edge)? in
                guard first.openBoundaryLoopID == loopIDs.first,
                      second.openBoundaryLoopID == loopIDs.last else { return nil }
                let firstDirection = first.end - first.start
                let secondDirection = second.end - second.start
                let alignment = firstDirection.dot(secondDirection)
                    / (firstDirection.length * secondDirection.length)
                return alignment < -0.999 ? (first, second) : nil
            }
        }.first
        let (firstEdge, secondEdge) = try #require(reversedParallelPair)
        let boundaries = [
            SelectionTarget(sceneNodeID: sourceSceneNodeID, component: .edge(firstEdge.componentID)),
            SelectionTarget(sceneNodeID: sourceSceneNodeID, component: .edge(secondEdge.componentID)),
        ]
        let documentBeforeBridge = session.document

        _ = try session.execute(.createBoundaryBridge(
            name: "Boundary Bridge",
            first: boundaries[0], second: boundaries[1],
            reverseSecondBoundary: true
        ))

        let bridgeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        guard case let .bridgeSurface(bridge)? = session.document.cadDocument.designGraph.nodes[bridgeFeatureID]?.operation else {
            Issue.record("Two selected boundaries must persist as a source-linked bridge operation.")
            return
        }
        #expect(bridge.targetFeatureID == sourceFeatureID)
        #expect(bridge.startBoundary.subshapeID != bridge.endBoundary.subshapeID)
        #expect(bridge.endOrientation == .reversed)
        #expect(session.document.cadDocument.designGraph.nodes[sourceFeatureID]
            == documentBeforeBridge.cadDocument.designGraph.nodes[sourceFeatureID])
        #expect(session.document.productMetadata.sceneNodes[sourceSceneNodeID]?.reference == sourceNode.reference)
        #expect(session.document.productMetadata.sceneNodes[sourceSceneNodeID]?.object == sourceNode.object)

        let bridged = try DocumentEvaluator.modelingDefault(for: session.document)
            .evaluateExact(session.document.cadDocument)
        try bridged.brep.validate(level: .exact, tolerance: session.document.modelingSettings.tolerance)
        #expect(bridged.brep.bodies.count == 2)
        #expect(bridged.brep.faces.count == sourceEvaluation.brep.faces.count + 1)
        #expect(sourceEvaluation.brep.faces.allSatisfy { bridged.brep.faces[$0.key] == $0.value })

        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph.nodes[bridgeFeatureID] == nil)
        _ = try session.redo()
        let redone = try DocumentEvaluator.modelingDefault(for: session.document)
            .evaluateExact(session.document.cadDocument)
        #expect(redone.brep == bridged.brep)
    }

    @Test
    func deletedCylinderCapCreatesExactPlanarFillThroughCoreCommand() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedCircle())
        let cylinderFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let capSceneNodeID = try #require(sceneNodeID(for: cylinderFeatureID, in: session.document))
        let originalEvaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let capFace = try #require(originalEvaluation.brep.faces.values.first { face in
            guard let surface = originalEvaluation.brep.geometry.surfaces[face.surfaceID] else {
                return false
            }
            if case .plane = surface { return true }
            return false
        })
        let capSubshapeID = try #require(originalEvaluation.subshapes.entries.first {
            $0.key.featureID == cylinderFeatureID && $0.value == .face(capFace.id)
        }?.key)
        let capTopology = try TopologySnapshotService().snapshot(document: session.document)
        let capEntry = try #require(capTopology.entries.first {
                $0.subshapeID == GeneratedSubshapeIdentity.string(for: capSubshapeID)
                    && $0.sceneNodeID == capSceneNodeID.description
            })
        let capTarget = try #require(capEntry.selectionTarget())

        _ = try session.execute(.deleteBodyFaces(targets: [capTarget]))

        let sourceFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let fillSourceNodeID = try #require(sceneNodeID(for: sourceFeatureID, in: session.document))
        let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let snapshot = try #require(
            BodyDisplaySnapshotService().snapshots(evaluatedDocument: evaluation)[sourceFeatureID]
        )
        let openingEdges = snapshot.topology.edges.filter { $0.openBoundaryLoopID != nil }
        #expect(openingEdges.count == 4)
        let boundaryEdge = try #require(openingEdges.first)
        let boundaryTarget = SelectionTarget(
            sceneNodeID: fillSourceNodeID,
            component: .edge(boundaryEdge.componentID)
        )

        _ = try session.execute(.createSurfaceFill(name: "Cap Fill", target: boundaryTarget))

        let fillFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let filled = try DocumentEvaluator.modelingDefault(for: session.document)
            .evaluateExact(session.document.cadDocument)
        let fillFaceID: FaceID
        guard case let .face(resolvedFaceID) = try #require(filled.subshapes.entries.first {
            guard $0.key.featureID == fillFeatureID,
                  case .face = $0.value else { return false }
            return true
        }?.value) else {
            Issue.record("A circular cap fill must produce one exact planar face.")
            return
        }
        fillFaceID = resolvedFaceID
        let fillFace = try #require(filled.brep.faces[fillFaceID])
        guard case .plane = filled.brep.geometry.surfaces[fillFace.surfaceID] else {
            Issue.record("A coplanar cylinder-cap opening must remain an exact plane.")
            return
        }
        #expect(filled.brep.bodies.count == 2)
        #expect(filled.brep.faces.count == 6)
        try filled.brep.validate(level: .exact, tolerance: session.document.modelingSettings.tolerance)
    }

    @Test
    func solidEdgeCannotBeUsedAsAnOpenBoundarySeed() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let topology = try TopologySnapshotService().snapshot(document: session.document, metricPolicy: .omit)
        let target = try #require(topology.entries.first { $0.kind == .edge }?.selectionTarget())
        let original = session.document

        #expect(throws: (any Error).self) {
            _ = try session.execute(.createSurfaceFill(name: "Invalid", target: target))
        }
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
    }

    @Test
    func curvedBoundaryDisplayPolylinePreservesTheBRepCurve() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedCircle())
        let solidFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let solidSceneNodeID = try #require(sceneNodeID(for: solidFeatureID, in: session.document))
        let topology = try TopologySnapshotService().snapshot(document: session.document)
        let lateralFace = try #require(topology.entries.first {
            $0.kind == .face
                && $0.sceneNodeID == solidSceneNodeID.description
                && $0.generatedRole == "sideFace"
        }?.selectionTarget())
        _ = try session.execute(.deleteBodyFaces(targets: [lateralFace]))

        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let snapshot = try #require(
            BodyDisplaySnapshotService().snapshots(evaluatedDocument: evaluation)[featureID]
        )
        let loopEdges = snapshot.topology.edges.filter { $0.openBoundaryLoopID != nil }

        #expect(loopEdges.count == 4)
        let curvedEdge = try #require(loopEdges.first { $0.displayPoints.count > 2 })
        #expect(curvedEdge.displayPoints.first == curvedEdge.start)
        #expect(curvedEdge.displayPoints.last == curvedEdge.end)
    }

    @Test
    func loneSurfaceOuterPerimeterOffersBridgingButRejectsSurfaceFill() throws {
        let session = EditorSession()
        _ = try session.execute(.createBSplineSurface(name: "Open surface", surface: curvedPatch))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let evaluation = try CADPipeline.modelingDefault(for: session.document)
            .evaluate(session.document.cadDocument)
        let snapshot = try #require(
            BodyDisplaySnapshotService().snapshots(evaluatedDocument: evaluation)[featureID]
        )

        #expect(snapshot.topology.edges.count == 4)
        #expect(snapshot.topology.edges.allSatisfy { $0.openBoundaryLoopID != nil })
        let sourceNodeID = try #require(sceneNodeID(for: featureID, in: session.document))
        let target = SelectionTarget(
            sceneNodeID: sourceNodeID,
            component: .edge(try #require(snapshot.topology.edges.first?.componentID))
        )
        let original = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.createSurfaceFill(name: "Invalid outer perimeter fill", target: target))
        }
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
    }

    @Test
    func separateSheetsBridgeWithBothSourceDependencies() throws {
        let session = EditorSession()
        for x in [0.0, 0.2] {
            _ = try session.execute(.createBSplineSurface(name: "Sheet", surface: .bilinearPatch(
                bottomLeft: Point3D(x: x, y: 0, z: 0),
                bottomRight: Point3D(x: x + 0.1, y: 0, z: 0),
                topRight: Point3D(x: x + 0.1, y: 0.1, z: 0),
                topLeft: Point3D(x: x, y: 0.1, z: 0)
            )))
        }
        let original = session.document
        let sources = original.cadDocument.designGraph.order
        let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let snapshots = BodyDisplaySnapshotService().snapshots(evaluatedDocument: evaluation)
        let boundaries = try sources.enumerated().map { index, source in
            let snapshot = try #require(snapshots[source])
            let x = index == 0 ? 0.1 : 0.2
            let edge = try #require(snapshot.topology.edges.first {
                abs($0.start.x - x) < 1e-10 && abs($0.end.x - x) < 1e-10
            })
            #expect(edge.openBoundaryLoopID != nil)
            return SelectionTarget(sceneNodeID: try #require(sceneNodeID(for: source, in: original)),
                component: .edge(edge.componentID))
        }
        var moved = original
        moved.productMetadata.sceneNodes[boundaries[1].sceneNodeID]?.localTransform = Transform3D(
            matrix: try Matrix4x4(values: [
                1, 0, 0, 0.1,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ]))
        let movedPlan = try moved.prepareBoundaryBridge(name: "Placed bridge", first: boundaries[0], second: boundaries[1],
            reverseSecondBoundary: true)
        #expect(movedPlan.presentations.first?.boundaryOccurrences?.second == boundaries[1].sceneNodeID)
        #expect(throws: (any Error).self) {
            _ = try session.execute(.createBoundaryBridge(name: "Twisted bridge", first: boundaries[0], second: boundaries[1],
                reverseSecondBoundary: false))
        }
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        #expect(session.document.productMetadata == original.productMetadata)
        _ = try session.execute(.createBoundaryBridge(name: "Bridge", first: boundaries[0], second: boundaries[1],
            reverseSecondBoundary: true))
        let bridgeID = try #require(session.document.cadDocument.designGraph.order.last)
        let feature = try #require(session.document.cadDocument.designGraph.nodes[bridgeID])
        #expect(feature.inputs.map(\.featureID) == sources)
        let result = try DocumentEvaluator.modelingDefault(for: session.document)
            .evaluateExact(session.document.cadDocument)
        try result.brep.validate(level: .exact, tolerance: session.document.modelingSettings.tolerance)
        #expect(result.brep.bodies.count == 3)
        #expect(result.brep.faces.count == 3)
        #expect(evaluation.brep.faces.allSatisfy { result.brep.faces[$0.key] == $0.value })
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph == original.cadDocument.designGraph)
        _ = try session.redo()
        #expect(session.document.cadDocument.designGraph.nodes[bridgeID] == feature)
        _ = try session.execute(.setSceneNodeTransform(id: boundaries[1].sceneNodeID,
            localTransform: .translation(Vector3D(x: 0.1, y: 0, z: 0))))
        let movedFeature = try #require(session.document.cadDocument.designGraph.nodes[bridgeID])
        guard case let .bridgeSurface(movedBridge) = movedFeature.operation else {
            Issue.record("A placement edit must retain the boundary feature.")
            return
        }
        #expect(movedBridge.endTransform?.translation.x == 0.1)
        let updated = try #require(session.currentEvaluationCache?.evaluatedDocument)
        let bridgeVertices = updated.subshapes.entries.compactMap { key, value -> Point3D? in
            guard key.featureID == bridgeID, case let .vertex(id) = value else { return nil }
            return updated.brep.vertices[id]?.point
        }
        #expect(bridgeVertices.contains { abs($0.x - 0.3) < 1e-8 })
        #expect(bridgeVertices.contains { abs($0.x - 0.1) < 1e-8 })
        var restored = session.document
        restored.productMetadata = try JSONDecoder().decode(ProductMetadata.self,
            from: JSONEncoder().encode(session.document.productMetadata))
        restored.cadDocument = try JSONDecoder().decode(CADDocument.self,
            from: JSONEncoder().encode(session.document.cadDocument))
        _ = try restored.validate()
        #expect(restored.productMetadata == session.document.productMetadata)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph.nodes[bridgeID] == feature)
        _ = try session.redo()
        #expect(session.document.cadDocument.designGraph.nodes[bridgeID] == movedFeature)
        let beforeFailure = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.setSceneNodeTransform(id: boundaries[1].sceneNodeID,
                localTransform: .translation(Vector3D(x: -0.1, y: 0, z: 0))))
        }
        #expect(session.document.cadDocument.designGraph == beforeFailure.cadDocument.designGraph)
        #expect(session.document.productMetadata == beforeFailure.productMetadata)
        var direct = session.document
        #expect(throws: (any Error).self) {
            try direct.setSceneNodeTransform(id: boundaries[1].sceneNodeID,
                localTransform: Transform3D(matrix: Matrix4x4(values: Array(repeating: 0, count: 16))))
        }
        #expect(direct.productMetadata == beforeFailure.productMetadata)
        #expect(direct.cadDocument.designGraph == beforeFailure.cadDocument.designGraph)
        var copied = session.document
        let fragment = try PatternArrayIndependentCopyBuilder().sourceFragment(
            definition: ComponentDefinition(
                name: "Sources", rootSceneNodeIDs: boundaries.map(\.sceneNodeID),
                rootPlacements: Dictionary(uniqueKeysWithValues: try boundaries.map { boundary in
                    let node = try #require(copied.productMetadata.sceneNodes[boundary.sceneNodeID])
                    return (boundary.sceneNodeID, ComponentDefinition.RootPlacement(
                        transform: node.localTransform, isVisible: node.isVisible
                    ))
                })
            ),
            metadata: copied.productMetadata, cadDocument: copied.cadDocument, authoredMeshAssets: copied.authoredMeshAssets)
        let clone = try PatternArrayIndependentCopyBuilder().createOutputs(name: "Copied boundaries",
            fragment: fragment,
            transforms: [.translation(Vector3D(x: 1, y: 0, z: 0))],
            metadata: &copied.productMetadata, cadDocument: &copied.cadDocument, authoredMeshAssets: &copied.authoredMeshAssets,
            tolerance: copied.modelingSettings.tolerance)
        let root = try #require(copied.productMetadata.rootSceneNodeIDs.first)
        copied.productMetadata.sceneNodes[root]?.childIDs += clone.outputSceneNodeIDs
        try copied.synchronizeBoundaryOccurrences()
        _ = try copied.validate()
        let clonedOwner = try #require(copied.productMetadata.sceneNodes.values.first {
            $0.boundaryOccurrences != nil && $0.object?.sourceFeatureID != bridgeID
        })
        let clonedBinding = try #require(clonedOwner.boundaryOccurrences)
        #expect(clonedBinding.first != boundaries[0].sceneNodeID)
        #expect(clonedBinding.second != boundaries[1].sceneNodeID)
        let cloneResult = try DocumentEvaluator.modelingDefault(for: copied).evaluateExact(copied.cadDocument)
        #expect(cloneResult.brep.bodies.count == 6)
        try copied.setSceneNodeTransform(id: clonedBinding.second,
            localTransform: .translation(Vector3D(x: 0.2, y: 0, z: 0)))
        _ = try copied.validate()
        #expect(copied.cadDocument.designGraph.nodes[bridgeID] == movedFeature)
    }

    @Test
    func boundaryLoopIdentityRequiresAnExplicitDisplayPolyline() {
        let start = Point3D(x: 0, y: 0, z: 0)
        let end = Point3D(x: 1, y: 0, z: 0)
        let loopID = "loop"
        let implicitChord = BodyDisplaySnapshot.Topology.Edge(
            componentID: .bodyEdgeLeftBottom,
            start: start,
            end: end,
            openBoundaryLoopID: loopID
        )
        let explicitPolyline = BodyDisplaySnapshot.Topology.Edge(
            componentID: .bodyEdgeLeftBottom,
            start: start,
            end: end,
            displayPoints: [start, Point3D(x: 0.5, y: 0.1, z: 0), end],
            openBoundaryLoopID: loopID
        )

        #expect(implicitChord.openBoundaryLoopID == nil)
        #expect(explicitPolyline.openBoundaryLoopID == loopID)
    }

    private func sceneNodeID(
        for featureID: FeatureID,
        in document: DesignDocument
    ) -> SceneNodeID? {
        document.productMetadata.sceneNodes.first { _, node in
            node.reference?.featureID == featureID
        }?.key
    }

    private var curvedPatch: BSplineSurface3D {
        var surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: .origin,
            bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0),
            topLeft: Point3D(x: 0, y: 0.1, z: 0)
        )
        surface.controlPoints[0][1].z = 0.02
        return surface
    }
}
