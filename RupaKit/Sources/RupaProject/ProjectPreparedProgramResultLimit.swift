/// Request-scoped ceilings checked against a prepared program's staged result.
///
/// Semantic interpretation and wire-size planning belong to the caller. The
/// project authority only measures the execution receipt that it owns before
/// publication.
public struct ProjectPreparedProgramResultLimit: Sendable, Equatable {
    public let maximumDiagnosticRecordCount: UInt64
    public let maximumDiagnosticScalarCount: UInt64
    public let maximumDiagnosticStringUTF8ByteCount: UInt64
    public let maximumTelemetryRecordCount: UInt64
    public let maximumTelemetryScalarCount: UInt64
    public let maximumTelemetryStringUTF8ByteCount: UInt64

    public init(
        maximumDiagnosticRecordCount: UInt64,
        maximumDiagnosticScalarCount: UInt64,
        maximumDiagnosticStringUTF8ByteCount: UInt64,
        maximumTelemetryRecordCount: UInt64,
        maximumTelemetryScalarCount: UInt64,
        maximumTelemetryStringUTF8ByteCount: UInt64
    ) {
        self.maximumDiagnosticRecordCount = maximumDiagnosticRecordCount
        self.maximumDiagnosticScalarCount = maximumDiagnosticScalarCount
        self.maximumDiagnosticStringUTF8ByteCount = maximumDiagnosticStringUTF8ByteCount
        self.maximumTelemetryRecordCount = maximumTelemetryRecordCount
        self.maximumTelemetryScalarCount = maximumTelemetryScalarCount
        self.maximumTelemetryStringUTF8ByteCount = maximumTelemetryStringUTF8ByteCount
    }
}
