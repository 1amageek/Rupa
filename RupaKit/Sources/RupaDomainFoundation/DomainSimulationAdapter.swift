import RupaCore
import RupaCoreTypes

public struct DomainSimulationRequest: Sendable {
    public var namespace: SemanticNamespaceID
    public var semanticExtensionID: SemanticExtensionID?
    public var payload: SemanticJSONValue
    public var generation: DocumentGeneration?

    public init(
        namespace: SemanticNamespaceID,
        semanticExtensionID: SemanticExtensionID? = nil,
        payload: SemanticJSONValue = .object([:]),
        generation: DocumentGeneration? = nil
    ) {
        self.namespace = namespace
        self.semanticExtensionID = semanticExtensionID
        self.payload = payload
        self.generation = generation
    }
}

public struct DomainSimulationPlan: Codable, Equatable, Sendable {
    public var namespace: SemanticNamespaceID
    public var semanticExtensionID: SemanticExtensionID?
    public var generation: DocumentGeneration?
    public var artifactKind: String
    public var diagnostics: [EditorDiagnostic]

    public init(
        namespace: SemanticNamespaceID,
        semanticExtensionID: SemanticExtensionID? = nil,
        generation: DocumentGeneration? = nil,
        artifactKind: String,
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.namespace = namespace
        self.semanticExtensionID = semanticExtensionID
        self.generation = generation
        self.artifactKind = artifactKind
        self.diagnostics = diagnostics
    }

    public func validate() throws {
        try namespace.validate()
        guard !artifactKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain simulation artifact kinds must not be empty."
            )
        }
    }
}

public protocol DomainSimulationAdapter: Sendable {
    var namespace: SemanticNamespaceID { get }

    func prepareSimulation(_ request: DomainSimulationRequest) throws -> DomainSimulationPlan
}
