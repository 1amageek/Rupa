/// A typed input consumed by one prepared step.
public struct PreparedAutomationInputSlot: Sendable, Equatable, Hashable {
    public let id: PreparedAutomationSlotID
    public let expectedKind: PreparedAutomationIdentityKind
    public let reference: PreparedAutomationInputReference

    public init(
        id: PreparedAutomationSlotID,
        expectedKind: PreparedAutomationIdentityKind,
        reference: PreparedAutomationInputReference
    ) {
        self.id = id
        self.expectedKind = expectedKind
        self.reference = reference
    }
}
