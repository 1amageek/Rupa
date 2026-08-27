import Foundation

/// A typed failure produced while validating or executing a Mesh edit plan.
public struct MeshEditError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case emptyPlan
        case invalidStepID
        case duplicateStepID
        case missingOutputReference
        case forwardOutputReference
        case inapplicableOutputRole
        case invalidOperationDomain
        case emptySelection
        case invalidReference
        case nonFiniteValue
        case integerOverflow
        case limitExceeded
        case callerLimitAboveCeiling
        case disconnectedFaceRegion
        case inconsistentFaceOrientation
        case nonManifoldFaceRegion
        case invalidFaceRegion
        case zeroExtrusionOffset
        case topologyAttributeRemappingUnsupported
        case sourceValidation
        case sourceMutation
        case copyBudgetExceeded
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
