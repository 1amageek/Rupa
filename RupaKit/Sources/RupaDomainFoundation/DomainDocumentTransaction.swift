import Foundation
import RupaCore
import RupaCoreTypes

public struct DomainDocumentTransaction: Codable, Equatable, Sendable {
    public var name: String
    public var sourceCommands: [EditorCommand]
    public var semanticMutations: [SemanticExtensionMutation]
    public var expectedGeneration: DocumentGeneration?
    public var resultPayload: SemanticJSONValue?

    public init(
        name: String,
        sourceCommands: [EditorCommand],
        semanticMutations: [SemanticExtensionMutation],
        expectedGeneration: DocumentGeneration? = nil,
        resultPayload: SemanticJSONValue? = nil
    ) {
        self.name = name
        self.sourceCommands = sourceCommands
        self.semanticMutations = semanticMutations
        self.expectedGeneration = expectedGeneration
        self.resultPayload = resultPayload
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain document transaction names must not be empty."
            )
        }
        guard !sourceCommands.isEmpty || !semanticMutations.isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain document transactions must contain at least one mutation."
            )
        }
        guard !semanticMutations.isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain document transactions must contain a semantic mutation."
            )
        }
        for command in sourceCommands {
            guard command.mutatesDocument else {
                throw DomainRegistryError(
                    code: .invalidRegistration,
                    message: "Domain document transactions may contain only source-mutating editor commands."
                )
            }
        }
        let extensionIDs = semanticMutations.map(\.extensionID)
        guard Set(extensionIDs).count == extensionIDs.count else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain document transactions may mutate each semantic extension at most once."
            )
        }
        if let resultPayload {
            try resultPayload.validate()
        }
    }
}
