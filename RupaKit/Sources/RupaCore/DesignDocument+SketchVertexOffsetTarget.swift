import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct GeneratedSketchVertexOffsetTarget {
        var featureID: FeatureID
        var target: SelectionTarget
        var handle: SketchEntityPointHandle
    }

    func generatedSketchVertexOffsetTarget(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeneratedSketchVertexOffsetTarget {
        let operationName = "Generated vertex Offset Vertex"
        guard case .vertex(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology vertex target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let bodyFeatureID = resolvedTarget.featureID
        guard let bodyFeature = cadDocument.designGraph.nodes[bodyFeatureID],
              case let .extrude(extrude) = bodyFeature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable extrude source sketch."
            )
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently requires a normal extrude so the generated vertex can be resolved back to its source sketch plane."
            )
        }

        let topology = try TopologySnapshotService().snapshot(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        guard entry.kind == .vertex,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference a vertex on the selected body."
            )
        }
        guard let vertexPoint = entry.start else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated vertex does not expose a resolved point."
            )
        }

        let coordinate = try sketchCoordinate(from: vertexPoint, on: sketch.plane)
        let endpoint = try sketchCurveEndpoint(
            at: (x: coordinate.x, y: coordinate.y),
            in: sketch,
            operationName: operationName
        )
        let sketchSceneNodeID = try sketchSceneNodeID(
            for: extrude.profile.featureID,
            operationName: operationName
        )
        return GeneratedSketchVertexOffsetTarget(
            featureID: extrude.profile.featureID,
            target: SelectionTarget(
                sceneNodeID: sketchSceneNodeID,
                component: .sketchEntity(
                    SelectionComponentID.sketchEntity(
                        featureID: extrude.profile.featureID,
                        entityID: endpoint.entityID
                    )
                )
            ),
            handle: endpoint.handle
        )
    }

    private func sketchCurveEndpoint(
        at point: (x: Double, y: Double),
        in sketch: Sketch,
        operationName: String
    ) throws -> (entityID: SketchEntityID, handle: SketchEntityPointHandle) {
        struct Candidate {
            var entityID: SketchEntityID
            var entity: SketchEntity
            var handle: SketchEntityPointHandle
            var distanceSquared: Double
        }

        let tolerance = 1.0e-8
        let toleranceSquared = tolerance * tolerance
        var candidates: [Candidate] = []

        func appendCandidate(
            entityID: SketchEntityID,
            entity: SketchEntity,
            handle: SketchEntityPointHandle,
            endpoint: (x: Double, y: Double)
        ) {
            let deltaX = point.x - endpoint.x
            let deltaY = point.y - endpoint.y
            let distanceSquared = deltaX * deltaX + deltaY * deltaY
            guard distanceSquared <= toleranceSquared else {
                return
            }
            candidates.append(
                Candidate(
                    entityID: entityID,
                    entity: entity,
                    handle: handle,
                    distanceSquared: distanceSquared
                )
            )
        }

        for (entityID, entity) in sketch.entities {
            switch entity {
            case .line(let line):
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .lineStart,
                    endpoint: try resolvedSketchVertexOffsetPoint(
                        line.start,
                        owner: "\(operationName) source line start"
                    )
                )
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .lineEnd,
                    endpoint: try resolvedSketchVertexOffsetPoint(
                        line.end,
                        owner: "\(operationName) source line end"
                    )
                )
            case .arc(let arc):
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .arcStart,
                    endpoint: try pointOnArc(
                        arc,
                        angle: arc.startAngle,
                        owner: "\(operationName) source arc start"
                    )
                )
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .arcEnd,
                    endpoint: try pointOnArc(
                        arc,
                        angle: arc.endAngle,
                        owner: "\(operationName) source arc end"
                    )
                )
            case .point,
                 .circle,
                 .spline:
                continue
            }
        }

        let orderedCandidates = candidates.sorted { lhs, rhs in
            if abs(lhs.distanceSquared - rhs.distanceSquared) > 1.0e-24 {
                return lhs.distanceSquared < rhs.distanceSquared
            }
            if lhs.entityID.description != rhs.entityID.description {
                return lhs.entityID.description < rhs.entityID.description
            }
            return lhs.handle.rawValue < rhs.handle.rawValue
        }

        var adjacencyError: Error?
        for candidate in orderedCandidates {
            let reference = try sketchPointReference(
                entityID: candidate.entityID,
                entity: candidate.entity,
                handle: candidate.handle,
                operationName: operationName
            )
            guard let endpoint = sketchCurveEndpoint(for: reference),
                  isSupportedOffsetVertexCurveEntity(candidate.entity, endpoint: endpoint) else {
                continue
            }
            do {
                _ = try adjacentSketchCurveEndpoint(
                    to: reference,
                    in: sketch,
                    owner: operationName
                )
                return (entityID: candidate.entityID, handle: candidate.handle)
            } catch {
                adjacencyError = error
            }
        }

        if let adjacencyError {
            throw adjacencyError
        }
        throw EditorError(
            code: .referenceUnresolved,
            message: "\(operationName) could not resolve the generated vertex to a connected source line or arc endpoint."
        )
    }

    private func sketchSceneNodeID(
        for featureID: FeatureID,
        operationName: String
    ) throws -> SceneNodeID {
        guard let sceneNodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.reference == .sketch(featureID)
        })?.key else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) source sketch scene node was not found."
            )
        }
        return sceneNodeID
    }

    private func resolvedSketchVertexOffsetPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }
}
