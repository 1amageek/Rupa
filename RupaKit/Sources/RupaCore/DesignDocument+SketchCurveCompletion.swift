import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Complete Edge: extends each open end of a sketch line, arc or open spline to the nearest
    /// place another curve in its plane, where the scene places it, crosses its extension, and
    /// returns the ends it extended.
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
        let others = try completionCandidates(for: selection, at: target.sceneNodeID, owner: owner)

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
        // Whether a curve lying along the extension between two of its parameters already covers
        // the end, which is then complete.
        let covers: (Double, Double) -> Bool
        switch curve {
        case .line(let start, let finish):
            let length = hypot(finish.x - start.x, finish.y - start.y)
            guard length > tolerance else {
                throw EditorError(code: .commandInvalid, message: "\(owner) cannot extend a zero-length line.")
            }
            extended = .line(start: start, end: finish)
            travel = { t in end == .end ? (t - 1) * length : -t * length }
            let endParameter: Double = end == .end ? 1 : 0
            covers = { a, b in min(a, b) <= endParameter + tolerance / length && max(a, b) >= endParameter - tolerance / length }
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
            let endAngleParameter = end == .end ? endAngle : startAngle
            covers = { otherStart, otherEnd in
                var sweep = (otherEnd - otherStart).truncatingRemainder(dividingBy: fullCircle)
                if sweep <= 0 { sweep += fullCircle }
                var offset = (endAngleParameter - otherStart).truncatingRemainder(dividingBy: fullCircle)
                if offset < 0 { offset += fullCircle }
                return offset <= sweep + tolerance / radius || offset >= fullCircle - tolerance / radius
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
            covers = { a, b in min(a, b) <= tolerance && max(a, b) >= -tolerance }
        }

        var nearest: Double?
        for other in others {
            let parameters: [Double]
            if let overlap = try overlapParameters(of: other, along: extended, tolerance: tolerance) {
                // A curve lying along the extension is met where it begins; one already over the
                // end completes it.
                if covers(overlap[0], overlap[1]) { return nil }
                parameters = overlap
            } else {
                do {
                    parameters = try SketchCurveIntersector(tolerance: .standard).intersections(
                        of: other, with: extended, secondReach: .extended
                    ).map(\.secondParameter)
                } catch let error as KernelError where error.code == .resourceLimitExceeded {
                    // A crossing the kernel cannot certify (a tangency, or one past its proof budget)
                    // could be the nearest, so no farther crossing may be taken instead.
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot certify where another curve meets the extension (it may touch it tangentially): \(error.message)"
                    )
                } catch let error as KernelError {
                    throw EditorError(code: .commandInvalid, message: "\(owner) geometry is invalid: \(error.message)")
                }
            }
            for parameter in parameters {
                guard let distance = travel(parameter) else { continue }
                if abs(distance) <= tolerance { return nil }
                if distance > tolerance, distance < (nearest ?? .infinity) { nearest = distance }
            }
        }
        return nearest
    }

    /// The parameters on `extended` where `other` begins and ends when it lies along it (a
    /// collinear line, or an arc or circle on the same circle), or `nil` when it does not.
    private func overlapParameters(
        of other: SketchCurveGeometry2D,
        along extended: SketchCurveGeometry2D,
        tolerance: Double
    ) throws -> [Double]? {
        switch (extended, other) {
        case let (.line(start, end), .line(a, b)):
            let dx = end.x - start.x, dy = end.y - start.y
            let length = hypot(dx, dy)
            func offset(_ p: Point2D) -> Double { abs((p.x - start.x) * dy - (p.y - start.y) * dx) / length }
            guard offset(a) <= tolerance, offset(b) <= tolerance else { return nil }
            func parameter(_ p: Point2D) -> Double { ((p.x - start.x) * dx + (p.y - start.y) * dy) / (length * length) }
            return [parameter(a), parameter(b)]
        case let (.arc(center, radius, _, _), .arc(otherCenter, otherRadius, otherStart, otherEnd)):
            guard hypot(center.x - otherCenter.x, center.y - otherCenter.y) <= tolerance,
                  abs(radius - otherRadius) <= tolerance else { return nil }
            return [otherStart, otherEnd]
        case let (.arc(center, radius, startAngle, _), .circle(otherCenter, otherRadius)):
            guard hypot(center.x - otherCenter.x, center.y - otherCenter.y) <= tolerance,
                  abs(radius - otherRadius) <= tolerance else { return nil }
            // A whole circle covers every angle, so it covers both ends.
            return [startAngle, startAngle + 2 * Double.pi]
        default:
            return nil
        }
    }

    /// Every curve in the selected curve's plane, placed where the scene draws it and expressed in
    /// the selected sketch's coordinates.
    ///
    /// Candidates come from each sketch's visible presentation occurrences, the placement rule the
    /// viewport, measurement and section analysis share: a sketch no scene node presents is
    /// history, not scene content. A curve whose placement leaves the plane is not a candidate; a
    /// circle or arc whose placement would distort it into an ellipse refuses the command, since
    /// leaving it out could make a farther crossing look nearest.
    private func completionCandidates(
        for selection: EditableSketchEntitySelection,
        at sceneNodeID: SceneNodeID,
        owner: String
    ) throws -> [SketchCurveGeometry2D] {
        let tolerance = ModelingTolerance.standard.distance
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let occurrences = try hierarchy.resolvedOccurrences()
        let selectedFrame = try SketchPlaneCoordinateSystem(plane: selection.sketch.plane)
        let selectedWorld = try hierarchy.worldTransform(of: sceneNodeID)
        let selectedInverse = try selectedWorld.inverse()

        var result: [SketchCurveGeometry2D] = []
        for featureID in cadDocument.designGraph.order {
            guard case .sketch(let sketch) = cadDocument.designGraph.nodes[featureID]?.operation else { continue }
            let frame = try SketchPlaneCoordinateSystem(plane: sketch.plane)
            for occurrence in hierarchy.presentationOccurrences(of: featureID, in: occurrences) where occurrence.isVisible {
                // A point of this occurrence's sketch in the selected sketch's coordinates, with
                // its distance off the selected plane.
                func placed(_ point: Point2D) throws -> (point: Point2D, depth: Double) {
                    let world = try occurrence.worldTransform.applied(to: frame.point(from: point))
                    let projection = selectedFrame.project(try selectedInverse.applied(to: world))
                    return (projection.point, projection.depth)
                }
                func inPlane(_ points: [Point2D]) throws -> [Point2D]? {
                    let mapped = try points.map(placed)
                    guard mapped.allSatisfy({ abs($0.depth) <= tolerance }) else { return nil }
                    return mapped.map(\.point)
                }
                let isSelectedOccurrence = featureID == selection.featureID && occurrence.sceneNodeID == sceneNodeID
                for entityID in sketch.entityOrder where !(isSelectedOccurrence && entityID == selection.entityID) {
                    guard let entity = sketch.entities[entityID],
                          let geometry = try completionOtherCurve(entity, owner: owner) else { continue }
                    switch geometry {
                    case let .line(start, end):
                        if let mapped = try inPlane([start, end]) { result.append(.line(start: mapped[0], end: mapped[1])) }
                    case let .cubicBezierChain(points):
                        // Bezier control points follow any affine placement exactly.
                        if let mapped = try inPlane(points) { result.append(.cubicBezierChain(controlPoints: mapped)) }
                    case let .circle(center, radius):
                        if let placedCircle = try placedCircle(center: center, radius: radius, start: 0, end: 0, through: inPlane, owner: owner) {
                            result.append(.circle(center: placedCircle.center, radius: placedCircle.radius))
                        }
                    case let .arc(center, radius, startAngle, endAngle):
                        if let placedArc = try placedCircle(center: center, radius: radius, start: startAngle, end: endAngle, through: inPlane, owner: owner) {
                            result.append(.arc(center: placedArc.center, radius: placedArc.radius, startAngle: placedArc.start, endAngle: placedArc.end))
                        }
                    }
                }
            }
        }
        return result
    }

    /// A circle or arc carried through a placement that must keep it a circle: its in-plane part
    /// has to be a rotation, reflection and uniform scale. A reflection reverses the arc's sense.
    private func placedCircle(
        center: Point2D, radius: Double, start: Double, end: Double,
        through inPlane: ([Point2D]) throws -> [Point2D]?,
        owner: String
    ) throws -> (center: Point2D, radius: Double, start: Double, end: Double)? {
        guard let mapped = try inPlane([
            center, Point2D(x: center.x + 1, y: center.y), Point2D(x: center.x, y: center.y + 1),
        ]) else { return nil }
        let ux = mapped[1].x - mapped[0].x, uy = mapped[1].y - mapped[0].y
        let vx = mapped[2].x - mapped[0].x, vy = mapped[2].y - mapped[0].y
        let scaleU = hypot(ux, uy), scaleV = hypot(vx, vy)
        guard abs(scaleU - scaleV) <= 1.0e-9 * max(scaleU, 1), abs(ux * vx + uy * vy) <= 1.0e-9 * scaleU * scaleV else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot use a circle or arc whose placement stretches it into an ellipse."
            )
        }
        let reflected = ux * vy - uy * vx < 0
        func angle(_ theta: Double) -> Double {
            atan2(uy * cos(theta) + vy * sin(theta), ux * cos(theta) + vx * sin(theta))
        }
        let (mappedStart, mappedEnd) = reflected ? (angle(end), angle(start)) : (angle(start), angle(end))
        return (mapped[0], radius * scaleU, mappedStart, mappedEnd)
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
