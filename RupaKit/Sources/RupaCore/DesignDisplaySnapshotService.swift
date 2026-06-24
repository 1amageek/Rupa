import SwiftCAD

public struct DesignDisplaySnapshotService: Sendable {
    private let sketchService: SketchDisplaySnapshotService
    private let bodyService: BodyDisplaySnapshotService

    public init(
        sketchService: SketchDisplaySnapshotService = SketchDisplaySnapshotService(),
        bodyService: BodyDisplaySnapshotService = BodyDisplaySnapshotService()
    ) {
        self.sketchService = sketchService
        self.bodyService = bodyService
    }

    public func snapshot(document: DesignDocument) -> DesignDisplaySnapshot {
        snapshot(document: document, bodies: [:])
    }

    public func evaluatedSnapshot(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> DesignDisplaySnapshot {
        let bodies = try bodyService.snapshots(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        return snapshot(document: document, bodies: bodies)
    }

    private func snapshot(
        document: DesignDocument,
        bodies: [FeatureID: BodyDisplaySnapshot]
    ) -> DesignDisplaySnapshot {
        let sketches = sketchService.snapshots(document: document)
        var extrudes: [FeatureID: ExtrudeDisplaySnapshot] = [:]
        var straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot] = [:]
        let graph = document.cadDocument.designGraph
        let parameters = document.cadDocument.parameters

        for featureID in graph.order {
            guard let feature = graph.nodes[featureID] else {
                continue
            }
            switch feature.operation {
            case .extrude(let extrude):
                guard let depthMeters = sketchService.resolvedLength(
                    extrude.distance,
                    parameters: parameters
                ) else {
                    continue
                }
                extrudes[featureID] = ExtrudeDisplaySnapshot(
                    featureID: featureID,
                    profileFeatureID: extrude.profile.featureID,
                    depthMeters: depthMeters,
                    direction: extrude.direction
                )
            case .sweep(let sweep):
                guard let snapshot = straightPrismSweepSnapshot(
                    featureID: featureID,
                    sweep: sweep,
                    sketches: sketches,
                    parameters: parameters
                ) else {
                    continue
                }
                straightPrismSweeps[featureID] = snapshot
            default:
                continue
            }
        }

        return DesignDisplaySnapshot(
            sketches: sketches,
            extrudes: extrudes,
            straightPrismSweeps: straightPrismSweeps,
            bodies: bodies,
            patternArrays: patternArraySnapshots(document: document)
        )
    }

    public func result(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        generation: DocumentGeneration,
        dirty: Bool
    ) throws -> DesignDisplaySnapshotResult {
        let snapshot = try evaluatedSnapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: generation
        )
        let order = document.cadDocument.designGraph.order
        return DesignDisplaySnapshotResult(
            generation: generation,
            dirty: dirty,
            sketches: order.compactMap { snapshot.sketches[$0] },
            extrudes: order.compactMap { snapshot.extrudes[$0] },
            straightPrismSweeps: order.compactMap { snapshot.straightPrismSweeps[$0] },
            bodies: order.compactMap { snapshot.bodies[$0] },
            patternArrays: sortedPatternArraySnapshots(snapshot.patternArrays)
        )
    }

    private func patternArraySnapshots(
        document: DesignDocument
    ) -> [PatternArraySourceID: PatternArrayDisplaySnapshot] {
        let metadata = document.productMetadata
        var snapshots: [PatternArraySourceID: PatternArrayDisplaySnapshot] = [:]
        snapshots.reserveCapacity(metadata.patternArrays.count)

        for (sourceID, source) in metadata.patternArrays {
            guard let definition = metadata.componentDefinitions[source.definitionID],
                  let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                continue
            }
            let sceneNodeIDsByInstanceID = componentInstanceSceneNodeIDs(
                rootNode: rootNode,
                metadata: metadata
            )
            let outputs = source.outputInstanceIDs.compactMap { componentInstanceID -> PatternArrayDisplaySnapshot.Output? in
                guard let instance = metadata.componentInstances[componentInstanceID],
                      let sceneNodeID = sceneNodeIDsByInstanceID[componentInstanceID] else {
                    return nil
                }
                return PatternArrayDisplaySnapshot.Output(
                    componentInstanceID: componentInstanceID,
                    sceneNodeID: sceneNodeID,
                    name: instance.name,
                    localTransform: instance.localTransform,
                    isVisible: instance.isVisible,
                    isLocked: instance.isLocked
                )
            }
            snapshots[sourceID] = PatternArrayDisplaySnapshot(
                sourceID: source.id,
                name: source.name,
                definitionID: source.definitionID,
                definitionName: definition.name,
                distribution: source.distribution,
                outputMode: source.outputMode,
                rootSceneNodeID: source.rootSceneNodeID,
                rootSceneNodeName: rootNode.name,
                outputCount: source.outputInstanceIDs.count,
                outputs: outputs
            )
        }
        return snapshots
    }

    private func componentInstanceSceneNodeIDs(
        rootNode: SceneNode,
        metadata: ProductMetadata
    ) -> [ComponentInstanceID: SceneNodeID] {
        var sceneNodeIDsByInstanceID: [ComponentInstanceID: SceneNodeID] = [:]
        sceneNodeIDsByInstanceID.reserveCapacity(rootNode.childIDs.count)
        for childID in rootNode.childIDs {
            guard let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID else {
                continue
            }
            sceneNodeIDsByInstanceID[componentInstanceID] = childID
        }
        return sceneNodeIDsByInstanceID
    }

    private func sortedPatternArraySnapshots(
        _ snapshots: [PatternArraySourceID: PatternArrayDisplaySnapshot]
    ) -> [PatternArrayDisplaySnapshot] {
        snapshots.values.sorted {
            if $0.name == $1.name {
                return $0.sourceID.description < $1.sourceID.description
            }
            return $0.name < $1.name
        }
    }

    private func straightPrismSweepSnapshot(
        featureID: FeatureID,
        sweep: SweepFeature,
        sketches: [FeatureID: SketchDisplaySnapshot],
        parameters: ParameterTable
    ) -> StraightPrismSweepDisplaySnapshot? {
        guard sweep.profiles.count == 1,
              let profile = sweep.profiles.first,
              sweep.guides.isEmpty,
              sweep.options.resultKind == .solid,
              sweep.options.booleanOperation == .newBody,
              sweep.options.keepTools == false,
              let twistAngle = sketchService.resolvedAngle(
                  sweep.options.twistAngle,
                  parameters: parameters
              ),
              twistAngle.isFinite,
              abs(twistAngle) <= 1.0e-9,
              let endScale = sketchService.resolvedScalar(
                  sweep.options.endScale,
                  parameters: parameters
              ),
              endScale.isFinite,
              abs(endScale - 1.0) <= 1.0e-9,
              let distanceFraction = sketchService.resolvedScalar(
                  sweep.options.distanceFraction,
                  parameters: parameters
              ),
              distanceFraction > 0.0,
              distanceFraction <= 1.0,
              let pathVector = sketches[sweep.path.featureID]?.straightOpenPathVector else {
            return nil
        }

        let pathLength = pathVector.length
        guard pathLength > 1.0e-9 else {
            return nil
        }

        return StraightPrismSweepDisplaySnapshot(
            featureID: featureID,
            profileFeatureID: profile.featureID,
            pathFeatureID: sweep.path.featureID,
            depthMeters: pathLength * distanceFraction,
            direction: .vector(Vector3D(
                x: pathVector.x / pathLength,
                y: pathVector.y / pathLength,
                z: pathVector.z / pathLength
            ))
        )
    }
}
