import RupaDomainFoundation

/// Runtime-owned bounded policy for semantic CAD compilation.
public enum ProjectAgentSemanticProgramLimits {
    /// Covers the fixed 100-case CAD workload while retaining hard ceilings
    /// for every decoded, lowered, and projected resource dimension.
    public static let standard = SemanticProgramLimitPolicy(
        maximumDecodedValueCount: 4_096,
        maximumDecodedNestingDepth: 32,
        maximumNodeCount: 32,
        maximumEdgeCount: 64,
        maximumParameterCount: 32,
        maximumRequestedOutputCount: 128,
        maximumLocalOutputReferenceCount: 64,
        maximumExpressionCount: 64,
        maximumExpressionDepth: 16,
        maximumExpressionWork: 512,
        maximumLoweredCommandCount: 32,
        maximumExpandedSourceWork: 512,
        maximumPreparedInputSlotCount: 128,
        maximumPreparedOutputSlotCount: 128,
        resultLimits: SemanticResultLimits(
            maximumRequestedOutputCount: 128,
            maximumDiagnosticRecordCount: 128,
            maximumDiagnosticScalarCount: 512,
            maximumDiagnosticStringUTF8ByteCount: 16_384,
            maximumTelemetryRecordCount: 256,
            maximumTelemetryScalarCount: 2_048,
            maximumTelemetryStringUTF8ByteCount: 16_384
        )
    )
}
