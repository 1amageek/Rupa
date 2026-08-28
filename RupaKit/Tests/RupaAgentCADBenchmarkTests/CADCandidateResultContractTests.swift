import Testing
@testable import RupaAgentCADBenchmark

@Test
func candidateStepResultAllowsPrimaryAliasOfCreatedFeature() throws {
    let result = CADCandidateStepResult(
        stepIndex: 0,
        operation: "createLineSketch",
        status: .published,
        primaryFeatureID: "feature-f",
        createdFeatureIDs: ["feature-f", "feature-g"]
    )

    try result.validate()
}

@Test
func outputRoleBindingsRejectPrimaryAndCreatedAliasAcrossRoles() throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "ANG-001")
    let result = CADCandidateStepResult(
        stepIndex: 0,
        operation: "createLineSketch",
        status: .published,
        primaryFeatureID: "feature-f",
        createdFeatureIDs: ["feature-f", "feature-g"]
    )
    let bindings = CADOutputRoleBindings(bindings: [
        CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
        CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .created(index: 0))
    ])

    expectInvalidBinding {
        try bindings.validate(for: challenge, availableStepResults: [result])
    }
}

@Test
func candidateStepResultRejectsDuplicateCreatedFeatureIDs() throws {
    let result = CADCandidateStepResult(
        stepIndex: 0,
        operation: "createLineSketch",
        status: .published,
        primaryFeatureID: "feature-f",
        createdFeatureIDs: ["feature-f", "feature-f"]
    )

    expectInvalidResult {
        try result.validate()
    }
}

@Test
func outputRoleBindingsRejectCrossStepResolvedFeatureIDReuse() throws {
    let challenge = try CADBenchmarkCatalog().challenge(for: "ANG-001")
    let first = CADCandidateStepResult(
        stepIndex: 0,
        operation: "createLineSketch",
        status: .published,
        primaryFeatureID: "feature-shared"
    )
    let second = CADCandidateStepResult(
        stepIndex: 1,
        operation: "createLineSketch",
        status: .published,
        primaryFeatureID: "feature-shared"
    )
    let bindings = CADOutputRoleBindings(bindings: [
        CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
        CADOutputRoleBinding(role: "second-line", stepIndex: 1, selector: .primary)
    ])

    expectInvalidBinding {
        try bindings.validate(for: challenge, availableStepResults: [first, second])
    }
}

private func expectInvalidBinding(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected an invalid output binding.")
    } catch let error as CADBenchmarkError {
        guard case .invalidBinding = error else {
            Issue.record("Unexpected benchmark error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}

private func expectInvalidResult(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected an invalid candidate result.")
    } catch let error as CADBenchmarkError {
        guard case .invalidInput = error else {
            Issue.record("Unexpected benchmark error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}
