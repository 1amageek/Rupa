public struct SemanticOperationResultEstimate: Sendable, Equatable, Hashable {
    public let diagnosticRecordCount: UInt64
    public let diagnosticScalarCount: UInt64
    public let diagnosticStringUTF8ByteCount: UInt64
    public let telemetryRecordCount: UInt64
    public let telemetryScalarCount: UInt64
    public let telemetryStringUTF8ByteCount: UInt64

    public init(
        diagnosticRecordCount: UInt64,
        diagnosticScalarCount: UInt64,
        diagnosticStringUTF8ByteCount: UInt64,
        telemetryRecordCount: UInt64,
        telemetryScalarCount: UInt64,
        telemetryStringUTF8ByteCount: UInt64
    ) {
        self.diagnosticRecordCount = diagnosticRecordCount
        self.diagnosticScalarCount = diagnosticScalarCount
        self.diagnosticStringUTF8ByteCount = diagnosticStringUTF8ByteCount
        self.telemetryRecordCount = telemetryRecordCount
        self.telemetryScalarCount = telemetryScalarCount
        self.telemetryStringUTF8ByteCount = telemetryStringUTF8ByteCount
    }

    public static let zero = SemanticOperationResultEstimate(
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 0,
        telemetryRecordCount: 0,
        telemetryScalarCount: 0,
        telemetryStringUTF8ByteCount: 0
    )
}
