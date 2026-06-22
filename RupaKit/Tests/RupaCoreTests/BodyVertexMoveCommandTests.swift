import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func moveBodyVertexCommandUpdatesRectangleProfileCorner() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(vertexMoveSceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try vertexMoveProfileBounds(forBody: bodyFeatureID, in: session.document)
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: sceneNodeID,
            cornerVertex: .frontTopRight,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .vertex(componentID))

    let result = try session.execute(
        .moveBodyVertex(
            target: target,
            deltaX: .length(1.0, .millimeter),
            deltaY: .length(2.0, .millimeter)
        )
    )

    let afterBounds = try vertexMoveProfileBounds(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(abs(afterBounds.minX - beforeBounds.minX) < 1.0e-12)
    #expect(abs(afterBounds.minY - beforeBounds.minY) < 1.0e-12)
    #expect(abs(afterBounds.maxX - (beforeBounds.maxX + 0.001)) < 1.0e-12)
    #expect(abs(afterBounds.maxY - (beforeBounds.maxY + 0.002)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
    #expect(
        try GeneratedTopologySelectionResolver().componentID(
            for: sceneNodeID,
            cornerVertex: .frontTopRight,
            in: session.document
        ) != nil
    )
}

@MainActor
@Test func moveBodyVertexCommandRejectsCollapsedRectangleProfile() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(vertexMoveSceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try vertexMoveProfileBounds(forBody: bodyFeatureID, in: session.document)
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: sceneNodeID,
            cornerVertex: .frontBottomLeft,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .vertex(componentID))

    do {
        _ = try session.execute(
            .moveBodyVertex(
                target: target,
                deltaX: .length(100.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            )
        )
        Issue.record("A vertex move that collapses the profile must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    let afterBounds = try vertexMoveProfileBounds(forBody: bodyFeatureID, in: session.document)
    #expect(session.generation == DocumentGeneration(1))
    #expect(afterBounds == beforeBounds)
}

@MainActor
@Test func moveBodyVertexCommandCanEditSharpGeneratedVertexAfterPriorFillet() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(vertexMoveSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first {
        isGeneratedVertex($0, x: -0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    let result = try session.execute(
        .moveBodyVertex(
            target: target,
            deltaX: .length(1.0, .millimeter),
            deltaY: .length(0.5, .millimeter)
        )
    )

    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(try vertexMoveProfileContainsPoint(
        x: -0.019,
        y: -0.0095,
        forBody: bodyFeatureID,
        in: session.document
    ))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveBodyVertexCommandRejectsSharpGeneratedVertexAdjacentToExistingFilletArc() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(vertexMoveSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first {
        isGeneratedVertex($0, x: 0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    do {
        _ = try session.execute(
            .moveBodyVertex(
                target: target,
                deltaX: .length(-1.0, .millimeter),
                deltaY: .length(0.5, .millimeter)
            )
        )
        Issue.record("A generated vertex move that breaks an existing fillet arc tangent must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(2))
    #expect(try vertexMoveProfileLineCount(forBody: bodyFeatureID, in: session.document) == 4)
    #expect(try vertexMoveProfileArcCount(forBody: bodyFeatureID, in: session.document) == 1)
}

private func vertexMoveSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func vertexMoveProfileBounds(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> RectangleBoundsForVertexMove {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation else {
        throw EditorError(code: .referenceUnresolved, message: "Expected an extruded sketch body.")
    }

    var points: [(x: Double, y: Double)] = []
    for entity in sketch.entities.values {
        guard case .line(let line) = entity else {
            continue
        }
        points.append(
            (
                x: try document.cadDocument.parameters.resolvedValue(for: line.start.x).value,
                y: try document.cadDocument.parameters.resolvedValue(for: line.start.y).value
            )
        )
        points.append(
            (
                x: try document.cadDocument.parameters.resolvedValue(for: line.end.x).value,
                y: try document.cadDocument.parameters.resolvedValue(for: line.end.y).value
            )
        )
    }

    let first = try #require(points.first)
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y
    for point in points.dropFirst() {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }
    return RectangleBoundsForVertexMove(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
}

private func vertexMoveProfileContainsPoint(
    x: Double,
    y: Double,
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Bool {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation else {
        throw EditorError(code: .referenceUnresolved, message: "Expected an extruded sketch body.")
    }

    for entity in sketch.entities.values {
        guard case .line(let line) = entity else {
            continue
        }
        let startX = try document.cadDocument.parameters.resolvedValue(for: line.start.x).value
        let startY = try document.cadDocument.parameters.resolvedValue(for: line.start.y).value
        let endX = try document.cadDocument.parameters.resolvedValue(for: line.end.x).value
        let endY = try document.cadDocument.parameters.resolvedValue(for: line.end.y).value
        if abs(startX - x) <= 1.0e-12 && abs(startY - y) <= 1.0e-12 {
            return true
        }
        if abs(endX - x) <= 1.0e-12 && abs(endY - y) <= 1.0e-12 {
            return true
        }
    }
    return false
}

private func vertexMoveProfileLineCount(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Int {
    try vertexMoveProfileEntityCount(forBody: featureID, in: document) { entity in
        if case .line = entity {
            return true
        }
        return false
    }
}

private func vertexMoveProfileArcCount(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Int {
    try vertexMoveProfileEntityCount(forBody: featureID, in: document) { entity in
        if case .arc = entity {
            return true
        }
        return false
    }
}

private func vertexMoveProfileEntityCount(
    forBody featureID: FeatureID,
    in document: DesignDocument,
    matching predicate: (SketchEntity) -> Bool
) throws -> Int {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation else {
        throw EditorError(code: .referenceUnresolved, message: "Expected an extruded sketch body.")
    }
    return sketch.entities.values.filter(predicate).count
}

private func isGeneratedVertex(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard entry.kind == .vertex,
          let point = entry.start else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(point.x - x) <= tolerance
        && abs(point.y - y) <= tolerance
}

private struct RectangleBoundsForVertexMove: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
}
