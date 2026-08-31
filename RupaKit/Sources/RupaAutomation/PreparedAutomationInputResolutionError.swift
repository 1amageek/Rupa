/// Typed failures from a prepared command builder's input accessor.
public enum PreparedAutomationInputResolutionError: Error, Equatable, Sendable {
    case missing(PreparedAutomationSlotID)
    case kindMismatch(
        slotID: PreparedAutomationSlotID,
        expected: PreparedAutomationIdentityKind,
        actual: PreparedAutomationIdentityKind
    )
}
