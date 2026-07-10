import RupaCore
import RupaAutomation
import RupaDomainFoundation

public struct AgentCapabilityDescriptor: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Equatable, Sendable {
        case document
        case parameter
        case component
        case pattern
        case sketch
        case solid
        case directEditing
        case sourceCurveEditing
        case domain
        case read
        case selection
        case persistence
    }

    public enum Access: String, Codable, Equatable, Sendable {
        case agentRequest
        case automationCommand
        case domainCapability
    }

    public enum Discovery: String, Codable, Equatable, Sendable {
        case sessions
        case parameters
        case sketchEntitySummary
        case sketchDimensionSummary
        case curveAnalysis
        case topologySummary
        case sweepEvaluationPlan
        case booleanEvaluationPlan
        case surfaceSourceSummary
        case surfaceAnalysis
        case sectionAnalysis
        case surfaceFrames
        case surfaceContinuitySummary
        case surfaceBoundaryContinuityCompatibility
        case meshSummary
        case polySplineMeshAnalysis
        case selectionMeasurement
        case objectDimensionSummary
        case selectionDimensionEvaluation
        case measurement
        case selectionState
        case snapResolution
        case constructionPlaneSummary
        case designDisplaySnapshot
        case patternArraySummary
        case savedViews
        case drawingProjection
        case cadInteractionQualityAssessment
    }

    public enum Target: String, Codable, Equatable, Sendable {
        case document
        case sceneNode
        case componentInstance
        case profile
        case body
        case face
        case edge
        case vertex
        case surface
        case surfaceControlPoint
        case surfaceKnot
        case surfaceSpan
        case surfaceTrim
        case surfaceTrimKnot
        case surfaceTrimSpan
        case region
        case sketchEntity
        case sketchPointHandle
        case sketchControlPoint
        case constructionPlane
        case savedView
    }

    public struct OptionAxis: Codable, Equatable, Sendable {
        public let name: String
        public let supportedValues: [String]
        public let notes: [String]

        public init(
            name: String,
            supportedValues: [String],
            notes: [String] = []
        ) {
            self.name = name
            self.supportedValues = supportedValues
            self.notes = notes
        }
    }

    public struct DomainContract: Codable, Equatable, Sendable {
        public let effect: DomainCapabilityEffect
        public let resultKind: DomainCapabilityResultKind
        public let targetKinds: [DomainCapabilityTargetKind]
        public let knownErrorCodes: [DomainCapabilityErrorCode]
        public let supportsCancellation: Bool
        public let reportsProgress: Bool
        public let determinism: DomainCapabilityDeterminism
        public let resultFidelity: ValidationFidelity?

        public init(
            effect: DomainCapabilityEffect,
            resultKind: DomainCapabilityResultKind,
            targetKinds: [DomainCapabilityTargetKind],
            knownErrorCodes: [DomainCapabilityErrorCode],
            supportsCancellation: Bool,
            reportsProgress: Bool,
            determinism: DomainCapabilityDeterminism,
            resultFidelity: ValidationFidelity?
        ) {
            self.effect = effect
            self.resultKind = resultKind
            self.targetKinds = targetKinds
            self.knownErrorCodes = knownErrorCodes
            self.supportsCancellation = supportsCancellation
            self.reportsProgress = reportsProgress
            self.determinism = determinism
            self.resultFidelity = resultFidelity
        }
    }

    public let name: String
    public let category: Category
    public let summary: String
    public let access: Access
    public let stateEffect: AutomationCommandEffect
    public let requiresSession: Bool
    public let requiresExpectedSourceGeneration: Bool
    public let requiresExpectedWorkspaceRevision: Bool
    public let supportsDryRun: Bool
    public let discovery: [Discovery]
    public let targets: [Target]
    public let failureMode: String
    public let optionMatrix: [OptionAxis]
    public let inputParameters: [DomainCommandParameterDescriptor]
    public let domainContract: DomainContract?

    public init(
        name: String,
        category: Category,
        summary: String,
        access: Access,
        stateEffect: AutomationCommandEffect,
        requiresSession: Bool = true,
        requiresExpectedSourceGeneration: Bool = true,
        requiresExpectedWorkspaceRevision: Bool = false,
        supportsDryRun: Bool = false,
        discovery: [Discovery] = [],
        targets: [Target] = [],
        failureMode: String,
        optionMatrix: [OptionAxis] = [],
        inputParameters: [DomainCommandParameterDescriptor] = [],
        domainContract: DomainContract? = nil
    ) {
        self.name = name
        self.category = category
        self.summary = summary
        self.access = access
        self.stateEffect = stateEffect
        self.requiresSession = requiresSession
        self.requiresExpectedSourceGeneration = requiresExpectedSourceGeneration
        self.requiresExpectedWorkspaceRevision = requiresExpectedWorkspaceRevision
        self.supportsDryRun = supportsDryRun
        self.discovery = discovery
        self.targets = targets
        self.failureMode = failureMode
        self.optionMatrix = optionMatrix
        self.inputParameters = inputParameters
        self.domainContract = domainContract
    }
}
