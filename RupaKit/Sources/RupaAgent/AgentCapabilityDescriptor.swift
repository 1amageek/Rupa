public struct AgentCapabilityDescriptor: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Equatable, Sendable {
        case document
        case parameter
        case component
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
        case surfaceAnalysis
        case surfaceContinuitySummary
        case meshSummary
        case polySplineMeshAnalysis
        case objectDimensionSummary
        case measurement
        case selectionState
        case snapResolution
        case constructionPlaneSummary
        case cadInteractionQualityAssessment
    }

    public enum Target: String, Codable, Equatable, Sendable {
        case document
        case sceneNode
        case profile
        case body
        case face
        case edge
        case vertex
        case region
        case sketchEntity
        case sketchPointHandle
        case sketchControlPoint
        case constructionPlane
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
        failureMode: String
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
    }
}
