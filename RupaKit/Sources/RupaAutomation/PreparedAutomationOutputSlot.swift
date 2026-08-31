/// A declared binding from one Core command result.
public struct PreparedAutomationOutputSlot: Sendable, Equatable, Hashable {
    public let id: PreparedAutomationSlotID
    public let selector: PreparedAutomationOutputSelector

    public init(
        id: PreparedAutomationSlotID,
        selector: PreparedAutomationOutputSelector
    ) {
        self.id = id
        self.selector = selector
    }

    public var kind: PreparedAutomationIdentityKind {
        selector.kind
    }
}
