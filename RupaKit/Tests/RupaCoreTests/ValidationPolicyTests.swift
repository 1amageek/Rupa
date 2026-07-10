import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func validationPolicyBlocksFailedInconclusiveUnsupportedAndMissingRules() throws {
    let inputIdentity = try validationInputIdentity()
    let findings = [
        validationFinding(id: "passed", outcome: .passed, inputIdentity: inputIdentity),
        validationFinding(id: "failed", outcome: .failed, inputIdentity: inputIdentity),
        validationFinding(id: "inconclusive", outcome: .inconclusive, inputIdentity: inputIdentity),
        validationFinding(
            id: "unsupported",
            outcome: .unsupported,
            severity: .warning,
            inputIdentity: inputIdentity
        ),
    ]
    let policy = ValidationPolicy(
        id: "fixture.required",
        requirements: ["passed", "failed", "inconclusive", "unsupported", "missing"].map {
            ValidationRuleRequirement(ruleID: $0)
        }
    )

    let evaluation = try policy.evaluate(
        findings,
        currentInputIdentity: inputIdentity
    )

    #expect(evaluation.decision == .block)
    #expect(evaluation.blockingRuleIDs == ["failed", "inconclusive", "unsupported"])
    #expect(evaluation.missingRuleIDs == ["missing"])
}

@Test(.timeLimit(.minutes(1)))
func validationPolicyAppliesFidelityAndFreshnessPerRule() throws {
    let currentInput = try validationInputIdentity()
    let staleInput = try validationInputIdentity(
        documentID: currentInput.documentID,
        sourceVersion: "stale"
    )
    let findings = [
        validationFinding(
            id: "exact-required",
            outcome: .passed,
            fidelity: .sampledApproximation,
            inputIdentity: currentInput
        ),
        validationFinding(
            id: "sampled-allowed",
            outcome: .passed,
            fidelity: .sampledApproximation,
            inputIdentity: currentInput
        ),
        validationFinding(
            id: "stale",
            outcome: .passed,
            inputIdentity: staleInput
        ),
    ]
    let policy = ValidationPolicy(
        id: "fixture.per-rule",
        requirements: [
            ValidationRuleRequirement(
                ruleID: "exact-required",
                acceptedFidelities: [.exact, .conservativeEstimate]
            ),
            ValidationRuleRequirement(
                ruleID: "sampled-allowed",
                acceptedFidelities: [.sampledApproximation]
            ),
            ValidationRuleRequirement(ruleID: "stale"),
        ]
    )

    let evaluation = try policy.evaluate(
        findings,
        currentInputIdentity: currentInput
    )

    #expect(evaluation.decision == .block)
    #expect(evaluation.blockingRuleIDs == ["exact-required", "stale"])
    #expect(evaluation.failures.first(where: { $0.ruleID == "exact-required" })?.reasons == [
        .unacceptableFidelity,
    ])
    #expect(evaluation.failures.first(where: { $0.ruleID == "stale" })?.reasons == [
        .staleInput,
    ])
}

@Test(.timeLimit(.minutes(1)))
func validationPolicyAppliesRecordedOverrideOnlyToExactCurrentFindings() throws {
    let inputIdentity = try validationInputIdentity()
    let finding = validationFinding(
        id: "overrideable",
        outcome: .failed,
        inputIdentity: inputIdentity
    )
    let policy = ValidationPolicy(
        id: "fixture.override",
        requirements: [
            ValidationRuleRequirement(
                ruleID: finding.id,
                allowsOverride: true
            ),
        ]
    )
    let overrideID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
    let override = ValidationPolicyOverride(
        id: overrideID,
        policyID: policy.id,
        actorID: "fixture.operator",
        recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
        reason: "Reviewed fixture exception.",
        inputIdentity: inputIdentity,
        findingIdentities: [finding.identity]
    )

    let blocked = try policy.evaluate(
        [finding],
        currentInputIdentity: inputIdentity
    )
    let overridden = try policy.evaluate(
        [finding],
        currentInputIdentity: inputIdentity,
        overrides: [override]
    )
    let staleCurrentInput = try validationInputIdentity(
        documentID: inputIdentity.documentID,
        sourceVersion: "changed"
    )
    let stale = try policy.evaluate(
        [finding],
        currentInputIdentity: staleCurrentInput,
        overrides: [override]
    )

    #expect(blocked.decision == .block)
    #expect(overridden.decision == .override)
    #expect(overridden.overriddenRuleIDs == [finding.id])
    #expect(overridden.appliedOverrideIDs == [overrideID])
    #expect(stale.decision == .block)
    #expect(stale.failures.first?.reasons.contains(.staleInput) == true)
}

@Test(.timeLimit(.minutes(1)))
func validationFindingRoundTripsTypedQuantitySubjectAndInputIdentity() throws {
    let inputIdentity = try validationInputIdentity()
    let measurement = ValidationMeasurement(
        id: "minimumWallThickness",
        value: .lengthMeters(0.0007),
        requirement: ValidationMeasurementRequirement(
            comparison: .atLeast,
            target: .lengthMeters(0.0008),
            tolerance: .lengthMeters(0.00001)
        )
    )
    let finding = ValidationFinding(
        id: "fixture.wallThickness",
        providerID: "fixture.validation",
        providerVersion: "1.0.0",
        outcome: .failed,
        severity: .error,
        fidelity: .sampledApproximation,
        subjects: [.document(inputIdentity.documentID)],
        inputIdentity: inputIdentity,
        diagnosticCode: "fixture.wall-too-thin",
        message: "Wall thickness is below the required minimum.",
        recoveryAction: "Increase the local wall thickness.",
        measurements: [measurement]
    )
    try finding.validate()

    let data = try JSONEncoder().encode(finding)
    let decoded = try JSONDecoder().decode(ValidationFinding.self, from: data)

    #expect(decoded == finding)
    #expect(decoded.measurements.first?.value.dimension == .length)
    #expect(decoded.measurements.first?.value.unit == .meter)
}

private func validationFinding(
    id: String,
    outcome: ValidationOutcome,
    severity: EditorDiagnostic.Severity = .error,
    fidelity: ValidationFidelity = .exact,
    inputIdentity: ValidationInputIdentity
) -> ValidationFinding {
    ValidationFinding(
        id: id,
        providerID: "fixture.validation",
        providerVersion: "1.0.0",
        outcome: outcome,
        severity: severity,
        fidelity: fidelity,
        subjects: [.document(inputIdentity.documentID)],
        inputIdentity: inputIdentity,
        message: id
    )
}

private func validationInputIdentity(
    documentID: DocumentID = DocumentID(),
    sourceVersion: String = "current"
) throws -> ValidationInputIdentity {
    let sourceDependencies = try SourceDependencySetIdentity(
        dependencies: [
            SourceDependencyIdentity(
                subject: .cadDocument(documentID),
                contentFingerprint: .init(
                    algorithm: "fixture-source-v1",
                    value: sourceVersion
                )
            ),
        ]
    )
    let configuration = try ArtifactConfigurationIdentity(
        schemaID: "fixture.validation-configuration",
        schemaVersion: "1.0.0",
        value: .object(["mode": .string("fixture")])
    )
    return try ValidationInputIdentity(
        documentID: documentID,
        sourceDependencies: sourceDependencies,
        configuration: configuration
    )
}
