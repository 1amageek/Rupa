import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func moveBodyEdgeCommandMovesGeneratedProfileLineEdge() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(edgeMoveSceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try edgeMoveRectangleBounds(forBody: bodyFeatureID, in: session.document)
    let beforeSizeZ = try edgeMoveObjectLengthProperty(
        "size.z",
        sceneNodeID: bodyNodeID,
        in: session.document
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let topEdge = try #require(topology.entries.first {
        edgeMoveIsGeneratedProfileLine($0) && edgeMoveLineIsAtY($0, beforeBounds.maxY)
    })
    let target = try #require(topEdge.selectionTarget())

    let result = try session.execute(
        .moveBodyEdge(
            target: target,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(1.0, .millimeter)
        )
    )

    let afterBounds = try edgeMoveRectangleBounds(forBody: bodyFeatureID, in: session.document)
    let afterSizeZ = try edgeMoveObjectLengthProperty(
        "size.z",
        sceneNodeID: bodyNodeID,
        in: session.document
    )
    #expect(result.commandName == "moveBodyEdge")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(edgeMoveNearlyEqual(afterBounds.minX, beforeBounds.minX))
    #expect(edgeMoveNearlyEqual(afterBounds.maxX, beforeBounds.maxX))
    #expect(edgeMoveNearlyEqual(afterBounds.minY, beforeBounds.minY))
    #expect(edgeMoveNearlyEqual(afterBounds.maxY, beforeBounds.maxY + 0.001))
    #expect(edgeMoveNearlyEqual(afterSizeZ, beforeSizeZ + 0.001))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveBodyEdgeCommandMovesGeneratedCircularEdgeWithoutChangingRadius() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let beforeCircle = try edgeMoveCircleProfile(forBody: bodyFeatureID, in: session.document)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let circularEdge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle"
    })
    let target = try #require(circularEdge.selectionTarget())

    let result = try session.execute(
        .moveBodyEdge(
            target: target,
            deltaX: .length(2.0, .millimeter),
            deltaY: .length(-1.0, .millimeter)
        )
    )

    let afterCircle = try edgeMoveCircleProfile(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "moveBodyEdge")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(edgeMoveNearlyEqual(afterCircle.centerX, beforeCircle.centerX + 0.002))
    #expect(edgeMoveNearlyEqual(afterCircle.centerY, beforeCircle.centerY - 0.001))
    #expect(edgeMoveNearlyEqual(afterCircle.radius, beforeCircle.radius))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func moveBodyEdgeCommandMovesGeneratedArcEdgeThroughTrimHealing() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(edgeMoveSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )
    let beforeArc = try edgeMoveArcProfile(forBody: bodyFeatureID, in: session.document)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let arcEdge = try #require(topology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.001) < 1.0e-12
    })
    let target = try #require(arcEdge.selectionTarget())

    let result = try session.execute(
        .moveBodyEdge(
            target: target,
            deltaX: .length(-1.0, .millimeter),
            deltaY: .length(-1.0, .millimeter)
        )
    )

    let afterArc = try edgeMoveArcProfile(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "moveBodyEdge")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(edgeMoveNearlyEqual(afterArc.centerX, beforeArc.centerX - 0.001))
    #expect(edgeMoveNearlyEqual(afterArc.centerY, beforeArc.centerY - 0.001))
    #expect(edgeMoveNearlyEqual(afterArc.radius, beforeArc.radius + 0.001))
    #expect(session.evaluationStatus == .valid)
}

private func edgeMoveSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func edgeMoveRectangleBounds(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> EdgeMoveRectangleBounds {
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
        points.append(try edgeMovePoint(line.start, in: document))
        points.append(try edgeMovePoint(line.end, in: document))
    }
    let first = try #require(points.first)
    var bounds = EdgeMoveRectangleBounds(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    for point in points.dropFirst() {
        bounds.minX = min(bounds.minX, point.x)
        bounds.minY = min(bounds.minY, point.y)
        bounds.maxX = max(bounds.maxX, point.x)
        bounds.maxY = max(bounds.maxY, point.y)
    }
    return bounds
}

private func edgeMoveCircleProfile(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> EdgeMoveCircleProfile {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation,
          let entity = sketch.entities.values.first,
          case let .circle(circle) = entity else {
        throw EditorError(code: .referenceUnresolved, message: "Expected an extruded circle body.")
    }
    let center = try edgeMovePoint(circle.center, in: document)
    let radius = try document.cadDocument.parameters.resolvedValue(for: circle.radius).value
    return EdgeMoveCircleProfile(centerX: center.x, centerY: center.y, radius: radius)
}

private func edgeMoveArcProfile(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> EdgeMoveArcProfile {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation,
          let entity = sketch.entities.values.first(where: { entity in
              if case .arc = entity {
                  return true
              }
              return false
          }),
          case let .arc(arc) = entity else {
        throw EditorError(code: .referenceUnresolved, message: "Expected an extruded arc profile edge.")
    }
    let center = try edgeMovePoint(arc.center, in: document)
    let radius = try document.cadDocument.parameters.resolvedValue(for: arc.radius).value
    return EdgeMoveArcProfile(centerX: center.x, centerY: center.y, radius: radius)
}

private func edgeMovePoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> (x: Double, y: Double) {
    (
        x: try document.cadDocument.parameters.resolvedValue(for: point.x).value,
        y: try document.cadDocument.parameters.resolvedValue(for: point.y).value
    )
}

private func edgeMoveObjectLengthProperty(
    _ propertyID: ObjectPropertyID,
    sceneNodeID: SceneNodeID,
    in document: DesignDocument
) throws -> Double {
    guard let value = document.productMetadata.sceneNodes[sceneNodeID]?.object?.properties[propertyID],
          case .length(let length) = value else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected body object length property \(propertyID.rawValue)."
        )
    }
    return length
}

private func edgeMoveIsGeneratedProfileLine(_ entry: TopologySummaryResult.Entry) -> Bool {
    entry.kind == .edge &&
        entry.generatedRole == "edge" &&
        entry.curveKind == "line" &&
        entry.start != nil &&
        entry.end != nil
}

private func edgeMoveLineIsAtY(
    _ entry: TopologySummaryResult.Entry,
    _ y: Double
) -> Bool {
    guard let start = entry.start,
          let end = entry.end else {
        return false
    }
    return edgeMoveNearlyEqual(start.z, end.z) &&
        edgeMoveNearlyEqual(start.y, y) &&
        edgeMoveNearlyEqual(end.y, y)
}

private func edgeMoveNearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= 1.0e-9
}

private struct EdgeMoveRectangleBounds: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
}

private struct EdgeMoveCircleProfile: Equatable {
    var centerX: Double
    var centerY: Double
    var radius: Double
}

private struct EdgeMoveArcProfile: Equatable {
    var centerX: Double
    var centerY: Double
    var radius: Double
}
