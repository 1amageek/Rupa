import Foundation
import SwiftCAD

public struct PatternArraySummaryService: Sendable {
    public init() {}

    public func summarize(
        document: DesignDocument,
        generation: DocumentGeneration,
        dirty: Bool
    ) -> PatternArraySummaryResult {
        let metadata = document.productMetadata
        let outputOwnershipIndex = outputOwnershipIndex(for: metadata.patternArrays.values)
        let summaries = metadata.patternArrays.values
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.id.description < rhs.id.description
                }
                return lhs.name < rhs.name
            }
            .map { source in
                summary(
                    for: source,
                    metadata: metadata,
                    cadDocument: document.cadDocument,
                    outputOwnershipIndex: outputOwnershipIndex
                )
            }
        return PatternArraySummaryResult(
            generation: generation,
            dirty: dirty,
            patternArrays: summaries
        )
    }

    private func summary(
        for source: PatternArraySource,
        metadata: ProductMetadata,
        cadDocument: CADDocument,
        outputOwnershipIndex: OutputOwnershipIndex
    ) -> PatternArraySummary {
        let definition = metadata.componentDefinitions[source.definitionID]
        let rootSceneNode = metadata.sceneNodes[source.rootSceneNodeID]
        let independentCopyOutputs = independentCopyOutputs(
            for: source,
            definition: definition,
            metadata: metadata,
            cadDocument: cadDocument
        )
        let diagnostics = diagnostics(
            for: source,
            metadata: metadata,
            cadDocument: cadDocument,
            outputOwnershipIndex: outputOwnershipIndex
        )
        return PatternArraySummary(
            sourceID: source.id,
            name: source.name,
            definitionID: source.definitionID,
            definitionName: definition?.name,
            definitionIdentity: source.definitionIdentity,
            rootSceneNodeID: source.rootSceneNodeID,
            rootSceneNodeName: rootSceneNode?.name,
            distributionKind: distributionKind(for: source.distribution),
            outputMode: source.outputMode,
            outputCount: outputCount(for: source),
            componentInstanceOutputIDs: source.outputInstanceIDs,
            outputSceneNodeIDs: source.outputSceneNodeIDs,
            outputFeatureIDs: source.outputFeatureIDs,
            editableFields: [.name, .definitionID, .distribution, .outputMode],
            lifecycleActions: [.updatePatternArray, .explodePatternArray],
            outputOwnership: outputOwnership(for: source.outputMode),
            independentCopyOutputs: independentCopyOutputs,
            diagnostics: diagnostics
        )
    }

    private struct OutputOwnershipIndex {
        var sourceIDsByOutputInstanceID: [ComponentInstanceID: [PatternArraySourceID]]
        var sourceIDsByOutputSceneNodeID: [SceneNodeID: [PatternArraySourceID]]
        var sourceIDsByOutputFeatureID: [FeatureID: [PatternArraySourceID]]
    }

    private func outputOwnershipIndex(
        for sources: Dictionary<PatternArraySourceID, PatternArraySource>.Values
    ) -> OutputOwnershipIndex {
        var sourceIDsByOutputInstanceID: [ComponentInstanceID: [PatternArraySourceID]] = [:]
        var sourceIDsByOutputSceneNodeID: [SceneNodeID: [PatternArraySourceID]] = [:]
        var sourceIDsByOutputFeatureID: [FeatureID: [PatternArraySourceID]] = [:]
        for source in sources {
            for instanceID in source.outputInstanceIDs {
                sourceIDsByOutputInstanceID[instanceID, default: []].append(source.id)
            }
            for sceneNodeID in source.outputSceneNodeIDs {
                sourceIDsByOutputSceneNodeID[sceneNodeID, default: []].append(source.id)
            }
            for featureID in source.outputFeatureIDs {
                sourceIDsByOutputFeatureID[featureID, default: []].append(source.id)
            }
        }
        return OutputOwnershipIndex(
            sourceIDsByOutputInstanceID: sourceIDsByOutputInstanceID,
            sourceIDsByOutputSceneNodeID: sourceIDsByOutputSceneNodeID,
            sourceIDsByOutputFeatureID: sourceIDsByOutputFeatureID
        )
    }

    private func distributionKind(
        for distribution: PatternArrayDistribution
    ) -> PatternArraySummary.DistributionKind {
        switch distribution {
        case .rectangular:
            .rectangular
        case .radial:
            .radial
        case .curve:
            .curve
        }
    }

    private func outputCount(for source: PatternArraySource) -> Int {
        switch source.outputMode {
        case .componentInstance:
            source.outputInstanceIDs.count
        case .independentCopy:
            source.outputSceneNodeIDs.count
        }
    }

    private func outputOwnership(
        for outputMode: PatternArrayOutputMode
    ) -> PatternArraySummary.OutputOwnership {
        let kind: PatternArraySummary.OutputOwnershipKind
        let directFeatureEditingAllowed: Bool
        switch outputMode {
        case .componentInstance:
            kind = .sourceOwnedComponentInstances
            directFeatureEditingAllowed = false
        case .independentCopy:
            kind = .sourceOwnedIndependentCopies
            directFeatureEditingAllowed = true
        }
        return PatternArraySummary.OutputOwnership(
            kind: kind,
            directOutputEditingAllowed: false,
            directFeatureEditingAllowed: directFeatureEditingAllowed,
            sourceEditAction: .updatePatternArray,
            detachAction: .explodePatternArray,
            editableAfterDetach: true
        )
    }

    private func independentCopyOutputs(
        for source: PatternArraySource,
        definition: ComponentDefinition?,
        metadata: ProductMetadata,
        cadDocument: CADDocument
    ) -> [PatternArraySummary.IndependentCopyOutputStatus] {
        guard source.outputMode == .independentCopy else {
            return []
        }
        let sourceFeatureIDs = definition.flatMap {
            sourceFeatureIDs(
                for: $0,
                metadata: metadata,
                cadDocument: cadDocument
            )
        }
        let sourceFingerprints = sourceFeatureIDs.flatMap {
            featureStructureFingerprints(
                featureIDs: $0,
                cadDocument: cadDocument
            )
        }
        return source.outputSceneNodeIDs.enumerated().map { outputIndex, sceneNodeID in
            let outputFeatureIDs = orderedFeatureIDs(
                dependencyFeatureClosure(
                    from: referencedFeatureIDs(
                        inSceneSubtreeRootedAt: sceneNodeID,
                        metadata: metadata
                    ),
                    cadDocument: cadDocument
                ),
                cadDocument: cadDocument
            )
            let state = independentCopyOutputState(
                sourceFeatureIDs: sourceFeatureIDs,
                sourceFingerprints: sourceFingerprints,
                outputFeatureIDs: outputFeatureIDs,
                cadDocument: cadDocument
            )
            return PatternArraySummary.IndependentCopyOutputStatus(
                outputIndex: outputIndex,
                sceneNodeID: sceneNodeID,
                featureIDs: outputFeatureIDs,
                state: state,
                regenerationPolicy: independentCopyRegenerationPolicy(for: state)
            )
        }
    }

    private func sourceFeatureIDs(
        for definition: ComponentDefinition,
        metadata: ProductMetadata,
        cadDocument: CADDocument
    ) -> [FeatureID]? {
        var referencedFeatureIDs: Set<FeatureID> = []
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            referencedFeatureIDs.formUnion(
                self.referencedFeatureIDs(
                    inSceneSubtreeRootedAt: rootSceneNodeID,
                    metadata: metadata
                )
            )
        }
        guard !referencedFeatureIDs.isEmpty else {
            return nil
        }
        let closureFeatureIDs = dependencyFeatureClosure(
            from: referencedFeatureIDs,
            cadDocument: cadDocument
        )
        let orderedIDs = orderedFeatureIDs(
            closureFeatureIDs,
            cadDocument: cadDocument
        )
        guard orderedIDs.count == closureFeatureIDs.count else {
            return nil
        }
        return orderedIDs
    }

    private func independentCopyOutputState(
        sourceFeatureIDs: [FeatureID]?,
        sourceFingerprints: [PatternArrayFeatureStructureFingerprint]?,
        outputFeatureIDs: [FeatureID],
        cadDocument: CADDocument
    ) -> PatternArraySummary.IndependentCopyOutputState {
        guard let sourceFeatureIDs,
              let sourceFingerprints,
              !sourceFeatureIDs.isEmpty,
              !outputFeatureIDs.isEmpty,
              sourceFeatureIDs.count == outputFeatureIDs.count else {
            return .unresolved
        }
        do {
            let outputFingerprints = try PatternArrayFeatureStructureFingerprintService().fingerprints(
                featureIDs: outputFeatureIDs,
                cadDocument: cadDocument
            )
            return sourceFingerprints == outputFingerprints
                ? .matchesSourceDefinition
                : .divergedFromSourceDefinition
        } catch {
            return .unresolved
        }
    }

    private func featureStructureFingerprints(
        featureIDs: [FeatureID],
        cadDocument: CADDocument
    ) -> [PatternArrayFeatureStructureFingerprint]? {
        do {
            return try PatternArrayFeatureStructureFingerprintService().fingerprints(
                featureIDs: featureIDs,
                cadDocument: cadDocument
            )
        } catch {
            return nil
        }
    }

    private func independentCopyRegenerationPolicy(
        for state: PatternArraySummary.IndependentCopyOutputState
    ) -> PatternArraySummary.IndependentCopyRegenerationPolicy {
        switch state {
        case .matchesSourceDefinition, .divergedFromSourceDefinition:
            .reuseUntilDefinitionIdentityChanges
        case .unresolved:
            .unavailable
        }
    }

    private func diagnostics(
        for source: PatternArraySource,
        metadata: ProductMetadata,
        cadDocument: CADDocument,
        outputOwnershipIndex: OutputOwnershipIndex
    ) -> [PatternArraySummary.Diagnostic] {
        var diagnostics: [PatternArraySummary.Diagnostic] = []
        if metadata.componentDefinitions[source.definitionID] == nil {
            diagnostics.append(
                PatternArraySummary.Diagnostic(
                    severity: .error,
                    code: "missingDefinition",
                    message: "Pattern array source references a missing component definition."
                )
            )
        }
        let rootSceneNode = metadata.sceneNodes[source.rootSceneNodeID]
        if rootSceneNode == nil {
            diagnostics.append(
                PatternArraySummary.Diagnostic(
                    severity: .error,
                    code: "missingRootSceneNode",
                    message: "Pattern array source references a missing root scene node."
                )
            )
        } else if rootSceneNode?.reference != nil || rootSceneNode?.object?.category != .group {
            diagnostics.append(
                PatternArraySummary.Diagnostic(
                    severity: .error,
                    code: "invalidRootSceneNode",
                    message: "Pattern array root scene node must be a group node."
                )
            )
        }

        let expectedTransforms: [Transform3D]?
        do {
            expectedTransforms = try PatternArrayInstancePlanner().transforms(
                for: source.distribution,
                parameters: cadDocument.parameters,
                cadDocument: cadDocument
            )
        } catch {
            expectedTransforms = nil
            diagnostics.append(
                PatternArraySummary.Diagnostic(
                    severity: .error,
                    code: "invalidDistribution",
                    message: error.localizedDescription
                )
            )
        }

        switch source.outputMode {
        case .componentInstance:
            componentInstanceDiagnostics(
                for: source,
                rootSceneNode: rootSceneNode,
                metadata: metadata,
                expectedTransforms: expectedTransforms,
                outputOwnershipIndex: outputOwnershipIndex,
                diagnostics: &diagnostics
            )
        case .independentCopy:
            independentCopyDiagnostics(
                for: source,
                rootSceneNode: rootSceneNode,
                metadata: metadata,
                cadDocument: cadDocument,
                expectedTransforms: expectedTransforms,
                outputOwnershipIndex: outputOwnershipIndex,
                diagnostics: &diagnostics
            )
        }
        return diagnostics
    }

    private func componentInstanceDiagnostics(
        for source: PatternArraySource,
        rootSceneNode: SceneNode?,
        metadata: ProductMetadata,
        expectedTransforms: [Transform3D]?,
        outputOwnershipIndex: OutputOwnershipIndex,
        diagnostics: inout [PatternArraySummary.Diagnostic]
    ) {
        if source.outputInstanceIDs.isEmpty {
            appendDiagnostic(
                code: "missingComponentInstanceOutputs",
                message: "Component-instance pattern array source has no output instances.",
                to: &diagnostics
            )
        }
        if !source.outputSceneNodeIDs.isEmpty || !source.outputFeatureIDs.isEmpty {
            appendDiagnostic(
                code: "mixedComponentInstanceOutputs",
                message: "Component-instance pattern array source also owns direct scene or feature outputs.",
                to: &diagnostics
            )
        }
        if let expectedTransforms,
           expectedTransforms.count != source.outputInstanceIDs.count {
            appendDiagnostic(
                code: "componentInstanceOutputCountMismatch",
                message: "Pattern array output instances must match the source distribution count.",
                to: &diagnostics
            )
        }

        for (index, instanceID) in source.outputInstanceIDs.enumerated() {
            if let ownerIDs = outputOwnershipIndex.sourceIDsByOutputInstanceID[instanceID],
               ownerIDs.count > 1 {
                appendDiagnostic(
                    code: "duplicateOutputInstanceOwnership",
                    message: "Pattern array output component instances must be owned by exactly one pattern source.",
                    to: &diagnostics
                )
            }
            guard let instance = metadata.componentInstances[instanceID] else {
                appendDiagnostic(
                    code: "missingOutputInstance",
                    message: "Pattern array output instances must exist.",
                    to: &diagnostics
                )
                continue
            }
            if instance.definitionID != source.definitionID {
                appendDiagnostic(
                    code: "outputInstanceDefinitionMismatch",
                    message: "Pattern array output instances must use the source component definition.",
                    to: &diagnostics
                )
            }
            if let expectedTransforms,
               index < expectedTransforms.count,
               !transform(instance.localTransform, approximatelyEquals: expectedTransforms[index]) {
                appendDiagnostic(
                    code: "outputInstanceTransformMismatch",
                    message: "Pattern array output instance transforms must match the source distribution.",
                    to: &diagnostics
                )
            }
        }

        guard let rootSceneNode else {
            return
        }
        if rootSceneNode.childIDs.count != source.outputInstanceIDs.count {
            appendDiagnostic(
                code: "componentInstanceOutputSceneNodeCountMismatch",
                message: "Pattern array root scene node must contain exactly its output instance scene nodes.",
                to: &diagnostics
            )
        }
        let outputInstanceIDs = Set(source.outputInstanceIDs)
        var childInstanceIDs: [ComponentInstanceID] = []
        childInstanceIDs.reserveCapacity(rootSceneNode.childIDs.count)
        for childID in rootSceneNode.childIDs {
            guard let childNode = metadata.sceneNodes[childID] else {
                appendDiagnostic(
                    code: "missingOutputSceneNode",
                    message: "Pattern array output scene nodes must exist.",
                    to: &diagnostics
                )
                continue
            }
            guard childNode.reference?.kind == .componentInstance,
                  let componentInstanceID = childNode.reference?.componentInstanceID else {
                appendDiagnostic(
                    code: "invalidOutputSceneNodeReference",
                    message: "Pattern array root scene node children must be output component instance nodes.",
                    to: &diagnostics
                )
                continue
            }
            if !outputInstanceIDs.contains(componentInstanceID) {
                appendDiagnostic(
                    code: "unexpectedOutputSceneNodeInstance",
                    message: "Pattern array root scene node children must reference owned output instances.",
                    to: &diagnostics
                )
            }
            if !transform(childNode.localTransform, approximatelyEquals: .identity) {
                appendDiagnostic(
                    code: "outputSceneNodeTransformNotIdentity",
                    message: "Pattern array output scene node transforms must be identity.",
                    to: &diagnostics
                )
            }
            childInstanceIDs.append(componentInstanceID)
        }
        if Set(childInstanceIDs) != outputInstanceIDs || childInstanceIDs.count != outputInstanceIDs.count {
            appendDiagnostic(
                code: "outputSceneNodeMappingMismatch",
                message: "Pattern array root scene node must map one child to each output instance.",
                to: &diagnostics
            )
        }
    }

    private func independentCopyDiagnostics(
        for source: PatternArraySource,
        rootSceneNode: SceneNode?,
        metadata: ProductMetadata,
        cadDocument: CADDocument,
        expectedTransforms: [Transform3D]?,
        outputOwnershipIndex: OutputOwnershipIndex,
        diagnostics: inout [PatternArraySummary.Diagnostic]
    ) {
        if source.outputSceneNodeIDs.isEmpty {
            appendDiagnostic(
                code: "missingIndependentCopySceneOutputs",
                message: "Independent-copy pattern array source has no output scene nodes.",
                to: &diagnostics
            )
        }
        if source.outputFeatureIDs.isEmpty {
            appendDiagnostic(
                code: "missingIndependentCopyFeatureOutputs",
                message: "Independent-copy pattern array source has no cloned feature outputs.",
                to: &diagnostics
            )
        }
        independentCopyDefinitionIdentityDiagnostics(
            for: source,
            metadata: metadata,
            cadDocument: cadDocument,
            diagnostics: &diagnostics
        )
        if !source.outputInstanceIDs.isEmpty {
            appendDiagnostic(
                code: "mixedIndependentCopyOutputs",
                message: "Independent-copy pattern array source also owns component instance outputs.",
                to: &diagnostics
            )
        }
        if let expectedTransforms,
           expectedTransforms.count != source.outputSceneNodeIDs.count {
            appendDiagnostic(
                code: "independentCopyOutputCountMismatch",
                message: "Independent-copy pattern array output scene nodes must match the source distribution count.",
                to: &diagnostics
            )
        }
        if let rootSceneNode,
           rootSceneNode.childIDs != source.outputSceneNodeIDs {
            appendDiagnostic(
                code: "independentCopyRootChildrenMismatch",
                message: "Independent-copy pattern array root scene node must contain exactly its output scene nodes.",
                to: &diagnostics
            )
        }

        let ownedFeatureIDs = Set(source.outputFeatureIDs)
        var outputReferencedFeatureIDs: Set<FeatureID> = []
        for sceneNodeID in source.outputSceneNodeIDs {
            if let ownerIDs = outputOwnershipIndex.sourceIDsByOutputSceneNodeID[sceneNodeID],
               ownerIDs.count > 1 {
                appendDiagnostic(
                    code: "duplicateOutputSceneNodeOwnership",
                    message: "Independent-copy pattern array output scene nodes must be owned by exactly one pattern source.",
                    to: &diagnostics
                )
            }
        }
        for featureID in source.outputFeatureIDs {
            if let ownerIDs = outputOwnershipIndex.sourceIDsByOutputFeatureID[featureID],
               ownerIDs.count > 1 {
                appendDiagnostic(
                    code: "duplicateOutputFeatureOwnership",
                    message: "Independent-copy pattern array output features must be owned by exactly one pattern source.",
                    to: &diagnostics
                )
            }
            if cadDocument.designGraph.nodes[featureID] == nil {
                appendDiagnostic(
                    code: "missingIndependentCopyFeature",
                    message: "Independent-copy pattern array output features must exist.",
                    to: &diagnostics
                )
            }
        }
        let externalDependentFeatureIDs = externalDependentFeatureIDs(
            of: ownedFeatureIDs,
            cadDocument: cadDocument
        )
        if !externalDependentFeatureIDs.isEmpty {
            let dependentList = externalDependentFeatureIDs
                .prefix(3)
                .map(\.description)
                .joined(separator: ", ")
            diagnostics.append(
                PatternArraySummary.Diagnostic(
                    severity: .warning,
                    code: "independentCopyExternalFeatureDependents",
                    message: "Independent-copy output features have downstream feature dependents; rebuild or output removal requires deleting or detaching those dependents first: \(dependentList)."
                )
            )
        }

        for (index, outputSceneNodeID) in source.outputSceneNodeIDs.enumerated() {
            guard let outputNode = metadata.sceneNodes[outputSceneNodeID] else {
                appendDiagnostic(
                    code: "missingIndependentCopySceneOutput",
                    message: "Independent-copy pattern array output scene nodes must exist.",
                    to: &diagnostics
                )
                continue
            }
            if outputNode.reference != nil || outputNode.object?.category != .group {
                appendDiagnostic(
                    code: "invalidIndependentCopySceneOutput",
                    message: "Independent-copy pattern array outputs must be group scene nodes.",
                    to: &diagnostics
                )
            }
            if let expectedTransforms,
               index < expectedTransforms.count,
               !transform(outputNode.localTransform, approximatelyEquals: expectedTransforms[index]) {
                appendDiagnostic(
                    code: "independentCopyOutputTransformMismatch",
                    message: "Independent-copy pattern array output transforms must match the source distribution.",
                    to: &diagnostics
                )
            }
            let descendantFeatureIDs = referencedFeatureIDs(
                inSceneSubtreeRootedAt: outputSceneNodeID,
                metadata: metadata
            )
            if descendantFeatureIDs.isEmpty {
                appendDiagnostic(
                    code: "missingIndependentCopyOutputFeatureReferences",
                    message: "Independent-copy pattern array output scene nodes must reference generated features.",
                    to: &diagnostics
                )
            } else if !descendantFeatureIDs.isSubset(of: ownedFeatureIDs) {
                appendDiagnostic(
                    code: "unexpectedIndependentCopyOutputFeatureReferences",
                    message: "Independent-copy pattern array output scene nodes must reference only owned cloned features.",
                    to: &diagnostics
                )
            }
            outputReferencedFeatureIDs.formUnion(descendantFeatureIDs)
        }

        if dependencyFeatureClosure(
            from: outputReferencedFeatureIDs,
            cadDocument: cadDocument
        ) != ownedFeatureIDs {
            appendDiagnostic(
                code: "independentCopyFeatureClosureMismatch",
                message: "Independent-copy pattern array output features must exactly match generated output dependencies.",
                to: &diagnostics
            )
        }
    }

    private func independentCopyDefinitionIdentityDiagnostics(
        for source: PatternArraySource,
        metadata: ProductMetadata,
        cadDocument: CADDocument,
        diagnostics: inout [PatternArraySummary.Diagnostic]
    ) {
        guard let definition = metadata.componentDefinitions[source.definitionID] else {
            return
        }
        guard let storedIdentity = source.definitionIdentity else {
            appendDiagnostic(
                code: "missingIndependentCopyDefinitionIdentity",
                message: "Independent-copy pattern array source must record the definition identity used to generate outputs.",
                to: &diagnostics
            )
            return
        }
        do {
            let currentIdentity = try PatternArrayDefinitionIdentityService().identity(
                for: definition,
                metadata: metadata,
                cadDocument: cadDocument
            )
            if storedIdentity != currentIdentity {
                appendDiagnostic(
                    code: "independentCopyDefinitionIdentityMismatch",
                    message: "Independent-copy pattern array outputs were generated from an older component definition identity.",
                    to: &diagnostics
                )
            }
        } catch {
            appendDiagnostic(
                code: "invalidIndependentCopyDefinitionIdentity",
                message: error.localizedDescription,
                to: &diagnostics
            )
        }
    }

    private func appendDiagnostic(
        code: String,
        message: String,
        to diagnostics: inout [PatternArraySummary.Diagnostic]
    ) {
        diagnostics.append(
            PatternArraySummary.Diagnostic(
                severity: .error,
                code: code,
                message: message
            )
        )
    }

    private func dependencyFeatureClosure(
        from seedFeatureIDs: Set<FeatureID>,
        cadDocument: CADDocument
    ) -> Set<FeatureID> {
        var featureIDs = seedFeatureIDs
        var pendingFeatureIDs = Array(seedFeatureIDs)
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                continue
            }
            for input in feature.inputs where featureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }
        return featureIDs
    }

    private func externalDependentFeatureIDs(
        of featureIDs: Set<FeatureID>,
        cadDocument: CADDocument
    ) -> [FeatureID] {
        guard !featureIDs.isEmpty else {
            return []
        }
        return cadDocument.designGraph.order.filter { featureID in
            guard !featureIDs.contains(featureID),
                  let feature = cadDocument.designGraph.nodes[featureID] else {
                return false
            }
            return feature.inputs.contains { featureIDs.contains($0.featureID) }
        }
    }

    private func orderedFeatureIDs(
        _ featureIDs: Set<FeatureID>,
        cadDocument: CADDocument
    ) -> [FeatureID] {
        let orderedFeatureIDs = cadDocument.designGraph.order.filter {
            featureIDs.contains($0)
        }
        let orderedFeatureIDSet = Set(orderedFeatureIDs)
        let missingOrderedFeatureIDs = featureIDs
            .subtracting(orderedFeatureIDSet)
            .sorted { $0.description < $1.description }
        return orderedFeatureIDs + missingOrderedFeatureIDs
    }

    private func referencedFeatureIDs(
        inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
        metadata: ProductMetadata
    ) -> Set<FeatureID> {
        var featureIDs: Set<FeatureID> = []
        collectReferencedFeatureIDs(
            rootSceneNodeID,
            metadata: metadata,
            featureIDs: &featureIDs
        )
        return featureIDs
    }

    private func collectReferencedFeatureIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        featureIDs: inout Set<FeatureID>
    ) {
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        if let featureID = sceneNode.reference?.featureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceFeatureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceProfileFeatureID {
            featureIDs.insert(featureID)
        }
        for childID in sceneNode.childIDs {
            collectReferencedFeatureIDs(
                childID,
                metadata: metadata,
                featureIDs: &featureIDs
            )
        }
    }

    private func transform(
        _ lhs: Transform3D,
        approximatelyEquals rhs: Transform3D
    ) -> Bool {
        let left = lhs.matrix.values
        let right = rhs.matrix.values
        guard left.count == right.count else {
            return false
        }
        for index in left.indices {
            guard abs(left[index] - right[index]) <= 1.0e-9 else {
                return false
            }
        }
        return true
    }
}
