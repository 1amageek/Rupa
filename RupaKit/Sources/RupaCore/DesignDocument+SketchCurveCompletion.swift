import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Complete Edge: extends each open end of a sketch line, arc or open spline to the nearest
    /// place another curve in its sketch plane crosses its extension, and returns the ends it
    /// extended.
    ///
    /// A line extends along itself, an arc around its circle and a spline straight along its end
    /// tangent. An end already lying on another curve is complete and stays. The extension itself is
    /// `extendSketchCurve`'s, so the same constraint and Bridge Curve refusals apply; nothing changes
    /// when either end fails. Refuses when no end reaches another curve.
    @discardableResult
    public mutating func completeSketchCurve(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SketchCurveEnd] {
        let owner = "Complete Edge"
        let selection = try editableSketchEntityBase(for: target, operationName: owner)
        let curve = try completionCurve(selection.entity, owner: owner)
        // Sketches on the same plane share its 2D coordinates, as Cut Curve's cutters do.
        var others: [SketchCurveGeometry2D] = []
        for featureID in cadDocument.designGraph.order {
            guard case .sketch(let sketch) = cadDocument.designGraph.nodes[featureID]?.operation,
                  sketch.plane == selection.sketch.plane else { continue }
            for entityID in sketch.entityOrder where featureID != selection.featureID || entityID != selection.entityID {
                guard let entity = sketch.entities[entityID],
                      let geometry = try completionOtherCurve(entity, owner: owner) else { continue }
                others.append(geometry)
            }
        }

        // The end first: prepending to a spline start would shift its end control point index.
        var reaches: [(end: SketchCurveEnd, distance: Double)] = []
        for end in [SketchCurveEnd.end, .start] {
            if let distance = try completionDistance(of: curve, at: end, toward: others, owner: owner) {
                reaches.append((end, distance))
            }
        }
        // Both ends of an arc can run around to the same crossing, which would close it into a
        // circle; only the end that gets there first is extended.
        if case .arc(_, let radius, let startAngle, let endAngle) = curve, reaches.count == 2,
           try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            + (reaches[0].distance + reaches[1].distance) / radius >= 2 * Double.pi - ModelingTolerance.standard.angle,
           let shorter = reaches.min(by: { $0.distance < $1.distance }) {
            reaches = [shorter]
        }
        guard !reaches.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) found no other curve in the sketch plane that the selected curve's extension reaches."
            )
        }

        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        for reach in reaches {
            try extendSketchCurve(
                target: SelectionTarget(
                    sceneNodeID: target.sceneNodeID,
                    component: .sketchEntity(try completionEndComponent(
                        of: selection, curve: curve, end: reach.end
                    ))
                ),
                distance: .length(reach.distance, .meter),
                shape: curve.extensionShape,
                objectRegistry: objectRegistry
            )
        }
        didCommit = true
        return reaches.map(\.end)
    }

    /// The selected curve with what its ends extend along.
    private enum CompletionCurve {
        case line(start: Point2D, end: Point2D)
        case arc(center: Point2D, radius: Double, startAngle: Double, endAngle: Double)
        case spline(controlPoints: [Point2D])

        var extensionShape: ExtendCurveShape {
            if case .spline = self { return .linear }
            return .natural
        }
    }

    private func completionCurve(_ entity: SketchEntity, owner: String) throws -> CompletionCurve {
        switch entity {
        case .line(let line):
            return .line(
                start: try completionPoint(line.start, owner: owner),
                end: try completionPoint(line.end, owner: owner)
            )
        case .arc(let arc):
            return .arc(
                center: try completionPoint(arc.center, owner: owner),
                radius: try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius"),
                startAngle: try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle"),
                endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
            )
        case .spline(let spline):
            guard !spline.isClosed else {
                throw EditorError(code: .commandInvalid, message: "\(owner) needs a curve with open ends; the spline is closed.")
            }
            return .spline(controlPoints: try spline.controlPoints.map { try completionPoint($0, owner: owner) })
        case .circle, .point:
            throw EditorError(code: .commandInvalid, message: "\(owner) extends a line, an arc or an open spline.")
        }
    }

    /// Another curve of the sketch as exact geometry; points bound nothing.
    private func completionOtherCurve(_ entity: SketchEntity, owner: String) throws -> SketchCurveGeometry2D? {
        switch entity {
        case .point:
            return nil
        case .line(let line):
            return .line(start: try completionPoint(line.start, owner: owner), end: try completionPoint(line.end, owner: owner))
        case .circle(let circle):
            return .circle(
                center: try completionPoint(circle.center, owner: owner),
                radius: try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) radius")
            )
        case .arc(let arc):
            return .arc(
                center: try completionPoint(arc.center, owner: owner),
                radius: try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius"),
                startAngle: try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle"),
                endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
            )
        case .spline(let spline):
            return .cubicBezierChain(controlPoints: try spline.controlPoints.map { try completionPoint($0, owner: owner) })
        }
    }

    /// How far `end` travels along its extension to the nearest other curve, `nil` when another
    /// curve already passes through it or none is reached.
    private func completionDistance(
        of curve: CompletionCurve,
        at end: SketchCurveEnd,
        toward others: [SketchCurveGeometry2D],
        owner: String
    ) throws -> Double? {
        let tolerance = ModelingTolerance.standard.distance
        let extended: SketchCurveGeometry2D
        // Maps an intersection parameter on `extended` to the distance travelled past the end.
        let travel: (Double) -> Double?
        switch curve {
        case .line(let start, let finish):
            let length = hypot(finish.x - start.x, finish.y - start.y)
            guard length > tolerance else {
                throw EditorError(code: .commandInvalid, message: "\(owner) cannot extend a zero-length line.")
            }
            extended = .line(start: start, end: finish)
            travel = { t in end == .end ? (t - 1) * length : -t * length }
        case .arc(let center, let radius, let startAngle, let endAngle):
            let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            let fullCircle = Double.pi * 2
            extended = .arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
            travel = { angle in
                var delta = (end == .end ? angle - endAngle : startAngle - angle).truncatingRemainder(dividingBy: fullCircle)
                if delta < 0 { delta += fullCircle }
                if delta > fullCircle - tolerance / radius { delta = 0 }
                // Beyond the gap the arc does not cover, the extension would overlap the arc itself.
                return delta < fullCircle - span ? delta * radius : nil
            }
        case .spline(let points):
            let (origin, previous) = end == .end
                ? (points[points.count - 1], points[points.count - 2])
                : (points[0], points[1])
            let tangentLength = hypot(origin.x - previous.x, origin.y - previous.y)
            guard tangentLength > tolerance else {
                throw EditorError(code: .commandInvalid, message: "\(owner) cannot extend a spline end without a tangent.")
            }
            // A unit-length ray, so its intersection parameter is the distance travelled.
            extended = .line(start: origin, end: Point2D(
                x: origin.x + (origin.x - previous.x) / tangentLength,
                y: origin.y + (origin.y - previous.y) / tangentLength
            ))
            travel = { t in t }
        }

        var nearest: Double?
        for other in others {
            let hits: [SketchCurveIntersection2D]
            do {
                hits = try SketchCurveIntersector(tolerance: .standard).intersections(
                    of: other, with: extended, secondReach: .extended
                )
            } catch let error as KernelError where error.code == .resourceLimitExceeded {
                // A curve lying along the extension has no single crossing to stop at.
                continue
            } catch let error as KernelError {
                throw EditorError(code: .commandInvalid, message: "\(owner) geometry is invalid: \(error.message)")
            }
            for hit in hits {
                guard let distance = travel(hit.secondParameter) else { continue }
                if abs(distance) <= tolerance { return nil }
                if distance > tolerance, distance < (nearest ?? .infinity) { nearest = distance }
            }
        }
        return nearest
    }

    private func completionEndComponent(
        of selection: EditableSketchEntitySelection,
        curve: CompletionCurve,
        end: SketchCurveEnd
    ) throws -> SelectionComponentID {
        switch curve {
        case .line:
            return .sketchPointHandle(featureID: selection.featureID, entityID: selection.entityID,
                                      handle: end == .start ? .lineStart : .lineEnd)
        case .arc:
            return .sketchPointHandle(featureID: selection.featureID, entityID: selection.entityID,
                                      handle: end == .start ? .arcStart : .arcEnd)
        case .spline:
            guard case .spline(let spline) = selection.entity else {
                throw EditorError(code: .commandInvalid, message: "Complete Edge lost the spline it extends.")
            }
            return .sketchControlPoint(featureID: selection.featureID, entityID: selection.entityID,
                                       index: end == .start ? 0 : spline.controlPoints.count - 1)
        }
    }

    private func completionPoint(_ point: SketchPoint, owner: String) throws -> Point2D {
        Point2D(
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }
}

/// An end of an open sketch curve.
public enum SketchCurveEnd: String, Codable, Equatable, Hashable, Sendable {
    case start
    case end
}
