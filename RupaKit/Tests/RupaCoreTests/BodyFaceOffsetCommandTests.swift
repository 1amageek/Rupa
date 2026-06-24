import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func offsetBodyFaceCommandEditsRectangleProfileFace() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceRight))

    let result = try session.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(2.0, .millimeter)
        )
    )

    let afterBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(nearlyEqual(afterBounds.minX, beforeBounds.minX))
    #expect(nearlyEqual(afterBounds.maxX, beforeBounds.maxX + 0.002))
    #expect(nearlyEqual(afterBounds.minY, beforeBounds.minY))
    #expect(nearlyEqual(afterBounds.maxY, beforeBounds.maxY))

    _ = try session.undo()
    let restoredBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    #expect(nearlyEqual(restoredBounds.minX, beforeBounds.minX))
    #expect(nearlyEqual(restoredBounds.maxX, beforeBounds.maxX))
}

@MainActor
@Test func offsetBodyFaceCommandKeepsOppositeDepthFaceFixed() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeDepth = try extrudeDepth(for: bodyFeatureID, in: session.document)
    let beforeTranslationY = translationY(for: bodyNodeID, in: session.document)
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceFront))

    let result = try session.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(1.5, .millimeter)
        )
    )

    let afterDepth = try extrudeDepth(for: bodyFeatureID, in: session.document)
    let afterTranslationY = translationY(for: bodyNodeID, in: session.document)
    #expect(result.commandName == "offsetBodyFace")
    #expect(nearlyEqual(afterDepth, beforeDepth + 0.0015))
    #expect(nearlyEqual(afterTranslationY, beforeTranslationY - 0.0015))

    _ = try session.undo()
    #expect(nearlyEqual(try extrudeDepth(for: bodyFeatureID, in: session.document), beforeDepth))
    #expect(nearlyEqual(translationY(for: bodyNodeID, in: session.document), beforeTranslationY))
}

@MainActor
@Test func offsetBodyFaceCommandAcceptsGeneratedTopologyFaceReference() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: bodyNodeID,
            bodyFace: .right,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(componentID))

    let result = try session.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(2.0, .millimeter)
        )
    )

    let afterBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(componentID.generatedTopologyPersistentName != nil)
    #expect(nearlyEqual(afterBounds.maxX, beforeBounds.maxX + 0.002))
}

@MainActor
@Test func offsetBodyFaceCommandResolvesComponentInstanceGeneratedFaceToSourceBody() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Offset Instance Source",
            rootSceneNodeIDs: [bodyNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Offset Instance Source"
    })
    _ = try session.execute(
        .createRectangularPatternArray(
            name: "Offset Instance Pattern",
            definitionID: definition.id,
            array: RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(20.0, .millimeter),
                    copyCount: 1
                )
            ),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    let instanceID = try #require(source.outputInstanceIDs.first)
    let instanceSceneNodeID = try #require(session.document.productMetadata.sceneNodes.first { _, node in
        node.reference == .componentInstance(instanceID)
    }?.key)
    let beforeBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: instanceSceneNodeID,
            bodyFace: .right,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: instanceSceneNodeID, component: .face(componentID))

    let result = try session.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(2.0, .millimeter)
        )
    )

    let afterBounds = try rectangleBounds(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(4))
    #expect(componentID.generatedTopologyPersistentName != nil)
    #expect(nearlyEqual(afterBounds.maxX, beforeBounds.maxX + 0.002))
    #expect(session.document.productMetadata.patternArrays[source.id] != nil)
}

@MainActor
@Test func offsetBodyFaceCommandEditsCylinderSideFaceRadius() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeRadius = try cylinderRadius(forBody: bodyFeatureID, in: session.document)
    let beforeDepth = try extrudeDepth(for: bodyFeatureID, in: session.document)
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceSide))

    let result = try session.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(2.0, .millimeter)
        )
    )

    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(nearlyEqual(try cylinderRadius(forBody: bodyFeatureID, in: session.document), beforeRadius + 0.002))
    #expect(nearlyEqual(try extrudeDepth(for: bodyFeatureID, in: session.document), beforeDepth))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetBodyFaceCommandAcceptsGeneratedTopologyCylinderSideReference() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let beforeRadius = try cylinderRadius(forBody: bodyFeatureID, in: session.document)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.surfaceKind == "cylinder"
    })
    let target = try #require(faceEntry.selectionTarget())

    let result = try session.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(-1.0, .millimeter)
        )
    )

    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(nearlyEqual(try cylinderRadius(forBody: bodyFeatureID, in: session.document), beforeRadius - 0.001))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func offsetBodyFaceCommandRejectsCollapsedProfile() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(sceneNodeID(for: bodyFeatureID, in: session.document))
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceRight))

    do {
        _ = try session.execute(
            .offsetBodyFace(
                target: target,
                distance: .length(-100.0, .millimeter)
            )
        )
        Issue.record("A face offset that collapses the profile must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(1))
}

private func sceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func rectangleBounds(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let extrude = try extrudeFeature(for: featureID, in: document)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case .sketch(let sketch) = profileFeature.operation else {
        Issue.record("Body profile must be a sketch.")
        return (0.0, 0.0, 0.0, 0.0)
    }
    var points: [(x: Double, y: Double)] = []
    for entity in sketch.entities.values {
        guard case .line(let line) = entity else {
            continue
        }
        points.append((try length(line.start.x, in: document), try length(line.start.y, in: document)))
        points.append((try length(line.end.x, in: document), try length(line.end.y, in: document)))
    }
    let first = try #require(points.first)
    return points.dropFirst().reduce(
        (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    ) { bounds, point in
        (
            minX: min(bounds.minX, point.x),
            minY: min(bounds.minY, point.y),
            maxX: max(bounds.maxX, point.x),
            maxY: max(bounds.maxY, point.y)
        )
    }
}

private func extrudeDepth(
    for featureID: FeatureID,
    in document: DesignDocument
) throws -> Double {
    try length(try extrudeFeature(for: featureID, in: document).distance, in: document)
}

private func extrudeFeature(
    for featureID: FeatureID,
    in document: DesignDocument
) throws -> ExtrudeFeature {
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .extrude(let extrude) = feature.operation else {
        Issue.record("Feature must be an extrude.")
        return ExtrudeFeature(profile: ProfileReference(featureID: FeatureID()), distance: .length(1.0, .meter))
    }
    return extrude
}

private func cylinderRadius(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Double {
    let extrude = try extrudeFeature(for: featureID, in: document)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case .sketch(let sketch) = profileFeature.operation else {
        Issue.record("Cylinder profile must be a sketch.")
        return 0.0
    }
    for entity in sketch.entities.values {
        guard case .circle(let circle) = entity else {
            continue
        }
        return try length(circle.radius, in: document)
    }
    Issue.record("Cylinder profile must contain a circle.")
    return 0.0
}

private func length(
    _ expression: CADExpression,
    in document: DesignDocument
) throws -> Double {
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func translationY(
    for sceneNodeID: SceneNodeID,
    in document: DesignDocument
) -> Double {
    guard let node = document.productMetadata.sceneNodes[sceneNodeID],
          node.localTransform.matrix.values.count == 16 else {
        return 0.0
    }
    return node.localTransform.matrix.values[13]
}

private func nearlyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs - rhs) <= tolerance
}
