import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SketchDimensionSnapshotService: Sendable {
    public init() {}

    public func snapshot(
        document: DesignDocument,
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SketchDimensionSnapshot {
        let resolvedTargets = try SketchDimensionTargetResolver().resolve(
            document: document,
            targets: targets,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let entries = try resolvedTargets.flatMap { target in
            try rectangleEntries(for: target, in: document) ?? dimensionEntries(for: target)
        }

        return SketchDimensionSnapshot(
            counts: SketchDimensionSummaryResult.Counts(
                targetCount: targets.count,
                entryCount: entries.count
            ),
            entries: entries
        )
    }

    private func dimensionEntries(
        for target: SketchDimensionTargetResolver.ResolvedTarget
    ) throws -> [SketchDimensionSummaryResult.Entry] {
        let entity = target.entity
        switch entity.entityKind {
        case "line":
            guard let start = entity.start,
                  let end = entity.end else {
                throw unresolvedEntityGeometry(entityKind: "line")
            }
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length.isFinite, length > 0.0 else {
                throw unresolvedEntityGeometry(entityKind: "line")
            }
            let angle = atan2(dy, dx)
            return [
                entry(
                    entity: entity,
                    target: target,
                    kind: .length,
                    label: "Length",
                    inputExpression: .length(length, .meter),
                    resolvedValue: length,
                    isPrimaryForTarget: true
                ),
                entry(
                    entity: entity,
                    target: target,
                    kind: .angle,
                    label: "Angle",
                    inputExpression: .angle(angle, .radian),
                    resolvedValue: angle,
                    isPrimaryForTarget: false
                ),
            ]
        case "circle":
            guard let radius = entity.radius,
                  radius.isFinite,
                  radius > 0.0 else {
                throw unresolvedEntityGeometry(entityKind: "circle")
            }
            return circularEntries(
                entity: entity,
                target: target,
                radius: radius,
                includesSpanAngle: false
            )
        case "arc":
            guard let radius = entity.radius,
                  let startAngle = entity.startAngle,
                  let endAngle = entity.endAngle,
                  radius.isFinite,
                  radius > 0.0 else {
                throw unresolvedEntityGeometry(entityKind: "arc")
            }
            let span = normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            return circularEntries(
                entity: entity,
                target: target,
                radius: radius,
                includesSpanAngle: true,
                primaryKind: primaryKindForArc(target: target),
                spanAngle: span
            )
        default:
            return []
        }
    }

    /// A selected side of a rectangle sketch offers the rectangle's width and height, each edited
    /// through the side that runs along it. An edge a body generated from the rectangle keeps its
    /// line entries; the body's own size is the object dimension's.
    private func rectangleEntries(
        for target: SketchDimensionTargetResolver.ResolvedTarget,
        in document: DesignDocument
    ) throws -> [SketchDimensionSummaryResult.Entry]? {
        guard target.entity.entityKind == "line",
              case .sketchEntity = target.requestedTarget.component,
              case .sketchEntity(let componentID) = target.editTarget.component,
              let reference = componentID.sketchEntityReference,
              let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let lines = try document.rectangleLineIDs(in: sketch),
              let axis = try document.rectangleSideDimensionAxis(in: sketch, entityID: reference.entityID),
              let bounds = try document.resolvedSketchBounds2D(sketch) else {
            return nil
        }
        func side(_ entityID: SketchEntityID, label: String, meters: Double, primary: Bool) -> SketchDimensionSummaryResult.Entry {
            SketchDimensionSummaryResult.Entry(
                requestedTarget: target.requestedTarget,
                target: SelectionTarget(
                    sceneNodeID: target.editTarget.sceneNodeID,
                    component: .sketchEntity(.sketchEntity(featureID: reference.featureID, entityID: entityID))
                ),
                sceneNodeID: target.entity.sceneNodeID ?? "",
                sourceFeatureID: target.entity.sourceFeatureID,
                entityID: entityID.description,
                entityKind: "line",
                kind: .length,
                label: label,
                inputExpression: .length(meters, .meter),
                resolvedValue: meters,
                isPrimaryForTarget: primary
            )
        }
        return [
            side(lines.bottom, label: "Width", meters: bounds.maxX - bounds.minX, primary: axis == .width),
            side(lines.left, label: "Height", meters: bounds.maxY - bounds.minY, primary: axis == .height),
        ]
    }

    private func circularEntries(
        entity: SketchEntitySummaryResult.EntityEntry,
        target: SketchDimensionTargetResolver.ResolvedTarget,
        radius: Double,
        includesSpanAngle: Bool,
        primaryKind: SketchEntityDimensionKind = .diameter,
        spanAngle: Double? = nil
    ) -> [SketchDimensionSummaryResult.Entry] {
        var entries: [SketchDimensionSummaryResult.Entry] = [
            entry(
                entity: entity,
                target: target,
                kind: .diameter,
                label: "Diameter",
                inputExpression: .length(radius * 2.0, .meter),
                resolvedValue: radius * 2.0,
                isPrimaryForTarget: primaryKind == .diameter
            ),
            entry(
                entity: entity,
                target: target,
                kind: .radius,
                label: "Radius",
                inputExpression: .length(radius, .meter),
                resolvedValue: radius,
                isPrimaryForTarget: primaryKind == .radius
            ),
        ]
        if includesSpanAngle,
           let spanAngle {
            entries.append(
                entry(
                    entity: entity,
                    target: target,
                    kind: .angle,
                    label: "Span",
                    inputExpression: .angle(spanAngle, .radian),
                    resolvedValue: spanAngle,
                    isPrimaryForTarget: false
                )
            )
        }
        return entries
    }

    private func primaryKindForArc(
        target: SketchDimensionTargetResolver.ResolvedTarget
    ) -> SketchEntityDimensionKind {
        switch target.requestedTarget.component {
        case .edge:
            .radius
        case .object, .face, .vertex, .sketchEntity, .region, .constructionPlane:
            .diameter
        }
    }

    private func entry(
        entity: SketchEntitySummaryResult.EntityEntry,
        target: SketchDimensionTargetResolver.ResolvedTarget,
        kind: SketchEntityDimensionKind,
        label: String,
        inputExpression: CADExpression,
        resolvedValue: Double,
        isPrimaryForTarget: Bool
    ) -> SketchDimensionSummaryResult.Entry {
        SketchDimensionSummaryResult.Entry(
            requestedTarget: target.requestedTarget,
            target: target.editTarget,
            sceneNodeID: entity.sceneNodeID ?? "",
            sourceFeatureID: entity.sourceFeatureID,
            entityID: entity.entityID,
            entityKind: entity.entityKind,
            kind: kind,
            label: label,
            inputExpression: inputExpression,
            resolvedValue: resolvedValue,
            isPrimaryForTarget: isPrimaryForTarget
        )
    }

    private func normalizedPartialArcSpan(
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

    private func unresolvedEntityGeometry(entityKind: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "Sketch dimension summary requires a finite \(entityKind) entity."
        )
    }
}
