import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func moveSketchEntityPointCommandUpdatesLineEndpoint() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Editable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(2.0, .millimeter),
            deltaY: .length(3.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedLine = try #require(after.entries.first { $0.entityKind == "line" })
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(abs((movedLine.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((movedLine.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((movedLine.end?.y ?? -1.0) - 0.003) < 1.0e-12)
    #expect(session.selectTarget(target))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesParallelSourceLineWithoutChangingOriginal() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Offset Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.entityKind == "line" }
    let original = try #require(lines.first { entry in
        abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let offset = try #require(lines.first { entry in
        abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 2)
    #expect(lines.count == 2)
    #expect(original.sourceFeatureID == sourceLine.sourceFeatureID)
    #expect(offset.sourceFeatureID != sourceLine.sourceFeatureID)
    #expect(abs((offset.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((offset.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesConcentricSourceCircle() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Offset Source Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceCircle = try #require(before.entries.first { $0.entityKind == "circle" })
    let target = try #require(sourceCircle.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let circles = after.entries.filter { $0.entityKind == "circle" }
    let offset = try #require(circles.first { entry in
        abs((entry.radius ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(circles.count == 2)
    #expect(abs((offset.center?.x ?? -1.0) - 0.001) < 1.0e-12)
    #expect(abs((offset.center?.y ?? -1.0) - 0.002) < 1.0e-12)
    #expect(offset.sourceFeatureID != sourceCircle.sourceFeatureID)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetSketchVertexCommandSplitsLineLineCornerAndKeepsProfileExtrudable() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Offset Vertex Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    let sourceFeatureID = try #require(UUID(uuidString: bottomLine.sourceFeatureID)).featureID

    let result = try session.execute(
        .offsetSketchVertex(
            target: target,
            handle: .lineEnd,
            distance: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 1)
    #expect(lines.count == 6)
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.008) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.008) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Offset Vertex Rectangle",
            profile: ProfileReference(featureID: sourceFeatureID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func offsetCurveCommandDispatchesGeneratedBodyVertexToSourceSketchVertexOffset() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Generated Vertex Offset Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Generated vertex offset fixture must create an extrude body.")
        return
    }
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: bodyNodeID,
            cornerVertex: .frontBottomRight,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .vertex(componentID))
    let beforeGeneration = session.generation

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter {
        $0.sourceFeatureID == extrude.profile.featureID.description &&
            $0.entityKind == "line"
    }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == (try beforeGeneration.advanced()))
    #expect(lines.count == 6)
    #expect(containsSketchPoint(after, x: 0.008, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.010, y: 0.002))
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveGeneratedBodyVertexRejectsPlanarOffsetOptionsBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Generated Vertex Option Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: bodyNodeID,
            cornerVertex: .frontBottomRight,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .vertex(componentID))
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let beforeGeneration = session.generation

    do {
        _ = try session.execute(
            .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true),
                vertexHandle: nil
            )
        )
        Issue.record("Generated vertex Offset Vertex must reject planar curve options.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("vertex dispatch"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == beforeGeneration)
    #expect(after.counts.entityCount == before.counts.entityCount)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveDispatchesGeneratedFaceToFaceLoopOffsetFeature() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Face Loop Offset Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: bodyNodeID,
            bodyFace: .front,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(componentID))
    let beforeGeneration = session.generation

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(mode: .offset, isSymmetric: false, gapFill: .linear),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .faceLoopOffset(let faceLoopOffset) = feature.operation else {
        Issue.record("Face target Offset Curve must create a FaceLoopOffset feature.")
        return
    }
    let topology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = topology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "faceLoopOffset" &&
            $0.subshapeRole == "offsetEdge"
    }
    let offsetSceneNode = try #require(bodySceneNode(for: offsetFeatureID, in: session.document))

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == (try beforeGeneration.advanced()))
    #expect(faceLoopOffset.target == FaceLoopOffsetTargetReference(featureID: bodyFeatureID))
    #expect(faceLoopOffset.gapFill == .linear)
    #expect(feature.inputs == [FeatureInput(featureID: bodyFeatureID, role: .target)])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(topology.counts.bodyCount == 1)
    #expect(topology.counts.faceCount == 7)
    #expect(topology.counts.edgeCount == 16)
    #expect(topology.counts.vertexCount == 12)
    #expect(generatedOffsetEdges.count == 4)
    #expect(offsetSceneNode.object?.sourceProfileFeatureID == nil)
    #expect(offsetSceneNode.object?.typeID == nil)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveDispatchesGeneratedEdgeWithSupportFaceToEdgeOffsetFeature() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Edge Offset Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeTopology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        beforeTopology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        beforeTopology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.curveKind == "line" &&
                topologyPoint($0.start, isOnDepth: supportDepth) &&
                topologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let target = try #require(edgeEntry.selectionTarget())
    let beforeGeneration = session.generation

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(
                mode: .offset,
                isSymmetric: false,
                gapFill: .linear,
                supportTarget: supportFaceTarget
            ),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Edge target Offset Curve must create an EdgeOffset feature.")
        return
    }
    let parser = GeneratedTopologyPersistentNameParser()
    let topology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = topology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }
    let offsetSceneNode = try #require(bodySceneNode(for: offsetFeatureID, in: session.document))

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == (try beforeGeneration.advanced()))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.edgePersistentName == (try parser.parse(edgeEntry.persistentName, operationName: "Offset Edge")))
    #expect(edgeOffset.supportFacePersistentName == (try parser.parse(supportFaceEntry.persistentName, operationName: "Offset Edge")))
    #expect(edgeOffset.gapFill == .linear)
    #expect(feature.inputs == [FeatureInput(featureID: bodyFeatureID, role: .target)])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(topology.counts.bodyCount == 1)
    #expect(topology.counts.faceCount == 7)
    #expect(topology.counts.edgeCount == 15)
    #expect(topology.counts.vertexCount == 10)
    #expect(generatedOffsetEdges.count == 1)
    #expect(topology.entries.contains { $0.persistentName == edgeEntry.persistentName })
    #expect(offsetSceneNode.object?.sourceProfileFeatureID == nil)
    #expect(offsetSceneNode.object?.typeID == nil)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveDispatchesSymmetricGeneratedEdgeToEvaluatedEdgeOffsetFeature() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Symmetric Edge Offset Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeTopology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        beforeTopology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        beforeTopology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.curveKind == "line" &&
                topologyPoint($0.start, isOnDepth: supportDepth) &&
                topologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let target = try #require(edgeEntry.selectionTarget())
    let beforeGeneration = session.generation

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(
                mode: .offset,
                isSymmetric: true,
                gapFill: .linear,
                supportTarget: supportFaceTarget
            ),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Symmetric edge target Offset Curve must create an EdgeOffset feature.")
        return
    }
    let topology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = topology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == (try beforeGeneration.advanced()))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.isSymmetric)
    #expect(edgeOffset.gapFill == .linear)
    #expect(feature.inputs == [FeatureInput(featureID: bodyFeatureID, role: .target)])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(topology.counts.bodyCount == 1)
    #expect(topology.counts.faceCount == 8)
    #expect(topology.counts.edgeCount == 18)
    #expect(topology.counts.vertexCount == 12)
    #expect(generatedOffsetEdges.count == 2)
    #expect(topology.entries.contains { $0.persistentName == edgeEntry.persistentName })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetSketchVertexCommandMigratesLineDimensionsAcrossSplitCorner() async throws {
    var document = DesignDocument.empty()
    _ = try document.createRectangleSketchFromCorners(
        name: "Offset Vertex Dimensioned Rectangle",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(6.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: document)
    let bottomLine = try #require(bottomRectangleLine(in: before))
    let rightLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.006) < 1.0e-12
    })
    let featureID = try #require(UUID(uuidString: bottomLine.sourceFeatureID)).featureID
    let bottomLineID = try #require(UUID(uuidString: bottomLine.entityID)).sketchEntityID
    let rightLineID = try #require(UUID(uuidString: rightLine.entityID)).sketchEntityID
    var feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case var .sketch(sketch) = feature.operation else {
        Issue.record("Offset Vertex dimension setup must remain a sketch.")
        return
    }
    sketch.dimensions = [
        .distance(
            from: .lineStart(bottomLineID),
            to: .lineEnd(bottomLineID),
            value: .length(10.0, .millimeter)
        ),
        .distance(
            from: .lineStart(rightLineID),
            to: .lineEnd(rightLineID),
            value: .length(6.0, .millimeter)
        ),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let session = EditorSession(document: document)
    let target = try #require(bottomLine.selectionTarget())

    let result = try session.execute(
        .offsetSketchVertex(
            target: target,
            handle: .lineEnd,
            distance: .length(2.0, .millimeter)
        )
    )

    let updatedSketch = try sketchFeature(in: session.document, featureID: featureID)
    let bottomDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .distance(.lineStart(let firstID), .lineEnd(let secondID), _) = dimension,
           firstID == bottomLineID,
           secondID != bottomLineID {
            return true
        }
        return false
    })
    let rightDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .distance(.lineStart(let firstID), .lineEnd(let secondID), _) = dimension,
           firstID != rightLineID,
           secondID == rightLineID {
            return true
        }
        return false
    })
    let bottomLength = try resolvedTestLength(
        sketchDimensionExpression(bottomDimension),
        in: session.document
    )
    let rightLength = try resolvedTestLength(
        sketchDimensionExpression(rightDimension),
        in: session.document
    )
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(updatedSketch.dimensions.count == 2)
    #expect(abs(bottomLength - 0.010) < 1.0e-12)
    #expect(abs(rightLength - 0.006) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandDispatchesLineEndpointToOffsetVertex() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Offset Curve Vertex Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: .lineEnd
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 1)
    #expect(lines.count == 6)
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.008) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetSketchVertexCommandSplitsLineArcCornerAndKeepsProfileExtrudable() async throws {
    let setup = try lineArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .offsetSketchVertex(
            target: target,
            handle: .lineEnd,
            distance: .length(1.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == 1)
    #expect(lines.count == 4)
    #expect(arcs.count == 2)
    #expect(lines.contains { line in
        pointMatches(line.start, x: 0.0, y: 0.0) &&
            pointMatches(line.end, x: 0.009, y: 0.0)
    })
    #expect(lines.contains { line in
        pointMatches(line.start, x: 0.009, y: 0.0) &&
            pointMatches(line.end, x: 0.010, y: 0.0)
    })
    #expect(arcs.contains { arc in
        abs((arc.startAngle ?? 0.0) - (-Double.pi / 2.0)) < 1.0e-12 &&
            abs((arc.endAngle ?? 0.0) - (-Double.pi / 2.0 + 0.5)) < 1.0e-12
    })
    #expect(arcs.contains { arc in
        abs((arc.startAngle ?? 0.0) - (-Double.pi / 2.0 + 0.5)) < 1.0e-12 &&
            abs((arc.endAngle ?? 0.0) - 0.0) < 1.0e-12
    })

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Offset Vertex Line Arc",
            profile: ProfileReference(featureID: setup.featureID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func offsetSketchVertexCommandMigratesArcSpanDimensionsAcrossSplitArc() async throws {
    let setup = try lineArcOffsetVertexSketchDocument()
    var document = setup.document
    var feature = try #require(document.cadDocument.designGraph.nodes[setup.featureID])
    guard case var .sketch(sketch) = feature.operation else {
        Issue.record("Offset Vertex arc span setup must remain a sketch.")
        return
    }
    sketch.dimensions = [
        .angle(
            from: .arcStart(setup.arcID),
            to: .arcEnd(setup.arcID),
            value: .angle(Double.pi / 2.0, .radian)
        ),
        .angle(
            from: .arcEnd(setup.arcID),
            to: .arcStart(setup.arcID),
            value: .angle(Double.pi / 2.0, .radian)
        ),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[setup.featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let session = EditorSession(document: document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .offsetSketchVertex(
            target: target,
            handle: .lineEnd,
            distance: .length(1.0, .millimeter)
        )
    )

    let updatedSketch = try sketchFeature(in: session.document, featureID: setup.featureID)
    let forwardDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .angle(.arcStart(let firstID), .arcEnd(let secondID), _) = dimension,
           firstID != setup.arcID,
           secondID == setup.arcID {
            return true
        }
        return false
    })
    let reverseDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .angle(.arcEnd(let firstID), .arcStart(let secondID), _) = dimension,
           firstID == setup.arcID,
           secondID != setup.arcID {
            return true
        }
        return false
    })
    let forwardSpan = try resolvedTestAngle(
        sketchDimensionExpression(forwardDimension),
        in: session.document
    )
    let reverseSpan = try resolvedTestAngle(
        sketchDimensionExpression(reverseDimension),
        in: session.document
    )
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(updatedSketch.dimensions.count == 2)
    #expect(abs(forwardSpan - Double.pi / 2.0) < 1.0e-12)
    #expect(abs(reverseSpan - Double.pi / 2.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandDispatchesArcEndpointToOffsetVertex() async throws {
    let setup = try lineArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceArc.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: .arcStart
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetSketchVertexCommandSplitsArcArcCornerAndKeepsProfileExtrudable() async throws {
    let setup = try arcArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.upperArcID.description })
    let target = try #require(sourceArc.selectionTarget())

    let result = try session.execute(
        .offsetSketchVertex(
            target: target,
            handle: .arcEnd,
            distance: .length(1.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(arcs.count == 4)
    #expect(arcs.contains { arcMatches($0, startAngle: 0.0, endAngle: Double.pi - 0.5) })
    #expect(arcs.contains { arcMatches($0, startAngle: Double.pi - 0.5, endAngle: Double.pi) })
    #expect(arcs.contains { arcMatches($0, startAngle: Double.pi, endAngle: Double.pi + 0.5) })
    #expect(arcs.contains { arcMatches($0, startAngle: Double.pi + 0.5, endAngle: Double.pi * 2.0) })

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Offset Vertex Arc Arc",
            profile: ProfileReference(featureID: setup.featureID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func offsetCurveCommandRejectsPlanarOptionsForVertexDispatchBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Offset Curve Vertex Option Rejection",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())

    do {
        _ = try session.execute(
            .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true, gapFill: .linear),
                vertexHandle: .lineEnd
            )
        )
        Issue.record("Offset Curve vertex dispatch must reject planar curve options.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("vertex dispatch"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func offsetSketchVertexCommandRejectsOpenSingleLineBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Open Vertex Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    do {
        _ = try session.execute(
            .offsetSketchVertex(
                target: target,
                handle: .lineEnd,
                distance: .length(2.0, .millimeter)
            )
        )
        Issue.record("Open single-line vertex offset must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("exactly one adjacent line or arc endpoint"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func createSlotSketchCommandCreatesExtrudableCapsuleProfileFromSourceLine() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .createSlotSketch(
            target: target,
            width: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Slot Source Line Slot" }
    )
    let slotObject = try #require(
        session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotLines = after.entries.filter {
        $0.sourceFeatureID == slotFeature.id.description && $0.entityKind == "line"
    }
    let slotArcs = after.entries.filter {
        $0.sourceFeatureID == slotFeature.id.description && $0.entityKind == "arc"
    }

    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 2)
    #expect(slotObject.typeID == .slot)
    #expect(slotObject.geometryRole == .sketchProfile)
    #expect(slotObject.properties["width"] == .length(0.002))
    #expect(slotObject.properties["path.length"] == .length(0.010))
    #expect(slotObject.properties["radius"] == .length(0.001))
    #expect(slotLines.count == 2)
    #expect(slotArcs.count == 2)
    #expect(slotLines.contains { line in
        abs((line.start?.y ?? -1.0) - 0.001) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.001) < 1.0e-12
    })
    #expect(slotLines.contains { line in
        abs((line.start?.y ?? -1.0) + 0.001) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) + 0.001) < 1.0e-12
    })

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Slot",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func createSlotSketchCommandCreatesExtrudableProfileFromOpenLineChain() async throws {
    let setup = try lineChainSlotSession(
        name: "Slot Source Chain",
        points: [
            SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(10.0, .millimeter), y: .length(6.0, .millimeter)),
        ]
    )
    let before = try SketchEntitySummaryService().summarize(document: setup.session.document)
    let sourceLine = try #require(before.entries.first { entry in
        entry.sourceFeatureID == setup.featureID.description &&
            entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(sourceLine.selectionTarget())

    let result = try setup.session.execute(
        .createSlotSketch(
            target: target,
            width: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: setup.session.document)
    let slotFeature = try #require(
        setup.session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Slot Source Chain Slot" }
    )
    let slotObject = try #require(
        setup.session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }

    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(setup.session.generation == DocumentGeneration(1))
    #expect(slotObject.typeID == .slot)
    #expect(slotObject.geometryRole == .sketchProfile)
    #expect(slotObject.properties["width"] == .length(0.002))
    #expect(slotObject.properties["path.length"] == .length(0.016))
    #expect(slotObject.properties["radius"] == .length(0.001))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResult = try setup.session.execute(
        .extrudeProfile(
            name: "Extruded Slot Chain",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(setup.session.generation == DocumentGeneration(2))
    #expect(setup.session.evaluationStatus == .valid)
    #expect(setup.session.evaluatedBodyCount == 1)
}

@MainActor
@Test func createSlotSketchCommandCreatesExtrudableProfileFromOpenLineArcChain() async throws {
    let setup = try lineArcChainSlotSession(name: "Slot Source Line Arc Chain")
    let before = try SketchEntitySummaryService().summarize(document: setup.session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try setup.session.execute(
        .createSlotSketch(
            target: target,
            width: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: setup.session.document)
    let slotFeature = try #require(
        setup.session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Slot Source Line Arc Chain Slot" }
    )
    let slotObject = try #require(
        setup.session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    let expectedPathLength = 0.010 + 0.005 * Double.pi / 2.0

    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(setup.session.generation == DocumentGeneration(1))
    #expect(slotObject.typeID == .slot)
    #expect(slotObject.geometryRole == .sketchProfile)
    #expect(slotObject.properties["width"] == .length(0.002))
    if case .length(let pathLength) = slotObject.properties["path.length"] {
        #expect(abs(pathLength - expectedPathLength) < 1.0e-12)
    } else {
        Issue.record("Line-arc Slot must store the source path length.")
    }
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResult = try setup.session.execute(
        .extrudeProfile(
            name: "Extruded Line Arc Slot",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(setup.session.generation == DocumentGeneration(2))
    #expect(setup.session.evaluationStatus == .valid)
    #expect(setup.session.evaluatedBodyCount == 1)
}

@MainActor
@Test func offsetCurveCommandActivatesSlotModeForSourceLine() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Offset Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(mode: .slot),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Offset Slot Source Line Slot" }
    )
    let slotObject = try #require(
        session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(slotObject.typeID == .slot)
    #expect(slotObject.geometryRole == .sketchProfile)
    #expect(slotObject.properties["width"] == .length(0.002))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandActivatesSlotModeForSourceArc() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Offset Slot Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(mode: .slot),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Offset Slot Source Arc Slot" }
    )
    let slotObject = try #require(
        session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(slotObject.typeID == .slot)
    #expect(slotObject.geometryRole == .sketchProfile)
    #expect(slotObject.properties["width"] == .length(0.001))
    #expect(slotEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandActivatesSlotModeForSourceLineArcChain() async throws {
    let setup = try lineArcChainSlotSession(name: "Offset Slot Source Line Arc Chain")
    let before = try SketchEntitySummaryService().summarize(document: setup.session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try setup.session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(mode: .slot),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: setup.session.document)
    let slotFeature = try #require(
        setup.session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Offset Slot Source Line Arc Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(setup.session.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(setup.session.evaluationStatus == .valid)
}

@MainActor
@Test func createSlotSketchCommandRejectsClosedLineChainBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Closed Slot Chain",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    do {
        _ = try session.execute(
            .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            )
        )
        Issue.record("Closed line-chain Slot must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("open curve"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func offsetCurveCommandRejectsSlotModeVertexHandleBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Invalid Offset Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    do {
        _ = try session.execute(
            .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(mode: .slot),
                vertexHandle: .lineEnd
            )
        )
        Issue.record("Offset Curve Slot mode must reject vertex dispatch before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("not a vertex handle"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func offsetCurveCommandRejectsSlotModePlanarOptionsBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Invalid Offset Slot Options Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    let invalidOptions: [(OffsetCurveOptions, String)] = [
        (OffsetCurveOptions(mode: .slot, isSymmetric: true), "planar symmetric"),
        (OffsetCurveOptions(mode: .slot, gapFill: .linear), "planar gap-fill"),
    ]

    for (options, expectedMessage) in invalidOptions {
        do {
            _ = try session.execute(
                .offsetCurve(
                    target: target,
                    distance: .length(2.0, .millimeter),
                    options: options,
                    vertexHandle: nil
                )
            )
            Issue.record("Offset Curve Slot mode must reject planar options before mutation.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
            #expect(error.message.contains(expectedMessage))
        }
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func createSlotSketchCommandCreatesExtrudableProfileFromSourceArc() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Slot Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())

    let result = try session.execute(
        .createSlotSketch(
            target: target,
            width: .length(1.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Slot Source Arc Slot" }
    )
    let slotObject = try #require(
        session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    let expectedPathLength = 0.005 * Double.pi / 2.0

    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 2)
    #expect(slotObject.typeID == .slot)
    #expect(slotObject.geometryRole == .sketchProfile)
    #expect(slotObject.properties["width"] == .length(0.001))
    #expect(slotObject.properties["radius"] == .length(0.0005))
    if case .length(let pathLength) = slotObject.properties["path.length"] {
        #expect(abs(pathLength - expectedPathLength) < 1.0e-12)
    } else {
        Issue.record("Arc Slot must store the source arc path length.")
    }
    #expect(slotEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Arc Slot",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func createSlotSketchCommandRejectsArcWidthThatCollapsesInnerRadiusBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Collapsing Slot Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())

    do {
        _ = try session.execute(
            .createSlotSketch(
                target: target,
                width: .length(10.0, .millimeter)
            )
        )
        Issue.record("Arc Slot width must fail before collapsing the inner radius.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("inner arc radius"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func offsetCurveCommandCreatesSymmetricConcentricSourceCircles() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Symmetric Offset Source Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceCircle = try #require(before.entries.first { $0.entityKind == "circle" })
    let target = try #require(sourceCircle.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(isSymmetric: true, gapFill: .round),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let circles = after.entries.filter { $0.entityKind == "circle" }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(circles.count == 3)
    #expect(circles.contains { abs(($0.radius ?? -1.0) - 0.007) < 1.0e-12 })
    #expect(circles.contains { abs(($0.radius ?? -1.0) - 0.003) < 1.0e-12 })
    #expect(circles.filter { $0.sourceFeatureID != sourceCircle.sourceFeatureID }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesInwardSourceArc() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Offset Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(-1.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = after.entries.filter { $0.entityKind == "arc" }
    let offset = try #require(arcs.first { entry in
        abs((entry.radius ?? -1.0) - 0.004) < 1.0e-12
    })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(arcs.count == 2)
    #expect(abs((offset.startAngle ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((offset.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12)
    #expect(offset.sourceFeatureID != sourceArc.sourceFeatureID)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandRejectsUnsupportedSplineBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Unsupported Offset Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceSpline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(sourceSpline.selectionTarget())

    do {
        _ = try session.execute(
            .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            )
        )
        Issue.record("Spline offset must fail until joined curve offset support exists.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("source line, circle, and arc"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func offsetCurveCommandCreatesSymmetricLineOffsets() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Symmetric Offset Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(isSymmetric: true, gapFill: .linear),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 3)
    #expect(lines.count == 3)
    #expect(lines.contains { entry in
        abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(lines.contains { entry in
        abs((entry.start?.y ?? -1.0) + 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) + 0.002) < 1.0e-12
    })
    #expect(lines.filter { $0.sourceFeatureID != sourceLine.sourceFeatureID }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionOffsetCurveHelperCreatesLinearOffsetSourceRegion() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Session Offset Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try #require(
        session.offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .linear)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != sourceRegion.sourceFeatureID })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount == 8)
    #expect(offsetRegion.boundarySegmentCount == 8)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesLinearOffsetSourceRegion() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Offset Source Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .linear),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != sourceRegion.sourceFeatureID })
    let minX = try #require(offsetRegion.boundaryPoints.map(\.x).min())
    let maxX = try #require(offsetRegion.boundaryPoints.map(\.x).max())
    let minY = try #require(offsetRegion.boundaryPoints.map(\.y).min())
    let maxY = try #require(offsetRegion.boundaryPoints.map(\.y).max())
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == 2)
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount == 8)
    #expect(offsetRegion.boundarySegmentCount == 8)
    #expect(abs(offsetRegion.areaSquareMeters - 0.000_094) < 1.0e-12)
    #expect(abs(minX + 0.001) < 1.0e-12)
    #expect(abs(maxX - 0.011) < 1.0e-12)
    #expect(abs(minY + 0.001) < 1.0e-12)
    #expect(abs(maxY - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesNaturalOffsetSourceRegion() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Natural Offset Source Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .natural),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != sourceRegion.sourceFeatureID })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(offsetRegion.boundaryPointCount == 4)
    #expect(offsetRegion.boundarySegmentCount == 4)
    #expect(abs(offsetRegion.areaSquareMeters - 0.000_096) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesNaturalOffsetConcaveSourceRegion() async throws {
    let session = EditorSession(document: try concaveLineLoopDocument())
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .natural),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != sourceRegion.sourceFeatureID })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    #expect(offsetRegion.boundaryPointCount == 6)
    #expect(offsetRegion.boundarySegmentCount == 6)
    #expect(abs(offsetRegion.areaSquareMeters - 0.000_108) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesRoundOffsetSourceRegionByDefault() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Round Region Gap Fill",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != sourceRegion.sourceFeatureID })
    let offsetEntries = after.entries.filter { $0.sourceFeatureID == offsetRegion.sourceFeatureID }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(offsetRegion.boundarySegmentCount == 8)
    #expect(offsetRegion.areaSquareMeters > 0.000_095)
    #expect(offsetRegion.areaSquareMeters < 0.000_096)
    #expect(offsetEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(offsetEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandCreatesSymmetricNaturalOffsetSourceRegions() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Symmetric Region Gap Fill",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
            vertexHandle: nil
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegions = after.regions.filter { $0.sourceFeatureID != sourceRegion.sourceFeatureID }
    let areas = offsetRegions.map(\.areaSquareMeters).sorted()
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.counts.sketchCount == before.counts.sketchCount + 2)
    #expect(after.counts.regionCount == before.counts.regionCount + 2)
    #expect(offsetRegions.allSatisfy { $0.boundaryPointCount == 4 })
    #expect(offsetRegions.allSatisfy { $0.boundarySegmentCount == 4 })
    #expect(abs((areas.first ?? 0.0) - 0.000_032) < 1.0e-12)
    #expect(abs((areas.last ?? 0.0) - 0.000_096) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetRegionsCommandCreatesCombinedDisjointSourceRegions() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Combined Region A",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Combined Region B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(30.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(40.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }

    let result = try session.execute(
        .offsetRegions(
            targets: targets,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .natural),
            combinesRegions: true
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newSketches = after.sketches.filter { sketch in
        before.sketches.contains { $0.sourceFeatureID == sketch.sourceFeatureID } == false
    }
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(newSketches.count == 1)
    #expect(newRegions.count == 2)
    #expect(newRegions.allSatisfy { $0.boundaryPointCount == 4 })
    #expect(newRegions.allSatisfy { abs($0.areaSquareMeters - 0.000_096) < 1.0e-12 })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetRegionsCommandCreatesConvexUnionForOverlappingCombinedOutput() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Combined Overlap A",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Combined Overlap B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(11.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(21.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }

    let result = try session.execute(
        .offsetRegions(
            targets: targets,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .natural),
            combinesRegions: true
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newSketches = after.sketches.filter { sketch in
        before.sketches.contains { $0.sourceFeatureID == sketch.sourceFeatureID } == false
    }
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(newSketches.count == 1)
    #expect(newRegions.count == 1)
    let unionRegion = try #require(newRegions.first)
    #expect(unionRegion.boundaryPointCount == 4)
    #expect(unionRegion.boundarySegmentCount == 4)
    #expect(abs(unionRegion.areaSquareMeters - 0.000_184) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetRegionsCommandCreatesConcaveCombinedUnion() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Combined Concave A",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Combined Concave B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(15.0, .millimeter),
                y: .length(11.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }

    let result = try session.execute(
        .offsetRegions(
            targets: targets,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .natural),
            combinesRegions: true
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newSketches = after.sketches.filter { sketch in
        before.sketches.contains { $0.sourceFeatureID == sketch.sourceFeatureID } == false
    }
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(newSketches.count == 1)
    #expect(newRegions.count == 1)
    let unionRegion = try #require(newRegions.first)
    #expect(unionRegion.boundaryPointCount == 8)
    #expect(unionRegion.boundarySegmentCount == 8)
    #expect(abs(unionRegion.areaSquareMeters - 0.000_171) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetCurveCommandRejectsCollapsingSymmetricRegionBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Collapsing Symmetric Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    do {
        _ = try session.execute(
            .offsetCurve(
                target: target,
                distance: .length(4.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
                vertexHandle: nil
            )
        )
        Issue.record("Offset Region must reject collapsing symmetric output before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("collapse") || error.message.contains("invert"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.regionCount == before.counts.regionCount)
}

@Test func offsetRegionBuilderCreatesNaturalConcaveProfile() throws {
    let result = try OffsetRegionBuilder().buildOffset(
        profile: concaveLineLoopProfile(),
        gapFill: .natural,
        distanceMeters: 0.001
    )

    #expect(result.boundaryPointCount == 6)
    #expect(abs(result.areaSquareMeters - 0.000_108) < 1.0e-12)
}

@Test func offsetRegionBuilderCreatesLinearConcaveProfile() throws {
    let result = try OffsetRegionBuilder().buildOffset(
        profile: concaveLineLoopProfile(),
        gapFill: .linear,
        distanceMeters: 0.001
    )

    #expect(result.boundaryPointCount == 11)
    #expect(abs(result.areaSquareMeters - 0.000_105_5) < 1.0e-12)
}

@Test func offsetRegionBuilderKeepsLinearCollinearSplitProfileValid() throws {
    let result = try OffsetRegionBuilder().buildOffset(
        profile: collinearSplitLineLoopProfile(),
        gapFill: .linear,
        distanceMeters: 0.001
    )

    #expect(result.boundaryPointCount == 9)
    #expect(abs(result.areaSquareMeters - 0.000_094) < 1.0e-12)
}

@Test func offsetRegionBuilderRejectsRoundConcaveProfile() throws {
    do {
        _ = try OffsetRegionBuilder().buildOffset(
            profile: concaveLineLoopProfile(),
            gapFill: .round,
            distanceMeters: 0.001
        )
        Issue.record("Offset Region builder must reject round gap fill for concave source regions.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("round"))
        #expect(error.message.contains("concave"))
    }
}

@MainActor
@Test func offsetCurveCommandRejectsCollapsingSymmetricCircleBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Symmetric Offset Collapse Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(1.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceCircle = try #require(before.entries.first { $0.entityKind == "circle" })
    let target = try #require(sourceCircle.selectionTarget())

    do {
        _ = try session.execute(
            .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true, gapFill: .round),
                vertexHandle: nil
            )
        )
        Issue.record("Symmetric circle offset must fail before creating one side when either radius collapses.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("collapse the radius"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(after.counts.sketchCount == before.counts.sketchCount)
    #expect(after.counts.entityCount == before.counts.entityCount)
}

@MainActor
@Test func moveSketchEntityPointPropagatesCoincidentRectangleCorner() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Move Constrained Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        isHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(2.0, .millimeter),
            deltaY: .length(0.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedBottom = try #require(after.entries.first { $0.entityID == bottomLine.entityID })
    let bodyNode = try #require(bodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(abs((movedBottom.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((movedBottom.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(containsSketchPoint(after, x: 0.0, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.012, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.012, y: 0.005))
    #expect(containsSketchPoint(after, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.y"]?.lengthValue ?? -1.0) - 0.003) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointRejectsFixedCoincidentRectangleCorner() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Fixed Corner Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        isHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())
    let featureID = try #require(UUID(uuidString: bottomLine.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: bottomLine.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
        )
    )

    do {
        _ = try session.execute(
            .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(2.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            )
        )
        Issue.record("Moving a fixed sketch point must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch point move cannot move a fixed sketch point.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(2))
    #expect(containsSketchPoint(after, x: 0.0, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.010, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.010, y: 0.005))
    #expect(containsSketchPoint(after, x: 0.0, y: 0.005))
}

@MainActor
@Test func moveSketchEntityPointPropagatesParallelLineAngle() async throws {
    let setup = try twoLineConstrainedSketchDocument(
        name: "Parallel Line Pair",
        constraint: { .parallel($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.010, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(after.entries.first { $0.entityID == setup.firstLineID.description })
    let movedFollower = try #require(after.entries.first { $0.entityID == setup.secondLineID.description })
    let expectedFollowerEndOffset = 0.005 / sqrt(2.0)
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lineEntriesAreParallel(movedSource, movedFollower))
    #expect(abs((movedFollower.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((movedFollower.start?.y ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((movedFollower.end?.x ?? -1.0) - expectedFollowerEndOffset) < 1.0e-12)
    #expect(abs((movedFollower.end?.y ?? -1.0) - (0.005 + expectedFollowerEndOffset)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointPropagatesChainedParallelLineAngles() async throws {
    let setup = try threeLineParallelSketchDocument(name: "Chained Parallel Line Pair")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.010, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(after.entries.first { $0.entityID == setup.firstLineID.description })
    let firstFollower = try #require(after.entries.first { $0.entityID == setup.secondLineID.description })
    let secondFollower = try #require(after.entries.first { $0.entityID == setup.thirdLineID.description })
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(lineEntriesAreParallel(movedSource, firstFollower))
    #expect(lineEntriesAreParallel(firstFollower, secondFollower))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointPropagatesPerpendicularLineAngle() async throws {
    let setup = try twoLineConstrainedSketchDocument(
        name: "Perpendicular Line Pair",
        constraint: { .perpendicular($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.010, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(after.entries.first { $0.entityID == setup.firstLineID.description })
    let movedFollower = try #require(after.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(lineEntriesArePerpendicular(movedSource, movedFollower))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointPropagatesEqualLengthLineConstraint() async throws {
    let setup = try twoLineConstrainedSketchDocument(
        name: "Equal Length Line Pair",
        constraint: { .equalLength($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.010, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(after.entries.first { $0.entityID == setup.firstLineID.description })
    let resizedFollower = try #require(after.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(abs(lineEntryLength(movedSource) - lineEntryLength(resizedFollower)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointPropagatesTangentCircleConstraint() async throws {
    let setup = try lineCircleTangentSketchDocument(name: "Tangent Circle Source")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(line.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.010, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedLine = try #require(after.entries.first { $0.entityID == setup.lineID.description })
    let movedCircle = try #require(after.entries.first { $0.entityID == setup.circleID.description })
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(abs(lineCircleDistance(movedLine, movedCircle) - (movedCircle.radius ?? -1.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointPropagatesConcentricCircleConstraint() async throws {
    let setup = try twoCircleConstrainedSketchDocument(
        name: "Concentric Circle Pair",
        constraint: { .concentric($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceCircle = try #require(before.entries.first { $0.entityID == setup.firstCircleID.description })
    let target = try #require(sourceCircle.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .circleCenter,
            deltaX: .length(0.004, .meter),
            deltaY: .length(0.005, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(after.entries.first { $0.entityID == setup.firstCircleID.description })
    let movedFollower = try #require(after.entries.first { $0.entityID == setup.secondCircleID.description })
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(abs((movedSource.center?.x ?? -1.0) - (movedFollower.center?.x ?? -2.0)) < 1.0e-12)
    #expect(abs((movedSource.center?.y ?? -1.0) - (movedFollower.center?.y ?? -2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchCircleParametersPropagatesEqualRadiusConstraint() async throws {
    let setup = try twoCircleConstrainedSketchDocument(
        name: "Equal Radius Circle Pair",
        constraint: { .equalRadius($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceCircle = try #require(before.entries.first { $0.entityID == setup.firstCircleID.description })
    let target = try #require(sourceCircle.selectionTarget())

    let result = try session.execute(
        .setSketchCircleParameters(
            target: target,
            center: nil,
            radius: .length(0.006, .meter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSource = try #require(after.entries.first { $0.entityID == setup.firstCircleID.description })
    let updatedFollower = try #require(after.entries.first { $0.entityID == setup.secondCircleID.description })
    #expect(result.commandName == "setSketchCircleParameters")
    #expect(result.didMutate)
    #expect(abs((updatedSource.radius ?? -1.0) - 0.006) < 1.0e-12)
    #expect(abs((updatedSource.radius ?? -1.0) - (updatedFollower.radius ?? -2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointRejectsParallelLineWithBothFollowerEndpointsFixed() async throws {
    var setup = try twoLineConstrainedSketchDocument(
        name: "Fixed Parallel Line Pair",
        constraint: { .parallel($0, $1) }
    )
    try appendSketchConstraints(
        [
            .fixed(.lineStart(setup.secondLineID)),
            .fixed(.lineEnd(setup.secondLineID)),
        ],
        toFeature: setup.featureID,
        in: &setup.document
    )
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    do {
        _ = try session.execute(
            .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(0.0, .meter),
                deltaY: .length(0.010, .meter)
            )
        )
        Issue.record("Moving the source line must fail when the constrained follower has both endpoints fixed.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch point move cannot satisfy a fixed sketch line angle constraint.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let follower = try #require(after.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(session.generation == DocumentGeneration(0))
    #expect(abs((follower.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((follower.start?.y ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((follower.end?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((follower.end?.y ?? -1.0) - 0.005) < 1.0e-12)
}

@MainActor
@Test func setSketchCircleParametersCommandUpdatesRadiusAndCenter() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Editable Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(3.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(before.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())

    let result = try session.execute(
        .setSketchCircleParameters(
            target: target,
            center: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            radius: .length(6.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedCircle = try #require(after.entries.first { $0.entityKind == "circle" })
    let featureID = try #require(UUID(uuidString: updatedCircle.sourceFeatureID)).featureID
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    #expect(result.commandName == "setSketchCircleParameters")
    #expect(result.didMutate)
    #expect(abs((updatedCircle.center?.x ?? -1.0) - 0.004) < 1.0e-12)
    #expect(abs((updatedCircle.center?.y ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((updatedCircle.radius ?? -1.0) - 0.006) < 1.0e-12)
    #expect(sceneNode.object?.properties["radius"] == .length(0.006))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchArcParametersCommandUpdatesAnalyticValues() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Editable Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let result = try session.execute(
        .setSketchArcParameters(
            target: target,
            center: nil,
            radius: .length(8.0, .millimeter),
            startAngle: nil,
            endAngle: .angle(120.0, .degree)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(after.entries.first { $0.entityKind == "arc" })
    let featureID = try #require(UUID(uuidString: updatedArc.sourceFeatureID)).featureID
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    #expect(result.commandName == "setSketchArcParameters")
    #expect(result.didMutate)
    #expect(abs((updatedArc.radius ?? -1.0) - 0.008) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (Double.pi * 2.0 / 3.0)) < 1.0e-12)
    #expect(abs((updatedArc.end?.x ?? -1.0) - (-0.004)) < 1.0e-12)
    #expect(abs((updatedArc.end?.y ?? -1.0) - 0.006_928_203_230_275_509) < 1.0e-12)
    #expect(sceneNode.object?.properties["radius"] == .length(0.008))
    #expect(abs((sceneNode.object?.properties["end.angle"]?.angleValue ?? -1.0) - 120.0) < 1.0e-9)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchArcParametersRejectsFullCircleArc() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Partial Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    do {
        _ = try session.execute(
            .setSketchArcParameters(
                target: target,
                center: nil,
                radius: nil,
                startAngle: nil,
                endAngle: .angle(360.0, .degree)
            )
        )
        Issue.record("A full-circle arc parameter update must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchangedArc = try #require(after.entries.first { $0.entityKind == "arc" })
    #expect(session.generation == DocumentGeneration(1))
    #expect(abs((unchangedArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
}

@MainActor
@Test func extendSketchCurveExtendsLineEndpointAndSupportsUndoRedo() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Extend Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try pointHandleSelectionTarget(line, handle: .lineEnd)

    let result = try session.execute(
        .extendSketchCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            shape: .linear
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((extendedLine.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((extendedLine.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((extendedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)

    _ = try session.undo()
    let undone = try SketchEntitySummaryService().summarize(document: session.document)
    let restoredLine = try #require(undone.entries.first { $0.entityID == line.entityID })
    #expect(session.generation == DocumentGeneration(3))
    #expect(abs((restoredLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)

    _ = try session.redo()
    let redone = try SketchEntitySummaryService().summarize(document: session.document)
    let redoneLine = try #require(redone.entries.first { $0.entityID == line.entityID })
    #expect(session.generation == DocumentGeneration(4))
    #expect(abs((redoneLine.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func extendSketchCurveExtendsArcEndpointByArcLength() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Extend Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try pointHandleSelectionTarget(arc, handle: .arcEnd)

    let result = try session.execute(
        .extendSketchCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            shape: .arc
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedArc = try #require(after.entries.first { $0.entityID == arc.entityID })
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(abs((extendedArc.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(abs((extendedArc.startAngle ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((extendedArc.endAngle ?? -1.0) - (Double.pi / 2.0 + 0.5)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func extendSketchCurveAppendsLinearSplineSegment() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Extend Source Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try controlPointSelectionTarget(spline, index: 3)

    let result = try session.execute(
        .extendSketchCurve(
            target: target,
            distance: .length(3.0, .millimeter),
            shape: .linear
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(extendedSpline.controlPoints.count == 7)
    #expect(abs(extendedSpline.controlPoints[4].x - 0.004) < 1.0e-12)
    #expect(abs(extendedSpline.controlPoints[5].x - 0.005) < 1.0e-12)
    #expect(abs(extendedSpline.controlPoints[6].x - 0.006) < 1.0e-12)
    #expect(abs(extendedSpline.controlPoints[6].y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func extendSketchCurveRejectsWholeCurveTarget() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Extend Whole Curve Rejection",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    do {
        _ = try session.execute(
            .extendSketchCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                shape: .linear
            )
        )
        Issue.record("Extend Curve must reject whole-curve selection targets.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchangedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    #expect(session.generation == DocumentGeneration(1))
    #expect(abs((unchangedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
}

@MainActor
@Test func applySketchCornerTreatmentFilletsConnectedLineCorner() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Source Fillet Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(bottomRectangleLine(in: before))
    let sourceFeatureID = try #require(UUID(uuidString: bottomLine.sourceFeatureID)).featureID
    let target = try pointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(2.0, .millimeter),
            treatment: .fillet
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    let arcs = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc" }
    let filletArc = try #require(arcs.first)
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 4)
    #expect(arcs.count == 1)
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.008) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(abs((filletArc.center?.x ?? -1.0) - 0.008) < 1.0e-12)
    #expect(abs((filletArc.center?.y ?? -1.0) - 0.002) < 1.0e-12)
    #expect(abs((filletArc.radius ?? -1.0) - 0.002) < 1.0e-12)

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Source Fillet Rectangle",
            profile: ProfileReference(featureID: sourceFeatureID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func applySketchCornerTreatmentChamfersConnectedLineCorner() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Source Chamfer Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(bottomRectangleLine(in: before))
    let target = try pointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(2.0, .millimeter),
            treatment: .chamfer
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    let arcs = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc" }
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 5)
    #expect(arcs.isEmpty)
    #expect(lines.contains { line in
        abs((line.start?.x ?? -1.0) - 0.008) < 1.0e-12 &&
            abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((line.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func applySketchCornerTreatmentFilletsLineArcCorner() async throws {
    let setup = try lineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try pointHandleSelectionTarget(sourceLine, handle: .lineEnd)

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(0.1, .meter),
            treatment: .fillet
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.1) < 1.0e-12 })
    let sourceArc = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(abs((insertedArc.center?.x ?? -1.0) - (1.0 + sqrt(0.8))) < 1.0e-12)
    #expect(abs((insertedArc.center?.y ?? -1.0) - 0.1) < 1.0e-12)
    #expect((sourceArc.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Source Fillet Line Arc",
            profile: ProfileReference(featureID: setup.featureID),
            distance: .length(0.2, .meter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func applySketchCornerTreatmentFilletsCurvePairSelection() async throws {
    let setup = try lineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceLine.selectionTarget())
    let adjacentTarget = try #require(sourceArc.selectionTarget())

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: adjacentTarget,
            distance: .length(0.1, .meter),
            treatment: .fillet
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.1) < 1.0e-12 })
    let sourceArcAfter = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(abs((insertedArc.center?.x ?? -1.0) - (1.0 + sqrt(0.8))) < 1.0e-12)
    #expect(abs((insertedArc.center?.y ?? -1.0) - 0.1) < 1.0e-12)
    #expect((sourceArcAfter.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArcAfter.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func applySketchCornerTreatmentMigratesDimensionsOnLineArcCorner() async throws {
    let setup = try lineArcCornerTreatmentSketchDocument()
    var document = setup.document
    var feature = try #require(document.cadDocument.designGraph.nodes[setup.featureID])
    guard case var .sketch(sketch) = feature.operation else {
        Issue.record("Dimension migration setup must remain a sketch.")
        return
    }
    sketch.dimensions = [
        .distance(
            from: .lineStart(setup.lineID),
            to: .lineEnd(setup.lineID),
            value: .length(2.0, .meter)
        ),
        .radius(
            entity: setup.arcID,
            value: .length(1.0, .meter)
        ),
        .angle(
            from: .arcStart(setup.arcID),
            to: .arcEnd(setup.arcID),
            value: .angle(Double.pi / 2.0, .radian)
        ),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[setup.featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let session = EditorSession(document: document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try pointHandleSelectionTarget(sourceLine, handle: .lineEnd)

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(0.1, .meter),
            treatment: .fillet
        )
    )

    let updatedSketch = try sketchFeature(in: session.document, featureID: setup.featureID)
    let updatedArc = try #require(updatedSketch.entities[setup.arcID])
    guard case .arc(let sourceArc) = updatedArc else {
        Issue.record("Dimension migration must keep the source arc.")
        return
    }
    let expectedLineLength = 1.0 + sqrt(0.8)
    let expectedArcSpan = try resolvedTestAngle(sourceArc.endAngle, in: session.document) -
        resolvedTestAngle(sourceArc.startAngle, in: session.document)
    let lineLengthDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .distance(.lineStart(let firstID), .lineEnd(let secondID), _) = dimension,
           firstID == setup.lineID,
           secondID == setup.lineID {
            return true
        }
        return false
    })
    let arcRadiusDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .radius(let entityID, _) = dimension,
           entityID == setup.arcID {
            return true
        }
        return false
    })
    let arcAngleDimension = try #require(updatedSketch.dimensions.first { dimension in
        if case .angle(.arcStart(let firstID), .arcEnd(let secondID), _) = dimension,
           firstID == setup.arcID,
           secondID == setup.arcID {
            return true
        }
        return false
    })
    let lineLength = try resolvedTestLength(
        sketchDimensionExpression(lineLengthDimension),
        in: session.document
    )
    let arcRadius = try resolvedTestLength(
        sketchDimensionExpression(arcRadiusDimension),
        in: session.document
    )
    let arcSpan = try resolvedTestAngle(
        sketchDimensionExpression(arcAngleDimension),
        in: session.document
    )
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(updatedSketch.dimensions.count == 3)
    #expect(abs(lineLength - expectedLineLength) < 1.0e-12)
    #expect(abs(arcRadius - 1.0) < 1.0e-12)
    #expect(abs(arcSpan - expectedArcSpan) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func applySketchCornerTreatmentChamfersArcLineCorner() async throws {
    let setup = try lineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try pointHandleSelectionTarget(sourceArc, handle: .arcEnd)

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(0.1, .meter),
            treatment: .chamfer
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let sourceArcAfter = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 4)
    #expect(arcs.count == 1)
    #expect((sourceArcAfter.endAngle ?? Double.pi) < Double.pi / 2.0)
    let expectedArcTrimPoint = (
        x: 1.0 + sin(0.1),
        y: cos(0.1)
    )
    let expectedLineTrimPoint = (
        x: 1.0 - 0.1 / sqrt(1.25),
        y: 1.0 - 0.05 / sqrt(1.25)
    )
    #expect(lines.contains { line in
        (
            pointMatches(line.start, x: expectedArcTrimPoint.x, y: expectedArcTrimPoint.y) &&
                pointMatches(line.end, x: expectedLineTrimPoint.x, y: expectedLineTrimPoint.y)
        ) || (
            pointMatches(line.start, x: expectedLineTrimPoint.x, y: expectedLineTrimPoint.y) &&
                pointMatches(line.end, x: expectedArcTrimPoint.x, y: expectedArcTrimPoint.y)
        )
    })

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Source Chamfer Arc Line",
            profile: ProfileReference(featureID: setup.featureID),
            distance: .length(0.2, .meter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func applySketchCornerTreatmentFilletsArcArcCorner() async throws {
    let setup = try arcArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.previousArcID.description })
    let target = try pointHandleSelectionTarget(sourceArc, handle: .arcEnd)

    let result = try session.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(0.1, .meter),
            treatment: .fillet
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.1) < 1.0e-12 })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 1)
    #expect(arcs.count == 3)
    #expect(insertedArc.center != nil)
    #expect(insertedArc.startAngle != nil)
    #expect(insertedArc.endAngle != nil)

    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Extruded Source Fillet Arc Arc",
            profile: ProfileReference(featureID: setup.featureID),
            distance: .length(0.2, .meter),
            direction: .normal
        )
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func applySketchCornerTreatmentRejectsWholeCurveTarget() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Source Fillet Whole Curve Rejection",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(bottomRectangleLine(in: before))
    let target = try #require(bottomLine.selectionTarget())

    do {
        _ = try session.execute(
            .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(2.0, .millimeter),
                treatment: .fillet
            )
        )
        Issue.record("Sketch corner treatment must reject whole-curve selection targets.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(session.generation == DocumentGeneration(1))
    #expect(lines.count == 4)
}

@MainActor
@Test func applySketchCornerTreatmentRejectsCollapsingDistance() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Source Fillet Collapse Rejection",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(bottomRectangleLine(in: before))
    let target = try pointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    do {
        _ = try session.execute(
            .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(10.0, .millimeter),
                treatment: .fillet
            )
        )
        Issue.record("Sketch corner treatment must reject distances that collapse adjacent line sides.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    let arcs = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc" }
    #expect(session.generation == DocumentGeneration(1))
    #expect(lines.count == 4)
    #expect(arcs.isEmpty)
}

@MainActor
@Test func moveSketchSplineControlPointCommandUpdatesControlPointAndMetadata() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Editable Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID

    let result = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 2,
            deltaX: .length(-1.0, .millimeter),
            deltaY: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    let unchangedControlPoint = try #require(updatedSpline.controlPoints.dropFirst(1).first)
    let movedControlPoint = try #require(updatedSpline.controlPoints.dropFirst(2).first)
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    #expect(result.commandName == "moveSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(updatedSpline.controlPoints.count == 4)
    #expect(abs(unchangedControlPoint.x - 0.002) < 1.0e-12)
    #expect(abs(unchangedControlPoint.y - 0.004) < 1.0e-12)
    #expect(abs(movedControlPoint.x - 0.005) < 1.0e-12)
    #expect(abs(movedControlPoint.y - 0.006) < 1.0e-12)
    #expect(sceneNode.object?.properties["control.point.count"] == .integer(4))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func slideSketchSplineControlPointsCommandUsesControlCageDirections() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Slide CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let positiveUResult = try session.execute(
        .slideSketchSplineControlPoints(
            target: target,
            controlPointIndexes: [1],
            direction: .positiveU,
            distance: .length(1.0, .millimeter)
        )
    )
    let afterPositiveU = try SketchEntitySummaryService().summarize(document: session.document)
    let positiveUSpline = try #require(afterPositiveU.entries.first { $0.entityID == spline.entityID })
    #expect(positiveUResult.commandName == "slideSketchSplineControlPoints")
    #expect(positiveUResult.didMutate)
    #expect(positiveUResult.generation == DocumentGeneration(2))
    #expect(abs(positiveUSpline.controlPoints[1].x - 0.003) < 1.0e-12)
    #expect(abs(positiveUSpline.controlPoints[1].y - 0.0) < 1.0e-12)

    let normalResult = try session.execute(
        .slideSketchSplineControlPoints(
            target: target,
            controlPointIndexes: [1],
            direction: .normal,
            distance: .length(2.0, .millimeter)
        )
    )
    let afterNormal = try SketchEntitySummaryService().summarize(document: session.document)
    let normalSpline = try #require(afterNormal.entries.first { $0.entityID == spline.entityID })
    #expect(normalResult.commandName == "slideSketchSplineControlPoints")
    #expect(normalResult.didMutate)
    #expect(normalResult.generation == DocumentGeneration(3))
    #expect(abs(normalSpline.controlPoints[1].x - 0.003) < 1.0e-12)
    #expect(abs(normalSpline.controlPoints[1].y - 0.002) < 1.0e-12)

    let signedDistanceResult = try session.execute(
        .slideSketchSplineControlPoints(
            target: target,
            controlPointIndexes: [1],
            direction: .positiveU,
            distance: .length(-1.0, .millimeter)
        )
    )
    let afterSignedDistance = try SketchEntitySummaryService().summarize(document: session.document)
    let signedDistanceSpline = try #require(afterSignedDistance.entries.first { $0.entityID == spline.entityID })
    #expect(signedDistanceResult.commandName == "slideSketchSplineControlPoints")
    #expect(signedDistanceResult.didMutate)
    #expect(signedDistanceResult.generation == DocumentGeneration(4))
    #expect(abs(signedDistanceSpline.controlPoints[1].x - 0.002) < 1.0e-12)
    #expect(abs(signedDistanceSpline.controlPoints[1].y - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func slideSketchSplineControlPointsMoveMultipleCVsInOneMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Slide Multiple CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try session.execute(
        .slideSketchSplineControlPoints(
            target: target,
            controlPointIndexes: [1, 2],
            direction: .normal,
            distance: .length(1.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "slideSketchSplineControlPoints")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[0].x - 0.0) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[0].y - 0.0) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].x - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.001) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].x - 0.006) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].y - 0.001) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[3].x - 0.008) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[3].y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func slideSketchSplineControlPointsRejectInvalidIndexesBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Slide CV Bounds Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    do {
        _ = try session.execute(
            .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: [9],
                direction: .positiveU,
                distance: .length(1.0, .millimeter)
            )
        )
        Issue.record("Out-of-range spline control point slide must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
        #expect(error.message == "Sketch spline control point slide requires existing control points.")
    }
    do {
        _ = try session.execute(
            .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: [1, 1],
                direction: .normal,
                distance: .length(1.0, .millimeter)
            )
        )
        Issue.record("Duplicate spline control point slide indexes must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch spline control point slide requires unique control point indexes.")
    }
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func insertSketchSplineControlPointPreservesCurveAsBezierChain() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Insert CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(0.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID

    let result = try session.execute(
        .insertSketchSplineControlPoint(
            target: target,
            fraction: .scalar(0.5)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    #expect(result.commandName == "insertSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(updatedSpline.controlPoints.count == 7)
    #expect(abs(updatedSpline.controlPoints[1].x - 0.0) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].x - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].y - 0.003) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[3].x - 0.004) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[3].y - 0.003) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[4].x - 0.006) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[4].y - 0.003) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[5].x - 0.008) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[5].y - 0.002) < 1.0e-12)
    #expect(sceneNode.object?.properties["control.point.count"] == .integer(7))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func insertSketchSplineControlPointMigratesLaterControlPointReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Insert CV Reference Migration",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(0.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 3))
        )
    )

    let result = try session.execute(
        .insertSketchSplineControlPoint(
            target: target,
            fraction: .scalar(0.5)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    let constraint = try #require(updatedSpline.constraints.first { $0.kind == "fixed" })
    #expect(result.commandName == "insertSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(updatedSpline.controlPoints.count == 7)
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):6"])
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func insertSketchSplineControlPointRejectsReplacedHandleReferencesWithoutMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Insert CV Handle Reference Rejection",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(0.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 1))
        )
    )

    do {
        _ = try session.execute(
            .insertSketchSplineControlPoint(
                target: target,
                fraction: .scalar(0.5)
            )
        )
        Issue.record("Insert CV must reject references to replaced spline handles before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch spline control point insertion cannot preserve references to replaced spline handles yet.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchangedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(session.generation == DocumentGeneration(2))
    #expect(unchangedSpline.controlPoints.count == 4)
}

@MainActor
@Test func rebuildSketchCurvePointsMethodPreservesSameCubicControlLayout() async throws {
    let session = EditorSession()
    let originalControlPoints = [
        sketchTestPoint(x: 0.000, y: 0.000),
        sketchTestPoint(x: 0.001, y: 0.002),
        sketchTestPoint(x: 0.002, y: 0.003),
        sketchTestPoint(x: 0.003, y: 0.000),
        sketchTestPoint(x: 0.004, y: -0.003),
        sketchTestPoint(x: 0.006, y: -0.003),
        sketchTestPoint(x: 0.007, y: 0.000),
    ]
    _ = try session.execute(
        .createSplineSketch(
            name: "Rebuild Same Points Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: originalControlPoints)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try session.execute(
        .rebuildSketchCurve(
            target: target,
            options: .points(controlPointCount: 7)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuilt = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let report = try #require(result.curveRebuildReport)
    #expect(report.method == .points)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == originalControlPoints.count)
    #expect(report.rebuiltControlPointCount == originalControlPoints.count)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 2)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters < 1.0e-12)
    #expect(report.rootMeanSquareDeviationMeters < 1.0e-12)
    #expect(report.maximumDeviationFraction >= 0.0)
    #expect(report.maximumDeviationFraction <= 1.0)
    #expect(rebuilt.controlPoints.count == originalControlPoints.count)
    for (index, controlPoint) in rebuilt.controlPoints.enumerated() {
        let expected = originalControlPoints[index]
        let expectedX = try session.document.cadDocument.parameters.resolvedValue(for: expected.x).value
        let expectedY = try session.document.cadDocument.parameters.resolvedValue(for: expected.y).value
        #expect(abs(controlPoint.x - expectedX) < 1.0e-12)
        #expect(abs(controlPoint.y - expectedY) < 1.0e-12)
    }
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurvePointsMethodChangesControlPointCountAndPreservesEndpoints() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Rebuild Reduced Points Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.002),
                sketchTestPoint(x: 0.002, y: 0.003),
                sketchTestPoint(x: 0.003, y: 0.000),
                sketchTestPoint(x: 0.004, y: -0.003),
                sketchTestPoint(x: 0.006, y: -0.003),
                sketchTestPoint(x: 0.007, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try session.execute(
        .rebuildSketchCurve(
            target: target,
            options: .points(controlPointCount: 4)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuilt = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(rebuilt.controlPoints.count == 4)
    #expect(abs((rebuilt.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuilt.controlPoints.first?.y ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuilt.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(abs((rebuilt.controlPoints.last?.y ?? -1.0) - 0.000) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurveRefitReducesSmoothSplineWithinTolerance() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Refit Smooth Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.001),
                sketchTestPoint(x: 0.002, y: 0.001),
                sketchTestPoint(x: 0.003, y: 0.000),
                sketchTestPoint(x: 0.004, y: -0.001),
                sketchTestPoint(x: 0.006, y: -0.001),
                sketchTestPoint(x: 0.007, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try session.execute(
        .rebuildSketchCurve(
            target: target,
            options: .refit(
                tolerance: .length(20.0, .millimeter),
                keepsCorners: false
            )
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuilt = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(rebuilt.controlPoints.count == 4)
    #expect(abs((rebuilt.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuilt.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurveRefitKeepsCornerAndMigratesReference() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Refit Keep Corner Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.000),
                sketchTestPoint(x: 0.002, y: 0.000),
                sketchTestPoint(x: 0.003, y: 0.000),
                sketchTestPoint(x: 0.004, y: 0.000),
                sketchTestPoint(x: 0.005, y: 0.000),
                sketchTestPoint(x: 0.006, y: 0.000),
                sketchTestPoint(x: 0.006, y: 0.001),
                sketchTestPoint(x: 0.006, y: 0.002),
                sketchTestPoint(x: 0.006, y: 0.003),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 6))
        )
    )

    let result = try session.execute(
        .rebuildSketchCurve(
            target: target,
            options: .refit(
                tolerance: .length(100.0, .millimeter),
                keepsCorners: true
            )
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuilt = try #require(after.entries.first { $0.entityID == spline.entityID })
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Rebuilt feature must remain a sketch.")
        return
    }
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(rebuilt.controlPoints.count == 7)
    #expect(abs(rebuilt.controlPoints[3].x - 0.006) < 1.0e-12)
    #expect(abs(rebuilt.controlPoints[3].y - 0.000) < 1.0e-12)
    #expect(sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 3))))
    #expect(!sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 6))))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurveExplicitControlUsesRequestedSpansAndWeight() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Explicit Control Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.002),
                sketchTestPoint(x: 0.002, y: 0.003),
                sketchTestPoint(x: 0.003, y: 0.000),
                sketchTestPoint(x: 0.004, y: -0.003),
                sketchTestPoint(x: 0.006, y: -0.003),
                sketchTestPoint(x: 0.007, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try session.execute(
        .rebuildSketchCurve(
            target: target,
            options: .explicitControl(
                degree: 3,
                spanCount: 2,
                weight: 0.0
            )
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuilt = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let report = try #require(result.curveRebuildReport)
    #expect(report.method == .explicitControl)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 7)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 2)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(report.maximumDeviationFraction >= 0.0)
    #expect(report.maximumDeviationFraction <= 1.0)
    #expect(rebuilt.controlPoints.count == 7)
    #expect(abs(rebuilt.controlPoints[1].x - 0.001) < 1.0e-12)
    #expect(abs(rebuilt.controlPoints[1].y - 0.000) < 1.0e-12)
    #expect(abs(rebuilt.controlPoints[2].x - 0.002) < 1.0e-12)
    #expect(abs(rebuilt.controlPoints[2].y - 0.000) < 1.0e-12)
    #expect(abs(rebuilt.controlPoints[4].x - (0.003 + 0.004 / 3.0)) < 1.0e-12)
    #expect(abs(rebuilt.controlPoints[4].y - 0.000) < 1.0e-12)
    #expect(abs((rebuilt.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurveExplicitControlRejectsUnsupportedDegreeBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Explicit Control Unsupported Degree",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.002),
                sketchTestPoint(x: 0.002, y: 0.003),
                sketchTestPoint(x: 0.003, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    do {
        _ = try session.execute(
            .rebuildSketchCurve(
                target: target,
                options: .explicitControl(
                    degree: 5,
                    spanCount: 2,
                    weight: 0.5
                )
            )
        )
        Issue.record("Explicit Control must reject unsupported non-cubic degree output.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("degree 5"))
    }

    #expect(session.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurveMigratesEndpointReferencesWhenPointCountChanges() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Rebuild Endpoint Reference Migration",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.002),
                sketchTestPoint(x: 0.002, y: 0.003),
                sketchTestPoint(x: 0.003, y: 0.000),
                sketchTestPoint(x: 0.004, y: -0.003),
                sketchTestPoint(x: 0.006, y: -0.003),
                sketchTestPoint(x: 0.007, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 6))
        )
    )

    let result = try session.execute(
        .rebuildSketchCurve(
            target: target,
            options: .points(controlPointCount: 4)
        )
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Rebuilt feature must remain a sketch.")
        return
    }
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 3))))
    #expect(!sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 6))))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func rebuildSketchCurveRejectsInternalReferencesWhenPointCountChanges() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Rebuild Internal Reference Rejection",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.001, y: 0.002),
                sketchTestPoint(x: 0.002, y: 0.003),
                sketchTestPoint(x: 0.003, y: 0.000),
                sketchTestPoint(x: 0.004, y: -0.003),
                sketchTestPoint(x: 0.006, y: -0.003),
                sketchTestPoint(x: 0.007, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 3))
        )
    )

    do {
        _ = try session.execute(
            .rebuildSketchCurve(
                target: target,
                options: .points(controlPointCount: 4)
            )
        )
        Issue.record("Rebuild Curve must reject internal CV references when point count changes.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("internal spline control-point references"))
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchanged = try #require(after.entries.first { $0.entityID == spline.entityID })
    #expect(session.generation == DocumentGeneration(2))
    #expect(unchanged.controlPoints.count == 7)
}

@MainActor
@Test func addSketchConstraintCommandLocksSplineControlPoint() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Fixed Spline Control Point",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID

    let result = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 0))
        )
    )

    let constrained = try SketchEntitySummaryService().summarize(document: session.document)
    let constrainedSpline = try #require(constrained.entries.first { $0.entityID == spline.entityID })
    let constraint = try #require(constrainedSpline.constraints.first { $0.kind == "fixed" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):0"])
    #expect(session.evaluationStatus == .valid)

    do {
        _ = try session.execute(
            .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 0,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(1.0, .millimeter)
            )
        )
        Issue.record("Fixed spline control point move must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch spline control point move cannot move a fixed sketch point.")
    }
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func addSketchConstraintCommandPropagatesCoincidentSplineControlPoint() async throws {
    let setup = try splinePointConstraintCommandDocument(name: "Coincident Spline Control Point")
    let session = EditorSession(document: setup.document)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .coincident(
                .splineControlPoint(entity: setup.splineID, index: 0),
                .entity(setup.pointID)
            )
        )
    )
    let afterConstraint = try SketchEntitySummaryService().summarize(document: session.document)
    let constrainedPoint = try #require(afterConstraint.entries.first { $0.entityID == setup.pointID.description })
    let target = try #require(
        afterConstraint.entries.first { $0.entityID == setup.splineID.description }?.selectionTarget()
    )
    let coincidentCenter = try #require(constrainedPoint.center)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(coincidentCenter.x - 0.0) < 1.0e-12)
    #expect(abs(coincidentCenter.y - 0.0) < 1.0e-12)

    let moveResult = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 0,
            deltaX: .length(1.0, .millimeter),
            deltaY: .length(2.0, .millimeter)
        )
    )

    let afterMove = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSpline = try #require(afterMove.entries.first { $0.entityID == setup.splineID.description })
    let movedPoint = try #require(afterMove.entries.first { $0.entityID == setup.pointID.description })
    let movedControlPoint = try #require(movedSpline.controlPoints.first)
    let movedCenter = try #require(movedPoint.center)
    #expect(moveResult.commandName == "moveSketchSplineControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(movedControlPoint.x - 0.001) < 1.0e-12)
    #expect(abs(movedControlPoint.y - 0.002) < 1.0e-12)
    #expect(abs(movedCenter.x - 0.001) < 1.0e-12)
    #expect(abs(movedCenter.y - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandSmoothsSplineControlPointAndPropagatesHandles() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Smooth Editable Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID

    let result = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .smoothSplineControlPoint(entity: entityID, index: 3)
        )
    )

    let afterConstraint = try SketchEntitySummaryService().summarize(document: session.document)
    let constrainedSpline = try #require(afterConstraint.entries.first { $0.entityID == spline.entityID })
    let smoothedHandle = try #require(constrainedSpline.controlPoints.dropFirst(4).first)
    let constraint = try #require(constrainedSpline.constraints.first { $0.kind == "smoothSplineControlPoint" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):3"])
    #expect(abs(smoothedHandle.x - 0.005) < 1.0e-12)
    #expect(abs(smoothedHandle.y - (-0.001)) < 1.0e-12)

    let moveResult = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 2,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(1.0, .millimeter)
        )
    )

    let afterMove = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSpline = try #require(afterMove.entries.first { $0.entityID == spline.entityID })
    let incomingHandle = try #require(movedSpline.controlPoints.dropFirst(2).first)
    let outgoingHandle = try #require(movedSpline.controlPoints.dropFirst(4).first)
    #expect(moveResult.commandName == "moveSketchSplineControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(abs(incomingHandle.x - 0.003) < 1.0e-12)
    #expect(abs(incomingHandle.y - 0.002) < 1.0e-12)
    #expect(abs(outgoingHandle.x - 0.005) < 1.0e-12)
    #expect(abs(outgoingHandle.y - (-0.002)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandAlignsSplineEndpointHandleToLine() async throws {
    let setup = try splineLineTangentSketchDocument(name: "Spline Line Tangency")
    let session = EditorSession(document: setup.document)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .splineEndpointTangent(
                spline: setup.splineID,
                endpoint: .start,
                line: setup.lineID
            )
        )
    )

    let afterConstraint = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(afterConstraint.entries.first { $0.entityID == setup.splineID.description })
    let alignedHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let constraint = try #require(spline.constraints.first { $0.kind == "splineEndpointTangent" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.splineID.description):start",
        "entity:\(setup.lineID.description)",
    ])
    #expect(abs(alignedHandle.x - 0.005) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandAlignsTangentSplineEndpoints() async throws {
    let setup = try twoSplineTangentSketchDocument(name: "Spline Endpoint Tangency")
    let session = EditorSession(document: setup.document)
    let firstEndpoint = SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end)
    let secondEndpoint = SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .tangentSplineEndpoints(first: firstEndpoint, second: secondEndpoint)
        )
    )

    let afterConstraint = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(afterConstraint.entries.first {
        $0.entityID == setup.secondSplineID.description
    })
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "tangentSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchSplineControlPointPropagatesTangentSplineEndpoints() async throws {
    let setup = try twoSplineTangentSketchDocument(name: "Moving Spline Endpoint Tangency")
    let session = EditorSession(document: setup.document)
    _ = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .tangentSplineEndpoints(
                first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
            )
        )
    )
    let beforeMove = try SketchEntitySummaryService().summarize(document: session.document)
    let firstSpline = try #require(beforeMove.entries.first { $0.entityID == setup.firstSplineID.description })
    let target = try #require(firstSpline.selectionTarget())

    let result = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 2,
            deltaX: .length(0.0, .meter),
            deltaY: .length(-0.003, .meter)
        )
    )

    let afterMove = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(afterMove.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let expectedOffset = 0.003 / sqrt(2.0)
    #expect(result.commandName == "moveSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(alignedHandle.x - (0.009 + expectedOffset)) < 1.0e-12)
    #expect(abs(alignedHandle.y - expectedOffset) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandAlignsSmoothSplineEndpoints() async throws {
    let setup = try twoSplineTangentSketchDocument(name: "Spline Endpoint Smoothness")
    let session = EditorSession(document: setup.document)
    let firstEndpoint = SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end)
    let secondEndpoint = SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .smoothSplineEndpoints(first: firstEndpoint, second: secondEndpoint)
        )
    )

    let afterConstraint = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(afterConstraint.entries.first {
        $0.entityID == setup.secondSplineID.description
    })
    let alignedEndpoint = try #require(secondSpline.controlPoints.first)
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "smoothSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedEndpoint.x - 0.009) < 1.0e-12)
    #expect(abs(alignedEndpoint.y - 0.0) < 1.0e-12)
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchSplineControlPointPropagatesSmoothSplineEndpoints() async throws {
    let setup = try twoSplineTangentSketchDocument(name: "Moving Spline Endpoint Smoothness")
    let session = EditorSession(document: setup.document)
    _ = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .smoothSplineEndpoints(
                first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
            )
        )
    )
    let beforeMove = try SketchEntitySummaryService().summarize(document: session.document)
    let firstSpline = try #require(beforeMove.entries.first { $0.entityID == setup.firstSplineID.description })
    let target = try #require(firstSpline.selectionTarget())

    let result = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 2,
            deltaX: .length(0.0, .meter),
            deltaY: .length(-0.003, .meter)
        )
    )

    let afterMove = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(afterMove.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedEndpoint = try #require(secondSpline.controlPoints.first)
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    #expect(result.commandName == "moveSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(alignedEndpoint.x - 0.009) < 1.0e-12)
    #expect(abs(alignedEndpoint.y - 0.0) < 1.0e-12)
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.003) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchEntityPointPropagatesSplineEndpointTangencyFromLine() async throws {
    let setup = try splineLineTangentSketchDocument(name: "Spline Tangency From Line")
    let session = EditorSession(document: setup.document)
    _ = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .splineEndpointTangent(
                spline: setup.splineID,
                endpoint: .start,
                line: setup.lineID
            )
        )
    )
    let beforeMove = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(beforeMove.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(line.selectionTarget())

    let result = try session.execute(
        .moveSketchEntityPoint(
            target: target,
            handle: .lineEnd,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.010, .meter)
        )
    )

    let afterMove = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(afterMove.entries.first { $0.entityID == setup.splineID.description })
    let alignedHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let expectedOffset = 0.005 / sqrt(2.0)
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(alignedHandle.x - expectedOffset) < 1.0e-12)
    #expect(abs(alignedHandle.y - expectedOffset) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveSketchSplineControlPointPropagatesSplineEndpointTangencyToLine() async throws {
    let setup = try splineLineTangentSketchDocument(name: "Spline Tangency To Line")
    let session = EditorSession(document: setup.document)
    _ = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .splineEndpointTangent(
                spline: setup.splineID,
                endpoint: .start,
                line: setup.lineID
            )
        )
    )
    let beforeMove = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(beforeMove.entries.first { $0.entityID == setup.splineID.description })
    let target = try #require(spline.selectionTarget())

    let result = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 1,
            deltaX: .length(0.0, .meter),
            deltaY: .length(0.005, .meter)
        )
    )

    let afterMove = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(afterMove.entries.first { $0.entityID == setup.lineID.description })
    let end = try #require(line.end)
    let expectedOffset = 0.010 / sqrt(2.0)
    #expect(result.commandName == "moveSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(end.x - expectedOffset) < 1.0e-12)
    #expect(abs(end.y - (0.006 + expectedOffset)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionUpdatesLineGeometryAndStoresDistanceDimension() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Dimensioned Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(25.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(abs((sceneNode.object?.properties["length"]?.lengthValue ?? -1.0) - 0.025) < 1.0e-12)
}

@MainActor
@Test func setSketchEntityDimensionPreservesFixedLineEnd() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Fixed End Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
        )
    )

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(25.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedLine.start?.x ?? -1.0) - (-0.015)) < 1.0e-12)
    #expect(abs((updatedLine.start?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(abs((sceneNode.object?.properties["length"]?.lengthValue ?? -1.0) - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionUpdatesLineAngleAndStoresAngleDimension() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Angled Dimensioned Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(90.0, .degree)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(abs((updatedLine.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.start?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (Double.pi / 2.0)) < 1.0e-12)
    #expect(dimension.references.contains { $0.hasPrefix("lineStart:") })
    #expect(dimension.references.contains { $0.hasPrefix("lineEnd:") })
    #expect(abs((sceneNode.object?.properties["angle"]?.angleValue ?? -1.0) - 90.0) < 1.0e-9)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionPreservesFixedLineEndForAngle() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Fixed End Angled Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
        )
    )

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(90.0, .degree)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedLine.start?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((updatedLine.start?.y ?? -1.0) - (-0.010)) < 1.0e-12)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionRejectsLineAngleConflictingWithOrientationConstraint() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Horizontally Constrained Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(entityID)
        )
    )

    do {
        _ = try session.execute(
            .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(45.0, .degree)
            )
        )
        Issue.record("Conflicting line angle dimension must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch line dimension update conflicts with a horizontal sketch constraint.")
    } catch {
        Issue.record("Conflicting line angle dimension must throw EditorError.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchangedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    #expect(session.generation == DocumentGeneration(2))
    #expect(abs((unchangedLine.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((unchangedLine.start?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((unchangedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((unchangedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(!unchangedLine.dimensions.contains { $0.kind == "angle" })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionUpdatesConstrainedRectangleSideAndBodyProperties() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Dimensioned Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        isHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())
    let sketchFeatureID = try #require(UUID(uuidString: bottomLine.sourceFeatureID)).featureID
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(25.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedBottom = try #require(after.entries.first { $0.entityID == bottomLine.entityID })
    let dimension = try #require(updatedBottom.dimensions.first { $0.kind == "distance" })
    let sketchFeature = try #require(session.document.cadDocument.designGraph.nodes[sketchFeatureID])
    guard case let .sketch(sketch) = sketchFeature.operation else {
        Issue.record("Dimensioned rectangle source must remain a sketch.")
        return
    }
    let bodyNode = try #require(bodySceneNode(for: bodyFeatureID, in: session.document))

    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(sketch.constraints.count == 8)
    #expect(sketch.dimensions.count == 1)
    #expect(sketchLineEntries(after).count == 4)
    #expect(containsSketchPoint(after, x: 0.0, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.025, y: 0.0))
    #expect(containsSketchPoint(after, x: 0.025, y: 0.005))
    #expect(containsSketchPoint(after, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.y"]?.lengthValue ?? -1.0) - 0.003) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionUpdatesCircleRadiusAndStoresDiameterDimension() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Dimensioned Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(before.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())
    let featureID = try #require(UUID(uuidString: circle.sourceFeatureID)).featureID

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .diameter,
            value: .length(20.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedCircle = try #require(after.entries.first { $0.entityID == circle.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let dimension = try #require(updatedCircle.dimensions.first { $0.kind == "diameter" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(abs((updatedCircle.radius ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.020) < 1.0e-12)
    #expect(abs((sceneNode.object?.properties["radius"]?.lengthValue ?? -1.0) - 0.010) < 1.0e-12)
}

@MainActor
@Test func setSketchEntityDimensionUpdatesArcRadiusAndStoresRadiusDimension() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Dimensioned Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())
    let featureID = try #require(UUID(uuidString: arc.sourceFeatureID)).featureID

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .radius,
            value: .length(12.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(after.entries.first { $0.entityID == arc.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "radius" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(abs((updatedArc.radius ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.012) < 1.0e-12)
    #expect(abs((sceneNode.object?.properties["radius"]?.lengthValue ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((updatedArc.startAngle ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
}

@MainActor
@Test func setSketchEntityDimensionUpdatesArcSpanAndStoresAngleDimension() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Angle Dimensioned Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(120.0, .degree)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(after.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(abs((updatedArc.startAngle ?? -1.0) - (10.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (130.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(dimension.references.count == 2)
}

@MainActor
@Test func setSketchEntityDimensionPreservesFixedArcEndForSpan() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Fixed End Span Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())
    let featureID = try #require(UUID(uuidString: arc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: arc.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
        )
    )

    let result = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(120.0, .degree)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(after.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (-40.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (80.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func setSketchEntityDimensionRejectsConflictingArcSpanWithFixedEndpoints() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Fixed Span Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())
    let featureID = try #require(UUID(uuidString: arc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: arc.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcStart(entityID))
        )
    )
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
        )
    )

    do {
        _ = try session.execute(
            .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            )
        )
        Issue.record("Conflicting fixed endpoint arc span dimension must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch arc span dimension update cannot change an arc with both endpoints fixed.")
    } catch {
        Issue.record("Conflicting fixed endpoint arc span dimension must throw EditorError.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchangedArc = try #require(after.entries.first { $0.entityID == arc.entityID })
    #expect(session.generation == DocumentGeneration(3))
    #expect(abs((unchangedArc.startAngle ?? -1.0) - (10.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((unchangedArc.endAngle ?? -1.0) - (80.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(!unchangedArc.dimensions.contains { $0.kind == "angle" })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func convertSketchLineToArcCommandPreservesEntityTargetAndMigratesReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Bendable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineStart(entityID))
        )
    )

    let result = try session.execute(
        .convertSketchLineToArc(
            target: target,
            sagitta: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(after.entries.first { $0.entityID == line.entityID })
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Converted feature must remain a sketch.")
        return
    }
    #expect(result.commandName == "convertSketchLineToArc")
    #expect(result.didMutate)
    #expect(arc.entityKind == "arc")
    #expect(abs((arc.radius ?? -1.0) - 0.00725) < 1.0e-12)
    #expect(sceneNode.object?.typeID == .arc)
    #expect(sketch.entities[entityID] != nil)
    #expect(sketch.constraints.contains { constraint in
        switch constraint {
        case .fixed(.arcStart(let id)):
            return id == entityID
        default:
            return false
        }
    })
    #expect(!sketch.constraints.contains { constraint in
        switch constraint {
        case .fixed(.lineStart(let id)), .fixed(.lineEnd(let id)):
            return id == entityID
        default:
            return false
        }
    })
}

@MainActor
@Test func convertSketchLineToArcKeepsRectangleProfileExtrudable() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Bendable Profile",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID

    _ = try session.execute(
        .convertSketchLineToArc(
            target: target,
            sagitta: .length(1.0, .millimeter)
        )
    )
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    let extrudeResult = try session.execute(
        .extrudeProfile(
            name: "Curved Profile Body",
            profile: ProfileReference(featureID: featureID),
            distance: .length(5.0, .millimeter),
            direction: .normal
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(after.entries.contains { $0.entityKind == "arc" })
    #expect(sceneNode.object?.typeID == nil)
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func convertSketchLineToSplinePreservesEntityTargetAndEnablesControlPointEditing() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Spline Convertible Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID

    let result = try session.execute(
        .convertSketchLineToSpline(target: target)
    )
    let moveResult = try session.execute(
        .moveSketchSplineControlPoint(
            target: target,
            controlPointIndex: 1,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(2.0, .millimeter)
        )
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(after.entries.first { $0.entityID == line.entityID })
    let firstPoint = try #require(spline.controlPoints.first)
    let firstHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let secondHandle = try #require(spline.controlPoints.dropFirst(2).first)
    let endPoint = try #require(spline.controlPoints.dropFirst(3).first)
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(moveResult.commandName == "moveSketchSplineControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(spline.entityKind == "spline")
    #expect(spline.controlPoints.count == 4)
    #expect(abs(firstPoint.x - 0.0) < 1.0e-12)
    #expect(abs(firstPoint.y - 0.0) < 1.0e-12)
    #expect(abs(firstHandle.x - 0.003) < 1.0e-12)
    #expect(abs(firstHandle.y - 0.002) < 1.0e-12)
    #expect(abs(secondHandle.x - 0.006) < 1.0e-12)
    #expect(abs(secondHandle.y - 0.0) < 1.0e-12)
    #expect(abs(endPoint.x - 0.009) < 1.0e-12)
    #expect(abs(endPoint.y - 0.0) < 1.0e-12)
    #expect(sceneNode.object?.typeID == .spline)
    #expect(sceneNode.object?.properties["control.point.count"] == .integer(4))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func convertSketchLineToSplineMigratesEndpointReferencesAndDimensions() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Referenced Spline Candidate",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineStart(entityID))
        )
    )
    _ = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(12.0, .millimeter)
        )
    )

    let result = try session.execute(.convertSketchLineToSpline(target: target))

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(after.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(spline.dimensions.first { $0.kind == "distance" })
    let constraint = try #require(spline.constraints.first { $0.kind == "fixed" })
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(4))
    #expect(spline.entityKind == "spline")
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):0"])
    #expect(dimension.references == [
        "splineControlPoint:\(entityID.description):0",
        "splineControlPoint:\(entityID.description):3",
    ])
    #expect(abs((spline.controlPoints.last?.x ?? 0.0) - 0.012) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)

    do {
        _ = try session.execute(
            .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 0,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            )
        )
        Issue.record("Fixed spline endpoint move must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch spline control point move cannot move a fixed sketch point.")
    }
    #expect(session.generation == DocumentGeneration(4))
}

@MainActor
@Test func convertSketchLineToSplineMigratesSplineEndpointTangency() async throws {
    let setup = try splineLineTangentSketchDocument(name: "Spline Tangent Line Conversion")
    let session = EditorSession(document: setup.document)
    let beforeConstraint = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(beforeConstraint.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(line.selectionTarget())
    _ = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .splineEndpointTangent(
                spline: setup.splineID,
                endpoint: .start,
                line: setup.lineID
            )
        )
    )

    let result = try session.execute(.convertSketchLineToSpline(target: target))

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceSpline = try #require(after.entries.first { $0.entityID == setup.splineID.description })
    let convertedSpline = try #require(after.entries.first { $0.entityID == setup.lineID.description })
    let sourceConstraint = try #require(sourceSpline.constraints.first { $0.kind == "tangentSplineEndpoints" })
    let convertedConstraint = try #require(convertedSpline.constraints.first { $0.kind == "tangentSplineEndpoints" })
    let expectedReferences = [
        "splineEndpoint:\(setup.splineID.description):start",
        "splineEndpoint:\(setup.lineID.description):start",
    ]
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(convertedSpline.entityKind == "spline")
    #expect(sourceConstraint.references == expectedReferences)
    #expect(convertedConstraint.references == expectedReferences)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func convertSketchLineToSplineRejectsLineSpecificConstraintsBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Line Constraint Spline Candidate",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(entityID)
        )
    )

    do {
        _ = try session.execute(
            .convertSketchLineToSpline(target: target)
        )
        Issue.record("Line-specific spline conversion must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch line spline conversion cannot preserve line orientation constraints as spline point references.")
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.entries.contains { $0.entityID == line.entityID && $0.entityKind == "line" })
}

@MainActor
@Test func reverseSketchLineCommandSwapsEndpointsAndMigratesReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Reversible Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineStart(entityID))
        )
    )
    _ = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(12.0, .millimeter)
        )
    )

    let result = try session.execute(.reverseSketchCurve(target: target))

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let reversedLine = try #require(after.entries.first { $0.entityID == line.entityID })
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Reversed feature must remain a sketch.")
        return
    }
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(4))
    #expect(abs((reversedLine.start?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((reversedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(sketch.constraints.contains(.fixed(.lineEnd(entityID))))
    #expect(!sketch.constraints.contains(.fixed(.lineStart(entityID))))
    #expect(sketch.dimensions.contains { dimension in
        switch dimension {
        case .distance(.lineEnd(let firstID), .lineStart(let secondID), _):
            return firstID == entityID && secondID == entityID
        default:
            return false
        }
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func reverseSketchSplineCommandMigratesControlPointReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Reversible Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.003, y: 0.002),
                sketchTestPoint(x: 0.006, y: 0.002),
                sketchTestPoint(x: 0.009, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 0))
        )
    )

    let result = try session.execute(.reverseSketchCurve(target: target))

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let reversedSpline = try #require(after.entries.first { $0.entityID == spline.entityID })
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Reversed spline feature must remain a sketch.")
        return
    }
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(reversedSpline.controlPoints.count == 4)
    #expect(abs((reversedSpline.controlPoints.first?.x ?? -1.0) - 0.009) < 1.0e-12)
    #expect(abs((reversedSpline.controlPoints.last?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 3))))
    #expect(!sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 0))))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func reverseSketchCurveUpdatesBridgeEndpointMetadata() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Bridge Reverse Source",
        plane: .xy,
        start: sketchTestPoint(x: 0.000, y: 0.000),
        end: sketchTestPoint(x: 0.003, y: 0.000)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        Issue.record("Bridge reverse setup requires a line sketch.")
        return
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.006, y: 0.003),
            end: sketchTestPoint(x: 0.006, y: 0.006)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    _ = try document.createBridgeCurve(
        featureID: featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .lineEnd(firstLineID)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(secondLineID)
        ),
        continuity: .g1
    )
    let session = EditorSession(document: document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try session.execute(.reverseSketchCurve(target: target))

    let source = try #require(session.document.productMetadata.bridgeCurveSources.values.first)
    let updatedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let updatedSketch) = updatedFeature.operation else {
        Issue.record("Bridge reverse feature must remain a sketch.")
        return
    }
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(source.firstEndpoint.reference == .lineStart(firstLineID))
    #expect(source.secondEndpoint.reference == .lineStart(secondLineID))
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: source.entityID, index: 0),
        .lineStart(firstLineID)
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: source.entityID,
        endpoint: .start,
        line: firstLineID
    )))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func reverseSketchCurveRejectsArcWithoutMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Directionless Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    do {
        _ = try session.execute(.reverseSketchCurve(target: target))
        Issue.record("Arc reverse must fail before mutation until arc direction is represented.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch curve reverse cannot reverse arc direction until arc source direction is represented.")
    } catch {
        Issue.record("Arc reverse must throw EditorError.")
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let unchangedArc = try #require(after.entries.first { $0.entityID == arc.entityID })
    #expect(session.generation == DocumentGeneration(1))
    #expect(unchangedArc.entityKind == "arc")
    #expect(abs((unchangedArc.startAngle ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((unchangedArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func splitSketchLineCommandInsertsSegmentAndMigratesEndReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Split Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(entityID)
        )
    )
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
        )
    )
    _ = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(10.0, .millimeter)
        )
    )

    let result = try session.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.4)
        )
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    let sceneNode = try #require(sketchEditSceneNode(for: featureID, in: session.document))
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Split line feature must remain a sketch.")
        return
    }
    let newLineID = try #require(sketch.entities.keys.first { $0 != entityID })
    let retainedEntity = try #require(sketch.entities[entityID])
    let newEntity = try #require(sketch.entities[newLineID])
    guard case .line(let retainedLine) = retainedEntity,
          case .line(let newLine) = newEntity else {
        Issue.record("Split line should produce two line entities.")
        return
    }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(5))
    #expect(abs((try resolvedTestLength(retainedLine.start.x, in: session.document)) - 0.0) < 1.0e-12)
    #expect(abs((try resolvedTestLength(retainedLine.end.x, in: session.document)) - 0.004) < 1.0e-12)
    #expect(abs((try resolvedTestLength(newLine.start.x, in: session.document)) - 0.004) < 1.0e-12)
    #expect(abs((try resolvedTestLength(newLine.end.x, in: session.document)) - 0.010) < 1.0e-12)
    #expect(sceneNode.object?.typeID == nil)
    #expect(sketch.constraints.contains(.horizontal(entityID)))
    #expect(sketch.constraints.contains(.horizontal(newLineID)))
    #expect(sketch.constraints.contains(.fixed(.lineEnd(newLineID))))
    #expect(sketch.constraints.contains(.coincident(.lineEnd(entityID), .lineStart(newLineID))))
    #expect(!sketch.constraints.contains(.fixed(.lineEnd(entityID))))
    #expect(sketch.dimensions.contains { dimension in
        switch dimension {
        case .distance(.lineStart(let firstID), .lineEnd(let secondID), _):
            return firstID == entityID && secondID == newLineID
        default:
            return false
        }
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func splitSketchSplineCommandInsertsSegmentAndMigratesEndReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Split Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                sketchTestPoint(x: 0.000, y: 0.000),
                sketchTestPoint(x: 0.003, y: 0.002),
                sketchTestPoint(x: 0.006, y: 0.002),
                sketchTestPoint(x: 0.009, y: 0.000),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 3))
        )
    )

    let result = try session.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.5)
        )
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Split spline feature must remain a sketch.")
        return
    }
    let newSplineID = try #require(sketch.entities.keys.first { $0 != entityID })
    let retainedEntity = try #require(sketch.entities[entityID])
    let newEntity = try #require(sketch.entities[newSplineID])
    guard case .spline(let retainedSpline) = retainedEntity,
          case .spline(let newSpline) = newEntity else {
        Issue.record("Split spline should produce two spline entities.")
        return
    }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(retainedSpline.controlPoints.count == 4)
    #expect(newSpline.controlPoints.count == 4)
    #expect(abs((try resolvedTestLength(retainedSpline.controlPoints.last?.x, in: session.document)) - 0.0045) < 1.0e-12)
    #expect(abs((try resolvedTestLength(newSpline.controlPoints.first?.x, in: session.document)) - 0.0045) < 1.0e-12)
    #expect(abs((try resolvedTestLength(newSpline.controlPoints.last?.x, in: session.document)) - 0.009) < 1.0e-12)
    #expect(sketch.constraints.contains(.fixed(.splineControlPoint(entity: newSplineID, index: 3))))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: entityID, index: 3),
        .splineControlPoint(entity: newSplineID, index: 0)
    )))
    #expect(!sketch.constraints.contains(.fixed(.splineControlPoint(entity: entityID, index: 3))))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func splitSketchArcCommandInsertsSegmentAndMigratesEndReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Split Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())
    let featureID = try #require(UUID(uuidString: arc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: arc.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
        )
    )
    _ = try session.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(90.0, .degree)
        )
    )

    let result = try session.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.25)
        )
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Split arc feature must remain a sketch.")
        return
    }
    let newArcID = try #require(sketch.entities.keys.first { $0 != entityID })
    let retainedEntity = try #require(sketch.entities[entityID])
    let newEntity = try #require(sketch.entities[newArcID])
    guard case .arc(let retainedArc) = retainedEntity,
          case .arc(let newArc) = newEntity else {
        Issue.record("Split arc should produce two arc entities.")
        return
    }

    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(4))
    #expect(abs((try resolvedTestAngle(retainedArc.startAngle, in: session.document)) - 0.0) < 1.0e-12)
    #expect(abs((try resolvedTestAngle(retainedArc.endAngle, in: session.document)) - (Double.pi / 8.0)) < 1.0e-12)
    #expect(abs((try resolvedTestAngle(newArc.startAngle, in: session.document)) - (Double.pi / 8.0)) < 1.0e-12)
    #expect(abs((try resolvedTestAngle(newArc.endAngle, in: session.document)) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(sketch.constraints.contains(.fixed(.arcEnd(newArcID))))
    #expect(sketch.constraints.contains(.coincident(.arcEnd(entityID), .arcStart(newArcID))))
    #expect(!sketch.constraints.contains(.fixed(.arcEnd(entityID))))
    #expect(sketch.dimensions.contains { dimension in
        switch dimension {
        case .angle(.arcStart(let firstID), .arcEnd(let secondID), _):
            return firstID == entityID && secondID == newArcID
        default:
            return false
        }
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func trimSketchCurveSegmentRemovesSplitLineSegmentAndAttachedReferences() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Trim Split Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let retainedLineID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.5)
        )
    )
    let splitSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let trimmedLine = try #require(splitSummary.entries.first { entry in
        entry.entityKind == "line" && entry.entityID != line.entityID
    })
    let trimmedTarget = try #require(trimmedLine.selectionTarget())
    let trimmedLineID = try #require(UUID(uuidString: trimmedLine.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(trimmedLineID))
        )
    )

    let result = try session.execute(
        .trimSketchCurveSegment(target: trimmedTarget)
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Trim line feature must remain a sketch.")
        return
    }
    let retainedEntity = try #require(sketch.entities[retainedLineID])
    guard case .line(let retainedLine) = retainedEntity else {
        Issue.record("Trim should preserve the untrimmed line segment.")
        return
    }
    #expect(result.commandName == "trimSketchCurveSegment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(4))
    #expect(sketch.entities.count == 1)
    #expect(sketch.entities[trimmedLineID] == nil)
    #expect(abs((try resolvedTestLength(retainedLine.start.x, in: session.document)) - 0.0) < 1.0e-12)
    #expect(abs((try resolvedTestLength(retainedLine.end.x, in: session.document)) - 0.006) < 1.0e-12)
    #expect(!sketch.constraints.contains { sketchConstraint($0, references: trimmedLineID) })
    #expect(!sketch.dimensions.contains { sketchDimension($0, references: trimmedLineID) })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func trimSketchCurveSegmentRejectsCircleWithoutMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Untrimmed Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(before.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())

    do {
        _ = try session.execute(.trimSketchCurveSegment(target: target))
        Issue.record("Circle trim must fail before mutation because a whole circle has no segment boundary.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch curve trim requires a bounded curve segment; circles do not expose segment boundaries.")
    } catch {
        Issue.record("Circle trim must throw EditorError.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(after.entries.filter { $0.entityKind == "circle" }.count == 1)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSplitsTargetLineAtLineCutterIntersection() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Target" })
    let cutterLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.004) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.004) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(cutterSegments.first?.start?.x == cutterLine.start?.x)
    #expect(cutterSegments.first?.end?.x == cutterLine.end?.x)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSupportsExtendedLineCutter() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Extend Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Extend Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Extend Target" })
    let cutterLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Extend Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    do {
        _ = try session.execute(
            .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            )
        )
        Issue.record("Cut Curve must reject a cutter that misses without extension.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Cut Curve cutter does not reach the target curve; enable cutter extension for this case.")
    } catch {
        Issue.record("Cut Curve must throw EditorError.")
    }

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions(extendsCutter: true)
        )
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Extend Target" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.006) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSplitsTargetLineAtCircleCutterIntersections() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Circle Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createCircleSketch(
            name: "Cut Circle Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Target" })
    let cutterCircle = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Circle Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Circle Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 3)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.007) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.007) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveFiltersLineTargetIntersectionsByArcCutterSpan() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Arc Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createArcSketch(
            name: "Cut Arc Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Target" })
    let cutterArc = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterArc.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Arc Target" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.007) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.007) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSplitsTargetArcAtLineCutterIntersection() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Cut Arc Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi, .radian)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Arc Line Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetArc = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Target" })
    let cutterLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Line Cutter" })
    let target = try #require(targetArc.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Arc Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Arc Line Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { arcMatches($0, startAngle: 0.0, endAngle: Double.pi / 2.0) })
    #expect(targetSegments.contains { arcMatches($0, startAngle: Double.pi / 2.0, endAngle: Double.pi) })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSplitsTargetArcAtCircleCutterIntersections() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Cut Arc Circle Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi, .radian)
        )
    )
    _ = try session.execute(
        .createCircleSketch(
            name: "Cut Arc Circle Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            radius: .length(3.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetArc = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Circle Target" })
    let cutterCircle = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Circle Cutter" })
    let target = try #require(targetArc.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let firstCutAngle = atan2(4.0, 3.0)
    let secondCutAngle = atan2(4.0, -3.0)
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Arc Circle Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Arc Circle Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 3)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { arcMatches($0, startAngle: 0.0, endAngle: firstCutAngle) })
    #expect(targetSegments.contains { arcMatches($0, startAngle: firstCutAngle, endAngle: secondCutAngle) })
    #expect(targetSegments.contains { arcMatches($0, startAngle: secondCutAngle, endAngle: Double.pi) })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSplitsTargetCircleAtLineCutterIntersections() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Cut Circle Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Circle Line Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-6.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetCircle = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Target" })
    let cutterLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Line Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Circle Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Circle Line Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "arc" })
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains {
        arcMatches($0, startAngle: Double.pi / 2.0, endAngle: Double.pi * 1.5)
    })
    #expect(targetSegments.contains {
        arcMatches($0, startAngle: Double.pi * 1.5, endAngle: Double.pi / 2.0)
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveSplitsTargetCircleAtCircleCutterIntersections() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Cut Circle Circle Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createCircleSketch(
            name: "Cut Circle Circle Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            radius: .length(3.0, .millimeter)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetCircle = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Circle Target" })
    let cutterCircle = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Circle Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let result = try session.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        )
    )

    let firstCutAngle = atan2(4.0, 3.0)
    let secondCutAngle = atan2(4.0, -3.0)
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Circle Circle Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Cut Circle Circle Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "arc" })
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { arcMatches($0, startAngle: firstCutAngle, endAngle: secondCutAngle) })
    #expect(targetSegments.contains { arcMatches($0, startAngle: secondCutAngle, endAngle: firstCutAngle) })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveRejectsTargetCircleTangentCutterWithoutMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Cut Circle Tangent Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Circle Tangent Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetCircle = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Tangent Target" })
    let cutterLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Circle Tangent Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    do {
        _ = try session.execute(
            .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            )
        )
        Issue.record("Cut Curve must reject a tangent circle target cut.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Cut Curve circle target requires two distinct cutter intersections to create two arc segments.")
    } catch {
        Issue.record("Cut Curve must throw EditorError.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(after.entries.filter { $0.sourceFeatureName == "Cut Circle Tangent Target" && $0.entityKind == "circle" }.count == 1)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func cutSketchCurveRejectsArcCutterExtensionWithoutMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Cut Arc Extend Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createArcSketch(
            name: "Cut Arc Extend Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Extend Target" })
    let cutterArc = try #require(before.entries.first { $0.sourceFeatureName == "Cut Arc Extend Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterArc.selectionTarget())

    do {
        _ = try session.execute(
            .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions(extendsCutter: true)
            )
        )
        Issue.record("Cut Curve must reject arc cutter extension until arc extension is represented.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Cut Curve arc cutter extension is not represented in the current source subset.")
    } catch {
        Issue.record("Cut Curve must throw EditorError.")
    }

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    #expect(session.generation == DocumentGeneration(2))
    #expect(after.entries.count == before.entries.count)
    #expect(session.evaluationStatus == .valid)
}

private func sketchEditSceneNode(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNode? {
    document.productMetadata.sceneNodes.values.first { node in
        node.reference == .sketch(featureID)
    }
}

private func bodySceneNode(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNode? {
    document.productMetadata.sceneNodes.values.first { node in
        node.reference == .body(featureID)
    }
}

private func bodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func sketchLineEntries(
    _ summary: SketchEntitySummaryResult
) -> [SketchEntitySummaryResult.EntityEntry] {
    summary.entries.filter { $0.entityKind == "line" }
}

private func isHorizontalLine(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    y: Double
) -> Bool {
    guard entry.entityKind == "line",
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    return abs(start.y - y) < 1.0e-12 &&
        abs(end.y - y) < 1.0e-12 &&
        abs(start.x - end.x) > 1.0e-12
}

private func containsSketchPoint(
    _ summary: SketchEntitySummaryResult,
    x: Double,
    y: Double
) -> Bool {
    sketchLineEntries(summary).contains { entry in
        pointMatches(entry.start, x: x, y: y) ||
            pointMatches(entry.end, x: x, y: y)
    }
}

private func pointMatches(
    _ point: SketchEntitySummaryResult.Point?,
    x: Double,
    y: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.x - x) < 1.0e-12 && abs(point.y - y) < 1.0e-12
}

private func arcMatches(
    _ arc: SketchEntitySummaryResult.EntityEntry,
    startAngle: Double,
    endAngle: Double
) -> Bool {
    guard let arcStartAngle = arc.startAngle,
          let arcEndAngle = arc.endAngle else {
        return false
    }
    return abs(arcStartAngle - startAngle) < 1.0e-12 &&
        abs(arcEndAngle - endAngle) < 1.0e-12
}

private func twoLineConstrainedSketchDocument(
    name: String,
    constraint: (SketchEntityID, SketchEntityID) -> SketchConstraint
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: sketchTestPoint(x: 0.0, y: 0.0),
        end: sketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two line constrained sketch setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.0, y: 0.005),
            end: sketchTestPoint(x: 0.005, y: 0.005)
        )
    )
    sketch.constraints.append(constraint(firstLineID, secondLineID))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func concaveLineLoopProfile() -> Profile {
    Profile(
        sourceFeatureID: FeatureID(),
        plane: .xy,
        vertices: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.010, y: 0.0, z: 0.0),
            Point3D(x: 0.010, y: 0.004, z: 0.0),
            Point3D(x: 0.004, y: 0.004, z: 0.0),
            Point3D(x: 0.004, y: 0.010, z: 0.0),
            Point3D(x: 0.0, y: 0.010, z: 0.0),
        ]
    )
}

private func collinearSplitLineLoopProfile() -> Profile {
    Profile(
        sourceFeatureID: FeatureID(),
        plane: .xy,
        vertices: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.005, y: 0.0, z: 0.0),
            Point3D(x: 0.010, y: 0.0, z: 0.0),
            Point3D(x: 0.010, y: 0.006, z: 0.0),
            Point3D(x: 0.0, y: 0.006, z: 0.0),
        ]
    )
}

private func concaveLineLoopDocument() throws -> DesignDocument {
    var document = DesignDocument.empty()
    let points = [
        sketchTestPoint(x: 0.0, y: 0.0),
        sketchTestPoint(x: 0.010, y: 0.0),
        sketchTestPoint(x: 0.010, y: 0.004),
        sketchTestPoint(x: 0.004, y: 0.004),
        sketchTestPoint(x: 0.004, y: 0.010),
        sketchTestPoint(x: 0.0, y: 0.010),
    ]
    let featureID = try document.createLineSketch(
        name: "Concave Source Region",
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstEntityID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Concave source region setup requires a source line sketch."
        )
    }
    let entityIDs = [firstEntityID] + (1..<points.count).map { _ in SketchEntityID() }
    sketch.constraints.removeAll()
    for index in 1..<points.count {
        let entityID = entityIDs[index]
        sketch.entities[entityID] = .line(SketchLine(
            start: points[index],
            end: points[(index + 1) % points.count]
        ))
    }
    for index in points.indices {
        let entityID = entityIDs[index]
        let nextEntityID = entityIDs[(index + 1) % entityIDs.count]
        sketch.constraints.append(.coincident(
            .lineEnd(entityID),
            .lineStart(nextEntityID)
        ))
    }
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return document
}

private func lineArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Offset Vertex Line Arc Profile",
        plane: .xy,
        start: sketchTestPoint(x: 0.0, y: 0.0),
        end: sketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Line arc offset vertex setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: sketchTestPoint(x: 0.010, y: 0.002),
            radius: .length(0.002, .meter),
            startAngle: .angle(-Double.pi / 2.0, .radian),
            endAngle: .angle(0.0, .radian)
        )
    )
    sketch.entities[topID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.012, y: 0.002),
            end: sketchTestPoint(x: 0.0, y: 0.002)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.0, y: 0.002),
            end: sketchTestPoint(x: 0.0, y: 0.0)
        )
    )
    sketch.constraints = [
        .coincident(.lineEnd(lineID), .arcStart(arcID)),
        .coincident(.arcEnd(arcID), .lineStart(topID)),
        .coincident(.lineEnd(topID), .lineStart(leftID)),
        .coincident(.lineEnd(leftID), .lineStart(lineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID)
}

private func lineArcCornerTreatmentSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID,
    diagonalID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Corner Treatment Line Arc Profile",
        plane: .xy,
        start: sketchTestPoint(x: 0.0, y: 0.0),
        end: sketchTestPoint(x: 2.0, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Line arc corner treatment setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: sketchTestPoint(x: 1.0, y: 0.0),
            radius: .length(1.0, .meter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    sketch.entities[diagonalID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 1.0, y: 1.0),
            end: sketchTestPoint(x: 0.0, y: 0.5)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.0, y: 0.5),
            end: sketchTestPoint(x: 0.0, y: 0.0)
        )
    )
    sketch.constraints = [
        .coincident(.lineEnd(lineID), .arcStart(arcID)),
        .coincident(.arcEnd(arcID), .lineStart(diagonalID)),
        .coincident(.lineEnd(diagonalID), .lineStart(leftID)),
        .coincident(.lineEnd(leftID), .lineStart(lineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID, diagonalID)
}

private func arcArcCornerTreatmentSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    previousArcID: SketchEntityID,
    currentArcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Corner Treatment Arc Arc Profile",
        plane: .xy,
        center: sketchTestPoint(x: 0.0, y: 1.0),
        radius: .length(1.0, .meter),
        startAngle: .angle(Double.pi, .radian),
        endAngle: .angle(Double.pi * 1.5, .radian)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let previousArcID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Arc arc corner treatment setup requires an arc sketch."
        )
    }
    let currentArcID = SketchEntityID()
    let lineID = SketchEntityID()
    sketch.entities[currentArcID] = .arc(
        SketchArc(
            center: sketchTestPoint(x: -2.0, y: 0.0),
            radius: .length(2.0, .meter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 3.0, .radian)
        )
    )
    sketch.entities[lineID] = .line(
        SketchLine(
            start: sketchTestPoint(x: -1.0, y: sqrt(3.0)),
            end: sketchTestPoint(x: -1.0, y: 1.0)
        )
    )
    sketch.constraints = [
        .coincident(.arcEnd(previousArcID), .arcStart(currentArcID)),
        .coincident(.arcEnd(currentArcID), .lineStart(lineID)),
        .coincident(.lineEnd(lineID), .arcStart(previousArcID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, previousArcID, currentArcID)
}

private func arcArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    upperArcID: SketchEntityID,
    lowerArcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Offset Vertex Arc Arc Profile",
        plane: .xy,
        center: sketchTestPoint(x: 0.005, y: 0.005),
        radius: .length(0.002, .meter),
        startAngle: .angle(0.0, .radian),
        endAngle: .angle(Double.pi, .radian)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let upperArcID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Arc arc offset vertex setup requires an arc sketch."
        )
    }
    let lowerArcID = SketchEntityID()
    sketch.entities[lowerArcID] = .arc(
        SketchArc(
            center: sketchTestPoint(x: 0.005, y: 0.005),
            radius: .length(0.002, .meter),
            startAngle: .angle(Double.pi, .radian),
            endAngle: .angle(Double.pi * 2.0, .radian)
        )
    )
    sketch.constraints = [
        .coincident(.arcEnd(upperArcID), .arcStart(lowerArcID)),
        .coincident(.arcEnd(lowerArcID), .arcStart(upperArcID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, upperArcID, lowerArcID)
}

private func lineCircleTangentSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    circleID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: sketchTestPoint(x: 0.0, y: 0.0),
        end: sketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Line circle tangent setup requires a line sketch."
        )
    }
    let circleID = SketchEntityID()
    sketch.entities[circleID] = .circle(
        SketchCircle(
            center: sketchTestPoint(x: 0.005, y: 0.002),
            radius: .length(0.002, .meter)
        )
    )
    sketch.constraints.append(.tangent(lineID, circleID))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, circleID)
}

private func splinePointConstraintCommandDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    splineID: SketchEntityID,
    pointID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: name,
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            sketchTestPoint(x: 0.0, y: 0.0),
            sketchTestPoint(x: 0.002, y: 0.003),
            sketchTestPoint(x: 0.006, y: 0.003),
            sketchTestPoint(x: 0.008, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Spline point constraint setup requires a spline sketch."
        )
    }
    let pointID = SketchEntityID()
    sketch.entities[pointID] = .point(sketchTestPoint(x: 0.004, y: 0.002))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, pointID)
}

private func splineLineTangentSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    splineID: SketchEntityID,
    lineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: name,
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            sketchTestPoint(x: 0.0, y: 0.0),
            sketchTestPoint(x: 0.003, y: 0.004),
            sketchTestPoint(x: 0.006, y: 0.004),
            sketchTestPoint(x: 0.009, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Spline line tangent setup requires a spline sketch."
        )
    }
    let lineID = SketchEntityID()
    sketch.entities[lineID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.0, y: 0.006),
            end: sketchTestPoint(x: 0.010, y: 0.006)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, lineID)
}

private func twoSplineTangentSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstSplineID: SketchEntityID,
    secondSplineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: name,
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            sketchTestPoint(x: 0.0, y: 0.0),
            sketchTestPoint(x: 0.003, y: 0.0),
            sketchTestPoint(x: 0.006, y: 0.0),
            sketchTestPoint(x: 0.009, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstSplineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two-spline tangent setup requires a spline sketch."
        )
    }
    let secondSplineID = SketchEntityID()
    sketch.entities[secondSplineID] = .spline(
        SketchSpline(controlPoints: [
            sketchTestPoint(x: 0.009, y: 0.0),
            sketchTestPoint(x: 0.0108, y: 0.0024),
            sketchTestPoint(x: 0.014, y: 0.002),
            sketchTestPoint(x: 0.017, y: 0.0),
        ])
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstSplineID, secondSplineID)
}

private func twoCircleConstrainedSketchDocument(
    name: String,
    constraint: (SketchEntityID, SketchEntityID) -> SketchConstraint
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstCircleID: SketchEntityID,
    secondCircleID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: name,
        plane: .xy,
        center: sketchTestPoint(x: 0.002, y: 0.003),
        radius: .length(0.004, .meter)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstCircleID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two circle constrained sketch setup requires a circle sketch."
        )
    }
    let secondCircleID = SketchEntityID()
    sketch.entities[secondCircleID] = .circle(
        SketchCircle(
            center: sketchTestPoint(x: 0.010, y: 0.011),
            radius: .length(0.001, .meter)
        )
    )
    sketch.constraints.append(constraint(firstCircleID, secondCircleID))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstCircleID, secondCircleID)
}

private func threeLineParallelSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID,
    thirdLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: sketchTestPoint(x: 0.0, y: 0.0),
        end: sketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Three line parallel sketch setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    let thirdLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.0, y: 0.005),
            end: sketchTestPoint(x: 0.005, y: 0.005)
        )
    )
    sketch.entities[thirdLineID] = .line(
        SketchLine(
            start: sketchTestPoint(x: 0.0, y: 0.010),
            end: sketchTestPoint(x: 0.004, y: 0.010)
        )
    )
    sketch.constraints.append(.parallel(firstLineID, secondLineID))
    sketch.constraints.append(.parallel(secondLineID, thirdLineID))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID, thirdLineID)
}

private func appendSketchConstraints(
    _ constraints: [SketchConstraint],
    toFeature featureID: FeatureID,
    in document: inout DesignDocument
) throws {
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Sketch constraint setup requires an existing sketch."
        )
    }
    sketch.constraints.append(contentsOf: constraints)
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
}

@MainActor
private func lineChainSlotSession(
    name: String,
    points: [SketchPoint]
) throws -> (
    session: EditorSession,
    featureID: FeatureID,
    lineIDs: [SketchEntityID]
) {
    guard points.count >= 2 else {
        throw EditorError(
            code: .commandInvalid,
            message: "Line-chain test setup requires at least two points."
        )
    }
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    let lineIDs = (0..<(points.count - 1)).map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in lineIDs.indices {
        entities[lineIDs[index]] = .line(SketchLine(
            start: points[index],
            end: points[index + 1]
        ))
        if index > 0 {
            constraints.append(.coincident(.lineEnd(lineIDs[index - 1]), .lineStart(lineIDs[index])))
        }
    }
    guard var feature = document.cadDocument.designGraph.nodes[featureID] else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Line-chain test setup requires a sketch feature."
        )
    }
    feature.operation = .sketch(Sketch(
        plane: .xy,
        entities: entities,
        constraints: constraints
    ))
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (
        session: EditorSession(document: document),
        featureID: featureID,
        lineIDs: lineIDs
    )
}

@MainActor
private func lineArcChainSlotSession(
    name: String
) throws -> (
    session: EditorSession,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: sketchTestPoint(x: 0.0, y: 0.0),
        end: sketchTestPoint(x: 0.010, y: 0.0)
    )
    let lineID = SketchEntityID()
    let arcID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID] else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Line-arc Slot setup requires a sketch feature."
        )
    }
    feature.operation = .sketch(Sketch(
        plane: .xy,
        entities: [
            lineID: .line(SketchLine(
                start: sketchTestPoint(x: 0.0, y: 0.0),
                end: sketchTestPoint(x: 0.010, y: 0.0)
            )),
            arcID: .arc(SketchArc(
                center: sketchTestPoint(x: 0.010, y: 0.005),
                radius: .length(0.005, .meter),
                startAngle: .angle(-Double.pi / 2.0, .radian),
                endAngle: .angle(0.0, .radian)
            )),
        ],
        constraints: [
            .coincident(.lineEnd(lineID), .arcStart(arcID)),
        ]
    ))
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (
        session: EditorSession(document: document),
        featureID: featureID,
        lineID: lineID,
        arcID: arcID
    )
}

private func resolvedTestLength(
    _ expression: CADExpression?,
    in document: DesignDocument
) throws -> Double {
    let expression = try #require(expression)
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func resolvedTestAngle(
    _ expression: CADExpression,
    in document: DesignDocument
) throws -> Double {
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .angle)
    return quantity.value
}

private func sketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Sketch {
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Feature must be a sketch.")
        throw EditorError(
            code: .commandInvalid,
            message: "Feature must be a sketch."
        )
    }
    return sketch
}

private func sketchDimensionExpression(_ dimension: SketchDimension) -> CADExpression {
    switch dimension {
    case .distance(_, _, let value),
         .angle(_, _, let value),
         .radius(_, let value),
         .diameter(_, let value):
        return value
    }
}

private func sketchConstraint(
    _ constraint: SketchConstraint,
    references entityID: SketchEntityID
) -> Bool {
    switch constraint {
    case .coincident(let first, let second):
        return sketchReference(first, references: entityID) ||
            sketchReference(second, references: entityID)
    case .fixed(let reference):
        return sketchReference(reference, references: entityID)
    case .horizontal(let id),
         .vertical(let id),
         .smoothSplineControlPoint(let id, _):
        return id == entityID
    case .parallel(let first, let second),
         .perpendicular(let first, let second),
         .equalLength(let first, let second),
         .tangent(let first, let second),
         .concentric(let first, let second),
         .equalRadius(let first, let second):
        return first == entityID || second == entityID
    case .splineEndpointTangent(let splineID, _, let lineID):
        return splineID == entityID || lineID == entityID
    case .tangentSplineEndpoints(let first, let second),
         .smoothSplineEndpoints(let first, let second):
        return first.splineID == entityID || second.splineID == entityID
    }
}

private func sketchDimension(
    _ dimension: SketchDimension,
    references entityID: SketchEntityID
) -> Bool {
    switch dimension {
    case .distance(let from, let to, _),
         .angle(let from, let to, _):
        return sketchReference(from, references: entityID) ||
            sketchReference(to, references: entityID)
    case .radius(let id, _),
         .diameter(let id, _):
        return id == entityID
    }
}

private func sketchReference(
    _ reference: SketchReference,
    references entityID: SketchEntityID
) -> Bool {
    switch reference {
    case .entity(let id),
         .lineStart(let id),
         .lineEnd(let id),
         .circleCenter(let id),
         .circleRadius(let id),
         .arcCenter(let id),
         .arcStart(let id),
         .arcEnd(let id),
         .arcRadius(let id),
         .splineControlPoint(let id, _):
        return id == entityID
    }
}

private func sketchTestPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func lineEntriesAreParallel(
    _ lhs: SketchEntitySummaryResult.EntityEntry,
    _ rhs: SketchEntitySummaryResult.EntityEntry
) -> Bool {
    guard let lhsStart = lhs.start,
          let lhsEnd = lhs.end,
          let rhsStart = rhs.start,
          let rhsEnd = rhs.end else {
        return false
    }
    let lhsX = lhsEnd.x - lhsStart.x
    let lhsY = lhsEnd.y - lhsStart.y
    let rhsX = rhsEnd.x - rhsStart.x
    let rhsY = rhsEnd.y - rhsStart.y
    return abs(lhsX * rhsY - lhsY * rhsX) < 1.0e-12
}

private func lineEntriesArePerpendicular(
    _ lhs: SketchEntitySummaryResult.EntityEntry,
    _ rhs: SketchEntitySummaryResult.EntityEntry
) -> Bool {
    guard let lhsStart = lhs.start,
          let lhsEnd = lhs.end,
          let rhsStart = rhs.start,
          let rhsEnd = rhs.end else {
        return false
    }
    let lhsX = lhsEnd.x - lhsStart.x
    let lhsY = lhsEnd.y - lhsStart.y
    let rhsX = rhsEnd.x - rhsStart.x
    let rhsY = rhsEnd.y - rhsStart.y
    return abs(lhsX * rhsX + lhsY * rhsY) < 1.0e-12
}

private func lineEntryLength(_ entry: SketchEntitySummaryResult.EntityEntry) -> Double {
    guard let start = entry.start,
          let end = entry.end else {
        return .nan
    }
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}

private func lineCircleDistance(
    _ line: SketchEntitySummaryResult.EntityEntry,
    _ circle: SketchEntitySummaryResult.EntityEntry
) -> Double {
    guard let start = line.start,
          let end = line.end,
          let center = circle.center else {
        return .nan
    }
    let lineX = end.x - start.x
    let lineY = end.y - start.y
    let length = sqrt(lineX * lineX + lineY * lineY)
    guard length > 0.0 else {
        return .nan
    }
    let centerX = center.x - start.x
    let centerY = center.y - start.y
    return abs(centerX * lineY - centerY * lineX) / length
}

private func pointHandleSelectionTarget(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    handle: SketchEntityPointHandle
) throws -> SelectionTarget {
    let sceneNodeID = try #require(entry.sceneNodeID.flatMap(UUID.init(uuidString:)))
    let handleEntry = try #require(entry.pointHandles.first { $0.handle == handle })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeID),
        component: .sketchEntity(SelectionComponentID(rawValue: handleEntry.selectionComponentID))
    )
}

private func controlPointSelectionTarget(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    index: Int
) throws -> SelectionTarget {
    let sceneNodeID = try #require(entry.sceneNodeID.flatMap(UUID.init(uuidString:)))
    let controlPointEntry = try #require(entry.controlPointTargets.first { $0.index == index })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeID),
        component: .sketchEntity(SelectionComponentID(rawValue: controlPointEntry.selectionComponentID))
    )
}

private func bottomRectangleLine(
    in summary: SketchEntitySummaryResult
) -> SketchEntitySummaryResult.EntityEntry? {
    summary.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    }
}

private func topologyPoint(
    _ point: TopologySummaryResult.Entry.Point?,
    isOnDepth depth: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.z - depth) < 1.0e-10
}

private extension UUID {
    var featureID: FeatureID {
        FeatureID(self)
    }

    var sketchEntityID: SketchEntityID {
        SketchEntityID(self)
    }
}

private extension ObjectPropertyValue {
    var lengthValue: Double? {
        guard case .length(let value) = self else {
            return nil
        }
        return value
    }

    var angleValue: Double? {
        guard case .angle(let value) = self else {
            return nil
        }
        return value
    }
}
