import Darwin
import Foundation
import Testing
import RupaCore
import SwiftCAD
import RupaAgent
import RupaAgentTransport

public func agentSourcePointSession() throws -> (
    session: EditorSession,
    targets: [SelectionTarget]
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Source Point CPlane Seeds",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
    )
    let firstID = SketchEntityID()
    let secondID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent source point construction-plane test requires a sketch feature."
        )
    }
    sketch.entities = [
        firstID: .point(SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter))),
        secondID: .point(SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entries = summary.entries.filter { $0.entityKind == "point" }
    #expect(entries.count == 2)
    let targets = try entries.map { entry in
        try #require(entry.selectionTarget())
    }
    return (EditorSession(document: document), targets)
}

public func agentSketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}

public func agentPointHandleSelectionTarget(
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

public func agentBottomRectangleLine(
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

public func agentVector(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
}

public func agentPoint3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
    Point3D(x: point.x, y: point.y, z: point.z)
}

public func agentTopologyPoint(
    _ point: TopologySummaryResult.Entry.Point?,
    isOnDepth depth: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.z - depth) < 1.0e-10
}

public func agentTranslationTransform(
    x: Double,
    y: Double,
    z: Double
) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(
            values: [
                1.0, 0.0, 0.0, x,
                0.0, 1.0, 0.0, y,
                0.0, 0.0, 1.0, z,
                0.0, 0.0, 0.0, 1.0,
            ]
        )
    )
}

public func agentLineEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: SelectionTarget, end: SelectionTarget) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .lineStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .lineEnd })
    return (
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

public func agentLineCurveTarget(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let curveComponentID = try #require(entry.selectionComponentID)
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeUUID),
        component: .sketchEntity(SelectionComponentID(rawValue: curveComponentID))
    )
}

public func createAgentStandalonePointSketch(
    in document: inout DesignDocument,
    name: String,
    plane: SketchPlane,
    point: SketchPoint
) throws -> FeatureID {
    let featureID = try document.createLineSketch(
        name: name,
        plane: plane,
        start: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
        end: SketchPoint(x: .length(1.0, .millimeter), y: .length(0.0, .millimeter))
    )
    let pointID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent standalone point test requires a sketch feature."
        )
    }
    sketch.entities[pointID] = .point(point)
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return featureID
}

public func agentStandalonePointTarget(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "point"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let pointHandle = try #require(entry.pointHandles.first { $0.handle == .point })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeUUID),
        component: .sketchEntity(SelectionComponentID(rawValue: pointHandle.selectionComponentID))
    )
}

public func agentStandalonePointEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SketchEntityID {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          let entityID = sketch.entities.first(where: { _, entity in
              if case .point = entity {
                  return true
              }
              return false
          })?.key else {
        Issue.record("Expected one standalone source point entity ID")
        return SketchEntityID()
    }
    return entityID
}

public func agentArcEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: SelectionTarget, end: SelectionTarget) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "arc"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .arcStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .arcEnd })
    return (
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

public func agentSplineControlPointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> [SelectionTarget] {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "spline"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    return entry.controlPointTargets
        .sorted { $0.index < $1.index }
        .map { controlPoint in
            SelectionTarget(
                sceneNodeID: sceneNodeID,
                component: .sketchEntity(SelectionComponentID(rawValue: controlPoint.selectionComponentID))
            )
        }
}

public func agentCircleCenterAndCurveTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (center: SelectionTarget, curve: SelectionTarget) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "circle"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let centerHandle = try #require(entry.pointHandles.first { $0.handle == .circleCenter })
    let curveComponentID = try #require(entry.selectionComponentID)
    return (
        center: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: centerHandle.selectionComponentID))
        ),
        curve: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: curveComponentID))
        )
    )
}

public func agentCircleRadius(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .circle(circle) = sketch.entities.values.first else {
        Issue.record("Expected one source circle")
        return 0.0
    }
    return try document.cadDocument.parameters.resolvedValue(for: circle.radius).value
}

public func agentArcStartAngle(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .arc(arc) = sketch.entities.values.first else {
        Issue.record("Expected one source arc")
        return 0.0
    }
    return try document.cadDocument.parameters.resolvedValue(for: arc.startAngle).value
}

public func agentSplineControlPoints(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> [Point2D] {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .spline(spline) = sketch.entities.values.first else {
        Issue.record("Expected one source spline")
        return []
    }
    return try spline.controlPoints.map { try agentPoint($0, in: document) }
}

public func agentStandalonePoint(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Point2D {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          let pointEntity = sketch.entities.values.first(where: { entity in
              if case .point = entity {
                  return true
              }
              return false
          }),
          case let .point(point) = pointEntity else {
        Issue.record("Expected one standalone source point")
        return Point2D(x: 0.0, y: 0.0)
    }
    return try agentPoint(point, in: document)
}

public func agentLineAngle(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    let endpoints = try agentLineEndpoints(in: document, featureID: featureID)
    return atan2(endpoints.end.y - endpoints.start.y, endpoints.end.x - endpoints.start.x)
}

public func agentLineEndpoints(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: Point2D, end: Point2D) {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .line(line) = sketch.entities.values.first else {
        Issue.record("Expected one source line")
        return (Point2D(x: 0.0, y: 0.0), Point2D(x: 0.0, y: 0.0))
    }
    return (
        start: try agentPoint(line.start, in: document),
        end: try agentPoint(line.end, in: document)
    )
}

public func assertAgentAngleQuantity(
    _ quantity: Quantity,
    equals expectedValue: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(quantity.kind == .angle)
    #expect(abs(quantity.value - expectedValue) <= tolerance)
}

public func assertAgentLengthQuantity(
    _ quantity: Quantity,
    equals expectedValue: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - expectedValue) <= tolerance)
}
