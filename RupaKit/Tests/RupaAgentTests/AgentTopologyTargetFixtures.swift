import Darwin
import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgent
@testable import RupaAgentTransport

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
