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
        case read
        case selection
        case persistence
    }

    public enum Access: String, Codable, Equatable, Sendable {
        case agentRequest
        case automationCommand
    }

    public enum Discovery: String, Codable, Equatable, Sendable {
        case sessions
        case parameters
        case sketchEntitySummary
        case sketchDimensionSummary
        case curveAnalysis
        case topologySummary
        case surfaceSourceSummary
        case surfaceAnalysis
        case surfaceFrames
        case surfaceContinuitySummary
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
        case surfaceTrim
        case region
        case sketchEntity
        case sketchPointHandle
        case sketchControlPoint
        case constructionPlane
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

    public let name: String
    public let category: Category
    public let summary: String
    public let access: Access
    public let mutatesDocument: Bool
    public let requiresSession: Bool
    public let requiresExpectedGeneration: Bool
    public let discovery: [Discovery]
    public let targets: [Target]
    public let failureMode: String
    public let optionMatrix: [OptionAxis]

    public init(
        name: String,
        category: Category,
        summary: String,
        access: Access,
        mutatesDocument: Bool,
        requiresSession: Bool = true,
        requiresExpectedGeneration: Bool = true,
        discovery: [Discovery] = [],
        targets: [Target] = [],
        failureMode: String,
        optionMatrix: [OptionAxis] = []
    ) {
        self.name = name
        self.category = category
        self.summary = summary
        self.access = access
        self.mutatesDocument = mutatesDocument
        self.requiresSession = requiresSession
        self.requiresExpectedGeneration = requiresExpectedGeneration
        self.discovery = discovery
        self.targets = targets
        self.failureMode = failureMode
        self.optionMatrix = optionMatrix
    }
}
