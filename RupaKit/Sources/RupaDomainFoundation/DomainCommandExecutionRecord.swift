import RupaAutomation
import RupaCore
import RupaCoreTypes

/// Provider-independent execution data consumed by a domain result projector.
public struct DomainCommandExecutionRecord: Sendable {
    public var message: String?
    public var baseGeneration: DocumentGeneration
    public var generation: DocumentGeneration
    public var proposedGeneration: DocumentGeneration
    public var baseTransactionRevision: DocumentTransactionRevision
    public var transactionRevision: DocumentTransactionRevision
    public var proposedTransactionRevision: DocumentTransactionRevision
    public var didMutate: Bool
    public var wouldMutate: Bool
    public var diagnostics: [EditorDiagnostic]
    public var validationFindings: [ValidationFinding]
    public var validationRegions: [ValidationRegionReference]
    public var automationResults: [AutomationResult]
    public var sourceCommandResults: [CommandExecutionResult]
    public var commandName: String?
    public var payload: SemanticJSONValue?

    public init(
        message: String? = nil,
        baseGeneration: DocumentGeneration,
        generation: DocumentGeneration,
        proposedGeneration: DocumentGeneration,
        baseTransactionRevision: DocumentTransactionRevision,
        transactionRevision: DocumentTransactionRevision,
        proposedTransactionRevision: DocumentTransactionRevision,
        didMutate: Bool,
        wouldMutate: Bool,
        diagnostics: [EditorDiagnostic] = [],
        validationFindings: [ValidationFinding] = [],
        validationRegions: [ValidationRegionReference] = [],
        automationResults: [AutomationResult] = [],
        sourceCommandResults: [CommandExecutionResult] = [],
        commandName: String? = nil,
        payload: SemanticJSONValue? = nil
    ) {
        self.message = message
        self.baseGeneration = baseGeneration
        self.generation = generation
        self.proposedGeneration = proposedGeneration
        self.baseTransactionRevision = baseTransactionRevision
        self.transactionRevision = transactionRevision
        self.proposedTransactionRevision = proposedTransactionRevision
        self.didMutate = didMutate
        self.wouldMutate = wouldMutate
        self.diagnostics = diagnostics
        self.validationFindings = validationFindings
        self.validationRegions = validationRegions
        self.automationResults = automationResults
        self.sourceCommandResults = sourceCommandResults
        self.commandName = commandName
        self.payload = payload
    }
}
