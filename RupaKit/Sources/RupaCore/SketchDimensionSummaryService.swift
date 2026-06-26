import Foundation
import SwiftCAD

public struct SketchDimensionSummaryService: Sendable {
    public init() {}

    public func summarize(
        document: DesignDocument,
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchDimensionSummaryResult {
        let resolvedTargets = try SketchDimensionTargetResolver().resolve(
            document: document,
            targets: targets,
            objectRegistry: objectRegistry
        )
        let entries = try resolvedTargets.flatMap { target in
            try dimensionEntries(for: target)
        }

        return SketchDimensionSummaryResult(
            displayUnit: document.displayUnit,
            counts: SketchDimensionSummaryResult.Counts(
                targetCount: targets.count,
                entryCount: entries.count
            ),
            entries: entries,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Sketch dimension summary completed with \(entries.count) editable dimension candidate(s)."
                ),
            ]
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
        case .object, .face, .vertex, .sketchEntity, .region:
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
