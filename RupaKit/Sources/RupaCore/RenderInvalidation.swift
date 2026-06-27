import Foundation
import RupaCoreTypes

public enum RenderInvalidationReason: String, Codable, Equatable, Hashable, Sendable {
    case none
    case evaluated
    case evaluationFailed
}

public struct RenderInvalidation: Codable, Equatable, Hashable, Sendable {
    public var generation: DocumentGeneration?
    public var reason: RenderInvalidationReason

    public init(
        generation: DocumentGeneration? = nil,
        reason: RenderInvalidationReason = .none
    ) {
        self.generation = generation
        self.reason = reason
    }

    public var requiresSceneRebuild: Bool {
        generation != nil && reason != .none
    }
}
