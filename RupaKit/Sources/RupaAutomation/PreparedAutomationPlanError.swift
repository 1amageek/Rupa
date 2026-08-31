import RupaCore

/// Structural failures found before a prepared program reaches a session.
public enum PreparedAutomationPlanError: Error, Equatable, Sendable {
    case invalidSlotIdentifier(PreparedAutomationSlotID)
    case duplicateInputSlot(stepIndex: Int, slotID: PreparedAutomationSlotID)
    case duplicateOutputSlot(stepIndex: Int, slotID: PreparedAutomationSlotID)
    case duplicateOutputProducer(PreparedAutomationSlotID)
    case duplicateOutputSelector(stepIndex: Int, selector: PreparedAutomationOutputSelector)
    case negativeOutputIndex(stepIndex: Int, selector: PreparedAutomationOutputSelector)
    case missingLocalOutput(stepIndex: Int, slotID: PreparedAutomationSlotID)
    case forwardLocalReference(
        stepIndex: Int,
        slotID: PreparedAutomationSlotID,
        producerStepIndex: Int
    )
    case inputKindMismatch(
        stepIndex: Int,
        slotID: PreparedAutomationSlotID,
        expected: PreparedAutomationIdentityKind,
        actual: PreparedAutomationIdentityKind
    )
    case invalidStepWork(stepIndex: Int)
    case invalidLimit(PreparedAutomationLimitMetric)
    case countOverflow
    case estimateExceedsLimit(
        metric: PreparedAutomationLimitMetric,
        estimated: UInt64,
        maximum: UInt64
    )
    case evaluatedTopologyIdentityUnsupported
}

public enum PreparedAutomationLimitMetric: String, Equatable, Sendable {
    case steps
    case inputSlots
    case outputSlots
    case commands
    case generatedSourceWork
}
