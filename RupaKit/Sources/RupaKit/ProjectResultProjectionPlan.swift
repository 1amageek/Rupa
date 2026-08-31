import RupaAutomation
import RupaDomainFoundation
import RupaProject

/// Immutable result shape accepted before a semantic program can be staged.
public struct ProjectResultProjectionPlan: Sendable {
    public let requestedOutputs: [CompiledSemanticOutputRequest]
    public let compilationTelemetry: SemanticCompilationTelemetry
    public let acceptedCharge: SemanticResultCharge
    public let preparedProgramResultLimit: ProjectPreparedProgramResultLimit
    public let committedFailurePlan: ProjectCommittedFailurePlan

    public init(
        compilation: SemanticCompilationResult,
        budget: ProjectSemanticResultBudget
    ) throws {
        let charge = compilation.resultCharge
        try Self.require(
            charge.requestedOutputCount,
            atMost: budget.maximumRequestedOutputCount,
            metric: "requested output"
        )
        try Self.require(
            charge.diagnosticRecordCount,
            atMost: budget.maximumDiagnosticRecordCount,
            metric: "diagnostic record"
        )
        try Self.require(
            charge.diagnosticScalarCount,
            atMost: budget.maximumDiagnosticScalarCount,
            metric: "diagnostic scalar"
        )
        try Self.require(
            charge.diagnosticStringUTF8ByteCount,
            atMost: budget.maximumDiagnosticStringUTF8ByteCount,
            metric: "diagnostic UTF-8 byte"
        )
        try Self.require(
            charge.telemetryRecordCount,
            atMost: budget.maximumTelemetryRecordCount,
            metric: "telemetry record"
        )
        try Self.require(
            charge.telemetryScalarCount,
            atMost: budget.maximumTelemetryScalarCount,
            metric: "telemetry scalar"
        )
        try Self.require(
            charge.telemetryStringUTF8ByteCount,
            atMost: budget.maximumTelemetryStringUTF8ByteCount,
            metric: "telemetry UTF-8 byte"
        )

        guard charge.requestedOutputCount == UInt64(compilation.requestedOutputs.count) else {
            throw ProjectSemanticProgramError(
                code: .invalidProjectionPlan,
                message: "The compiler result charge does not match its requested output mapping."
            )
        }
        var sources = Set<SemanticOutputReference>()
        var slots = Set<PreparedAutomationSlotID>()
        var bodyLookupCount: UInt64 = 0
        for output in compilation.requestedOutputs {
            guard output.source.kind.isSourceIdentity,
                  sources.insert(output.source).inserted,
                  slots.insert(output.preparedSlot).inserted else {
                throw ProjectSemanticProgramError(
                    code: .invalidProjectionPlan,
                    message: "The compiler requested-output mapping is duplicated or not a source identity."
                )
            }
            if case .sourceBody = output.source.kind {
                bodyLookupCount = try Self.adding(bodyLookupCount, 1, metric: "evaluated body lookup")
            }
        }
        try Self.require(
            bodyLookupCount,
            atMost: budget.maximumEvaluatedBodyLookupCount,
            metric: "evaluated body lookup"
        )

        guard charge.telemetryRecordCount >= 1,
              charge.telemetryScalarCount >= 12 else {
            throw ProjectSemanticProgramError(
                code: .invalidProjectionPlan,
                message: "The semantic result charge omits the compiler telemetry record."
            )
        }

        requestedOutputs = compilation.requestedOutputs
        compilationTelemetry = compilation.telemetry
        acceptedCharge = charge
        preparedProgramResultLimit = ProjectPreparedProgramResultLimit(
            maximumDiagnosticRecordCount: charge.diagnosticRecordCount,
            maximumDiagnosticScalarCount: charge.diagnosticScalarCount,
            maximumDiagnosticStringUTF8ByteCount: charge.diagnosticStringUTF8ByteCount,
            maximumTelemetryRecordCount: charge.telemetryRecordCount - 1,
            maximumTelemetryScalarCount: charge.telemetryScalarCount - 12,
            maximumTelemetryStringUTF8ByteCount: charge.telemetryStringUTF8ByteCount
        )
        committedFailurePlan = ProjectCommittedFailurePlan()
    }

    private static func require(
        _ actual: UInt64,
        atMost maximum: UInt64,
        metric: String
    ) throws {
        guard actual <= maximum else {
            throw ProjectSemanticProgramError(
                code: .resultBudgetExceeded,
                message: "The semantic \(metric) charge \(actual) exceeds the caller budget \(maximum)."
            )
        }
    }

    private static func adding(
        _ lhs: UInt64,
        _ rhs: UInt64,
        metric: String
    ) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw ProjectSemanticProgramError(
                code: .invalidProjectionPlan,
                message: "The semantic \(metric) count overflowed."
            )
        }
        return value
    }
}
