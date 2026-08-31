import RupaAutomation

public struct SemanticLoweredOperation: Sendable {
    public let step: PreparedAutomationStep

    public init(step: PreparedAutomationStep) {
        self.step = step
    }
}
