import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The joined chain the selected curve belongs to (Join's group), if any.
    func joinedCurveGroup(featureID: FeatureID, entityID: SketchEntityID) -> JoinedCurveGroupSource? {
        productMetadata.joinedCurveGroupSources.values.first { source in
            source.featureID == featureID && source.memberEntityIDs.contains(entityID)
        }
    }

    /// Offset Planar Curve on a joined chain: its members, each turned to run on from the one
    /// before through the group's joints, become one run of Bezier spans (a line one straight
    /// span, an arc Swift-CAD's cubic chain within the modeling distance, a spline its own
    /// segments) and Swift-CAD offsets that run as one curve, corners joined by the gap fill.
    /// A chain that returns to its start stays closed. The result is a cubic chain spline.
    func offsetJoinedChain(
        _ group: JoinedCurveGroupSource, sketch: Sketch, distance: Double, gapFill: OffsetCurveGapFill
    ) throws -> SketchSpline {
        let spans = try joinedChainSpans(group, sketch: sketch)
        let kernelGapFill: CubicBezierChainOffset.GapFill = switch gapFill {
        case .round: .round
        case .linear: .linear
        case .natural: .natural
        }
        let chain: [Point2D]
        do {
            chain = try CubicBezierChainOffset(tolerance: .standard).offset(spans: spans, distance: distance, gapFill: kernelGapFill)
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "Offset Planar Curve: \(error.message)")
        }
        let isClosed = hypot(chain[0].x - chain[chain.count - 1].x, chain[0].y - chain[chain.count - 1].y) <= modelingSettings.tolerance.distance
        return SketchSpline(controlPoints: chain.map { sketchPoint(x: $0.x, y: $0.y) }, isClosed: isClosed)
    }

    /// The joined chain as one run of Bezier spans in sketch coordinates, each member turned to
    /// run on from the one before.
    func joinedChainSpans(_ group: JoinedCurveGroupSource, sketch: Sketch) throws -> [[Point2D]] {
        let owner = "Offset Planar Curve"
        // Each end of a member, 0 its start and 1 its end, and the end it is joined to.
        struct End: Hashable { var entity: SketchEntityID; var isEnd: Bool }
        func end(_ reference: SketchReference) throws -> End {
            switch reference {
            case .lineStart(let id), .arcStart(let id): return End(entity: id, isEnd: false)
            case .lineEnd(let id), .arcEnd(let id): return End(entity: id, isEnd: true)
            case .splineControlPoint(let id, let index):
                guard case .spline(let spline) = sketch.entities[id] else {
                    throw EditorError(code: .referenceUnresolved, message: "\(owner): a joint names a missing spline.")
                }
                return End(entity: id, isEnd: index != 0 && index == spline.controlPoints.count - 1)
            case .entity, .circleCenter, .circleRadius, .arcCenter, .arcRadius:
                throw EditorError(code: .commandInvalid, message: "\(owner): a joint is not a curve end.")
            }
        }
        var joined: [End: End] = [:]
        let joints = [(group.firstJoinedReference, group.secondJoinedReference)]
            + group.additionalJoints.map { ($0.firstReference, $0.secondReference) }
        for (first, second) in joints {
            let a = try end(first), b = try end(second)
            joined[a] = b
            joined[b] = a
        }
        // Start where the chain is open, or anywhere on a closed one.
        let members = group.memberEntityIDs
        guard let first = members.first(where: { joined[End(entity: $0, isEnd: false)] == nil })
                .map({ End(entity: $0, isEnd: false) })
            ?? members.first(where: { joined[End(entity: $0, isEnd: true)] == nil }).map({ End(entity: $0, isEnd: true) })
            ?? members.first.map({ End(entity: $0, isEnd: false) }) else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the joined curve has no members.")
        }
        var spans: [[Point2D]] = []
        var visited = Set<SketchEntityID>()
        var entering = first
        while visited.insert(entering.entity).inserted {
            guard let entity = sketch.entities[entering.entity] else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner): a joined member is missing.")
            }
            let memberSpans = try bezierSpans(of: entity, owner: owner)
            // Entering at its end runs the member backwards.
            spans += entering.isEnd ? memberSpans.reversed().map { $0.reversed() } : memberSpans
            guard let next = joined[End(entity: entering.entity, isEnd: !entering.isEnd)] else { break }
            entering = next
        }
        guard visited.count == members.count else {
            throw EditorError(code: .commandInvalid, message: "\(owner): the joined curve's members do not form one chain.")
        }
        return spans
    }

    /// A line, arc or spline as Bezier spans in its own direction.
    func bezierSpans(of entity: SketchEntity, owner: String) throws -> [[Point2D]] {
        switch entity {
        case .line(let line):
            let start = try resolvedProjectionPoint(line.start, owner: "\(owner) line start")
            let end = try resolvedProjectionPoint(line.end, owner: "\(owner) line end")
            return [[Point2D(x: start.x, y: start.y), Point2D(x: end.x, y: end.y)]]
        case .arc(let arc):
            let center = try resolvedProjectionPoint(arc.center, owner: "\(owner) arc center")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
            let chain = try CubicBezierArcApproximation(tolerance: modelingSettings.tolerance).chain(
                center: Point2D(x: center.x, y: center.y),
                radius: try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius"),
                startAngle: startAngle,
                sweep: try normalizedPartialArcSpan(
                    startAngle: startAngle, endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
                )
            )
            return stride(from: 0, to: chain.count - 1, by: 3).map { Array(chain[$0...($0 + 3)]) }
        case .spline(let spline):
            return try resolvedSketchSplineCurve(spline, owner: owner).segments.map(\.controlPoints)
        case .circle, .point:
            throw EditorError(code: .commandInvalid, message: "\(owner): a joined curve holds only lines, arcs and splines.")
        }
    }
}
