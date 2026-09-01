import RupaCore
import RupaDomainFoundation

/// Projects only authored source identities into semantic compilation.
public struct ProjectSemanticCompilationContextBuilder: Sendable {
    public init() {}

    public func build(
        from document: DesignDocument
    ) -> SemanticCompilationContext {
        var references = Set<SemanticSourceReference>()
        let graph = document.cadDocument.designGraph
        references.reserveCapacity(
            graph.nodes.count
                + document.productMetadata.sceneNodes.count
                + document.productMetadata.componentDefinitions.count
                + document.productMetadata.componentInstances.count
                + document.productMetadata.patternArrays.count
        )

        for featureID in graph.order {
            guard let feature = graph.nodes[featureID] else {
                continue
            }
            references.insert(.feature(featureID))
            for output in feature.outputs {
                switch output.role {
                case .body:
                    references.insert(.sourceBody(featureID: featureID, role: .body))
                case .sheet:
                    references.insert(.sourceBody(featureID: featureID, role: .sheet))
                case .profile, .curve, .path, .guide, .target:
                    break
                }
            }
        }

        references.formUnion(
            document.productMetadata.sceneNodes.keys.map(SemanticSourceReference.sceneNode)
        )
        references.formUnion(
            document.productMetadata.componentDefinitions.keys.map(
                SemanticSourceReference.componentDefinition
            )
        )
        references.formUnion(
            document.productMetadata.componentInstances.keys.map(
                SemanticSourceReference.componentInstance
            )
        )
        references.formUnion(
            document.productMetadata.patternArrays.keys.map(
                SemanticSourceReference.patternArraySource
            )
        )
        return SemanticCompilationContext(existingSourceReferences: references)
    }
}
