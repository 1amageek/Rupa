/// One output slot bound to a generated source identity.
public struct PreparedAutomationOutputBinding: Sendable, Equatable {
    public let slotID: PreparedAutomationSlotID
    public let kind: PreparedAutomationIdentityKind
    public let identity: PreparedAutomationIdentity

    init(
        slotID: PreparedAutomationSlotID,
        kind: PreparedAutomationIdentityKind,
        identity: PreparedAutomationIdentity
    ) {
        self.slotID = slotID
        self.kind = kind
        self.identity = identity
    }
}
