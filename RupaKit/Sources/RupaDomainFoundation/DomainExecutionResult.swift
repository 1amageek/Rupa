import RupaAutomation
import RupaCore
import RupaCoreTypes

public struct DomainExecutionResult: Codable, Equatable, Sendable {
    public var capabilityID: DomainCapabilityID
    public var namespace: SemanticNamespaceID
    public var message: String
    public var baseGeneration: DocumentGeneration
    public var generation: DocumentGeneration
    public var proposedGeneration: DocumentGeneration
    public var didMutate: Bool
    public var wouldMutate: Bool
    public var dryRun: Bool
    public var diagnostics: [EditorDiagnostic]
    public var validationFindings: [ValidationFinding]
    public var validationRegions: [ValidationRegionReference]
    public var automationResults: [AutomationResult]
    public var sourceCommandResults: [CommandExecutionResult]
    public var commandName: String?
    public var payload: SemanticJSONValue?

    public init(
        capabilityID: DomainCapabilityID,
        namespace: SemanticNamespaceID,
        message: String,
        baseGeneration: DocumentGeneration,
        generation: DocumentGeneration,
        proposedGeneration: DocumentGeneration,
        didMutate: Bool,
        wouldMutate: Bool,
        dryRun: Bool,
        diagnostics: [EditorDiagnostic] = [],
        validationFindings: [ValidationFinding] = [],
        validationRegions: [ValidationRegionReference] = [],
        automationResults: [AutomationResult] = [],
        sourceCommandResults: [CommandExecutionResult] = [],
        commandName: String? = nil,
        payload: SemanticJSONValue? = nil
    ) {
        self.capabilityID = capabilityID
        self.namespace = namespace
        self.message = message
        self.baseGeneration = baseGeneration
        self.generation = generation
        self.proposedGeneration = proposedGeneration
        self.didMutate = didMutate
        self.wouldMutate = wouldMutate
        self.dryRun = dryRun
        self.diagnostics = diagnostics
        self.validationFindings = validationFindings
        self.validationRegions = validationRegions
        self.automationResults = automationResults
        self.sourceCommandResults = sourceCommandResults
        self.commandName = commandName
        self.payload = payload
    }
}
