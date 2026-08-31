/// Caller-supplied ceilings for one semantic program result.
public struct ProjectSemanticResultBudget: Sendable, Equatable {
    public let maximumRequestedOutputCount: UInt64
    public let maximumEvaluatedBodyLookupCount: UInt64
    public let maximumDiagnosticRecordCount: UInt64
    public let maximumDiagnosticScalarCount: UInt64
    public let maximumDiagnosticStringUTF8ByteCount: UInt64
    public let maximumTelemetryRecordCount: UInt64
    public let maximumTelemetryScalarCount: UInt64
    public let maximumTelemetryStringUTF8ByteCount: UInt64

    public init(
        maximumRequestedOutputCount: UInt64,
        maximumEvaluatedBodyLookupCount: UInt64,
        maximumDiagnosticRecordCount: UInt64,
        maximumDiagnosticScalarCount: UInt64,
        maximumDiagnosticStringUTF8ByteCount: UInt64,
        maximumTelemetryRecordCount: UInt64,
        maximumTelemetryScalarCount: UInt64,
        maximumTelemetryStringUTF8ByteCount: UInt64
    ) {
        self.maximumRequestedOutputCount = maximumRequestedOutputCount
        self.maximumEvaluatedBodyLookupCount = maximumEvaluatedBodyLookupCount
        self.maximumDiagnosticRecordCount = maximumDiagnosticRecordCount
        self.maximumDiagnosticScalarCount = maximumDiagnosticScalarCount
        self.maximumDiagnosticStringUTF8ByteCount = maximumDiagnosticStringUTF8ByteCount
        self.maximumTelemetryRecordCount = maximumTelemetryRecordCount
        self.maximumTelemetryScalarCount = maximumTelemetryScalarCount
        self.maximumTelemetryStringUTF8ByteCount = maximumTelemetryStringUTF8ByteCount
    }
}
