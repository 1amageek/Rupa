import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DesignDocument: Identifiable, Sendable {
    typealias EditableProfileRegionSelection = (
        featureID: FeatureID,
        profileIndex: Int,
        feature: FeatureNode,
        sketch: Sketch,
        profile: Profile
    )
    typealias PlannedOffsetRegionFeature = (
        name: String,
        result: OffsetRegionBuilder.Result
    )
    typealias EditableSketchEntitySelection = (
        featureID: FeatureID,
        entityID: SketchEntityID,
        feature: FeatureNode,
        sketch: Sketch,
        entity: SketchEntity
    )

    public var cadDocument: CADDocument
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var productMetadata: ProductMetadata

    public var id: DocumentID {
        cadDocument.id
    }

    public init(
        cadDocument: CADDocument,
        displayUnit: LengthDisplayUnit,
        ruler: RulerConfiguration,
        productMetadata: ProductMetadata = .empty()
    ) {
        self.cadDocument = cadDocument
        self.displayUnit = displayUnit
        self.ruler = ruler
        self.productMetadata = productMetadata
    }

    public static func empty(named name: String = "Untitled") -> DesignDocument {
        let unit: LengthDisplayUnit = .millimeter
        return DesignDocument(
            cadDocument: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: name)
            ),
            displayUnit: unit,
            ruler: .standard(for: unit),
            productMetadata: .empty()
        )
    }

    struct LineEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .lineStart(entityID) : .lineEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .lineEnd(entityID) : .lineStart(entityID)
        }
    }

    struct ArcEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .arcEnd(entityID) : .arcStart(entityID)
        }
    }

    enum SketchCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            }
        }

        var oppositeReference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.oppositeReference
            case .arc(let endpoint):
                endpoint.oppositeReference
            }
        }
    }

    private func lineEndpoint(for reference: SketchReference) -> LineEndpoint? {
        switch reference {
        case .lineStart(let entityID):
            LineEndpoint(entityID: entityID, isStart: true)
        case .lineEnd(let entityID):
            LineEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    private func arcEndpoint(for reference: SketchReference) -> ArcEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            ArcEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            ArcEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    func sketchCurveEndpoint(for reference: SketchReference) -> SketchCurveEndpoint? {
        if let lineEndpoint = lineEndpoint(for: reference) {
            return .line(lineEndpoint)
        }
        if let arcEndpoint = arcEndpoint(for: reference) {
            return .arc(arcEndpoint)
        }
        return nil
    }

    func adjacentSketchCurveEndpoint(
        to reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (reference: SketchReference, endpoint: SketchCurveEndpoint, entity: SketchEntity) {
        let matches = sketch.constraints.compactMap { constraint -> SketchReference? in
            guard case .coincident(let first, let second) = constraint else {
                return nil
            }
            if first == reference {
                return second
            }
            if second == reference {
                return first
            }
            return nil
        }
        let curveEndpointMatches = matches.compactMap { candidate -> (SketchReference, SketchCurveEndpoint, SketchEntity)? in
            guard let endpoint = sketchCurveEndpoint(for: candidate),
                  let entity = sketch.entities[endpoint.entityID],
                  isSupportedOffsetVertexCurveEntity(entity, endpoint: endpoint) else {
                return nil
            }
            return (candidate, endpoint, entity)
        }
        guard curveEndpointMatches.count == 1,
              let match = curveEndpointMatches.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires exactly one adjacent line or arc endpoint at the selected vertex."
            )
        }
        return match
    }

    func refreshedSketchDimension(
        _ dimension: SketchDimension,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchDimension {
        switch dimension {
        case .distance(let from, let to, _):
            let distance = try measuredSketchDistanceDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .distance(from: from, to: to, value: .length(distance, .meter))
        case .angle(let from, let to, _):
            let angle = try measuredSketchAngleDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .angle(from: from, to: to, value: .angle(angle, .radian))
        case .radius(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .radius(entity: entityID, value: .length(radius, .meter))
        case .diameter(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .diameter(entity: entityID, value: .length(radius * 2.0, .meter))
        }
    }

    private func measuredSketchDistanceDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed distance references."
            )
        }
        return hypot(second.x - first.x, second.y - first.y)
    }

    private func measuredSketchAngleDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        if let arcSpan = try measuredSketchArcSpanAngle(
            from: from,
            to: to,
            in: sketch,
            owner: owner
        ) {
            return arcSpan
        }
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed angle references."
            )
        }
        return atan2(second.y - first.y, second.x - first.x)
    }

    func measuredSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        let entityID: SketchEntityID
        switch (from, to) {
        case (.arcStart(let firstID), .arcEnd(let secondID)) where firstID == secondID:
            entityID = firstID
        case (.arcEnd(let firstID), .arcStart(let secondID)) where firstID == secondID:
            entityID = firstID
        default:
            return try measuredConnectedSketchArcSpanAngle(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
        }
        guard let entity = sketch.entities[entityID],
              case .arc(let arc) = entity else {
            return nil
        }
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
    }

    private struct SketchArcPathEndpoint: Hashable {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }
    }

    private struct SketchArcPathGeometry {
        var entityID: SketchEntityID
        var center: (x: Double, y: Double)
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var span: Double

        var startEndpoint: SketchArcPathEndpoint {
            SketchArcPathEndpoint(entityID: entityID, isStart: true)
        }

        var endEndpoint: SketchArcPathEndpoint {
            SketchArcPathEndpoint(entityID: entityID, isStart: false)
        }
    }

    private func measuredConnectedSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        guard let fromEndpoint = sketchArcPathEndpoint(for: from),
              let toEndpoint = sketchArcPathEndpoint(for: to),
              let seedEntity = sketch.entities[fromEndpoint.entityID],
              case .arc(let seedArc) = seedEntity else {
            return nil
        }
        let seedGeometry = try sketchArcPathGeometry(
            entityID: fromEndpoint.entityID,
            arc: seedArc,
            owner: owner
        )
        var geometries: [SketchEntityID: SketchArcPathGeometry] = [:]
        for (entityID, entity) in sketch.entities {
            guard case .arc(let arc) = entity else {
                continue
            }
            let geometry = try sketchArcPathGeometry(
                entityID: entityID,
                arc: arc,
                owner: owner
            )
            guard sketchArcPathGeometry(geometry, matchesCircleOf: seedGeometry) else {
                continue
            }
            geometries[entityID] = geometry
        }
        guard geometries[toEndpoint.entityID] != nil else {
            return nil
        }
        let spans = [
            connectedSketchArcSpanAngle(
                from: fromEndpoint,
                to: toEndpoint,
                geometries: geometries
            ),
            connectedSketchArcSpanAngle(
                from: toEndpoint,
                to: fromEndpoint,
                geometries: geometries
            ),
        ]
            .compactMap { $0 }
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func sketchArcPathEndpoint(for reference: SketchReference) -> SketchArcPathEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func sketchArcPathGeometry(
        entityID: SketchEntityID,
        arc: SketchArc,
        owner: String
    ) throws -> SketchArcPathGeometry {
        let center = try resolvedPoint(arc.center, owner: "\(owner) arc center")
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return SketchArcPathGeometry(
            entityID: entityID,
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            span: try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        )
    }

    private func sketchArcPathGeometry(
        _ geometry: SketchArcPathGeometry,
        matchesCircleOf seed: SketchArcPathGeometry
    ) -> Bool {
        nearlyEqual(geometry.center.x, seed.center.x, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.center.y, seed.center.y, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.radius, seed.radius, tolerance: 1.0e-9)
    }

    private func connectedSketchArcSpanAngle(
        from start: SketchArcPathEndpoint,
        to target: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> Double? {
        func search(
            from current: SketchArcPathEndpoint,
            accumulatedSpan: Double,
            visitedArcs: Set<SketchEntityID>,
            visitedEndpoints: Set<SketchArcPathEndpoint>
        ) -> [Double] {
            if current == target {
                return [accumulatedSpan]
            }
            guard visitedEndpoints.contains(current) == false else {
                return []
            }
            let nextVisitedEndpoints = visitedEndpoints.union([current])
            var spans: [Double] = []
            if current.isStart,
               visitedArcs.contains(current.entityID) == false,
               let geometry = geometries[current.entityID] {
                spans.append(
                    contentsOf: search(
                        from: geometry.endEndpoint,
                        accumulatedSpan: accumulatedSpan + geometry.span,
                        visitedArcs: visitedArcs.union([current.entityID]),
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            for endpoint in matchingSketchArcPathEndpoints(
                current,
                geometries: geometries
            ) where endpoint != current {
                spans.append(
                    contentsOf: search(
                        from: endpoint,
                        accumulatedSpan: accumulatedSpan,
                        visitedArcs: visitedArcs,
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            return spans
        }
        let spans = search(
            from: start,
            accumulatedSpan: 0.0,
            visitedArcs: [],
            visitedEndpoints: []
        )
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func matchingSketchArcPathEndpoints(
        _ endpoint: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> [SketchArcPathEndpoint] {
        guard let source = geometries[endpoint.entityID] else {
            return []
        }
        let sourcePoint = sketchArcPathPoint(endpoint, geometry: source)
        return geometries.values.flatMap { geometry in
            [geometry.startEndpoint, geometry.endEndpoint].filter { candidate in
                let point = sketchArcPathPoint(candidate, geometry: geometry)
                return nearlyEqual(point.x, sourcePoint.x, tolerance: 1.0e-9) &&
                    nearlyEqual(point.y, sourcePoint.y, tolerance: 1.0e-9)
            }
        }
    }

    private func sketchArcPathPoint(
        _ endpoint: SketchArcPathEndpoint,
        geometry: SketchArcPathGeometry
    ) -> (x: Double, y: Double) {
        let angle = endpoint.isStart ? geometry.startAngle : geometry.endAngle
        return (
            x: geometry.center.x + cos(angle) * geometry.radius,
            y: geometry.center.y + sin(angle) * geometry.radius
        )
    }

    private func uniqueSketchArcPathSpans(_ spans: [Double]) -> [Double] {
        spans.reduce(into: []) { uniqueSpans, span in
            guard uniqueSpans.contains(where: { nearlyEqual($0, span, tolerance: 1.0e-9) }) == false else {
                return
            }
            uniqueSpans.append(span)
        }
    }

    private func measuredSketchCircularRadius(
        _ entityID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing circular entity."
            )
        }
        switch entity {
        case .circle(let circle):
            return try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
        case .arc(let arc):
            return try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        case .point,
             .line,
             .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a circle or arc dimension target."
            )
        }
    }

    private func normalizedNonnegativeAngleSpan(
        from startAngle: Double,
        to endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span < 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    func isSupportedOffsetVertexCurveEntity(
        _ entity: SketchEntity,
        endpoint: SketchCurveEndpoint
    ) -> Bool {
        switch (entity, endpoint) {
        case (.line, .line),
             (.arc, .arc):
            return true
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            return false
        }
    }

    func translatedSketchPoint(
        _ point: SketchPoint,
        directionX: Double,
        directionY: Double,
        distance: CADExpression,
        scale: Double = 1.0
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, .scalar(directionX * scale))),
            y: .add(point.y, .multiply(distance, .scalar(directionY * scale)))
        )
    }

    func normalizedDirection(
        from start: SketchPoint,
        to end: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let startX = try resolvedLengthValue(start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) direction must not collapse to zero."
            )
        }
        return (x: deltaX / length, y: deltaY / length)
    }

    func dimensionReferencesAny(
        _ dimension: SketchDimension,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch dimension {
        case .distance(let first, let second, _),
             .angle(let first, let second, _):
            entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .radius(let entityID, _),
             .diameter(let entityID, _):
            entityIDs.contains(entityID)
        }
    }

    func constraintReferencesAny(
        _ constraint: SketchConstraint,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .horizontal(let entityID),
             .vertical(let entityID),
             .smoothSplineControlPoint(let entityID, _):
            return entityIDs.contains(entityID)
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return entityIDs.contains(first) || entityIDs.contains(second)
        case .splineEndpointTangent(let splineID, _, let lineID):
            return entityIDs.contains(splineID) || entityIDs.contains(lineID)
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return entityIDs.contains(first.splineID) || entityIDs.contains(second.splineID)
        case .fixed(let reference):
            return entityIDs.contains(entityID(for: reference))
        }
    }

    func entityID(for reference: SketchReference) -> SketchEntityID {
        switch reference {
        case .entity(let entityID),
             .lineStart(let entityID),
             .lineEnd(let entityID),
             .circleCenter(let entityID),
             .circleRadius(let entityID),
             .arcCenter(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID),
             .arcRadius(let entityID),
             .splineControlPoint(let entityID, _):
            entityID
        }
    }

    func resolvedLineMetrics(
        _ line: SketchLine,
        owner: String
    ) throws -> (length: Double, angleRadians: Double, angleDegrees: Double) {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) length must be greater than zero."
            )
        }
        let angleRadians = atan2(deltaY, deltaX)
        return (
            length: length,
            angleRadians: angleRadians,
            angleDegrees: angleRadians * 180.0 / .pi
        )
    }

    func resizedLine(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + deltaX / currentLength * length,
                y: startY + deltaY / currentLength * length
            )
        )
    }

    func resizedLinePreservingEnd(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: sketchPoint(
                x: endX - deltaX / currentLength * length,
                y: endY - deltaY / currentLength * length
            ),
            end: line.end
        )
    }

    func angledLinePreservingStart(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + cos(angleRadians) * length,
                y: startY + sin(angleRadians) * length
            )
        )
    }

    func angledLinePreservingEnd(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: sketchPoint(
                x: endX - cos(angleRadians) * length,
                y: endY - sin(angleRadians) * length
            ),
            end: line.end
        )
    }

    func angularDistance(_ first: Double, _ second: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = (first - second).truncatingRemainder(dividingBy: fullCircle)
        if delta > Double.pi {
            delta -= fullCircle
        }
        if delta < -Double.pi {
            delta += fullCircle
        }
        return abs(delta)
    }

    private func lineOrientationDistance(_ first: Double, _ second: Double) -> Double {
        let period = Double.pi
        var delta = (first - second).truncatingRemainder(dividingBy: period)
        if delta > period / 2.0 {
            delta -= period
        }
        if delta < -period / 2.0 {
            delta += period
        }
        return abs(delta)
    }

    func validateLineAngleDimensionAgainstDirectOrientationConstraints(
        _ angleRadians: Double,
        lineID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case .horizontal(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, 0.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a horizontal sketch constraint."
                    )
                }
            case .vertical(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, Double.pi / 2.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a vertical sketch constraint."
                    )
                }
            default:
                continue
            }
        }
    }

    func positiveArcSpan(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    func sketchConstraint(
        _ constraint: SketchConstraint,
        references entityID: SketchEntityID
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return sketchReference(first, references: entityID) ||
                sketchReference(second, references: entityID)
        case .fixed(let reference):
            return sketchReference(reference, references: entityID)
        case .horizontal(let id),
             .vertical(let id),
             .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return first == entityID || second == entityID
        case .splineEndpointTangent(let splineID, _, let lineID):
            return splineID == entityID || lineID == entityID
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return first.splineID == entityID || second.splineID == entityID
        }
    }

    func sketchDimension(
        _ dimension: SketchDimension,
        references entityID: SketchEntityID
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            return id == entityID
        }
    }
    func squaredDistance(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double)
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    func sketchReference(
        _ reference: SketchReference,
        references entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case .entity(let id),
             .lineStart(let id),
             .lineEnd(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id),
             .splineControlPoint(let id, _):
            return id == entityID
        }
    }

    func validateArc(
        _ arc: SketchArc,
        owner: String
    ) throws {
        _ = try resolvedLengthValue(arc.center.x, owner: "\(owner) center x")
        _ = try resolvedLengthValue(arc.center.y, owner: "\(owner) center y")
        _ = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let resolvedStartAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let resolvedEndAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        _ = try normalizedPartialArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )
    }

    func validateSpline(
        _ spline: SketchSpline,
        owner: String
    ) throws {
        let count = spline.controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control point count must be 3n + 1 and at least 4."
            )
        }
        let resolvedPoints = try spline.controlPoints.enumerated().map { index, point in
            (
                x: try resolvedLengthValue(point.x, owner: "\(owner) control point \(index) x"),
                y: try resolvedLengthValue(point.y, owner: "\(owner) control point \(index) y")
            )
        }
        for segmentIndex in stride(from: 0, to: resolvedPoints.count - 1, by: 3) {
            let start = resolvedPoints[segmentIndex]
            let end = resolvedPoints[segmentIndex + 3]
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) > ModelingTolerance.standard.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cubic segment \(segmentIndex / 3) must not collapse to a point."
                )
            }
        }
    }

    mutating func commitSketchEntityEdit(
        featureID: FeatureID,
        feature: inout FeatureNode,
        sketch: Sketch,
        objectRegistry: ObjectTypeRegistry,
        errorOwner: String
    ) throws {
        feature.operation = .sketch(sketch)
        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(errorOwner) produced invalid sketch geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeSketchObjectProperties(
            featureID: featureID,
            sketch: sketch,
            objectRegistry: objectRegistry
        )
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    mutating func synchronizeSketchObjectProperties(
        featureID: FeatureID,
        sketch: Sketch,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard sketch.entities.count == 1,
              let entity = sketch.entities.values.first else {
            return
        }
        switch entity {
        case .line(let line):
            let metrics = try resolvedLineMetrics(line, owner: "Sketch line")
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .line else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "length"),
                    to: metrics.length,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "angle"),
                    to: metrics.angleDegrees,
                    object: &object,
                    definition: definition
                )
            }
        case .circle(let circle):
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .circle else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "radius"),
                    to: radius,
                    object: &object,
                    definition: definition
                )
            }
        case .arc(let arc):
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "Sketch arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "Sketch arc start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "Sketch arc end angle")
            let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .arc else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "radius"),
                    to: radius,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "start.angle"),
                    to: startAngle * 180.0 / .pi,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "end.angle"),
                    to: (startAngle + span) * 180.0 / .pi,
                    object: &object,
                    definition: definition
                )
            }
        case .spline(let spline):
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .spline else {
                    return
                }
                Self.setIntegerProperty(
                    ObjectPropertyID(rawValue: "control.point.count"),
                    to: spline.controlPoints.count,
                    object: &object,
                    definition: definition
                )
            }
        case .point:
            return
        }
    }

    private mutating func updateSketchObjectProperties(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry,
        update: (inout ObjectDescriptor, ObjectTypeDefinition) -> Void
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch,
            object.typeID != nil else {
            return
        }
        let definition = try objectRegistry.requireDefinition(for: object.typeID)
        var resolved = definition.resolvedProperties(object.properties)
        object.properties = resolved
        update(&object, definition)
        resolved = definition.resolvedProperties(object.properties)
        try resolved.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        object.properties = resolved
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    mutating func setSketchObjectType(
        featureID: FeatureID,
        typeID: ObjectTypeID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch else {
            return
        }

        let definition = try objectRegistry.requireDefinition(for: typeID)
        var nextProperties = objectRegistry.defaultProperties(for: typeID)
        if let strokeWidth = object.properties[ObjectPropertyID(rawValue: "stroke.width")] {
            nextProperties[ObjectPropertyID(rawValue: "stroke.width")] = strokeWidth
        }
        nextProperties = definition.resolvedProperties(nextProperties)
        try nextProperties.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        object.typeID = typeID
        object.geometryRole = definition.geometryRole
        object.properties = nextProperties
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    mutating func markSketchObjectAsSourceEdited(featureID: FeatureID) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch else {
            return
        }
        object.typeID = nil
        object.properties = ObjectPropertySet()
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    func normalizedPartialArcSpan(
        startAngle: Double,
        endAngle: Double
    ) throws -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= ModelingTolerance.standard.angle {
            span += fullCircle
        }
        while span > fullCircle + ModelingTolerance.standard.angle {
            span -= fullCircle
        }
        guard span > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch angle span must be greater than zero."
            )
        }
        guard span < fullCircle - ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch must be partial; use a circle sketch for full circles."
            )
        }
        return span
    }

    private func rectangleSketch(
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) -> Sketch {
        let bottom = SketchEntityID()
        let right = SketchEntityID()
        let top = SketchEntityID()
        let left = SketchEntityID()
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        return Sketch(
            plane: plane,
            entities: [
                bottom: .line(SketchLine(start: bottomLeft, end: bottomRight)),
                right: .line(SketchLine(start: bottomRight, end: topRight)),
                top: .line(SketchLine(start: topRight, end: topLeft)),
                left: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ],
            constraints: [
                .horizontal(bottom),
                .vertical(right),
                .horizontal(top),
                .vertical(left),
                .coincident(.lineEnd(bottom), .lineStart(right)),
                .coincident(.lineEnd(right), .lineStart(top)),
                .coincident(.lineEnd(top), .lineStart(left)),
                .coincident(.lineEnd(left), .lineStart(bottom)),
            ]
        )
    }

    func sketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    func sketchCoordinate(
        from point: TopologySummaryResult.Entry.Point,
        on plane: SketchPlane
    ) throws -> (x: Double, y: Double, depth: Double) {
        switch plane {
        case .xy:
            return (x: point.x, y: point.y, depth: point.z)
        case .yz:
            return (x: point.y, y: point.z, depth: point.x)
        case .zx:
            return (x: point.z, y: point.x, depth: point.y)
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: 1.0e-12)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: 1.0e-12)
            let v = normal.cross(u)
            let delta = Point3D(x: point.x, y: point.y, z: point.z) - plane.origin
            return (
                x: delta.dot(u),
                y: delta.dot(v),
                depth: delta.dot(normal)
            )
        }
    }

    func updateRectangleSketch(
        _ sketch: inout Sketch,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) throws {
        guard let lineIDs = try rectangleLineIDs(in: sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an axis-aligned rectangle profile."
            )
        }
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        sketch.entities[lineIDs.bottom] = .line(SketchLine(start: bottomLeft, end: bottomRight))
        sketch.entities[lineIDs.right] = .line(SketchLine(start: bottomRight, end: topRight))
        sketch.entities[lineIDs.top] = .line(SketchLine(start: topRight, end: topLeft))
        sketch.entities[lineIDs.left] = .line(SketchLine(start: topLeft, end: bottomLeft))
    }

    func resolvedPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (x: Double, y: Double)? {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(point, owner: owner)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(line.start, owner: owner)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(line.end, owner: owner)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(circle.center, owner: owner)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(arc.center, owner: owner)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.startAngle, owner: owner)
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.endAngle, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(spline.controlPoints[index], owner: owner)
        case .circleRadius, .arcRadius:
            return nil
        }
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    func pointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let center = try resolvedPoint(arc.center, owner: owner)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let resolvedAngle = try resolvedAngleValue(angle, owner: "\(owner) arc angle")
        return (
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    private func invalidSketchPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references an unsupported sketch point."
        )
    }

    func rectangleLineIDs(
        in sketch: Sketch
    ) throws -> (bottom: SketchEntityID, right: SketchEntityID, top: SketchEntityID, left: SketchEntityID)? {
        guard let bounds = try resolvedSketchBounds2D(sketch),
              sketch.entities.count == 4 else {
            return nil
        }
        var bottom: SketchEntityID?
        var right: SketchEntityID?
        var top: SketchEntityID?
        var left: SketchEntityID?
        let tolerance = 1.0e-9

        for (id, entity) in sketch.entities {
            guard case .line(let line) = entity else {
                return nil
            }
            let startX = try resolvedLengthValue(line.start.x, owner: "Rectangle line start x")
            let startY = try resolvedLengthValue(line.start.y, owner: "Rectangle line start y")
            let endX = try resolvedLengthValue(line.end.x, owner: "Rectangle line end x")
            let endY = try resolvedLengthValue(line.end.y, owner: "Rectangle line end y")
            if nearlyEqual(startY, bounds.minY, tolerance: tolerance),
               nearlyEqual(endY, bounds.minY, tolerance: tolerance) {
                bottom = id
            } else if nearlyEqual(startY, bounds.maxY, tolerance: tolerance),
                      nearlyEqual(endY, bounds.maxY, tolerance: tolerance) {
                top = id
            } else if nearlyEqual(startX, bounds.minX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.minX, tolerance: tolerance) {
                left = id
            } else if nearlyEqual(startX, bounds.maxX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.maxX, tolerance: tolerance) {
                right = id
            } else {
                return nil
            }
        }

        guard let bottom,
              let right,
              let top,
              let left else {
            return nil
        }
        return (bottom, right, top, left)
    }

    func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    func resolvedSketchBounds2D(
        _ sketch: Sketch
    ) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var points: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            for point in sketchPoints(in: entity) {
                points.append(
                    (
                        x: try resolvedLengthValue(point.x, owner: "Sketch point x"),
                        y: try resolvedLengthValue(point.y, owner: "Sketch point y")
                    )
                )
            }
        }
        guard let first = points.first else {
            return nil
        }
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
        return (minX, minY, maxX, maxY)
    }

    private func sketchPoints(in entity: SketchEntity) -> [SketchPoint] {
        switch entity {
        case .point(let point):
            [point]
        case .line(let line):
            [line.start, line.end]
        case .circle(let circle):
            [circle.center]
        case .arc(let arc):
            [arc.center]
        case .spline(let spline):
            spline.controlPoints
        }
    }

    func isRectangleProfile(_ sketch: Sketch) -> Bool {
        guard sketch.entities.count == 4 else {
            return false
        }
        return sketch.entities.values.allSatisfy { entity in
            if case .line(_) = entity {
                return true
            }
            return false
        }
    }

    func singleCircleEntry(in sketch: Sketch) -> (id: SketchEntityID, circle: SketchCircle)? {
        var circleEntry: (id: SketchEntityID, circle: SketchCircle)?
        for (id, entity) in sketch.entities {
            guard case .circle(let circle) = entity else {
                return nil
            }
            guard circleEntry == nil else {
                return nil
            }
            circleEntry = (id, circle)
        }
        return circleEntry
    }

    public func validate(objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        try cadDocument.validate()
        try ruler.validate()
        guard ruler.displayUnit == displayUnit else {
            throw DocumentValidationError.invalidProductMetadata(
                "Document ruler display unit must match the document display unit."
            )
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

}

private extension SketchEntity {
    var line: SketchLine? {
        if case .line(let line) = self {
            return line
        }
        return nil
    }

    var circle: SketchCircle? {
        if case .circle(let circle) = self {
            return circle
        }
        return nil
    }

    var arc: SketchArc? {
        if case .arc(let arc) = self {
            return arc
        }
        return nil
    }

    var spline: SketchSpline? {
        if case .spline(let spline) = self {
            return spline
        }
        return nil
    }
}
