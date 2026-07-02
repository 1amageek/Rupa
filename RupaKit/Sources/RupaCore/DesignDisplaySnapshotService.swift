import SwiftCAD
import RupaCoreTypes

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
        guard hasRenderableBodyOutput(in: document) else {
            return snapshot(document: document, bodies: [:])
        }
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
            componentDefinitions: componentDefinitionSnapshots(document: document),
            componentInstances: componentInstanceSnapshots(document: document),
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
            workspaceScale: WorkspaceScaleSnapshot(ruler: document.ruler),
            viewportGridSettings: document.productMetadata.viewportGridSettings,
            sketches: order.compactMap { snapshot.sketches[$0] },
            extrudes: order.compactMap { snapshot.extrudes[$0] },
            straightPrismSweeps: order.compactMap { snapshot.straightPrismSweeps[$0] },
            bodies: order.compactMap { snapshot.bodies[$0] },
            componentDefinitions: sortedComponentDefinitionSnapshots(snapshot.componentDefinitions),
            componentInstances: sortedComponentInstanceSnapshots(snapshot.componentInstances),
            patternArrays: sortedPatternArraySnapshots(snapshot.patternArrays)
        )
    }

    private func hasRenderableBodyOutput(in document: DesignDocument) -> Bool {
        document.cadDocument.designGraph.order.contains { featureID in
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  !feature.isSuppressed else {
                return false
            }
            return feature.outputs.contains { $0.role == .body }
        }
    }

    private func componentDefinitionSnapshots(
        document: DesignDocument
    ) -> [ComponentDefinitionID: ComponentDefinitionDisplaySnapshot] {
        let metadata = document.productMetadata
        var snapshots: [ComponentDefinitionID: ComponentDefinitionDisplaySnapshot] = [:]
        snapshots.reserveCapacity(metadata.componentDefinitions.count)

        for (_, definition) in metadata.componentDefinitions {
            var accumulator = ComponentDefinitionSnapshotAccumulator()
            var visitedSceneNodeIDs: Set<SceneNodeID> = []
            var visitedDefinitionIDs: Set<ComponentDefinitionID> = [definition.id]
            let rootSceneNodes: [ComponentDefinitionDisplaySnapshot.RootSceneNode] =
                definition.rootSceneNodeIDs.compactMap { rootSceneNodeID in
                    guard let sceneNode = metadata.sceneNodes[rootSceneNodeID] else {
                        return nil
                    }
                    appendComponentDefinitionSceneTree(
                        rootSceneNodeID,
                        metadata: metadata,
                        visitedSceneNodeIDs: &visitedSceneNodeIDs,
                        visitedDefinitionIDs: &visitedDefinitionIDs,
                        accumulator: &accumulator
                    )
                    return ComponentDefinitionDisplaySnapshot.RootSceneNode(
                        sceneNodeID: rootSceneNodeID,
                        name: sceneNode.name,
                        referenceKind: sceneNode.reference?.kind,
                        featureID: sceneNode.reference?.featureID,
                        componentInstanceID: sceneNode.reference?.componentInstanceID,
                        objectCategory: sceneNode.object?.category,
                        isVisible: sceneNode.isVisible,
                        isLocked: sceneNode.isLocked,
                        childCount: sceneNode.childIDs.count
                    )
                }

            snapshots[definition.id] = ComponentDefinitionDisplaySnapshot(
                definitionID: definition.id,
                name: definition.name,
                rootSceneNodes: rootSceneNodes,
                bodySceneNodeIDs: accumulator.bodySceneNodeIDs,
                sketchSceneNodeIDs: accumulator.sketchSceneNodeIDs,
                featureIDs: featureClosure(
                    from: accumulator.featureIDs,
                    cadDocument: document.cadDocument
                ),
                bodyFeatureIDs: accumulator.bodyFeatureIDs,
                sketchFeatureIDs: accumulator.sketchFeatureIDs,
                nestedComponentInstanceIDs: accumulator.nestedComponentInstanceIDs,
                nestedDefinitionIDs: accumulator.nestedDefinitionIDs,
                isRenderable: !accumulator.bodyFeatureIDs.isEmpty || !accumulator.sketchFeatureIDs.isEmpty
            )
        }
        return snapshots
    }

    private func appendComponentDefinitionSceneTree(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>,
        accumulator: inout ComponentDefinitionSnapshotAccumulator
    ) {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }

        appendSceneNodeReference(
            sceneNode.reference,
            sceneNodeID: sceneNodeID,
            metadata: metadata,
            visitedSceneNodeIDs: &visitedSceneNodeIDs,
            visitedDefinitionIDs: &visitedDefinitionIDs,
            accumulator: &accumulator
        )
        for childID in sceneNode.childIDs {
            appendComponentDefinitionSceneTree(
                childID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs,
                accumulator: &accumulator
            )
        }
    }

    private func appendSceneNodeReference(
        _ reference: SceneNodeReference?,
        sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>,
        accumulator: inout ComponentDefinitionSnapshotAccumulator
    ) {
        guard let reference else {
            return
        }
        switch reference.kind {
        case .feature:
            if let featureID = reference.featureID {
                accumulator.appendFeatureID(featureID)
            }
        case .body:
            if let featureID = reference.featureID {
                accumulator.appendBodySceneNodeID(sceneNodeID)
                accumulator.appendBodyFeatureID(featureID)
            }
        case .sketch:
            if let featureID = reference.featureID {
                accumulator.appendSketchSceneNodeID(sceneNodeID)
                accumulator.appendSketchFeatureID(featureID)
            }
        case .componentInstance:
            appendNestedComponentDefinition(
                reference.componentInstanceID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs,
                accumulator: &accumulator
            )
        case .construction:
            break
        }
    }

    private func appendNestedComponentDefinition(
        _ componentInstanceID: ComponentInstanceID?,
        metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>,
        accumulator: inout ComponentDefinitionSnapshotAccumulator
    ) {
        guard let componentInstanceID,
              let instance = metadata.componentInstances[componentInstanceID],
              let definition = metadata.componentDefinitions[instance.definitionID] else {
            return
        }
        accumulator.appendNestedComponentInstanceID(componentInstanceID)
        guard visitedDefinitionIDs.insert(definition.id).inserted else {
            return
        }
        accumulator.appendNestedDefinitionID(definition.id)
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            appendComponentDefinitionSceneTree(
                rootSceneNodeID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs,
                accumulator: &accumulator
            )
        }
    }

    private func featureClosure(
        from seedFeatureIDs: [FeatureID],
        cadDocument: CADDocument
    ) -> [FeatureID] {
        var featureIDs = Set(seedFeatureIDs)
        var pendingFeatureIDs = seedFeatureIDs
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                continue
            }
            for input in feature.inputs where featureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }
        return cadDocument.designGraph.order.filter { featureIDs.contains($0) }
    }

    private func componentInstanceSnapshots(
        document: DesignDocument
    ) -> [ComponentInstanceID: ComponentInstanceDisplaySnapshot] {
        let metadata = document.productMetadata
        let sceneNodeIDsByInstanceID = componentInstanceSceneNodeIDs(metadata: metadata)
        let patternOwnershipByInstanceID = componentInstancePatternOwnership(metadata: metadata)
        var snapshots: [ComponentInstanceID: ComponentInstanceDisplaySnapshot] = [:]
        snapshots.reserveCapacity(metadata.componentInstances.count)

        for (_, instance) in metadata.componentInstances {
            guard let definition = metadata.componentDefinitions[instance.definitionID] else {
                continue
            }
            let sceneNodeIDs = sceneNodeIDsByInstanceID[instance.id] ?? []
            let ownership = patternOwnershipByInstanceID[instance.id] ?? .document
            snapshots[instance.id] = ComponentInstanceDisplaySnapshot(
                instanceID: instance.id,
                name: instance.name,
                definitionID: instance.definitionID,
                definitionName: definition.name,
                sceneNodeIDs: sceneNodeIDs,
                primarySceneNodeID: sceneNodeIDs.first,
                localTransform: instance.localTransform,
                isVisible: instance.isVisible,
                isLocked: instance.isLocked,
                propertyCount: instance.properties.count,
                ownership: ownership
            )
        }
        return snapshots
    }

    private func componentInstanceSceneNodeIDs(
        metadata: ProductMetadata
    ) -> [ComponentInstanceID: [SceneNodeID]] {
        var sceneNodeIDsByInstanceID: [ComponentInstanceID: [SceneNodeID]] = [:]
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        for rootSceneNodeID in metadata.rootSceneNodeIDs {
            appendComponentInstanceSceneNodeIDs(
                rootSceneNodeID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                sceneNodeIDsByInstanceID: &sceneNodeIDsByInstanceID
            )
        }
        return sceneNodeIDsByInstanceID
    }

    private func appendComponentInstanceSceneNodeIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        sceneNodeIDsByInstanceID: inout [ComponentInstanceID: [SceneNodeID]]
    ) {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        if sceneNode.reference?.kind == .componentInstance,
           let componentInstanceID = sceneNode.reference?.componentInstanceID {
            sceneNodeIDsByInstanceID[componentInstanceID, default: []].append(sceneNodeID)
        }
        for childID in sceneNode.childIDs {
            appendComponentInstanceSceneNodeIDs(
                childID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                sceneNodeIDsByInstanceID: &sceneNodeIDsByInstanceID
            )
        }
    }

    private func componentInstancePatternOwnership(
        metadata: ProductMetadata
    ) -> [ComponentInstanceID: ComponentInstanceOwnershipDisplaySnapshot] {
        var ownershipByInstanceID: [ComponentInstanceID: ComponentInstanceOwnershipDisplaySnapshot] = [:]
        for (_, source) in metadata.patternArrays {
            for (index, instanceID) in source.outputInstanceIDs.enumerated() {
                guard ownershipByInstanceID[instanceID] == nil else {
                    continue
                }
                ownershipByInstanceID[instanceID] = .patternArrayOutput(
                    sourceID: source.id,
                    sourceName: source.name,
                    outputIndex: index
                )
            }
        }
        return ownershipByInstanceID
    }

    private func patternArraySnapshots(
        document: DesignDocument
    ) -> [PatternArraySourceID: PatternArrayDisplaySnapshot] {
        let metadata = document.productMetadata
        let summaries = PatternArraySummaryService().summarize(
            document: document,
            generation: DocumentGeneration(),
            dirty: false
        )
        let summariesBySourceID = Dictionary(
            uniqueKeysWithValues: summaries.patternArrays.map { ($0.sourceID, $0) }
        )
        var snapshots: [PatternArraySourceID: PatternArrayDisplaySnapshot] = [:]
        snapshots.reserveCapacity(metadata.patternArrays.count)

        for (sourceID, source) in metadata.patternArrays {
            let definition = metadata.componentDefinitions[source.definitionID]
            let rootNode = metadata.sceneNodes[source.rootSceneNodeID]
            let outputs = patternArrayOutputs(
                source: source,
                rootNode: rootNode,
                metadata: metadata,
                summary: summariesBySourceID[sourceID]
            )
            snapshots[sourceID] = PatternArrayDisplaySnapshot(
                sourceID: source.id,
                name: source.name,
                definitionID: source.definitionID,
                definitionName: definition?.name,
                definitionIdentity: source.definitionIdentity,
                distribution: source.distribution,
                outputMode: source.outputMode,
                rootSceneNodeID: source.rootSceneNodeID,
                rootSceneNodeName: rootNode?.name,
                outputCount: outputCount(for: source),
                outputs: outputs,
                diagnostics: summariesBySourceID[sourceID]?.diagnostics ?? []
            )
        }
        return snapshots
    }

    private func patternArrayOutputs(
        source: PatternArraySource,
        rootNode: SceneNode?,
        metadata: ProductMetadata,
        summary: PatternArraySummary?
    ) -> [PatternArrayDisplaySnapshot.Output] {
        switch source.outputMode {
        case .componentInstance:
            guard let rootNode else {
                return []
            }
            let sceneNodeIDsByInstanceID = componentInstanceSceneNodeIDs(
                rootNode: rootNode,
                metadata: metadata
            )
            return source.outputInstanceIDs.compactMap { componentInstanceID -> PatternArrayDisplaySnapshot.Output? in
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
        case .independentCopy:
            let outputStatusBySceneNodeID = outputStatusBySceneNodeID(summary?.independentCopyOutputs ?? [])
            return source.outputSceneNodeIDs.compactMap { sceneNodeID -> PatternArrayDisplaySnapshot.Output? in
                guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
                    return nil
                }
                let outputStatus = outputStatusBySceneNodeID[sceneNodeID]
                return PatternArrayDisplaySnapshot.Output(
                    sceneNodeID: sceneNodeID,
                    featureIDs: featureIDs(inSceneSubtreeRootedAt: sceneNodeID, metadata: metadata),
                    name: sceneNode.name,
                    localTransform: sceneNode.localTransform,
                    isVisible: sceneNode.isVisible,
                    isLocked: sceneNode.isLocked,
                    independentCopyState: outputStatus?.state,
                    independentCopyRegenerationPolicy: outputStatus?.regenerationPolicy
                )
            }
        }
    }

    private func outputStatusBySceneNodeID(
        _ statuses: [PatternArraySummary.IndependentCopyOutputStatus]
    ) -> [SceneNodeID: PatternArraySummary.IndependentCopyOutputStatus] {
        var statusBySceneNodeID: [SceneNodeID: PatternArraySummary.IndependentCopyOutputStatus] = [:]
        statusBySceneNodeID.reserveCapacity(statuses.count)
        for status in statuses where statusBySceneNodeID[status.sceneNodeID] == nil {
            statusBySceneNodeID[status.sceneNodeID] = status
        }
        return statusBySceneNodeID
    }

    private func outputCount(for source: PatternArraySource) -> Int {
        switch source.outputMode {
        case .componentInstance:
            source.outputInstanceIDs.count
        case .independentCopy:
            source.outputSceneNodeIDs.count
        }
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

    private func featureIDs(
        inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
        metadata: ProductMetadata
    ) -> [FeatureID] {
        var featureIDs: [FeatureID] = []
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        appendFeatureIDs(
            rootSceneNodeID,
            metadata: metadata,
            featureIDs: &featureIDs,
            visitedSceneNodeIDs: &visitedSceneNodeIDs
        )
        return featureIDs
    }

    private func appendFeatureIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        featureIDs: inout [FeatureID],
        visitedSceneNodeIDs: inout Set<SceneNodeID>
    ) {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        if let featureID = sceneNode.reference?.featureID,
           !featureIDs.contains(featureID) {
            featureIDs.append(featureID)
        }
        for childID in sceneNode.childIDs {
            appendFeatureIDs(
                childID,
                metadata: metadata,
                featureIDs: &featureIDs,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            )
        }
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

    private func sortedComponentDefinitionSnapshots(
        _ snapshots: [ComponentDefinitionID: ComponentDefinitionDisplaySnapshot]
    ) -> [ComponentDefinitionDisplaySnapshot] {
        snapshots.values.sorted {
            if $0.name == $1.name {
                return $0.definitionID.description < $1.definitionID.description
            }
            return $0.name < $1.name
        }
    }

    private func sortedComponentInstanceSnapshots(
        _ snapshots: [ComponentInstanceID: ComponentInstanceDisplaySnapshot]
    ) -> [ComponentInstanceDisplaySnapshot] {
        snapshots.values.sorted {
            if $0.name == $1.name {
                return $0.instanceID.description < $1.instanceID.description
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
        guard sweep.sections.count == 1,
              let profile = sweep.sections.first?.profile,
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

private struct ComponentDefinitionSnapshotAccumulator: Sendable {
    private(set) var bodySceneNodeIDs: [SceneNodeID] = []
    private(set) var sketchSceneNodeIDs: [SceneNodeID] = []
    private(set) var featureIDs: [FeatureID] = []
    private(set) var bodyFeatureIDs: [FeatureID] = []
    private(set) var sketchFeatureIDs: [FeatureID] = []
    private(set) var nestedComponentInstanceIDs: [ComponentInstanceID] = []
    private(set) var nestedDefinitionIDs: [ComponentDefinitionID] = []

    private var bodySceneNodeIDSet: Set<SceneNodeID> = []
    private var sketchSceneNodeIDSet: Set<SceneNodeID> = []
    private var featureIDSet: Set<FeatureID> = []
    private var bodyFeatureIDSet: Set<FeatureID> = []
    private var sketchFeatureIDSet: Set<FeatureID> = []
    private var nestedComponentInstanceIDSet: Set<ComponentInstanceID> = []
    private var nestedDefinitionIDSet: Set<ComponentDefinitionID> = []

    mutating func appendBodySceneNodeID(_ sceneNodeID: SceneNodeID) {
        Self.append(sceneNodeID, to: &bodySceneNodeIDs, tracking: &bodySceneNodeIDSet)
    }

    mutating func appendSketchSceneNodeID(_ sceneNodeID: SceneNodeID) {
        Self.append(sceneNodeID, to: &sketchSceneNodeIDs, tracking: &sketchSceneNodeIDSet)
    }

    mutating func appendFeatureID(_ featureID: FeatureID) {
        Self.append(featureID, to: &featureIDs, tracking: &featureIDSet)
    }

    mutating func appendBodyFeatureID(_ featureID: FeatureID) {
        Self.append(featureID, to: &bodyFeatureIDs, tracking: &bodyFeatureIDSet)
        appendFeatureID(featureID)
    }

    mutating func appendSketchFeatureID(_ featureID: FeatureID) {
        Self.append(featureID, to: &sketchFeatureIDs, tracking: &sketchFeatureIDSet)
        appendFeatureID(featureID)
    }

    mutating func appendNestedComponentInstanceID(_ componentInstanceID: ComponentInstanceID) {
        Self.append(
            componentInstanceID,
            to: &nestedComponentInstanceIDs,
            tracking: &nestedComponentInstanceIDSet
        )
    }

    mutating func appendNestedDefinitionID(_ definitionID: ComponentDefinitionID) {
        Self.append(definitionID, to: &nestedDefinitionIDs, tracking: &nestedDefinitionIDSet)
    }

    private static func append<T: Hashable>(
        _ value: T,
        to values: inout [T],
        tracking seenValues: inout Set<T>
    ) {
        guard seenValues.insert(value).inserted else {
            return
        }
        values.append(value)
    }
}
