import Foundation
import SwiftCAD

public struct ObjectDimensionSummaryService: Sendable {
    public init() {}

    public func summarize(
        document: DesignDocument,
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ObjectDimensionSummaryResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before object dimension summary: \(String(describing: error))"
            )
        }

        let resolver = ObjectDimensionSourceResolver()
        let dimensionTargets = dimensionTargets(
            for: targets,
            in: document.productMetadata
        )
        let summaryEntries: [ObjectDimensionSummaryResult.Entry]
        if let facePairEntry = try facePairEntryIfPresent(
            for: dimensionTargets,
            in: document,
            objectRegistry: objectRegistry
        ) {
            summaryEntries = [facePairEntry]
        } else {
            summaryEntries = try dimensionTargets.flatMap { target in
                try entries(for: resolver.resolve(target: target, in: document))
            }
        }
        return ObjectDimensionSummaryResult(
            displayUnit: document.displayUnit,
            counts: ObjectDimensionSummaryResult.Counts(
                targetCount: targets.count,
                entryCount: summaryEntries.count
            ),
            entries: summaryEntries,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Object dimension summary completed with \(summaryEntries.count) editable dimension candidate(s)."
                ),
            ]
        )
    }

    private func facePairEntryIfPresent(
        for targets: [SelectionTarget],
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> ObjectDimensionSummaryResult.Entry? {
        guard targets.count == 2,
              let first = targets.first,
              let second = targets.dropFirst().first else {
            return nil
        }
        guard let dimension = try ObjectFacePairDimensionResolver().resolveIfPresent(
            first: first,
            second: second,
            in: document,
            objectRegistry: objectRegistry,
            operationName: "Object dimension face-pair summary"
        ) else {
            return nil
        }
        let resolvedMeters = resolvedDimensionValue(
            source: dimension.source,
            kind: dimension.kind
        )
        return entry(
            source: dimension.source,
            sourceKind: sourceKind(for: dimension.source),
            kind: dimension.kind,
            label: "Face Distance",
            inputExpression: .length(resolvedMeters, .meter),
            sourceExpression: sourceExpression(source: dimension.source, kind: dimension.kind),
            resolvedMeters: resolvedMeters,
            isPrimaryForTarget: true,
            target: dimension.target
        )
    }

    private func dimensionTargets(
        for targets: [SelectionTarget],
        in metadata: ProductMetadata
    ) -> [SelectionTarget] {
        targets.flatMap { target in
            dimensionTargets(for: target, in: metadata)
        }
    }

    private func dimensionTargets(
        for target: SelectionTarget,
        in metadata: ProductMetadata
    ) -> [SelectionTarget] {
        guard target.component == .object,
              let sceneNode = metadata.sceneNodes[target.sceneNodeID],
              sceneNode.object?.category != .body else {
            return [target]
        }
        var bodySceneNodeIDs: [SceneNodeID] = []
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        appendBodySceneNodeIDs(
            rootedAt: target.sceneNodeID,
            metadata: metadata,
            bodySceneNodeIDs: &bodySceneNodeIDs,
            visitedSceneNodeIDs: &visitedSceneNodeIDs
        )
        guard !bodySceneNodeIDs.isEmpty else {
            return [target]
        }
        return bodySceneNodeIDs.map { sceneNodeID in
            SelectionTarget(sceneNodeID: sceneNodeID)
        }
    }

    private func appendBodySceneNodeIDs(
        rootedAt sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        bodySceneNodeIDs: inout [SceneNodeID],
        visitedSceneNodeIDs: inout Set<SceneNodeID>
    ) {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        if sceneNode.object?.category == .body {
            bodySceneNodeIDs.append(sceneNodeID)
        }
        for childID in sceneNode.childIDs {
            appendBodySceneNodeIDs(
                rootedAt: childID,
                metadata: metadata,
                bodySceneNodeIDs: &bodySceneNodeIDs,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            )
        }
    }

    private func entries(for source: ObjectDimensionSource) -> [ObjectDimensionSummaryResult.Entry] {
        switch source.shape {
        case .box:
            return [
                entry(
                    source: source,
                    sourceKind: .box,
                    kind: .sizeX,
                    label: "Size X",
                    inputExpression: .length(source.sizeX, .meter),
                    resolvedMeters: source.sizeX,
                    isPrimaryForTarget: isPrimary(source: source, kind: .sizeX)
                ),
                entry(
                    source: source,
                    sourceKind: .box,
                    kind: .sizeY,
                    label: "Size Y",
                    inputExpression: .length(source.sizeY, .meter),
                    sourceExpression: source.depthExpression,
                    resolvedMeters: source.sizeY,
                    isPrimaryForTarget: isPrimary(source: source, kind: .sizeY)
                ),
                entry(
                    source: source,
                    sourceKind: .box,
                    kind: .sizeZ,
                    label: "Size Z",
                    inputExpression: .length(source.sizeZ, .meter),
                    resolvedMeters: source.sizeZ,
                    isPrimaryForTarget: isPrimary(source: source, kind: .sizeZ)
                ),
            ]
        case .cylinder:
            let radius = source.radius ?? source.sizeX / 2.0
            return [
                entry(
                    source: source,
                    sourceKind: .cylinder,
                    kind: .diameter,
                    label: "Diameter",
                    inputExpression: .length(radius * 2.0, .meter),
                    resolvedMeters: radius * 2.0,
                    isPrimaryForTarget: isPrimary(source: source, kind: .diameter)
                ),
                entry(
                    source: source,
                    sourceKind: .cylinder,
                    kind: .radius,
                    label: "Radius",
                    inputExpression: .length(radius, .meter),
                    sourceExpression: source.radiusExpression,
                    resolvedMeters: radius,
                    isPrimaryForTarget: isPrimary(source: source, kind: .radius)
                ),
                entry(
                    source: source,
                    sourceKind: .cylinder,
                    kind: .sizeY,
                    label: "Size Y",
                    inputExpression: .length(source.sizeY, .meter),
                    sourceExpression: source.depthExpression,
                    resolvedMeters: source.sizeY,
                    isPrimaryForTarget: isPrimary(source: source, kind: .sizeY)
                ),
            ]
        }
    }

    private func entry(
        source: ObjectDimensionSource,
        sourceKind: ObjectDimensionSummaryResult.SourceKind,
        kind: ObjectDimensionKind,
        label: String,
        inputExpression: CADExpression,
        sourceExpression: CADExpression? = nil,
        resolvedMeters: Double,
        isPrimaryForTarget: Bool,
        target: SelectionTarget? = nil
    ) -> ObjectDimensionSummaryResult.Entry {
        ObjectDimensionSummaryResult.Entry(
            target: target ?? source.target,
            sceneNodeID: source.sceneNodeID.description,
            sourceFeatureID: source.featureID.description,
            sourceKind: sourceKind,
            kind: kind,
            label: label,
            inputExpression: inputExpression,
            sourceExpression: sourceExpression,
            resolvedMeters: resolvedMeters,
            isPrimaryForTarget: isPrimaryForTarget
        )
    }

    private func sourceKind(for source: ObjectDimensionSource) -> ObjectDimensionSummaryResult.SourceKind {
        switch source.shape {
        case .box:
            .box
        case .cylinder:
            .cylinder
        }
    }

    private func resolvedDimensionValue(
        source: ObjectDimensionSource,
        kind: ObjectDimensionKind
    ) -> Double {
        switch kind {
        case .sizeX, .diameter:
            source.sizeX
        case .sizeY:
            source.sizeY
        case .sizeZ:
            source.sizeZ
        case .radius:
            source.radius ?? source.sizeX / 2.0
        }
    }

    private func sourceExpression(
        source: ObjectDimensionSource,
        kind: ObjectDimensionKind
    ) -> CADExpression? {
        switch kind {
        case .sizeY:
            source.depthExpression
        case .radius:
            source.radiusExpression
        case .sizeX, .sizeZ, .diameter:
            nil
        }
    }

    private func isPrimary(source: ObjectDimensionSource, kind: ObjectDimensionKind) -> Bool {
        switch source.target.component {
        case .object:
            switch source.shape {
            case .box:
                return kind == .sizeX
            case .cylinder:
                return kind == .diameter
            }
        case .face(let componentID):
            if source.shape == .cylinder, componentID == .bodyFaceSide {
                return kind == .diameter
            }
            return false
        case .edge(_):
            return kind == .sizeY
        case .vertex(_), .sketchEntity(_), .region(_):
            return false
        }
    }
}
