import Foundation
import Testing
@testable import RupaAgentCADBenchmark

@Test
func catalogHasExactlyOneHundredLexicallyOrderedTargetSpecifications() throws {
    let catalog = try CADBenchmarkCatalog()
    try catalog.validate()

    #expect(catalog.challenges.count == 100)
    #expect(catalog.caseIDs == catalog.caseIDs.sorted())
    #expect(Set(catalog.caseIDs).count == 100)

    let counts = Dictionary(uniqueKeysWithValues: catalog.manifest.categoryCounts.map {
        ($0.category, $0.count)
    })
    for category in CADBenchmarkCategory.allCases {
        #expect(counts[category] == category.expectedCount)
    }
    #expect(counts.values.reduce(0, +) == 100)
}

@Test
func publicManifestDigestIsDeterministicAndFrozen() throws {
    let first = try CADBenchmarkCatalog()
    let second = try CADBenchmarkCatalog()

    #expect(first.manifest == second.manifest)
    #expect(first.manifest.digest == "b2a623e301375de1131c6c166582b2680ced3b2970fa7ebf508298c4ca320c85")

    let encoded = try JSONEncoder().encode(first.manifest)
    let encodedText = String(decoding: encoded, as: UTF8.self)
    #expect(encodedText.contains("CADExpectedGeometry") == false)
    #expect(encodedText.contains("oracle") == false)
}

@Test
func internalExpectationAndCapabilityDigestsAreVersionedAndFrozen() throws {
    let contract = try CADInternalCatalogStore.expectationContract()
    try contract.validate()

    #expect(contract.schemaVersion == CADBenchmarkExpectationContract.schemaVersion)
    #expect(contract.expectationVersion == CADBenchmarkExpectationContract.expectationVersion)
    #expect(contract.capabilityClassificationVersion == CADBenchmarkExpectationContract.capabilityClassificationVersion)
    #expect(contract.capabilityBaselineContractVersion == CADBenchmarkExpectationContract.capabilityBaselineContractVersion)
    #expect(contract.tolerancePolicyVersion == CADBenchmarkTolerancePolicy.version)
    #expect(contract.entries.count == 100)
    #expect(contract.expectationDigest == "d24c4ad24217aeabcd9f6cd504bc5b9a11d45fe0ad2b2d9938a25d33f0a8c5d6")
    #expect(contract.capabilityClassificationDigest.count == 64)
    #expect(contract.capabilityBaseline.digest.count == 64)

    var object = try #require(JSONSerialization.jsonObject(
        with: JSONEncoder().encode(contract),
        options: []
    ) as? [String: Any])
    object["capabilityClassificationDigest"] = String(repeating: "0", count: 64)
    let mutated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let decoded = try JSONDecoder().decode(CADBenchmarkExpectationContract.self, from: mutated)
    requireCatalogDrift {
        try decoded.validate()
    }
}

@Test
func candidateProjectionContainsOnlyCandidateVisibleFields() throws {
    let catalog = try CADBenchmarkCatalog()
    let encoder = JSONEncoder()

    for challenge in catalog.challenges {
        let encoded = try encoder.encode(challenge)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["input"] == nil)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("CADExpectedGeometry") == false)
        #expect(text.contains("expectation") == false)
        #expect(text.contains("topology") == false)
        #expect(text.contains("tolerance") == false)
        #expect(text.contains("featureID") == false)
    }
}

@Test
func lin001UsesAnAffinePlaneAnchoredAtLineStart() throws {
    let caseID: CADBenchmarkCaseID = "LIN-001"
    let start = CADPoint3D(x: 10.0, y: -2.0, z: 25.0, unit: .millimeter)
    let end = CADPoint3D(x: 35.0, y: -2.0, z: 25.0, unit: .millimeter)
    let valid = CADLineChallengeInput(
        start: start,
        end: end,
        length: CADLength(value: 25.0, unit: .millimeter),
        plane: .xy
    )
    let frame = valid.plane.frame(anchor: valid.start)
    try frame.validate(caseID: caseID)
    try CADChallengeGeometryValidator.validate(.line(valid), caseID: caseID)
    let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: .standard).modelingTolerance.distance
    #expect(abs(frame.signedNormalDistance(to: end)) <= tolerance)
    #expect(abs(frame.signedNormalDistance(to: CADPoint3D(x: 10.0, y: -2.0, z: 25.0, unit: .millimeter))) <= tolerance)
    #expect(abs(frame.signedNormalDistance(to: CADPoint3D(x: 10.0, y: -2.0, z: 26.0, unit: .millimeter))) > tolerance)

    let offPlane = CADLineChallengeInput(
        start: start,
        end: CADPoint3D(x: 35.0, y: -2.0, z: 26.0, unit: .millimeter),
        length: CADLength(value: sqrt(25.0 * 25.0 + 1.0), unit: .millimeter),
        plane: .xy
    )
    requireInvalidInput {
        try CADChallengeGeometryValidator.validate(.line(offPlane), caseID: caseID)
    }

    let wrongLength = CADLineChallengeInput(
        start: start,
        end: end,
        length: CADLength(value: 24.0, unit: .millimeter),
        plane: .xy
    )
    requireInvalidInput {
        try CADChallengeGeometryValidator.validate(.line(wrongLength), caseID: caseID)
    }
}

@Test
func candidateLineActionIsTheOnlyActiveAutomationPayload() throws {
    let action = CADCandidateAction.automation(.sketch(.line(
        name: "segment",
        plane: .xy,
        start: CADPoint3D(x: 0.0, y: 0.0, z: 0.0),
        end: CADPoint3D(x: 25.0, y: 0.0, z: 0.0)
    )))
    let encoded = try JSONEncoder().encode(action)
    let decoded = try JSONDecoder().decode(CADCandidateAction.self, from: encoded)
    #expect(decoded == action)
}

@Test
func outputRoleSelectorsResolveAgainstPublishedPriorResults() throws {
    let catalog = try CADBenchmarkCatalog()
    let angle = try catalog.challenge(for: "ANG-001")
    let result = CADCandidateStepResult(
        stepIndex: 0,
        operation: "sketch",
        status: .published,
        primaryFeatureID: "feature-primary",
        createdFeatureIDs: ["feature-first", "feature-second"]
    )

    let valid = CADOutputRoleBindings(bindings: [
        CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .created(index: 0)),
        CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .created(index: 1))
    ])
    try valid.validate(for: angle, availableStepResults: [result])

    let primary = CADOutputRoleBindings(bindings: [
        CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
        CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .created(index: 1))
    ])
    try primary.validate(for: angle, availableStepResults: [result])

    requireBindingFailure {
        try CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .created(index: 0)),
            CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .created(index: 0))
        ]).validate(for: angle, availableStepResults: [result])
    }
    requireBindingFailure {
        try CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .created(index: 2)),
            CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .created(index: 1))
        ]).validate(for: angle, availableStepResults: [result])
    }
    requireBindingFailure {
        try CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
            CADOutputRoleBinding(role: "second-line", stepIndex: 0, selector: .created(index: 1))
        ]).validate(for: angle, availableStepResults: [
            CADCandidateStepResult(stepIndex: 0, operation: "sketch", status: .failed, createdFeatureIDs: ["feature-second"])
        ])
    }

    requireResultFailure {
        try CADCandidateStepResult(
            stepIndex: 0,
            operation: "sketch",
            status: .published,
            primaryFeatureID: "feature-first",
            createdFeatureIDs: ["feature-first", "feature-first"]
        ).validate()
    }

    requireBindingFailure {
        try CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "first-line", stepIndex: 0, selector: .primary),
            CADOutputRoleBinding(role: "second-line", stepIndex: 1, selector: .primary)
        ]).validate(for: angle, availableStepResults: [
            CADCandidateStepResult(stepIndex: 0, operation: "sketch", status: .published, primaryFeatureID: "feature-shared"),
            CADCandidateStepResult(stepIndex: 1, operation: "sketch", status: .published, primaryFeatureID: "feature-shared")
        ])
    }
}

@Test
func capabilityAvailabilityBaselineDigestTracksObservedStatus() throws {
    let unavailable = CADCapabilitySnapshot(
        version: "capabilities.observed.v1",
        statuses: [CADCapabilityStatus(
            id: "cad.sketch.line",
            version: "1",
            available: false,
            reasonCode: "not-exposed"
        )]
    )
    let available = CADCapabilitySnapshot(
        version: "capabilities.observed.v1",
        statuses: [CADCapabilityStatus(
            id: "cad.sketch.line",
            version: "1",
            available: true
        )]
    )
    let changedReason = CADCapabilitySnapshot(
        version: "capabilities.observed.v1",
        statuses: [CADCapabilityStatus(
            id: "cad.sketch.line",
            version: "1",
            available: false,
            reasonCode: "temporarily-disabled"
        )]
    )

    let unavailableBaseline = try CADCapabilityAvailabilityBaseline(snapshot: unavailable)
    let availableBaseline = try CADCapabilityAvailabilityBaseline(snapshot: available)
    let changedReasonBaseline = try CADCapabilityAvailabilityBaseline(snapshot: changedReason)
    try unavailableBaseline.validate()
    try availableBaseline.validate()
    try changedReasonBaseline.validate()
    #expect(unavailableBaseline.digest != availableBaseline.digest)
    #expect(unavailableBaseline.digest != changedReasonBaseline.digest)
    #expect(availableBaseline.digest != changedReasonBaseline.digest)
}

@Test
func typedUnsupportedAndBindingFailuresRemainExplicit() throws {
    let catalog = try CADBenchmarkCatalog()
    let sphere = try catalog.challenge(for: "SPH-001")
    let unavailable = CADCapabilitySnapshot(
        version: "capabilities.v1",
        statuses: [CADCapabilityStatus(
            id: sphere.requiredCapability.id,
            version: sphere.requiredCapability.version,
            available: false,
            reasonCode: "structurally-absent"
        )]
    )
    try CADUnsupportedDeclaration(
        capabilityID: sphere.requiredCapability.id,
        capabilityVersion: sphere.requiredCapability.version,
        reason: .analyticSphereUnavailable
    ).validate(for: sphere, capabilities: unavailable)

    requireUnsupportedFailure {
        try CADUnsupportedDeclaration(
            capabilityID: sphere.requiredCapability.id,
            capabilityVersion: sphere.requiredCapability.version,
            reason: .capabilityUnavailable
        ).validate(for: sphere, capabilities: unavailable)
    }
    requireUnsupportedFailure {
        try CADUnsupportedDeclaration(
            capabilityID: sphere.requiredCapability.id,
            capabilityVersion: sphere.requiredCapability.version,
            reason: .analyticSphereUnavailable
        ).validate(for: sphere, capabilities: CADCapabilitySnapshot(
            version: "capabilities.v1",
            statuses: [CADCapabilityStatus(
                id: sphere.requiredCapability.id,
                version: sphere.requiredCapability.version,
                available: true
            )]
        ))
    }
}

@Test
func candidateAndOracleSourcesRemainPhysicallySeparated() throws {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let packageRoot = testDirectory.deletingLastPathComponent().deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/RupaAgentCADBenchmark")
    let candidateRoot = sourceRoot.appendingPathComponent("Candidate")
    let oracleRoot = sourceRoot.appendingPathComponent("Oracle")
    let fileManager = FileManager.default
    let candidateFiles = try fileManager.contentsOfDirectory(at: candidateRoot, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    let oracleFiles = try fileManager.contentsOfDirectory(at: oracleRoot, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }

    #expect(candidateFiles.isEmpty == false)
    #expect(oracleFiles.isEmpty == false)
    for file in candidateFiles {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("CADExpectedGeometry") == false)
        #expect(text.contains("CADCatalogEntry") == false)
        #expect(text.contains("CADInternalCatalogStore") == false)
        #expect(text.contains("CADChallengeInput") == false)
    }
    for file in oracleFiles {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("public ") == false)
    }
}

private func requireInvalidInput(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Invalid geometry must be rejected.")
    } catch let error as CADBenchmarkError {
        guard case .invalidInput = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}

private func requireUnsupportedFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Unsupported declaration mismatch must be rejected.")
    } catch let error as CADBenchmarkError {
        guard case .unsupportedCapabilityMismatch = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}

private func requireBindingFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Invalid output binding must be rejected.")
    } catch let error as CADBenchmarkError {
        switch error {
        case .invalidBinding, .duplicateRole:
            break
        default:
            Issue.record("Unexpected typed error: \(error)")
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}

private func requireResultFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Invalid candidate result must be rejected.")
    } catch let error as CADBenchmarkError {
        guard case .invalidInput = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}

private func requireCatalogDrift(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Digest drift must be rejected.")
    } catch let error as CADBenchmarkError {
        guard case .catalogDrift = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}
