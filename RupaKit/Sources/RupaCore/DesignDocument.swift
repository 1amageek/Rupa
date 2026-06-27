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

    public mutating func rebuildSketchCurve(
        target: SelectionTarget,
        options: CurveRebuildOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> CurveRebuildReport {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve rebuild")
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild currently requires a spline entity target."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild currently requires an open spline curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild cannot edit a generated Bridge Curve source."
            )
        }

        let rebuilt: RebuiltSketchSpline
        switch options.method {
        case .points(let controlPointCount):
            rebuilt = try rebuiltSketchSplineByPointCount(
                spline,
                controlPointCount: controlPointCount,
                owner: "Sketch curve rebuild"
            )
        case .refit(let tolerance, let keepsCorners):
            rebuilt = try rebuiltSketchSplineByRefit(
                spline,
                tolerance: tolerance,
                keepsCorners: keepsCorners,
                owner: "Sketch curve rebuild"
            )
        case .explicitControl(let degree, let spanCount, let weight):
            rebuilt = try rebuiltSketchSplineByExplicitControl(
                spline,
                degree: degree,
                spanCount: spanCount,
                weight: weight,
                owner: "Sketch curve rebuild"
            )
        }

        let constraints = try constraintsAfterSketchCurveRebuild(
            selection.sketch.constraints,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )
        let dimensions = try dimensionsAfterSketchCurveRebuild(
            selection.sketch.dimensions,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )
        let bridgeCurveSources = try bridgeCurveSourcesAfterSketchCurveRebuild(
            productMetadata.bridgeCurveSources,
            featureID: selection.featureID,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(rebuilt.spline)
        sketch.constraints = constraints
        sketch.dimensions = dimensions

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitRebuild = false
        defer {
            if didCommitRebuild == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources = bridgeCurveSources
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve rebuild"
        )
        didCommitRebuild = true
        return CurveRebuildReport(
            sourceFeatureID: selection.featureID.description,
            entityID: selection.entityID.description,
            method: curveRebuildReportMethod(for: options),
            originalControlPointCount: rebuilt.originalControlPointCount,
            rebuiltControlPointCount: rebuilt.rebuiltControlPointCount,
            originalSpanCount: rebuilt.originalSegmentCount,
            rebuiltSpanCount: rebuilt.rebuiltSegmentCount,
            deviationMeasurement: .analyticCubicBezier,
            maximumDeviationMeters: rebuilt.deviation.maximumDistance,
            rootMeanSquareDeviationMeters: rebuilt.deviation.rootMeanSquareDistance,
            maximumDeviationFraction: rebuilt.deviation.maximumDistanceFraction,
            evaluatedIntervalCount: rebuilt.deviation.evaluatedIntervalCount,
            criticalPointCount: rebuilt.deviation.criticalPointCount
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

    private struct RebuiltSketchSpline {
        var spline: SketchSpline
        var originalControlPointCount: Int
        var rebuiltControlPointCount: Int
        var originalSegmentCount: Int
        var rebuiltSegmentCount: Int
        var deviation: SketchSplineRebuildDeviation
        var controlPointIndexMap: [Int: Int]

        var changesControlPointCount: Bool {
            originalControlPointCount != rebuiltControlPointCount
        }
    }

    private struct SketchSplineRebuildDeviation {
        var maximumDistance: Double
        var rootMeanSquareDistance: Double
        var maximumDistanceFraction: Double
        var evaluatedIntervalCount: Int
        var criticalPointCount: Int
    }

    private struct SketchSplineRebuildSample {
        var point: CADCore.Point2D
        var derivative: CADCore.Point2D
    }

    private enum SketchSplineRebuildSampleSide {
        case before
        case after
    }

    private struct SketchSplineRebuildInterval {
        var startFraction: Double
        var endFraction: Double
        var segmentCount: Int
    }

    private struct CubicBezierSegment2D {
        var p0: CADCore.Point2D
        var p1: CADCore.Point2D
        var p2: CADCore.Point2D
        var p3: CADCore.Point2D
    }

    private struct CubicSplineSegmentLocation {
        var segmentIndex: Int
        var localFraction: Double
    }

    private struct AnalyticCubicBezierDeviation {
        var maximumSquaredDistance: Double
        var maximumDistanceFraction: Double
        var squaredDistanceIntegral: Double
        var criticalPointCount: Int
    }

    private func curveRebuildReportMethod(
        for options: CurveRebuildOptions
    ) -> CurveRebuildReport.Method {
        switch options.method {
        case .points:
            return .points
        case .refit:
            return .refit
        case .explicitControl:
            return .explicitControl
        }
    }

    private func rebuiltSketchSplineByPointCount(
        _ spline: SketchSpline,
        controlPointCount: Int,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard controlPointCount >= 4,
              (controlPointCount - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Points method requires a 3n + 1 control point count of at least 4."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let rebuiltSegmentCount = (controlPointCount - 1) / 3
        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: rebuiltSegmentCount
                ),
            ],
            tangentWeight: 1.0,
            owner: owner
        )
    }

    private func rebuiltSketchSplineByRefit(
        _ spline: SketchSpline,
        tolerance: CADExpression,
        keepsCorners: Bool,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let toleranceMeters = try resolvedPositiveLengthValue(
            tolerance,
            owner: "\(owner) Refit tolerance"
        )
        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let intervals: [SketchSplineRebuildInterval]
        if keepsCorners {
            intervals = try refitIntervalsKeepingCorners(
                originalControlPoints,
                originalSegmentCount: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
        } else {
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: 0.0,
                endFraction: 1.0,
                originalSegmentSpan: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
            intervals = [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: segmentCount
                ),
            ]
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: intervals,
            tangentWeight: 1.0,
            owner: owner
        )
    }

    private func rebuiltSketchSplineByExplicitControl(
        _ spline: SketchSpline,
        degree: Int,
        spanCount: Int,
        weight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard degree == 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control currently supports degree 3 cubic Bezier output; degree \(degree) requires a B-spline/NURBS source model."
            )
        }
        guard spanCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control requires at least one span."
            )
        }
        guard weight.isFinite,
              weight >= 0.0,
              weight <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control weight must be between 0 and 1."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: spanCount
                ),
            ],
            tangentWeight: weight,
            owner: owner
        )
    }

    private func rebuiltSketchSpline(
        from spline: SketchSpline,
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        tangentWeight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = intervals.reduce(0) { $0 + $1.segmentCount }
        guard rebuiltSegmentCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires at least one rebuilt span."
            )
        }
        var rebuiltControlPoints: [SketchPoint] = []
        rebuiltControlPoints.reserveCapacity(rebuiltSegmentCount * 3 + 1)
        var indexMap: [Int: Int] = [:]

        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }

            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let handles = sketchSplineRebuildHandles(
                    start: start,
                    end: end,
                    span: span,
                    tangentWeight: tangentWeight
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(
                        sketchPoint(x: start.point.x, y: start.point.y)
                    )
                    mapOriginalKnotIfAligned(
                        fraction: startFraction,
                        originalSegmentCount: originalSegmentCount,
                        rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                        into: &indexMap
                    )
                }
                rebuiltControlPoints.append(sketchPoint(x: handles.first.x, y: handles.first.y))
                rebuiltControlPoints.append(sketchPoint(x: handles.second.x, y: handles.second.y))
                rebuiltControlPoints.append(sketchPoint(x: end.point.x, y: end.point.y))
                mapOriginalKnotIfAligned(
                    fraction: endFraction,
                    originalSegmentCount: originalSegmentCount,
                    rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                    into: &indexMap
                )
            }
        }

        let rebuiltSpline = SketchSpline(
            controlPoints: rebuiltControlPoints,
            isClosed: spline.isClosed
        )
        try validateSpline(rebuiltSpline, owner: owner)
        let rebuiltControlPointValues = try resolvedSplineControlPoints(
            rebuiltSpline,
            owner: owner
        )
        let deviation = try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPointValues,
            startFraction: 0.0,
            endFraction: 1.0
        )
        return RebuiltSketchSpline(
            spline: rebuiltSpline,
            originalControlPointCount: originalControlPoints.count,
            rebuiltControlPointCount: rebuiltControlPoints.count,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount,
            deviation: deviation,
            controlPointIndexMap: indexMap
        )
    }

    private func sketchSplineRebuildHandles(
        start: SketchSplineRebuildSample,
        end: SketchSplineRebuildSample,
        span: Double,
        tangentWeight: Double
    ) -> (first: CADCore.Point2D, second: CADCore.Point2D) {
        let chord = CADCore.Point2D(
            x: end.point.x - start.point.x,
            y: end.point.y - start.point.y
        )
        let chordFirst = CADCore.Point2D(
            x: start.point.x + chord.x / 3.0,
            y: start.point.y + chord.y / 3.0
        )
        let chordSecond = CADCore.Point2D(
            x: end.point.x - chord.x / 3.0,
            y: end.point.y - chord.y / 3.0
        )
        let tangentFirst = CADCore.Point2D(
            x: start.point.x + start.derivative.x * span / 3.0,
            y: start.point.y + start.derivative.y * span / 3.0
        )
        let tangentSecond = CADCore.Point2D(
            x: end.point.x - end.derivative.x * span / 3.0,
            y: end.point.y - end.derivative.y * span / 3.0
        )
        return (
            first: interpolate(
                from: chordFirst,
                to: tangentFirst,
                fraction: tangentWeight
            ),
            second: interpolate(
                from: chordSecond,
                to: tangentSecond,
                fraction: tangentWeight
            )
        )
    }

    private func interpolate(
        from first: CADCore.Point2D,
        to second: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        CADCore.Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func refitIntervalsKeepingCorners(
        _ originalControlPoints: [CADCore.Point2D],
        originalSegmentCount: Int,
        tolerance: Double,
        owner: String
    ) throws -> [SketchSplineRebuildInterval] {
        let cornerBoundaries = cornerKnotSegmentBoundaries(
            originalControlPoints
        )
        var boundaries = [0]
        boundaries.append(contentsOf: cornerBoundaries)
        boundaries.append(originalSegmentCount)

        var intervals: [SketchSplineRebuildInterval] = []
        intervals.reserveCapacity(boundaries.count - 1)
        for index in 0 ..< boundaries.count - 1 {
            let startBoundary = boundaries[index]
            let endBoundary = boundaries[index + 1]
            let span = endBoundary - startBoundary
            guard span > 0 else {
                continue
            }
            let startFraction = Double(startBoundary) / Double(originalSegmentCount)
            let endFraction = Double(endBoundary) / Double(originalSegmentCount)
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: startFraction,
                endFraction: endFraction,
                originalSegmentSpan: span,
                tolerance: tolerance,
                owner: owner
            )
            intervals.append(
                SketchSplineRebuildInterval(
                    startFraction: startFraction,
                    endFraction: endFraction,
                    segmentCount: segmentCount
                )
            )
        }
        return intervals
    }

    private func refitSegmentCount(
        originalControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double,
        originalSegmentSpan: Int,
        tolerance: Double,
        owner: String
    ) throws -> Int {
        for segmentCount in 1 ... originalSegmentSpan {
            let candidateControlPoints = try rebuiltSketchSplineControlPoints(
                originalControlPoints: originalControlPoints,
                intervals: [
                    SketchSplineRebuildInterval(
                        startFraction: startFraction,
                        endFraction: endFraction,
                        segmentCount: segmentCount
                    ),
                ],
                owner: owner
            )
            let deviation = try maxSketchSplineDeviation(
                originalControlPoints: originalControlPoints,
                rebuiltControlPoints: candidateControlPoints,
                startFraction: startFraction,
                endFraction: endFraction
            )
            if deviation <= tolerance {
                return segmentCount
            }
        }
        return originalSegmentSpan
    }

    private func rebuiltSketchSplineControlPoints(
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        owner: String
    ) throws -> [CADCore.Point2D] {
        var rebuiltControlPoints: [CADCore.Point2D] = []
        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }
            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let firstHandle = CADCore.Point2D(
                    x: start.point.x + start.derivative.x * span / 3.0,
                    y: start.point.y + start.derivative.y * span / 3.0
                )
                let secondHandle = CADCore.Point2D(
                    x: end.point.x - end.derivative.x * span / 3.0,
                    y: end.point.y - end.derivative.y * span / 3.0
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(start.point)
                }
                rebuiltControlPoints.append(firstHandle)
                rebuiltControlPoints.append(secondHandle)
                rebuiltControlPoints.append(end.point)
            }
        }
        return rebuiltControlPoints
    }

    private func maxSketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> Double {
        try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPoints,
            startFraction: startFraction,
            endFraction: endFraction
        ).maximumDistance
    }

    private func sketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> SketchSplineRebuildDeviation {
        guard endFraction > startFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild generated an invalid deviation range."
            )
        }
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = (rebuiltControlPoints.count - 1) / 3
        let boundaries = sketchSplineDeviationBoundaries(
            startFraction: startFraction,
            endFraction: endFraction,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount
        )

        var maximumSquaredDistance = 0.0
        var maximumDistanceFraction = startFraction
        var squaredDistanceIntegral = 0.0
        var criticalPointCount = 0
        var evaluatedIntervalCount = 0

        for index in 0 ..< boundaries.count - 1 {
            let intervalStart = boundaries[index]
            let intervalEnd = boundaries[index + 1]
            guard intervalEnd > intervalStart + 1.0e-14 else {
                continue
            }
            let originalSegment = try cubicBezierSubcurve(
                controlPoints: originalControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let rebuiltSegment = try cubicBezierSubcurve(
                controlPoints: rebuiltControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let intervalDeviation = analyticCubicBezierDeviation(
                original: originalSegment,
                rebuilt: rebuiltSegment,
                globalStartFraction: intervalStart,
                globalEndFraction: intervalEnd
            )
            evaluatedIntervalCount += 1
            criticalPointCount += intervalDeviation.criticalPointCount
            squaredDistanceIntegral += intervalDeviation.squaredDistanceIntegral
            if intervalDeviation.maximumSquaredDistance > maximumSquaredDistance {
                maximumSquaredDistance = intervalDeviation.maximumSquaredDistance
                maximumDistanceFraction = intervalDeviation.maximumDistanceFraction
            }
        }
        let rangeLength = endFraction - startFraction
        let meanSquaredDistance = squaredDistanceIntegral / rangeLength
        return SketchSplineRebuildDeviation(
            maximumDistance: sqrt(max(0.0, maximumSquaredDistance)),
            rootMeanSquareDistance: sqrt(max(0.0, meanSquaredDistance)),
            maximumDistanceFraction: maximumDistanceFraction,
            evaluatedIntervalCount: evaluatedIntervalCount,
            criticalPointCount: criticalPointCount
        )
    }

    private func sketchSplineDeviationBoundaries(
        startFraction: Double,
        endFraction: Double,
        originalSegmentCount: Int,
        rebuiltSegmentCount: Int
    ) -> [Double] {
        var boundaries = [startFraction, endFraction]
        appendSplineSegmentBoundaries(
            segmentCount: originalSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        appendSplineSegmentBoundaries(
            segmentCount: rebuiltSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        return sortedUniqueFractions(boundaries)
    }

    private func appendSplineSegmentBoundaries(
        segmentCount: Int,
        startFraction: Double,
        endFraction: Double,
        to boundaries: inout [Double]
    ) {
        guard segmentCount > 1 else {
            return
        }
        for boundaryIndex in 1 ..< segmentCount {
            let boundary = Double(boundaryIndex) / Double(segmentCount)
            if boundary > startFraction + 1.0e-12,
               boundary < endFraction - 1.0e-12 {
                boundaries.append(boundary)
            }
        }
    }

    private func sortedUniqueFractions(_ fractions: [Double]) -> [Double] {
        var unique: [Double] = []
        for fraction in fractions.sorted() {
            if unique.last.map({ abs($0 - fraction) <= 1.0e-12 }) == true {
                continue
            }
            unique.append(fraction)
        }
        return unique
    }

    private func cubicBezierSubcurve(
        controlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> CubicBezierSegment2D {
        let start = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: startFraction,
            side: .after
        )
        let end = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: endFraction,
            side: .before
        )
        guard start.segmentIndex == end.segmentIndex,
              end.localFraction > start.localFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild deviation interval must stay inside one cubic span."
            )
        }

        let segmentStart = start.segmentIndex * 3
        var segment = CubicBezierSegment2D(
            p0: controlPoints[segmentStart],
            p1: controlPoints[segmentStart + 1],
            p2: controlPoints[segmentStart + 2],
            p3: controlPoints[segmentStart + 3]
        )
        if start.localFraction > 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: start.localFraction
            ).right
        }
        let remainingLength = 1.0 - start.localFraction
        let endInTrimmedSegment = (end.localFraction - start.localFraction) / remainingLength
        if endInTrimmedSegment < 1.0 - 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: endInTrimmedSegment
            ).left
        }
        return segment
    }

    private func cubicSplineSegmentLocation(
        controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> CubicSplineSegmentLocation {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            return CubicSplineSegmentLocation(segmentIndex: 0, localFraction: 0.0)
        }
        if scaledFraction >= Double(segmentCount) {
            return CubicSplineSegmentLocation(segmentIndex: segmentCount - 1, localFraction: 1.0)
        }
        if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                return CubicSplineSegmentLocation(
                    segmentIndex: max(0, boundary - 1),
                    localFraction: 1.0
                )
            case .after:
                return CubicSplineSegmentLocation(
                    segmentIndex: min(segmentCount - 1, boundary),
                    localFraction: 0.0
                )
            }
        }
        let segmentIndex = max(0, Int(floor(scaledFraction)))
        return CubicSplineSegmentLocation(
            segmentIndex: segmentIndex,
            localFraction: scaledFraction - Double(segmentIndex)
        )
    }

    private func splitCubicBezier(
        _ segment: CubicBezierSegment2D,
        fraction: Double
    ) -> (left: CubicBezierSegment2D, right: CubicBezierSegment2D) {
        let q0 = interpolate(from: segment.p0, to: segment.p1, fraction: fraction)
        let q1 = interpolate(from: segment.p1, to: segment.p2, fraction: fraction)
        let q2 = interpolate(from: segment.p2, to: segment.p3, fraction: fraction)
        let r0 = interpolate(from: q0, to: q1, fraction: fraction)
        let r1 = interpolate(from: q1, to: q2, fraction: fraction)
        let s = interpolate(from: r0, to: r1, fraction: fraction)
        return (
            left: CubicBezierSegment2D(p0: segment.p0, p1: q0, p2: r0, p3: s),
            right: CubicBezierSegment2D(p0: s, p1: r1, p2: q2, p3: segment.p3)
        )
    }

    private func analyticCubicBezierDeviation(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D,
        globalStartFraction: Double,
        globalEndFraction: Double
    ) -> AnalyticCubicBezierDeviation {
        let squaredDistance = squaredDistancePolynomial(
            original: original,
            rebuilt: rebuilt
        )
        let derivative = polynomialDerivative(squaredDistance)
        let roots = polynomialRootsInUnitInterval(derivative)
            .filter { $0 > 1.0e-10 && $0 < 1.0 - 1.0e-10 }
        let candidates = [0.0, 1.0] + roots
        var maximumSquaredDistance = 0.0
        var maximumLocalFraction = 0.0
        for candidate in candidates {
            let value = max(0.0, polynomialEvaluate(squaredDistance, at: candidate))
            if value > maximumSquaredDistance {
                maximumSquaredDistance = value
                maximumLocalFraction = candidate
            }
        }
        let intervalLength = globalEndFraction - globalStartFraction
        let squaredDistanceIntegral = intervalLength
            * max(0.0, polynomialUnitIntegral(squaredDistance))
        return AnalyticCubicBezierDeviation(
            maximumSquaredDistance: maximumSquaredDistance,
            maximumDistanceFraction: globalStartFraction
                + intervalLength * maximumLocalFraction,
            squaredDistanceIntegral: squaredDistanceIntegral,
            criticalPointCount: roots.count
        )
    }

    private func squaredDistancePolynomial(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D
    ) -> [Double] {
        let originalX = cubicBezierPowerCoefficients(
            original.p0.x,
            original.p1.x,
            original.p2.x,
            original.p3.x
        )
        let originalY = cubicBezierPowerCoefficients(
            original.p0.y,
            original.p1.y,
            original.p2.y,
            original.p3.y
        )
        let rebuiltX = cubicBezierPowerCoefficients(
            rebuilt.p0.x,
            rebuilt.p1.x,
            rebuilt.p2.x,
            rebuilt.p3.x
        )
        let rebuiltY = cubicBezierPowerCoefficients(
            rebuilt.p0.y,
            rebuilt.p1.y,
            rebuilt.p2.y,
            rebuilt.p3.y
        )
        let deltaX = zip(originalX, rebuiltX).map { $0 - $1 }
        let deltaY = zip(originalY, rebuiltY).map { $0 - $1 }
        return polynomialAdd(
            polynomialMultiply(deltaX, deltaX),
            polynomialMultiply(deltaY, deltaY)
        )
    }

    private func cubicBezierPowerCoefficients(
        _ p0: Double,
        _ p1: Double,
        _ p2: Double,
        _ p3: Double
    ) -> [Double] {
        [
            p0,
            -3.0 * p0 + 3.0 * p1,
            3.0 * p0 - 6.0 * p1 + 3.0 * p2,
            -p0 + 3.0 * p1 - 3.0 * p2 + p3,
        ]
    }

    private func polynomialAdd(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        var result = Array(repeating: 0.0, count: count)
        for index in lhs.indices {
            result[index] += lhs[index]
        }
        for index in rhs.indices {
            result[index] += rhs[index]
        }
        return result
    }

    private func polynomialMultiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        guard lhs.isEmpty == false,
              rhs.isEmpty == false else {
            return []
        }
        var result = Array(repeating: 0.0, count: lhs.count + rhs.count - 1)
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func polynomialDerivative(_ coefficients: [Double]) -> [Double] {
        guard coefficients.count > 1 else {
            return [0.0]
        }
        return coefficients.dropFirst().enumerated().map { index, coefficient in
            coefficient * Double(index + 1)
        }
    }

    private func polynomialUnitIntegral(_ coefficients: [Double]) -> Double {
        coefficients.enumerated().reduce(0.0) { partial, element in
            partial + element.element / Double(element.offset + 1)
        }
    }

    private func polynomialEvaluate(
        _ coefficients: [Double],
        at fraction: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * fraction + coefficient
        }
    }

    private func polynomialRootsInUnitInterval(_ coefficients: [Double]) -> [Double] {
        let trimmed = trimmedPolynomial(coefficients)
        let degree = trimmed.count - 1
        guard degree > 0 else {
            return []
        }
        let valueTolerance = polynomialValueTolerance(trimmed)
        if degree == 1 {
            let root = -trimmed[0] / trimmed[1]
            guard root >= -1.0e-12,
                  root <= 1.0 + 1.0e-12 else {
                return []
            }
            return [min(max(root, 0.0), 1.0)]
        }

        let criticalPoints = polynomialRootsInUnitInterval(
            polynomialDerivative(trimmed)
        )
        let splitPoints = sortedUniqueFractions([0.0] + criticalPoints + [1.0])
        var roots: [Double] = []
        for point in splitPoints where abs(polynomialEvaluate(trimmed, at: point)) <= valueTolerance {
            roots.append(point)
        }
        for index in 0 ..< splitPoints.count - 1 {
            let start = splitPoints[index]
            let end = splitPoints[index + 1]
            guard end > start + 1.0e-12 else {
                continue
            }
            let startValue = polynomialEvaluate(trimmed, at: start)
            let endValue = polynomialEvaluate(trimmed, at: end)
            if startValue * endValue < 0.0 {
                roots.append(
                    bisectedPolynomialRoot(
                        trimmed,
                        lower: start,
                        upper: end,
                        lowerValue: startValue,
                        tolerance: valueTolerance
                    )
                )
            }
        }
        return sortedUniqueFractions(
            roots.map { min(max($0, 0.0), 1.0) }
        )
    }

    private func bisectedPolynomialRoot(
        _ coefficients: [Double],
        lower: Double,
        upper: Double,
        lowerValue: Double,
        tolerance: Double
    ) -> Double {
        var low = lower
        var high = upper
        var lowValue = lowerValue
        for _ in 0 ..< 80 {
            let mid = (low + high) * 0.5
            let midValue = polynomialEvaluate(coefficients, at: mid)
            if abs(midValue) <= tolerance || high - low <= 1.0e-13 {
                return mid
            }
            if lowValue * midValue <= 0.0 {
                high = mid
            } else {
                low = mid
                lowValue = midValue
            }
        }
        return (low + high) * 0.5
    }

    private func trimmedPolynomial(_ coefficients: [Double]) -> [Double] {
        var trimmed = coefficients
        let tolerance = polynomialValueTolerance(coefficients)
        while trimmed.count > 1,
              abs(trimmed.last ?? 0.0) <= tolerance {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func polynomialValueTolerance(_ coefficients: [Double]) -> Double {
        max(1.0e-24, (coefficients.map { abs($0) }.max() ?? 0.0) * 1.0e-12)
    }

    private func cornerKnotSegmentBoundaries(
        _ controlPoints: [CADCore.Point2D]
    ) -> [Int] {
        let segmentCount = (controlPoints.count - 1) / 3
        guard segmentCount > 1 else {
            return []
        }

        var boundaries: [Int] = []
        for segmentBoundary in 1 ..< segmentCount {
            let knotIndex = segmentBoundary * 3
            let incoming = CADCore.Point2D(
                x: controlPoints[knotIndex].x - controlPoints[knotIndex - 1].x,
                y: controlPoints[knotIndex].y - controlPoints[knotIndex - 1].y
            )
            let outgoing = CADCore.Point2D(
                x: controlPoints[knotIndex + 1].x - controlPoints[knotIndex].x,
                y: controlPoints[knotIndex + 1].y - controlPoints[knotIndex].y
            )
            if isCornerBetweenSplineHandles(incoming: incoming, outgoing: outgoing) {
                boundaries.append(segmentBoundary)
            }
        }
        return boundaries
    }

    private func isCornerBetweenSplineHandles(
        incoming: CADCore.Point2D,
        outgoing: CADCore.Point2D
    ) -> Bool {
        let incomingLength = vectorLength(incoming)
        let outgoingLength = vectorLength(outgoing)
        let tinyLength = 1.0e-12
        guard incomingLength > tinyLength,
              outgoingLength > tinyLength else {
            return true
        }
        let dot = (incoming.x * outgoing.x + incoming.y * outgoing.y)
            / (incomingLength * outgoingLength)
        let clampedDot = min(max(dot, -1.0), 1.0)
        return clampedDot < cos(1.0e-4)
    }

    private func distance(
        _ first: CADCore.Point2D,
        _ second: CADCore.Point2D
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }

    private func vectorLength(_ vector: CADCore.Point2D) -> Double {
        sqrt(vector.x * vector.x + vector.y * vector.y)
    }

    private func mapOriginalKnotIfAligned(
        fraction: Double,
        originalSegmentCount: Int,
        rebuiltControlPointIndex: Int,
        into indexMap: inout [Int: Int]
    ) {
        let scaled = fraction * Double(originalSegmentCount)
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) <= 1.0e-9 else {
            return
        }
        let segmentBoundary = Int(rounded)
        guard segmentBoundary >= 0,
              segmentBoundary <= originalSegmentCount else {
            return
        }
        indexMap[segmentBoundary * 3] = rebuiltControlPointIndex
    }

    private func resolvedSplineControlPoints(
        _ spline: SketchSpline,
        owner: String
    ) throws -> [CADCore.Point2D] {
        try spline.controlPoints.enumerated().map { index, point in
            let resolved = try resolvedPoint(
                point,
                owner: "\(owner) control point \(index + 1)"
            )
            return CADCore.Point2D(x: resolved.x, y: resolved.y)
        }
    }

    private func sketchSplineRebuildSample(
        on controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> SketchSplineRebuildSample {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let segmentIndex: Int
        let localFraction: Double
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            segmentIndex = 0
            localFraction = 0.0
        } else if scaledFraction >= Double(segmentCount) {
            segmentIndex = segmentCount - 1
            localFraction = 1.0
        } else if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                segmentIndex = max(0, boundary - 1)
                localFraction = 1.0
            case .after:
                segmentIndex = min(segmentCount - 1, boundary)
                localFraction = 0.0
            }
        } else {
            segmentIndex = max(0, Int(floor(scaledFraction)))
            localFraction = scaledFraction - Double(segmentIndex)
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let localDerivative = cubicBezierDerivative(
            p0,
            p1,
            p2,
            p3,
            fraction: localFraction
        )
        return SketchSplineRebuildSample(
            point: cubicBezierPoint(
                p0,
                p1,
                p2,
                p3,
                fraction: localFraction
            ),
            derivative: CADCore.Point2D(
                x: localDerivative.x * Double(segmentCount),
                y: localDerivative.y * Double(segmentCount)
            )
        )
    }

    private func cubicBezierPoint(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        let inverseSquared = inverse * inverse
        let fractionSquared = fraction * fraction
        let inverseCubed = inverseSquared * inverse
        let fractionCubed = fractionSquared * fraction
        return CADCore.Point2D(
            x: inverseCubed * p0.x
                + 3.0 * inverseSquared * fraction * p1.x
                + 3.0 * inverse * fractionSquared * p2.x
                + fractionCubed * p3.x,
            y: inverseCubed * p0.y
                + 3.0 * inverseSquared * fraction * p1.y
                + 3.0 * inverse * fractionSquared * p2.y
                + fractionCubed * p3.y
        )
    }

    private func cubicBezierDerivative(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        return CADCore.Point2D(
            x: 3.0 * inverse * inverse * (p1.x - p0.x)
                + 6.0 * inverse * fraction * (p2.x - p1.x)
                + 3.0 * fraction * fraction * (p3.x - p2.x),
            y: 3.0 * inverse * inverse * (p1.y - p0.y)
                + 6.0 * inverse * fraction * (p2.y - p1.y)
                + 3.0 * fraction * fraction * (p3.y - p2.y)
        )
    }

    private func constraintsAfterSketchCurveRebuild(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        first,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    try rewriteSketchReferenceAfterCurveRebuild(
                        second,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID else {
                    return constraint
                }
                if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                    return .smoothSplineControlPoint(entity: id, index: rebuiltIndex)
                }
                guard rebuilt.changesControlPointCount == false else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "internal smooth spline constraints when the point count changes"
                    )
                }
                return .smoothSplineControlPoint(entity: id, index: index)
            case .splineEndpointTangent:
                return constraint
            case .tangentSplineEndpoints:
                return constraint
            case .smoothSplineEndpoints(let first, let second):
                guard rebuilt.changesControlPointCount == false ||
                    (first.splineID != entityID && second.splineID != entityID) else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "smooth spline endpoint constraints when the point count changes"
                    )
                }
                return constraint
            case .horizontal(let id),
                 .vertical(let id):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline orientation constraints"
                    )
                }
                return constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second),
                 .concentric(let first, let second),
                 .equalRadius(let first, let second):
                guard first != entityID && second != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchCurveRebuild(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .radius(let id, _),
                 .diameter(let id, _):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "circular dimensions"
                    )
                }
                return dimension
            }
        }
    }

    private func bridgeCurveSourcesAfterSketchCurveRebuild(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        var updated: [BridgeCurveSourceID: BridgeCurveSource] = [:]
        updated.reserveCapacity(sources.count)
        for (id, source) in sources {
            guard source.featureID != featureID || source.entityID != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "generated Bridge Curve source entities"
                )
            }
            updated[id] = BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.firstEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.firstEndpoint.parameter,
                    reversesSense: source.firstEndpoint.reversesSense,
                    tension: source.firstEndpoint.tension
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.secondEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.secondEndpoint.parameter,
                    reversesSense: source.secondEndpoint.reversesSense,
                    tension: source.secondEndpoint.tension
                ),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
        return updated
    }

    private func rewriteSketchReferenceAfterCurveRebuild(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> SketchReference {
        switch reference {
        case .splineControlPoint(let id, let index) where id == entityID:
            guard index >= 0,
                  index < rebuilt.originalControlPointCount else {
                throw sketchCurveRebuildUnsupportedReference(
                    "out-of-range spline control-point references"
                )
            }
            if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                return .splineControlPoint(
                    entity: entityID,
                    index: rebuiltIndex
                )
            }
            guard rebuilt.changesControlPointCount == false else {
                throw sketchCurveRebuildUnsupportedReference(
                    "internal spline control-point references when the point count changes"
                )
            }
            return reference
        case .splineControlPoint:
            return reference
        case .lineStart(let id),
             .lineEnd(let id),
             .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id):
            guard id != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "incompatible point references"
                )
            }
            return reference
        }
    }

    private func sketchCurveRebuildUnsupportedReference(
        _ reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve rebuild cannot preserve \(reason) yet."
        )
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
