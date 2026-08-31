public enum SemanticProgramLimitMetric: String, Sendable, Equatable, Hashable {
    case decodedValueCount
    case decodedNestingDepth
    case nodeCount
    case edgeCount
    case parameterCount
    case requestedOutputCount
    case localOutputReferenceCount
    case expressionCount
    case expressionDepth
    case expressionWork
    case loweredCommandCount
    case expandedSourceWork
    case preparedInputSlotCount
    case preparedOutputSlotCount
    case resultRequestedOutputCount
    case resultDiagnosticRecordCount
    case resultDiagnosticScalarCount
    case resultDiagnosticStringUTF8ByteCount
    case resultTelemetryRecordCount
    case resultTelemetryScalarCount
    case resultTelemetryStringUTF8ByteCount
}
