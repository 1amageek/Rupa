import Foundation
import SwiftCAD
import CADModeling
import RupaCoreTypes

public struct SketchEntitySnapshotService: Sendable {
    public init() {}

    public func snapshot(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntitySnapshot {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before sketch entity summary: \(String(describing: error))"
            )
        }

        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        let resolvedParameters = try ParameterResolver().resolve(document.cadDocument.parameters)
        let profileExtractor = SketchProfileExtractor(
            tolerance: document.modelingSettings.tolerance
        )
        var sketchEntries: [SketchEntitySummaryResult.SketchEntry] = []
        var entityEntries: [SketchEntitySummaryResult.EntityEntry] = []
        var regionEntries: [SketchEntitySummaryResult.RegionEntry] = []
        var diagnostics: [EditorDiagnostic] = []
        var constraintCount = 0
        var dimensionCount = 0

        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation else {
                continue
            }

            let sceneNodeID = sceneNodeIDsByFeatureID[featureID]?.description
            constraintCount += sketch.constraints.count
            dimensionCount += sketch.dimensions.count
            sketchEntries.append(
                SketchEntitySummaryResult.SketchEntry(
                    sourceFeatureID: featureID.description,
                    sourceFeatureName: feature.name,
                    sceneNodeID: sceneNodeID,
                    plane: sketch.plane,
                    entityCount: sketch.entities.count,
                    constraintCount: sketch.constraints.count,
                    dimensionCount: sketch.dimensions.count
                )
            )

            for (entityID, entity) in sketch.entities.sorted(by: { $0.key.description < $1.key.description }) {
                entityEntries.append(
                    try entityEntry(
                        featureID: featureID,
                        featureName: feature.name,
                        sceneNodeID: sceneNodeID,
                        entityID: entityID,
                        entity: entity,
                        sketch: sketch,
                        document: document
                    )
                )
            }

            if feature.outputs.contains(where: { $0.role == .profile }) {
                regionEntries += regionEntriesForSketch(
                    featureID: featureID,
                    featureName: feature.name,
                    sceneNodeID: sceneNodeID,
                    sketch: sketch,
                    resolvedParameters: resolvedParameters,
                    profileExtractor: profileExtractor,
                    tolerance: document.modelingSettings.tolerance,
                    diagnostics: &diagnostics
                )
            }
        }

        return SketchEntitySnapshot(
            counts: SketchEntitySummaryResult.Counts(
                sketchCount: sketchEntries.count,
                entityCount: entityEntries.count,
                regionCount: regionEntries.count,
                constraintCount: constraintCount,
                dimensionCount: dimensionCount
            ),
            sketches: sketchEntries,
            entries: entityEntries,
            regions: regionEntries,
            diagnostics: diagnostics
        )
    }

    private func regionEntriesForSketch(
        featureID: FeatureID,
        featureName: String?,
        sceneNodeID: String?,
        sketch: Sketch,
        resolvedParameters: ResolvedParameterTable,
        profileExtractor: SketchProfileExtractor,
        tolerance: ModelingTolerance,
        diagnostics: inout [EditorDiagnostic]
    ) -> [SketchEntitySummaryResult.RegionEntry] {
        let profiles: [Profile]
        do {
            profiles = try profileExtractor.extractProfiles(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: resolvedParameters
            )
        } catch is SketchError {
            return []
        } catch is GeometryError {
            return []
        } catch is UnitError {
            return []
        } catch {
            diagnostics.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "Sketch entity summary skipped region extraction for \(featureID.description): \(String(describing: error))"
                )
            )
            return []
        }

        let regionAnalyzer = ProfileRegionAnalyzer(tolerance: tolerance)
        return profiles.enumerated().compactMap { profileIndex, profile in
            let summary: ProfileRegionSummary
            do {
                summary = try regionAnalyzer.summary(for: profile)
            } catch {
                return nil
            }
            let selectionComponentID = sceneNodeID.map { _ in
                SelectionComponentID.profileRegion(
                    featureID: featureID,
                    profileIndex: profileIndex
                ).rawValue
            }
            return SketchEntitySummaryResult.RegionEntry(
                sourceFeatureID: featureID.description,
                sourceFeatureName: featureName,
                sceneNodeID: sceneNodeID,
                profileIndex: profileIndex,
                selectionComponentID: selectionComponentID,
                plane: profile.plane,
                center: point(summary.center),
                areaSquareMeters: summary.areaSquareMeters,
                boundaryPointCount: summary.points.count,
                boundarySegmentCount: profile.boundarySegments.count,
                boundaryPoints: summary.points.map(point)
            )
        }
    }

    private func entityEntry(
        featureID: FeatureID,
        featureName: String?,
        sceneNodeID: String?,
        entityID: SketchEntityID,
        entity: SketchEntity,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> SketchEntitySummaryResult.EntityEntry {
        let constraints = sketch.constraints
            .filter { constraintAffects($0, entityID: entityID) }
            .map(constraintEntry)
        let dimensions = try sketch.dimensions
            .filter { dimensionAffects($0, entityID: entityID) }
            .map { try dimensionEntry($0, document: document) }
        let selectionComponentID = sceneNodeID.map { _ in
            SelectionComponentID.sketchEntity(featureID: featureID, entityID: entityID).rawValue
        }
        func pointHandles(
            _ handles: [SketchEntityPointHandle]
        ) -> [SketchEntitySummaryResult.PointHandleEntry] {
            guard sceneNodeID != nil else {
                return []
            }
            return handles.map { handle in
                SketchEntitySummaryResult.PointHandleEntry(
                    handle: handle,
                    selectionComponentID: SelectionComponentID.sketchPointHandle(
                        featureID: featureID,
                        entityID: entityID,
                        handle: handle
                    ).rawValue
                )
            }
        }
        func controlPointTargets(
            count: Int
        ) -> [SketchEntitySummaryResult.ControlPointEntry] {
            guard sceneNodeID != nil else {
                return []
            }
            return (0..<count).map { index in
                SketchEntitySummaryResult.ControlPointEntry(
                    index: index,
                    selectionComponentID: SelectionComponentID.sketchControlPoint(
                        featureID: featureID,
                        entityID: entityID,
                        index: index
                    ).rawValue
                )
            }
        }

        switch entity {
        case .point(let point):
            return SketchEntitySummaryResult.EntityEntry(
                sourceFeatureID: featureID.description,
                sourceFeatureName: featureName,
                sceneNodeID: sceneNodeID,
                entityID: entityID.description,
                entityKind: "point",
                selectionComponentID: selectionComponentID,
                pointHandles: pointHandles([.point]),
                center: try resolvedPoint(point, document: document),
                centerExpression: expressionPoint(point),
                constraints: constraints,
                dimensions: dimensions
            )
        case .line(let line):
            return SketchEntitySummaryResult.EntityEntry(
                sourceFeatureID: featureID.description,
                sourceFeatureName: featureName,
                sceneNodeID: sceneNodeID,
                entityID: entityID.description,
                entityKind: "line",
                selectionComponentID: selectionComponentID,
                pointHandles: pointHandles([.lineStart, .lineEnd]),
                start: try resolvedPoint(line.start, document: document),
                end: try resolvedPoint(line.end, document: document),
                startExpression: expressionPoint(line.start),
                endExpression: expressionPoint(line.end),
                constraints: constraints,
                dimensions: dimensions
            )
        case .circle(let circle):
            return SketchEntitySummaryResult.EntityEntry(
                sourceFeatureID: featureID.description,
                sourceFeatureName: featureName,
                sceneNodeID: sceneNodeID,
                entityID: entityID.description,
                entityKind: "circle",
                selectionComponentID: selectionComponentID,
                pointHandles: pointHandles([.circleCenter]),
                center: try resolvedPoint(circle.center, document: document),
                radius: try resolvedValue(circle.radius, kind: .length, document: document),
                centerExpression: expressionPoint(circle.center),
                radiusExpression: circle.radius,
                constraints: constraints,
                dimensions: dimensions
            )
        case .arc(let arc):
            let center = try resolvedPoint(arc.center, document: document)
            let radius = try resolvedValue(arc.radius, kind: .length, document: document)
            let startAngle = try resolvedValue(arc.startAngle, kind: .angle, document: document)
            let endAngle = try resolvedValue(arc.endAngle, kind: .angle, document: document)
            return SketchEntitySummaryResult.EntityEntry(
                sourceFeatureID: featureID.description,
                sourceFeatureName: featureName,
                sceneNodeID: sceneNodeID,
                entityID: entityID.description,
                entityKind: "arc",
                selectionComponentID: selectionComponentID,
                pointHandles: pointHandles([.arcCenter, .arcStart, .arcEnd]),
                start: pointOnCircle(center: center, radius: radius, angle: startAngle),
                end: pointOnCircle(center: center, radius: radius, angle: endAngle),
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                centerExpression: expressionPoint(arc.center),
                radiusExpression: arc.radius,
                startAngleExpression: arc.startAngle,
                endAngleExpression: arc.endAngle,
                constraints: constraints,
                dimensions: dimensions
            )
        case .spline(let spline):
            let controlPoints = try spline.controlPoints.map { point in
                try resolvedPoint(point, document: document)
            }
            return SketchEntitySummaryResult.EntityEntry(
                sourceFeatureID: featureID.description,
                sourceFeatureName: featureName,
                sceneNodeID: sceneNodeID,
                entityID: entityID.description,
                entityKind: "spline",
                selectionComponentID: selectionComponentID,
                controlPointTargets: controlPointTargets(count: spline.controlPoints.count),
                start: controlPoints.first,
                end: controlPoints.last,
                controlPoints: controlPoints,
                startExpression: spline.controlPoints.first.map(expressionPoint),
                endExpression: spline.controlPoints.last.map(expressionPoint),
                controlPointExpressions: spline.controlPoints.map(expressionPoint),
                constraints: constraints,
                dimensions: dimensions
            )
        }
    }

    private func sceneNodeIDsByFeatureID(in document: DesignDocument) -> [FeatureID: SceneNodeID] {
        var mapping: [FeatureID: SceneNodeID] = [:]
        for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
            guard sceneNode.reference?.kind == .sketch,
                  let featureID = sceneNode.reference?.featureID else {
                continue
            }
            mapping[featureID] = sceneNodeID
        }
        return mapping
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        document: DesignDocument
    ) throws -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(
            x: try resolvedValue(point.x, kind: .length, document: document),
            y: try resolvedValue(point.y, kind: .length, document: document)
        )
    }

    private func expressionPoint(_ point: SketchPoint) -> SketchEntitySummaryResult.ExpressionPoint {
        SketchEntitySummaryResult.ExpressionPoint(x: point.x, y: point.y)
    }

    private func point(_ point: Point2D) -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(x: point.x, y: point.y)
    }

    private func resolvedValue(
        _ expression: CADExpression,
        kind: QuantityKind,
        document: DesignDocument
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == kind else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Sketch entity summary expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func pointOnCircle(
        center: SketchEntitySummaryResult.Point,
        radius: Double,
        angle: Double
    ) -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func constraintAffects(_ constraint: SketchConstraint, entityID: SketchEntityID) -> Bool {
        switch constraint {
        case let .coincident(first, second):
            return referenceAffects(first, entityID: entityID) || referenceAffects(second, entityID: entityID)
        case let .horizontal(id), let .vertical(id):
            return id == entityID
        case let .parallel(first, second),
             let .perpendicular(first, second),
             let .equalLength(first, second),
             let .concentric(first, second),
             let .equalRadius(first, second):
            return first == entityID || second == entityID
        case let .tangent(tangency):
            switch tangency {
            case let .lineCircular(line, circular, _):
                return line == entityID || circular == entityID
            case let .circularCircular(first, second, _):
                return first == entityID || second == entityID
            }
        case let .smoothSplineControlPoint(id, _):
            return id == entityID
        case let .splineEndpointTangent(tangency):
            return tangency.splineEndpoint.splineID == entityID || tangency.line == entityID
        case let .tangentSplineEndpoints(tangency):
            return tangency.first.splineID == entityID || tangency.second.splineID == entityID
        case let .smoothSplineEndpoints(tangency):
            return tangency.first.splineID == entityID || tangency.second.splineID == entityID
        case let .fixed(reference):
            return referenceAffects(reference, entityID: entityID)
        }
    }

    private func dimensionAffects(_ dimension: SketchDimension, entityID: SketchEntityID) -> Bool {
        switch dimension {
        case let .distance(from, to, _):
            return referenceAffects(from, entityID: entityID) || referenceAffects(to, entityID: entityID)
        case let .angle(from, to, _):
            return referenceAffects(from, entityID: entityID) || referenceAffects(to, entityID: entityID)
        case let .radius(id, _), let .diameter(id, _):
            return id == entityID
        }
    }

    private func referenceAffects(_ reference: SketchReference, entityID: SketchEntityID) -> Bool {
        switch reference {
        case let .entity(id),
             let .lineStart(id),
             let .lineEnd(id),
             let .circleCenter(id),
             let .circleRadius(id),
             let .arcCenter(id),
             let .arcStart(id),
             let .arcEnd(id),
             let .arcRadius(id),
             let .splineControlPoint(id, _):
            return id == entityID
        }
    }

    private func constraintEntry(_ constraint: SketchConstraint) -> SketchEntitySummaryResult.ConstraintEntry {
        switch constraint {
        case let .coincident(first, second):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "coincident",
                references: [referenceDescription(first), referenceDescription(second)]
            )
        case let .horizontal(entityID):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "horizontal",
                references: [entityDescription(entityID)]
            )
        case let .vertical(entityID):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "vertical",
                references: [entityDescription(entityID)]
            )
        case let .parallel(first, second):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "parallel",
                references: [entityDescription(first), entityDescription(second)]
            )
        case let .perpendicular(first, second):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "perpendicular",
                references: [entityDescription(first), entityDescription(second)]
            )
        case let .equalLength(first, second):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "equalLength",
                references: [entityDescription(first), entityDescription(second)]
            )
        case let .tangent(tangency):
            switch tangency {
            case let .lineCircular(line, circular, side):
                return SketchEntitySummaryResult.ConstraintEntry(
                    kind: "tangent",
                    references: [
                        entityDescription(line),
                        entityDescription(circular),
                        "side:\(side.rawValue)",
                    ]
                )
            case let .circularCircular(first, second, contact):
                return SketchEntitySummaryResult.ConstraintEntry(
                    kind: "tangent",
                    references: [
                        entityDescription(first),
                        entityDescription(second),
                        "contact:\(contact.rawValue)",
                    ]
                )
            }
        case let .concentric(first, second):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "concentric",
                references: [entityDescription(first), entityDescription(second)]
            )
        case let .equalRadius(first, second):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "equalRadius",
                references: [entityDescription(first), entityDescription(second)]
            )
        case let .smoothSplineControlPoint(entityID, index):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "smoothSplineControlPoint",
                references: ["splineControlPoint:\(entityID.description):\(index)"]
            )
        case let .splineEndpointTangent(tangency):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "splineEndpointTangent",
                references: [
                    "splineEndpoint:\(tangency.splineEndpoint.splineID.description):\(tangency.splineEndpoint.endpoint.rawValue)",
                    entityDescription(tangency.line),
                    "orientation:\(tangency.orientation.rawValue)",
                ]
            )
        case let .tangentSplineEndpoints(tangency):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "tangentSplineEndpoints",
                references: [
                    "splineEndpoint:\(tangency.first.splineID.description):\(tangency.first.endpoint.rawValue)",
                    "splineEndpoint:\(tangency.second.splineID.description):\(tangency.second.endpoint.rawValue)",
                    "orientation:\(tangency.orientation.rawValue)",
                ]
            )
        case let .smoothSplineEndpoints(tangency):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "smoothSplineEndpoints",
                references: [
                    "splineEndpoint:\(tangency.first.splineID.description):\(tangency.first.endpoint.rawValue)",
                    "splineEndpoint:\(tangency.second.splineID.description):\(tangency.second.endpoint.rawValue)",
                    "orientation:\(tangency.orientation.rawValue)",
                ]
            )
        case let .fixed(reference):
            return SketchEntitySummaryResult.ConstraintEntry(
                kind: "fixed",
                references: [referenceDescription(reference)]
            )
        }
    }

    private func dimensionEntry(
        _ dimension: SketchDimension,
        document: DesignDocument
    ) throws -> SketchEntitySummaryResult.DimensionEntry {
        switch dimension {
        case let .distance(from, to, value):
            return SketchEntitySummaryResult.DimensionEntry(
                kind: "distance",
                references: [referenceDescription(from), referenceDescription(to)],
                expression: value,
                resolvedValue: try resolvedValue(value, kind: .length, document: document)
            )
        case let .angle(from, to, value):
            return SketchEntitySummaryResult.DimensionEntry(
                kind: "angle",
                references: [referenceDescription(from), referenceDescription(to)],
                expression: value,
                resolvedValue: try resolvedValue(value, kind: .angle, document: document)
            )
        case let .radius(entityID, value):
            return SketchEntitySummaryResult.DimensionEntry(
                kind: "radius",
                references: [entityDescription(entityID)],
                expression: value,
                resolvedValue: try resolvedValue(value, kind: .length, document: document)
            )
        case let .diameter(entityID, value):
            return SketchEntitySummaryResult.DimensionEntry(
                kind: "diameter",
                references: [entityDescription(entityID)],
                expression: value,
                resolvedValue: try resolvedValue(value, kind: .length, document: document)
            )
        }
    }

    private func referenceDescription(_ reference: SketchReference) -> String {
        switch reference {
        case let .entity(entityID):
            return entityDescription(entityID)
        case let .lineStart(entityID):
            return "lineStart:\(entityID.description)"
        case let .lineEnd(entityID):
            return "lineEnd:\(entityID.description)"
        case let .circleCenter(entityID):
            return "circleCenter:\(entityID.description)"
        case let .circleRadius(entityID):
            return "circleRadius:\(entityID.description)"
        case let .arcCenter(entityID):
            return "arcCenter:\(entityID.description)"
        case let .arcStart(entityID):
            return "arcStart:\(entityID.description)"
        case let .arcEnd(entityID):
            return "arcEnd:\(entityID.description)"
        case let .arcRadius(entityID):
            return "arcRadius:\(entityID.description)"
        case let .splineControlPoint(entityID, index):
            return "splineControlPoint:\(entityID.description):\(index)"
        }
    }

    private func entityDescription(_ entityID: SketchEntityID) -> String {
        "entity:\(entityID.description)"
    }
}
