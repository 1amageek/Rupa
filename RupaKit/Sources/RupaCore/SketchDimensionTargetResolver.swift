import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SketchDimensionTargetResolver: Sendable {
    public struct ResolvedTarget: Sendable {
        public var requestedTarget: SelectionTarget
        public var editTarget: SelectionTarget
        public var entity: SketchEntitySummaryResult.EntityEntry

        public init(
            requestedTarget: SelectionTarget,
            editTarget: SelectionTarget,
            entity: SketchEntitySummaryResult.EntityEntry
        ) {
            self.requestedTarget = requestedTarget
            self.editTarget = editTarget
            self.entity = entity
        }
    }

    private let topologyService: TopologySnapshotService
    private let sketchEntityService: SketchEntitySnapshotService
    private let tolerance: Double

    public init(
        topologyService: TopologySnapshotService = TopologySnapshotService(),
        sketchEntityService: SketchEntitySnapshotService = SketchEntitySnapshotService(),
        tolerance: Double = 1.0e-8
    ) {
        self.topologyService = topologyService
        self.sketchEntityService = sketchEntityService
        self.tolerance = tolerance
    }

    public func resolve(
        document: DesignDocument,
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [ResolvedTarget] {
        let sketchSummary = try sketchEntityService.snapshot(
            document: document,
            objectRegistry: objectRegistry
        )
        let entriesByTarget = Dictionary(
            uniqueKeysWithValues: sketchSummary.entries.compactMap { entity in
                entity.selectionTarget().map { ($0, entity) }
            }
        )

        var topologySummary: TopologySnapshot?
        return try targets.map { target in
            if case .sketchEntity = target.component {
                guard let entity = entriesByTarget[target] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Sketch dimension summary could not resolve the selected sketch entity."
                    )
                }
                return ResolvedTarget(
                    requestedTarget: target,
                    editTarget: target,
                    entity: entity
                )
            }

            guard case .edge = target.component else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch dimension summary requires sketch curve or generated body edge targets."
                )
            }

            if topologySummary == nil {
                topologySummary = try topologyService.snapshot(
                    document: document,
                    objectRegistry: objectRegistry
                )
            }
            return try resolveGeneratedEdge(
                target,
                document: document,
                sketchEntries: sketchSummary.entries,
                topologyEntries: topologySummary?.entries ?? []
            )
        }
    }

    private func resolveGeneratedEdge(
        _ target: SelectionTarget,
        document: DesignDocument,
        sketchEntries: [SketchEntitySummaryResult.EntityEntry],
        topologyEntries: [TopologySummaryResult.Entry]
    ) throws -> ResolvedTarget {
        guard case .edge(let componentID) = target.component,
              componentID.isStableTopology else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch dimension summary requires generated body edge targets."
            )
        }
        let stableReference = try componentID.stableTopologyReference(
            operationName: "Sketch dimension summary"
        )
        guard let edgeEntry = topologyEntries.first(where: {
            $0.kind == .edge &&
                $0.sceneNodeID == target.sceneNodeID.description &&
                $0.stableReference == stableReference
        }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch dimension summary generated edge target was not found in the current topology."
            )
        }
        guard edgeEntry.generatedRole == "edge",
              let bodyFeatureID = bodyFeatureID(for: target, document: document),
              edgeEntry.sourceFeatureID == bodyFeatureID.description,
              let bodyFeature = document.cadDocument.designGraph.nodes[bodyFeatureID],
              case let .extrude(extrude) = bodyFeature.operation,
              let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
              case .sketch = profileFeature.operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch dimension summary requires an editable generated extrude profile edge."
            )
        }
        guard let sketchSceneNodeID = sketchSceneNodeID(
            for: extrude.profile.featureID,
            document: document
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch dimension summary could not resolve the source sketch scene node for the generated edge."
            )
        }

        let candidates = try sketchEntries.filter {
            guard $0.sourceFeatureID == extrude.profile.featureID.description else {
                return false
            }
            return try matchesGeneratedEdge(edgeEntry, sketchEntity: $0, sketch: profileFeature)
        }
        guard candidates.count == 1,
              let entity = candidates.first,
              let entityUUID = UUID(uuidString: entity.entityID) else {
            if candidates.isEmpty {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Sketch dimension summary could not map the generated edge to an editable source sketch curve."
                )
            }
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch dimension summary found multiple source sketch curves for the generated edge."
            )
        }

        let editTarget = SelectionTarget(
            sceneNodeID: sketchSceneNodeID,
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: extrude.profile.featureID,
                    entityID: SketchEntityID(entityUUID)
                )
            )
        )
        return ResolvedTarget(
            requestedTarget: target,
            editTarget: editTarget,
            entity: entity
        )
    }

    private func bodyFeatureID(
        for target: SelectionTarget,
        document: DesignDocument
    ) -> FeatureID? {
        guard let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .body else {
            return nil
        }
        return sceneNode.reference?.featureID
    }

    private func sketchSceneNodeID(
        for featureID: FeatureID,
        document: DesignDocument
    ) -> SceneNodeID? {
        document.productMetadata.sceneNodes.first { _, node in
            node.reference == .sketch(featureID)
        }?.key
    }

    private func matchesGeneratedEdge(
        _ edge: TopologySummaryResult.Entry,
        sketchEntity: SketchEntitySummaryResult.EntityEntry,
        sketch: FeatureNode
    ) throws -> Bool {
        guard case let .sketch(sourceSketch) = sketch.operation,
              let start = edge.start,
              let end = edge.end else {
            return false
        }
        let coordinateSystem = try SketchPlaneCoordinateSystem(
            plane: sourceSketch.plane,
            tolerance: tolerance
        )
        let startProjection = coordinateSystem.project(point(start))
        let endProjection = coordinateSystem.project(point(end))
        guard nearlyEqual(startProjection.depth, endProjection.depth) else {
            return false
        }

        switch sketchEntity.entityKind {
        case "line":
            return matchesLine(
                sketchEntity,
                start: startProjection.point,
                end: endProjection.point
            )
        case "circle":
            return matchesCircle(
                sketchEntity,
                edge: edge,
                coordinateSystem: coordinateSystem
            )
        case "arc":
            return matchesArc(
                sketchEntity,
                edge: edge,
                coordinateSystem: coordinateSystem,
                start: startProjection.point,
                end: endProjection.point
            )
        default:
            return false
        }
    }

    private func matchesLine(
        _ entity: SketchEntitySummaryResult.EntityEntry,
        start: Point2D,
        end: Point2D
    ) -> Bool {
        guard let entityStart = entity.start,
              let entityEnd = entity.end else {
            return false
        }
        let sourceStart = Point2D(x: entityStart.x, y: entityStart.y)
        let sourceEnd = Point2D(x: entityEnd.x, y: entityEnd.y)
        return pointsMatch(start, sourceStart) &&
            pointsMatch(end, sourceEnd) ||
            pointsMatch(start, sourceEnd) &&
            pointsMatch(end, sourceStart)
    }

    private func matchesCircle(
        _ entity: SketchEntitySummaryResult.EntityEntry,
        edge: TopologySummaryResult.Entry,
        coordinateSystem: SketchPlaneCoordinateSystem
    ) -> Bool {
        guard edge.curveKind == "circle",
              let entityCenter = entity.center,
              let entityRadius = entity.radius,
              let edgeCenter = edge.curveCenter,
              let edgeRadius = edge.curveRadius else {
            return false
        }
        let projectedCenter = coordinateSystem.project(point(edgeCenter)).point
        return pointsMatch(
            projectedCenter,
            Point2D(x: entityCenter.x, y: entityCenter.y)
        ) && nearlyEqual(edgeRadius, entityRadius)
    }

    private func matchesArc(
        _ entity: SketchEntitySummaryResult.EntityEntry,
        edge: TopologySummaryResult.Entry,
        coordinateSystem: SketchPlaneCoordinateSystem,
        start: Point2D,
        end: Point2D
    ) -> Bool {
        guard matchesCircle(
            entity,
            edge: edge,
            coordinateSystem: coordinateSystem
        ),
              let entityStart = entity.start,
              let entityEnd = entity.end else {
            return false
        }
        let sourceStart = Point2D(x: entityStart.x, y: entityStart.y)
        let sourceEnd = Point2D(x: entityEnd.x, y: entityEnd.y)
        return pointsMatch(start, sourceStart) &&
            pointsMatch(end, sourceEnd) ||
            pointsMatch(start, sourceEnd) &&
            pointsMatch(end, sourceStart)
    }

    private func point(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func pointsMatch(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        nearlyEqual(lhs.x, rhs.x) && nearlyEqual(lhs.y, rhs.y)
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
