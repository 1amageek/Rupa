import Darwin
import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgent
@testable import RupaAgentTransport

func withRunningListener<T>(
    controller: sending AgentCommandController,
    socketURL: URL,
    operation: (AgentSocketListener, AgentClient) async throws -> T
) async throws -> T {
    let socketPath = AgentSocketPath(socketURL.path)
    let listener = AgentSocketListener(
        controller: controller,
        socketPath: socketPath
    )
    let client = AgentClient(socketPath: socketPath)

    try await listener.start()
    do {
        let result = try await operation(listener, client)
        await listener.stop()
        return result
    } catch {
        await listener.stop()
        throw error
    }
}

func sendRaw(_ data: Data, to socketURL: URL) throws -> Data {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw EditorError(
            code: .agentUnavailable,
            message: "Failed to create test socket. errno=\(errno)"
        )
    }
    defer {
        Darwin.close(descriptor)
    }

    try AgentSocketAddress.withUnixAddress(path: socketURL.path) { address, length in
        guard Darwin.connect(descriptor, address, length) == 0 else {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Failed to connect test socket. errno=\(errno)"
            )
        }
    }
    try AgentSocketIO.writeAll(data, to: descriptor)
    Darwin.shutdown(descriptor, SHUT_WR)
    return try AgentSocketIO.readAll(from: descriptor)
}

func sendThroughDetachedClient(
    _ request: AgentRequest,
    socketPath: AgentSocketPath
) async throws -> AgentResponse {
    try await Task.detached {
        let client = AgentClient(socketPath: socketPath)
        return try client.send(request)
    }.value
}

func makeTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    return temporaryDirectory
}

func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}

func agentSketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation else {
        return nil
    }
    return sketch
}

func agentSingleSketchEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) -> SketchEntityID? {
    guard let sketch = agentSketchFeature(in: document, featureID: featureID),
          sketch.entities.count == 1 else {
        return nil
    }
    return sketch.entities.keys.first
}

func agentSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

func agentLineArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
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

func agentArcArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
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

func agentLineArcProfileSketch() -> Sketch {
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

func agentArcArcProfileSketch() -> Sketch {
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

func agentBodySceneNode(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNode? {
    document.productMetadata.sceneNodes.values.first { node in
        node.reference == .body(featureID)
    }
}

func agentIsHorizontalLine(
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

func agentContainsSketchPoint(
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

func agentSketchSummaryBounds(
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

func agentPointMatches(
    _ point: SketchEntitySummaryResult.Point?,
    x: Double,
    y: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.x - x) < 1.0e-12 && abs(point.y - y) < 1.0e-12
}

func agentResolvedSketchPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> SketchEntitySummaryResult.Point {
    let x = try document.cadDocument.parameters.resolvedValue(for: point.x)
    let y = try document.cadDocument.parameters.resolvedValue(for: point.y)
    #expect(x.kind == .length)
    #expect(y.kind == .length)
    return SketchEntitySummaryResult.Point(x: x.value, y: y.value)
}

func agentTwoLineConstrainedSketchDocument(
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

func agentTwoLineUnconstrainedSketchDocument(
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

func agentCollinearLineChainSketchDocument(
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

func agentOpenLineChainSlotDocument(
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

func agentOpenLineArcChainSlotDocument(
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

func agentLineCircleTangentSketchDocument(
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

func agentSplinePointConstraintDocument(
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

func agentSplineLineTangentSketchDocument(
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

func agentTwoSplineTangentSketchDocument(
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

func agentTwoCircleSketchDocument(
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

func agentSketchTestPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

func agentClosedBezierCircleSpline(radius: Double) -> SketchSpline {
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

func agentLineEntriesAreParallel(
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

func agentLineEntryLength(_ entry: SketchEntitySummaryResult.EntityEntry) -> Double {
    guard let start = entry.start,
          let end = entry.end else {
        return .nan
    }
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}

func agentCylinderRadius(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent cylinder radius setup requires an extruded circle body."
        )
    }
    for entity in sketch.entities.values {
        guard case .circle(let circle) = entity else {
            continue
        }
        let quantity = try document.cadDocument.parameters.resolvedValue(for: circle.radius)
        #expect(quantity.kind == .length)
        return quantity.value
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent cylinder radius setup requires a circle profile."
    )
}

func agentLineArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Offset Vertex Line Arc Profile",
        plane: .xy,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line arc offset vertex setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: agentSketchPoint(x: 0.010, y: 0.002),
            radius: .length(0.002, .meter),
            startAngle: .angle(-Double.pi / 2.0, .radian),
            endAngle: .angle(0.0, .radian)
        )
    )
    sketch.entities[topID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.012, y: 0.002),
            end: agentSketchPoint(x: 0.0, y: 0.002)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.0, y: 0.002),
            end: agentSketchPoint(x: 0.0, y: 0.0)
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

func agentLineArcCornerTreatmentSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID,
    diagonalID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Corner Treatment Line Arc Profile",
        plane: .xy,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line arc corner treatment setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: agentSketchPoint(x: 0.005, y: 0.0),
            radius: .length(0.005, .meter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    sketch.entities[diagonalID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.005, y: 0.005),
            end: agentSketchPoint(x: 0.0, y: 0.0025)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.0, y: 0.0025),
            end: agentSketchPoint(x: 0.0, y: 0.0)
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

func agentArcArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    upperArcID: SketchEntityID,
    lowerArcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Agent Offset Vertex Arc Arc Profile",
        plane: .xy,
        center: agentSketchPoint(x: 0.005, y: 0.005),
        radius: .length(0.002, .meter),
        startAngle: .angle(0.0, .radian),
        endAngle: .angle(Double.pi, .radian)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let upperArcID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent arc arc offset vertex setup requires an arc sketch."
        )
    }
    let lowerArcID = SketchEntityID()
    sketch.entities[lowerArcID] = .arc(
        SketchArc(
            center: agentSketchPoint(x: 0.005, y: 0.005),
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

func agentConcaveLineLoopDocument() throws -> DesignDocument {
    var document = DesignDocument.empty()
    let points = [
        agentSketchPoint(x: 0.0, y: 0.0),
        agentSketchPoint(x: 0.010, y: 0.0),
        agentSketchPoint(x: 0.010, y: 0.004),
        agentSketchPoint(x: 0.004, y: 0.004),
        agentSketchPoint(x: 0.004, y: 0.010),
        agentSketchPoint(x: 0.0, y: 0.010),
    ]
    let featureID = try document.createLineSketch(
        name: "Agent Concave Source Region",
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstEntityID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent concave source region setup requires a source line sketch."
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

func agentSketchPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

func nearlyEqualAgent(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

func isAgentVerticalGeneratedEdge(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard entry.kind == .edge,
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(start.x - end.x) <= tolerance
        && abs(start.y - end.y) <= tolerance
        && abs(start.z - end.z) > tolerance
}

func isAgentVerticalGeneratedEdge(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard isAgentVerticalGeneratedEdge(entry),
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(((start.x + end.x) / 2.0) - x) <= tolerance
        && abs(((start.y + end.y) / 2.0) - y) <= tolerance
}

func isAgentGeneratedVertex(
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

func agentParallelFaceTargets(
    in topology: TopologySummaryResult
) throws -> [SelectionTarget] {
    let faces = topology.entries.filter { $0.kind == .face }
    for firstIndex in faces.indices {
        let first = faces[firstIndex]
        guard let firstCenter = first.center,
              let firstNormal = first.normal,
              let firstTarget = first.selectionTarget() else {
            continue
        }
        let firstNormalVector = try agentVector(firstNormal).normalized(tolerance: 1.0e-12)
        for second in faces.dropFirst(firstIndex + 1) {
            guard let secondCenter = second.center,
                  let secondNormal = second.normal,
                  let secondTarget = second.selectionTarget() else {
                continue
            }
            let secondNormalVector = try agentVector(secondNormal).normalized(tolerance: 1.0e-12)
            guard abs(abs(firstNormalVector.dot(secondNormalVector)) - 1.0) <= 1.0e-8 else {
                continue
            }
            let centerDelta = agentPoint3D(secondCenter) - agentPoint3D(firstCenter)
            guard abs(centerDelta.dot(firstNormalVector)) > 1.0e-9 else {
                continue
            }
            return [firstTarget, secondTarget]
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent construction-plane test requires parallel generated faces."
    )
}

func agentParallelFaceDimensionTargets(
    in topology: TopologySummaryResult
) throws -> (first: SelectionTarget, second: SelectionTarget, distance: Double) {
    let faces = topology.entries.filter { $0.kind == .face }
    for firstIndex in faces.indices {
        let first = faces[firstIndex]
        guard let firstCenter = first.center,
              let firstNormal = first.normal,
              let firstTarget = first.selectionTarget() else {
            continue
        }
        let firstPoint = agentPoint3D(firstCenter)
        let firstNormalVector = try agentVector(firstNormal).normalized(tolerance: 1.0e-12)
        for second in faces.dropFirst(firstIndex + 1) {
            guard let secondCenter = second.center,
                  let secondNormal = second.normal,
                  let secondTarget = second.selectionTarget() else {
                continue
            }
            let secondNormalVector = try agentVector(secondNormal).normalized(tolerance: 1.0e-12)
            guard abs(abs(firstNormalVector.dot(secondNormalVector)) - 1.0) <= 1.0e-8 else {
                continue
            }
            let distance = (agentPoint3D(secondCenter) - firstPoint).length
            guard distance > 1.0e-9 else {
                continue
            }
            return (firstTarget, secondTarget, distance)
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent selection-dimension test requires parallel generated faces."
    )
}

func agentTwoPointVertexTargets(
    in topology: TopologySummaryResult,
    viewNormal: Vector3D
) throws -> [SelectionTarget] {
    let vertices = topology.entries.compactMap { entry -> (target: SelectionTarget, point: Point3D)? in
        guard entry.kind == .vertex,
              let target = entry.selectionTarget(),
              let point = entry.start else {
            return nil
        }
        return (target, agentPoint3D(point))
    }
    let unitViewNormal = try viewNormal.normalized(tolerance: 1.0e-12)
    for firstIndex in vertices.indices {
        for second in vertices.dropFirst(firstIndex + 1) {
            let first = vertices[firstIndex]
            do {
                let direction = try (second.point - first.point).normalized(tolerance: 1.0e-12)
                let projectedNormal = unitViewNormal - direction * unitViewNormal.dot(direction)
                _ = try projectedNormal.normalized(tolerance: 1.0e-12)
                return [first.target, second.target]
            } catch {
                continue
            }
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent construction-plane test requires two generated vertex targets compatible with the view normal."
    )
}

func agentSourcePointSession() throws -> (
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

func agentSketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}

func agentPointHandleSelectionTarget(
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

func agentBottomRectangleLine(
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

func agentVector(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
}

func agentPoint3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
    Point3D(x: point.x, y: point.y, z: point.z)
}

func agentTopologyPoint(
    _ point: TopologySummaryResult.Entry.Point?,
    isOnDepth depth: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.z - depth) < 1.0e-10
}

func agentTranslationTransform(
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

func agentLineEndpointTargets(
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

func agentLineCurveTarget(
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

func createAgentStandalonePointSketch(
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

func agentStandalonePointTarget(
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

func agentStandalonePointEntityID(
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

func agentArcEndpointTargets(
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

func agentSplineControlPointTargets(
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

func agentCircleCenterAndCurveTargets(
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

func agentCircleRadius(
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

func agentArcStartAngle(
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

func agentSplineControlPoints(
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

func agentStandalonePoint(
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

func agentLineAngle(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    let endpoints = try agentLineEndpoints(in: document, featureID: featureID)
    return atan2(endpoints.end.y - endpoints.start.y, endpoints.end.x - endpoints.start.x)
}

func agentLineEndpoints(
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

func assertAgentAngleQuantity(
    _ quantity: Quantity,
    equals expectedValue: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(quantity.kind == .angle)
    #expect(abs(quantity.value - expectedValue) <= tolerance)
}

func assertAgentLengthQuantity(
    _ quantity: Quantity,
    equals expectedValue: Double,
    tolerance: Double = 1.0e-12
) {
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - expectedValue) <= tolerance)
}

func agentPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> Point2D {
    Point2D(
        x: try document.cadDocument.parameters.resolvedValue(for: point.x).value,
        y: try document.cadDocument.parameters.resolvedValue(for: point.y).value
    )
}

func agentPatternArrayBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

struct AgentIndependentCopyCloneExtrudeFeature {
    var output: PatternArraySummary.IndependentCopyOutputStatus
    var featureID: FeatureID
}

func agentIndependentCopyCloneExtrudeFeature(
    server: AgentCommandController,
    sessionID: UUID,
    sourceID: PatternArraySourceID,
    expectedGeneration: DocumentGeneration
) throws -> AgentIndependentCopyCloneExtrudeFeature {
    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: expectedGeneration
        )
    )
    guard case .patternArraySummary(let summaryResult) = summaryResponse else {
        Issue.record("Agent must return a pattern array summary.")
        throw EditorError(
            code: .commandFailed,
            message: "Pattern array summary response was not returned."
        )
    }
    let summary = try #require(summaryResult.patternArrays.first { $0.sourceID == sourceID })
    let output = try #require(summary.independentCopyOutputs.first)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: expectedGeneration
        )
    )
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        Issue.record("Agent must return a design display snapshot.")
        throw EditorError(
            code: .commandFailed,
            message: "Design display snapshot response was not returned."
        )
    }
    let extrudeFeatureIDs = Set(snapshot.extrudes.map(\.featureID))
    let featureID = try #require(output.featureIDs.first { extrudeFeatureIDs.contains($0) })
    return AgentIndependentCopyCloneExtrudeFeature(
        output: output,
        featureID: featureID
    )
}

func agentFeatureID(
    inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> FeatureID? {
    guard let sceneNode = document.productMetadata.sceneNodes[rootSceneNodeID] else {
        return nil
    }
    if let featureID = sceneNode.reference?.featureID {
        return featureID
    }
    for childID in sceneNode.childIDs {
        if let featureID = agentFeatureID(
            inSceneSubtreeRootedAt: childID,
            document: document
        ) {
            return featureID
        }
    }
    return nil
}

extension ObjectPropertyValue {
    var lengthValue: Double? {
        guard case .length(let value) = self else {
            return nil
        }
        return value
    }
}

extension UUID {
    var featureID: FeatureID {
        FeatureID(self)
    }

    var sketchEntityID: SketchEntityID {
        SketchEntityID(self)
    }
}
