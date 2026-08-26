import RupaCore
import RupaCoreTypes

public extension DomainDocumentTransaction {
    func proposedGeneration(
        from baseGeneration: DocumentGeneration
    ) throws -> DocumentGeneration {
        var generation = baseGeneration
        for _ in 0..<(sourceCommands.count + 1) {
            generation = try generation.advanced()
        }
        return generation
    }

    func executionEditorCommands(
        namespace: SemanticNamespaceID
    ) -> [EditorCommand] {
        sourceCommands + [
            .applyNamespacedSemanticExtensionMutations(
                namespace: namespace,
                mutations: semanticMutations
            ),
        ]
    }
}
