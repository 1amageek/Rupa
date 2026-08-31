import RupaCore

/// Typed failures that abort prepared execution and must escape the caller's
/// source-group closure.
public enum PreparedAutomationExecutionError: Error, Equatable, Sendable {
    case inactiveSourceCommandGroup
    case inputUnavailable(
        stepIndex: Int,
        slotID: PreparedAutomationSlotID,
        identity: PreparedAutomationIdentity
    )
    case localInputUnavailable(stepIndex: Int, slotID: PreparedAutomationSlotID)
    case inputKindMismatch(
        stepIndex: Int,
        slotID: PreparedAutomationSlotID,
        expected: PreparedAutomationIdentityKind,
        actual: PreparedAutomationIdentityKind
    )
    case sourceCommandRejected(stepIndex: Int, commandName: String)
    case commandBuildFailed(
        stepIndex: Int,
        commandName: String,
        code: EditorError.Code?,
        message: String
    )
    case coreCommandFailed(
        stepIndex: Int,
        commandName: String,
        code: EditorError.Code?,
        message: String
    )
    case generatedIdentityMissing(
        stepIndex: Int,
        selector: PreparedAutomationOutputSelector
    )
    case duplicateGeneratedIdentity(stepIndex: Int, identity: PreparedAutomationIdentity)
    case generatedWorkOverflow(stepIndex: Int)
    case generatedSourceWorkExceeded(
        stepIndex: Int,
        measured: UInt64,
        maximum: UInt64
    )
    case cancelled
    case invalidPlan(PreparedAutomationPlanError)
}
