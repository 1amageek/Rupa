import Darwin
import Foundation
import Testing
import RupaCore
import SwiftCAD
import RupaAgent
import RupaAgentTransport

public func agentSketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation else {
        return nil
    }
    return sketch
}

public func agentSingleSketchEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) -> SketchEntityID? {
    guard let sketch = agentSketchFeature(in: document, featureID: featureID),
          sketch.entities.count == 1 else {
        return nil
    }
    return sketch.entities.keys.first
}

public func agentSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

public func agentLineArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Agent Line Arc Profile",
        operation: .sketch(agentLineArcProfileSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let bodyFeatureID = try document.extrudeProfile(
        name: "Agent Line Arc Body",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(500.0, .millimeter),
        direction: .normal
    )
    return (EditorSession(document: document), bodyFeatureID)
}

public func agentArcArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Agent Arc Arc Profile",
        operation: .sketch(agentArcArcProfileSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let bodyFeatureID = try document.extrudeProfile(
        name: "Agent Arc Arc Body",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(500.0, .millimeter),
        direction: .normal
    )
    return (EditorSession(document: document), bodyFeatureID)
}

public func agentLineArcProfileSketch() -> Sketch {
    let arcID = SketchEntityID()
    let bottomID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            arcID: .arc(
                SketchArc(
                    center: agentSketchTestPoint(x: 1.0, y: 0.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 2.0, .radian)
                )
            ),
            bottomID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: 0.0, y: 0.0),
                    end: agentSketchTestPoint(x: 2.0, y: 0.0)
                )
            ),
            diagonalID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: 1.0, y: 1.0),
                    end: agentSketchTestPoint(x: 0.0, y: 0.5)
                )
            ),
            leftID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: 0.0, y: 0.5),
                    end: agentSketchTestPoint(x: 0.0, y: 0.0)
                )
            ),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .arcStart(arcID)),
            .coincident(.arcEnd(arcID), .lineStart(diagonalID)),
            .coincident(.lineEnd(diagonalID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

public func agentArcArcProfileSketch() -> Sketch {
    let previousArcID = SketchEntityID()
    let currentArcID = SketchEntityID()
    let lineID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            previousArcID: .arc(
                SketchArc(
                    center: agentSketchTestPoint(x: 0.0, y: 1.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(Double.pi, .radian),
                    endAngle: .angle(Double.pi * 1.5, .radian)
                )
            ),
            currentArcID: .arc(
                SketchArc(
                    center: agentSketchTestPoint(x: -2.0, y: 0.0),
                    radius: .length(2.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 3.0, .radian)
                )
            ),
            lineID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: -1.0, y: sqrt(3.0)),
                    end: agentSketchTestPoint(x: -1.0, y: 1.0)
                )
            ),
        ],
        constraints: [
            .coincident(.arcEnd(previousArcID), .arcStart(currentArcID)),
            .coincident(.arcEnd(currentArcID), .lineStart(lineID)),
            .coincident(.lineEnd(lineID), .arcStart(previousArcID)),
        ]
    )
}

public func agentBodySceneNode(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNode? {
    document.productMetadata.sceneNodes.values.first { node in
        node.reference == .body(featureID)
    }
}

public func agentIsHorizontalLine(
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

public func agentContainsSketchPoint(
    _ summary: SketchEntitySummaryResult,
    x: Double,
    y: Double
) -> Bool {
    summary.entries.contains { entry in
        guard entry.entityKind == "line" else {
            return false
        }
        return agentPointMatches(entry.start, x: x, y: y) ||
            agentPointMatches(entry.end, x: x, y: y)
    }
}

public func agentSketchSummaryBounds(
    _ summary: SketchEntitySummaryResult
) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
    var points: [SketchEntitySummaryResult.Point] = []
    for entry in summary.entries where entry.entityKind == "line" {
        if let start = entry.start {
            points.append(start)
        }
        if let end = entry.end {
            points.append(end)
        }
    }
    guard let first = points.first else {
        return nil
    }
    return points.reduce(
        (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    ) { partial, point in
        (
            minX: min(partial.minX, point.x),
            minY: min(partial.minY, point.y),
            maxX: max(partial.maxX, point.x),
            maxY: max(partial.maxY, point.y)
        )
    }
}

public func agentPointMatches(
    _ point: SketchEntitySummaryResult.Point?,
    x: Double,
    y: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.x - x) < 1.0e-12 && abs(point.y - y) < 1.0e-12
}

public func agentResolvedSketchPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> SketchEntitySummaryResult.Point {
    let x = try document.cadDocument.parameters.resolvedValue(for: point.x)
    let y = try document.cadDocument.parameters.resolvedValue(for: point.y)
    #expect(x.kind == .length)
    #expect(y.kind == .length)
    return SketchEntitySummaryResult.Point(x: x.value, y: y.value)
}

public func agentTwoLineConstrainedSketchDocument(
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two line constrained sketch setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.005),
            end: agentSketchTestPoint(x: 0.005, y: 0.005)
        )
    )
    sketch.constraints.append(constraint(firstLineID, secondLineID))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

public func agentTwoLineUnconstrainedSketchDocument(
    name: String
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.005, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two line unconstrained sketch setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.005),
            end: agentSketchTestPoint(x: 0.0, y: 0.015)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

public func agentCollinearLineChainSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineIDs: [SketchEntityID]
) {
    let points = [
        agentSketchTestPoint(x: 0.000, y: 0.000),
        agentSketchTestPoint(x: 0.005, y: 0.000),
        agentSketchTestPoint(x: 0.010, y: 0.000),
    ]
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent collinear line-chain setup requires a source line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    let lineIDs = [firstLineID, secondLineID]
    sketch.entities = [
        firstLineID: .line(SketchLine(start: points[0], end: points[1])),
        secondLineID: .line(SketchLine(start: points[1], end: points[2])),
    ]
    sketch.constraints = [
        .coincident(.lineEnd(firstLineID), .lineStart(secondLineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineIDs)
}

public func agentOpenLineChainSlotDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineIDs: [SketchEntityID]
) {
    let points = [
        agentSketchTestPoint(x: 0.0, y: 0.0),
        agentSketchTestPoint(x: 0.010, y: 0.0),
        agentSketchTestPoint(x: 0.010, y: 0.006),
    ]
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line-chain Slot setup requires a source line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    let lineIDs = [firstLineID, secondLineID]
    sketch.entities = [
        firstLineID: .line(SketchLine(start: points[0], end: points[1])),
        secondLineID: .line(SketchLine(start: points[1], end: points[2])),
    ]
    sketch.constraints = [
        .coincident(.lineEnd(firstLineID), .lineStart(secondLineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineIDs)
}

public func agentOpenLineArcChainSlotDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line-arc Slot setup requires a source line sketch."
        )
    }
    let arcID = SketchEntityID()
    sketch.entities = [
        lineID: .line(SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.0),
            end: agentSketchTestPoint(x: 0.010, y: 0.0)
        )),
        arcID: .arc(SketchArc(
            center: agentSketchTestPoint(x: 0.010, y: 0.005),
            radius: .length(0.005, .meter),
            startAngle: .angle(-Double.pi / 2.0, .radian),
            endAngle: .angle(0.0, .radian)
        )),
    ]
    sketch.constraints = [
        .coincident(.lineEnd(lineID), .arcStart(arcID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID)
}

public func agentLineCircleTangentSketchDocument(
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line circle tangent setup requires a line sketch."
        )
    }
    let circleID = SketchEntityID()
    sketch.entities[circleID] = .circle(
        SketchCircle(
            center: agentSketchTestPoint(x: 0.005, y: 0.006),
            radius: .length(0.002, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, circleID)
}

public func agentSplinePointConstraintDocument(
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
            agentSketchTestPoint(x: 0.0, y: 0.0),
            agentSketchTestPoint(x: 0.002, y: 0.003),
            agentSketchTestPoint(x: 0.006, y: 0.003),
            agentSketchTestPoint(x: 0.008, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent spline point constraint setup requires a spline sketch."
        )
    }
    let pointID = SketchEntityID()
    sketch.entities[pointID] = .point(agentSketchTestPoint(x: 0.004, y: 0.002))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, pointID)
}

public func agentSplineLineTangentSketchDocument(
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
            agentSketchTestPoint(x: 0.0, y: 0.0),
            agentSketchTestPoint(x: 0.003, y: 0.004),
            agentSketchTestPoint(x: 0.006, y: 0.004),
            agentSketchTestPoint(x: 0.009, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent spline line tangent setup requires a spline sketch."
        )
    }
    let lineID = SketchEntityID()
    sketch.entities[lineID] = .line(
        SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.006),
            end: agentSketchTestPoint(x: 0.010, y: 0.006)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, lineID)
}

public func agentTwoSplineTangentSketchDocument(
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
            agentSketchTestPoint(x: 0.0, y: 0.0),
            agentSketchTestPoint(x: 0.003, y: 0.0),
            agentSketchTestPoint(x: 0.006, y: 0.0),
            agentSketchTestPoint(x: 0.009, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstSplineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two-spline tangent setup requires a spline sketch."
        )
    }
    let secondSplineID = SketchEntityID()
    sketch.entities[secondSplineID] = .spline(
        SketchSpline(controlPoints: [
            agentSketchTestPoint(x: 0.009, y: 0.0),
            agentSketchTestPoint(x: 0.0108, y: 0.0024),
            agentSketchTestPoint(x: 0.014, y: 0.002),
            agentSketchTestPoint(x: 0.017, y: 0.0),
        ])
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstSplineID, secondSplineID)
}

public func agentTwoCircleSketchDocument(
    name: String
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
        center: agentSketchTestPoint(x: 0.002, y: 0.003),
        radius: .length(0.004, .meter)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstCircleID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two circle setup requires a circle sketch."
        )
    }
    let secondCircleID = SketchEntityID()
    sketch.entities[secondCircleID] = .circle(
        SketchCircle(
            center: agentSketchTestPoint(x: 0.010, y: 0.011),
            radius: .length(0.001, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstCircleID, secondCircleID)
}

public func agentSketchTestPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

public func agentClosedBezierCircleSpline(radius: Double) -> SketchSpline {
    let kappa = 0.552_284_749_830_793_6
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        agentSketchTestPoint(x: x * radius, y: y * radius)
    }
    return SketchSpline(
        controlPoints: [
            point(1.0, 0.0),
            point(1.0, kappa),
            point(kappa, 1.0),
            point(0.0, 1.0),
            point(-kappa, 1.0),
            point(-1.0, kappa),
            point(-1.0, 0.0),
            point(-1.0, -kappa),
            point(-kappa, -1.0),
            point(0.0, -1.0),
            point(kappa, -1.0),
            point(1.0, -kappa),
            point(1.0, 0.0),
        ],
        isClosed: true
    )
}

public func agentLineEntriesAreParallel(
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

public func agentLineEntryLength(_ entry: SketchEntitySummaryResult.EntityEntry) -> Double {
    guard let start = entry.start,
          let end = entry.end else {
        return .nan
    }
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}
