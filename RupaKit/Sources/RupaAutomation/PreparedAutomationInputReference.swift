import SwiftCAD
import RupaCore

/// A prepared input either refers to an existing source identity or a prior
/// output slot in the same program.
public enum PreparedAutomationInputReference: Sendable, Equatable, Hashable {
    case existing(PreparedAutomationIdentity)
    case local(PreparedAutomationSlotID)

    /// Evaluated topology identities are intentionally not representable.
    /// This overload provides a typed rejection at an integration boundary
    /// without retaining a BodyID in a prepared value.
    public init(evaluatedBodyID _: BodyID) throws {
        throw PreparedAutomationPlanError.evaluatedTopologyIdentityUnsupported
    }
}
