public struct PatternArraySummaryService: Sendable {
    public init() {}

    public func summarize(
        document: DesignDocument,
        generation: DocumentGeneration,
        dirty: Bool
    ) -> PatternArraySummaryResult {
        let metadata = document.productMetadata
        let summaries = metadata.patternArrays.values
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.id.description < rhs.id.description
                }
                return lhs.name < rhs.name
            }
            .map { source in
                summary(for: source, metadata: metadata)
            }
        return PatternArraySummaryResult(
            generation: generation,
            dirty: dirty,
            patternArrays: summaries
        )
    }

    private func summary(
        for source: PatternArraySource,
        metadata: ProductMetadata
    ) -> PatternArraySummary {
        let definition = metadata.componentDefinitions[source.definitionID]
        let rootSceneNode = metadata.sceneNodes[source.rootSceneNodeID]
        let diagnostics = diagnostics(for: source, metadata: metadata)
        return PatternArraySummary(
            sourceID: source.id,
            name: source.name,
            definitionID: source.definitionID,
            definitionName: definition?.name,
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
            diagnostics: diagnostics
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
        switch outputMode {
        case .componentInstance:
            kind = .sourceOwnedComponentInstances
        case .independentCopy:
            kind = .sourceOwnedIndependentCopies
        }
        return PatternArraySummary.OutputOwnership(
            kind: kind,
            directOutputEditingAllowed: false,
            sourceEditAction: .updatePatternArray,
            detachAction: .explodePatternArray,
            editableAfterDetach: true
        )
    }

    private func diagnostics(
        for source: PatternArraySource,
        metadata: ProductMetadata
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
        if metadata.sceneNodes[source.rootSceneNodeID] == nil {
            diagnostics.append(
                PatternArraySummary.Diagnostic(
                    severity: .error,
                    code: "missingRootSceneNode",
                    message: "Pattern array source references a missing root scene node."
                )
            )
        }
        switch source.outputMode {
        case .componentInstance:
            if source.outputInstanceIDs.isEmpty {
                diagnostics.append(
                    PatternArraySummary.Diagnostic(
                        severity: .error,
                        code: "missingComponentInstanceOutputs",
                        message: "Component-instance pattern array source has no output instances."
                    )
                )
            }
            if !source.outputSceneNodeIDs.isEmpty || !source.outputFeatureIDs.isEmpty {
                diagnostics.append(
                    PatternArraySummary.Diagnostic(
                        severity: .error,
                        code: "mixedComponentInstanceOutputs",
                        message: "Component-instance pattern array source also owns direct scene or feature outputs."
                    )
                )
            }
        case .independentCopy:
            if source.outputSceneNodeIDs.isEmpty {
                diagnostics.append(
                    PatternArraySummary.Diagnostic(
                        severity: .error,
                        code: "missingIndependentCopySceneOutputs",
                        message: "Independent-copy pattern array source has no output scene nodes."
                    )
                )
            }
            if source.outputFeatureIDs.isEmpty {
                diagnostics.append(
                    PatternArraySummary.Diagnostic(
                        severity: .error,
                        code: "missingIndependentCopyFeatureOutputs",
                        message: "Independent-copy pattern array source has no cloned feature outputs."
                    )
                )
            }
            if !source.outputInstanceIDs.isEmpty {
                diagnostics.append(
                    PatternArraySummary.Diagnostic(
                        severity: .error,
                        code: "mixedIndependentCopyOutputs",
                        message: "Independent-copy pattern array source also owns component instance outputs."
                    )
                )
            }
        }
        return diagnostics
    }
}
