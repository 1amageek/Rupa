public struct PatternArraySummary: Codable, Equatable, Sendable {
    public enum DistributionKind: String, Codable, Equatable, Sendable {
        case rectangular
        case radial
        case curve
    }

    public enum EditableField: String, Codable, Equatable, Sendable {
        case name
        case definitionID
        case distribution
        case outputMode
    }

    public enum LifecycleAction: String, Codable, Equatable, Sendable {
        case updatePatternArray
        case explodePatternArray
    }

    public enum OutputOwnershipKind: String, Codable, Equatable, Sendable {
        case sourceOwnedComponentInstances
        case sourceOwnedIndependentCopies
    }

    public enum IndependentCopyOutputState: String, Codable, Equatable, Sendable {
        case matchesSourceDefinition
        case divergedFromSourceDefinition
        case unresolved
    }

    public enum IndependentCopyRegenerationPolicy: String, Codable, Equatable, Sendable {
        case reuseUntilDefinitionIdentityChanges
        case unavailable
    }

    public enum DiagnosticSeverity: String, Codable, Equatable, Sendable {
        case warning
        case error
    }

    public struct OutputOwnership: Codable, Equatable, Sendable {
        public var kind: OutputOwnershipKind
        public var directOutputEditingAllowed: Bool
        public var directFeatureEditingAllowed: Bool
        public var sourceEditAction: LifecycleAction
        public var detachAction: LifecycleAction
        public var editableAfterDetach: Bool

        public init(
            kind: OutputOwnershipKind,
            directOutputEditingAllowed: Bool,
            directFeatureEditingAllowed: Bool = false,
            sourceEditAction: LifecycleAction,
            detachAction: LifecycleAction,
            editableAfterDetach: Bool
        ) {
            self.kind = kind
            self.directOutputEditingAllowed = directOutputEditingAllowed
            self.directFeatureEditingAllowed = directFeatureEditingAllowed
            self.sourceEditAction = sourceEditAction
            self.detachAction = detachAction
            self.editableAfterDetach = editableAfterDetach
        }
    }

    public struct Diagnostic: Codable, Equatable, Sendable {
        public var severity: DiagnosticSeverity
        public var code: String
        public var message: String

        public init(
            severity: DiagnosticSeverity,
            code: String,
            message: String
        ) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public struct IndependentCopyOutputStatus: Codable, Equatable, Sendable {
        public var outputIndex: Int
        public var sceneNodeID: SceneNodeID
        public var featureIDs: [FeatureID]
        public var state: IndependentCopyOutputState
        public var regenerationPolicy: IndependentCopyRegenerationPolicy

        public init(
            outputIndex: Int,
            sceneNodeID: SceneNodeID,
            featureIDs: [FeatureID],
            state: IndependentCopyOutputState,
            regenerationPolicy: IndependentCopyRegenerationPolicy
        ) {
            self.outputIndex = outputIndex
            self.sceneNodeID = sceneNodeID
            self.featureIDs = featureIDs
            self.state = state
            self.regenerationPolicy = regenerationPolicy
        }
    }

    public var sourceID: PatternArraySourceID
    public var name: String
    public var definitionID: ComponentDefinitionID
    public var definitionName: String?
    public var rootSceneNodeID: SceneNodeID
    public var rootSceneNodeName: String?
    public var distributionKind: DistributionKind
    public var outputMode: PatternArrayOutputMode
    public var outputCount: Int
    public var componentInstanceOutputIDs: [ComponentInstanceID]
    public var outputSceneNodeIDs: [SceneNodeID]
    public var outputFeatureIDs: [FeatureID]
    public var editableFields: [EditableField]
    public var lifecycleActions: [LifecycleAction]
    public var outputOwnership: OutputOwnership
    public var independentCopyOutputs: [IndependentCopyOutputStatus]
    public var diagnostics: [Diagnostic]

    public init(
        sourceID: PatternArraySourceID,
        name: String,
        definitionID: ComponentDefinitionID,
        definitionName: String?,
        rootSceneNodeID: SceneNodeID,
        rootSceneNodeName: String?,
        distributionKind: DistributionKind,
        outputMode: PatternArrayOutputMode,
        outputCount: Int,
        componentInstanceOutputIDs: [ComponentInstanceID],
        outputSceneNodeIDs: [SceneNodeID],
        outputFeatureIDs: [FeatureID],
        editableFields: [EditableField],
        lifecycleActions: [LifecycleAction],
        outputOwnership: OutputOwnership,
        independentCopyOutputs: [IndependentCopyOutputStatus] = [],
        diagnostics: [Diagnostic]
    ) {
        self.sourceID = sourceID
        self.name = name
        self.definitionID = definitionID
        self.definitionName = definitionName
        self.rootSceneNodeID = rootSceneNodeID
        self.rootSceneNodeName = rootSceneNodeName
        self.distributionKind = distributionKind
        self.outputMode = outputMode
        self.outputCount = outputCount
        self.componentInstanceOutputIDs = componentInstanceOutputIDs
        self.outputSceneNodeIDs = outputSceneNodeIDs
        self.outputFeatureIDs = outputFeatureIDs
        self.editableFields = editableFields
        self.lifecycleActions = lifecycleActions
        self.outputOwnership = outputOwnership
        self.independentCopyOutputs = independentCopyOutputs
        self.diagnostics = diagnostics
    }
}
