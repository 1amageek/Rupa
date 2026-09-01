import RupaCoreTypes
import RupaDomainFoundation

/// The wire-safe projection of one registered semantic operation.
///
/// The runtime creates this value from the same registry snapshot used by the
/// compiler. It is descriptive only; it does not grant access or carry a
/// project identity.
public struct AgentSemanticOperationDescriptor: Codable, Equatable, Sendable {
    public enum InvocationForm: String, Codable, Equatable, Sendable {
        case direct
        case program
    }

    public struct Input: Codable, Equatable, Sendable {
        public let id: String
        public let type: SemanticValueType
        public let isRequired: Bool

        public init(id: String, type: SemanticValueType, isRequired: Bool) {
            self.id = id
            self.type = type
            self.isRequired = isRequired
        }
    }

    public struct Output: Codable, Equatable, Sendable {
        public let id: String
        public let type: SemanticValueType
        public let selector: SemanticOutputSelector

        public init(
            id: String,
            type: SemanticValueType,
            selector: SemanticOutputSelector
        ) {
            self.id = id
            self.type = type
            self.selector = selector
        }
    }

    public let version: CapabilityVersion
    public let inputs: [Input]
    public let outputs: [Output]
    public let route: SemanticOperationRoute
    public let effect: SemanticOperationEffect
    public let invocationForms: [InvocationForm]

    public init(
        version: CapabilityVersion,
        inputs: [Input],
        outputs: [Output],
        route: SemanticOperationRoute,
        effect: SemanticOperationEffect,
        invocationForms: [InvocationForm]
    ) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.route = route
        self.effect = effect
        self.invocationForms = invocationForms
    }
}
