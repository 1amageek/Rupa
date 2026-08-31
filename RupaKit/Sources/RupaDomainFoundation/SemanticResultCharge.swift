public struct SemanticResultCharge: Sendable, Equatable, Hashable {
    public let requestedOutputCount: UInt64
    public let diagnosticRecordCount: UInt64
    public let diagnosticScalarCount: UInt64
    public let diagnosticStringUTF8ByteCount: UInt64
    public let telemetryRecordCount: UInt64
    public let telemetryScalarCount: UInt64
    public let telemetryStringUTF8ByteCount: UInt64

    public init(
        requestedOutputCount: UInt64,
        diagnosticRecordCount: UInt64,
        diagnosticScalarCount: UInt64,
        diagnosticStringUTF8ByteCount: UInt64,
        telemetryRecordCount: UInt64,
        telemetryScalarCount: UInt64,
        telemetryStringUTF8ByteCount: UInt64
    ) {
        self.requestedOutputCount = requestedOutputCount
        self.diagnosticRecordCount = diagnosticRecordCount
        self.diagnosticScalarCount = diagnosticScalarCount
        self.diagnosticStringUTF8ByteCount = diagnosticStringUTF8ByteCount
        self.telemetryRecordCount = telemetryRecordCount
        self.telemetryScalarCount = telemetryScalarCount
        self.telemetryStringUTF8ByteCount = telemetryStringUTF8ByteCount
    }
}
