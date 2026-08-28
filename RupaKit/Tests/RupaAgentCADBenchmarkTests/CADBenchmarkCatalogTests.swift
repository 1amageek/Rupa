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
    #expect(first.manifest.schema == "t12.manifest.v2")
    #expect(first.manifest.catalog == "t12.catalog.v4")
    #expect(first.manifest.tolerancePolicy == "t12.tolerance.v1")
    #expect(first.manifest.challengeInputDigest == "7a9e3be7ec08961e9372f2449c8abc642afdb70140c6674f59e2bae3c67d50f8")
    #expect(first.manifest.digest == "be933d060bc7c569cea0b7a266577191c85e397109361af5a1eb6dea70abdf4b")

    let encoded = try JSONEncoder().encode(first.manifest)
    let encodedText = String(decoding: encoded, as: UTF8.self)
    #expect(encodedText.contains("CADExpectedGeometry") == false)
    #expect(encodedText.contains("oracle") == false)

    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let orderedCaseIDs = try #require(object["orderedCaseIDs"] as? [Any])
    #expect(orderedCaseIDs.count == 100)
    #expect(orderedCaseIDs.allSatisfy { $0 is String })
    #expect(orderedCaseIDs.contains { ($0 as? String) == "LIN-001" })
}

@Test
func internalExpectationAndCapabilityDigestsAreVersionedAndFrozen() throws {
    let contract = try CADInternalCatalogStore.expectationContract()
    try contract.validate()

    #expect(contract.schemaVersion == "t12.expectation.v3")
    #expect(contract.expectationVersion == "t12.expectation-contract.v3")
    #expect(contract.capabilityClassificationVersion == "t12.capability-classification.v1")
    #expect(contract.capabilityBaselineContractVersion == "t12.capability-baseline.v1")
    #expect(contract.tolerancePolicyVersion == "t12.tolerance.v1")
    #expect(contract.entries.count == 100)
    #expect(contract.expectationDigest == "a3ce61a5c4503717d7a5d9dbcc8571e27067fdb03f0924e8c67594e4707e3451")
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
func benchmarkCaseIDUsesValidatedSingleValueCodable() throws {
    let valid: CADBenchmarkCaseID = "LIN-001"
    let encoded = try JSONEncoder().encode(valid)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"LIN-001\"")
    #expect(try JSONDecoder().decode(CADBenchmarkCaseID.self, from: encoded) == valid)

    requireDecodingFailure {
        try JSONDecoder().decode(
            CADBenchmarkCaseID.self,
            from: Data(#"{"rawValue":"LIN-001"}"#.utf8)
        )
    }
    requireDecodingFailure {
        try JSONDecoder().decode(
            CADBenchmarkCaseID.self,
            from: Data(#""LIN-999""#.utf8)
        )
    }
    requireEncodingFailure {
        try JSONEncoder().encode(CADBenchmarkCaseID(rawValue: "LIN-999"))
    }
}

@Test
func scalarCaseIDsPropagateThroughNestedCandidateWireValues() throws {
    let catalog = try CADBenchmarkCatalog()
    let challenge = try catalog.challenge(for: "LIN-001")

    let challengeObject = try #require(JSONSerialization.jsonObject(
        with: JSONEncoder().encode(challenge),
        options: []
    ) as? [String: Any])
    #expect(challengeObject["id"] as? String == "LIN-001")
    #expect(!(challengeObject["id"] is [String: Any]))

    let context = CADCandidateContext(
        challenge: challenge,
        capabilities: CADCapabilitySnapshot(
            version: "agent-capabilities.v1",
            statuses: [CADCapabilityStatus(
                id: challenge.requiredCapability.id,
                version: challenge.requiredCapability.version,
                available: true
            )]
        ),
        remainingRounds: challenge.budget.maximumRounds,
        remainingActions: challenge.budget.maximumActions
    )
    let contextObject = try #require(JSONSerialization.jsonObject(
        with: JSONEncoder().encode(context),
        options: []
    ) as? [String: Any])
    let nestedChallenge = try #require(contextObject["challenge"] as? [String: Any])
    #expect(nestedChallenge["id"] as? String == "LIN-001")
    #expect(!(nestedChallenge["id"] is [String: Any]))

    let result = CADCaseResult(id: "LIN-001", category: .line, outcome: .realized)
    let resultObject = try #require(JSONSerialization.jsonObject(
        with: JSONEncoder().encode(result),
        options: []
    ) as? [String: Any])
    #expect(resultObject["id"] as? String == "LIN-001")
    #expect(!(resultObject["id"] is [String: Any]))
}

@Test
func manifestAndExpectationRejectLegacyCaseIDObjectWireShape() throws {
    let catalog = try CADBenchmarkCatalog()
    let manifestText = String(
        decoding: try JSONEncoder().encode(catalog.manifest),
        as: UTF8.self
    )
    let legacyManifest = Data(
        manifestText.replacingOccurrences(
            of: "\"LIN-001\"",
            with: "{\"rawValue\":\"LIN-001\"}",
            options: .literal,
            range: manifestText.startIndex..<manifestText.endIndex
        ).utf8
    )
    requireDecodingFailure {
        try JSONDecoder().decode(CADBenchmarkManifest.self, from: legacyManifest)
    }

    let contract = try CADInternalCatalogStore.expectationContract()
    let contractText = String(
        decoding: try JSONEncoder().encode(contract),
        as: UTF8.self
    )
    let legacyContract = Data(
        contractText.replacingOccurrences(
            of: "\"LIN-001\"",
            with: "{\"rawValue\":\"LIN-001\"}",
            options: .literal,
            range: contractText.startIndex..<contractText.endIndex
        ).utf8
    )
    requireDecodingFailure {
        try JSONDecoder().decode(CADBenchmarkExpectationContract.self, from: legacyContract)
    }
}

@Test
func rectangleInstructionsUseExplicitCenteredPlacement() throws {
    let catalog = try CADBenchmarkCatalog()
    let rectangleChallenges = catalog.challenges.filter { $0.category == .rectangle }
    #expect(rectangleChallenges.count == 12)
    for challenge in rectangleChallenges {
        #expect(challenge.instruction.contains(" centered at "))
        #expect(challenge.instruction.contains(" on the "))
        #expect(challenge.instruction.contains("rectangle"))
        #expect(challenge.instruction.contains("origin") == false)
    }

    for caseID in ["TRN-002", "TRN-007"] {
        let challenge = try catalog.challenge(for: CADBenchmarkCaseID(rawValue: caseID))
        #expect(challenge.instruction.contains("rectangle"))
        #expect(challenge.instruction.contains(" centered at "))
        #expect(challenge.instruction.contains("origin") == false)
    }
}

@Test
func rectanglePrivateInputsEncodeCenterWithoutOrigin() throws {
    let entries = try CADInternalCatalogStore.entries()
    let rectangleEntries = entries.filter { $0.challenge.category == .rectangle }
    #expect(rectangleEntries.count == 12)

    func assertCenterEncoding(_ input: CADRectangleChallengeInput) throws {
        let object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(input),
            options: []
        ) as? [String: Any])
        #expect(object["center"] != nil)
        #expect(object["origin"] == nil)
    }

    for entry in rectangleEntries {
        guard case let .rectangle(input) = entry.input else {
            Issue.record("Rectangle catalog entry must retain rectangle input.")
            continue
        }
        try assertCenterEncoding(input)
    }

    var transformRectangleCount = 0
    for entry in entries {
        guard case let .transform(input) = entry.input,
              case let .rectangle(source) = input.source else {
            continue
        }
        transformRectangleCount += 1
        try assertCenterEncoding(source)
        let sourceObject = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(input.source),
            options: []
        ) as? [String: Any])
        let rectangleObject = try #require(sourceObject["rectangle"] as? [String: Any])
        let encodedInput = try #require(rectangleObject["_0"] as? [String: Any])
        #expect(encodedInput["center"] != nil)
        #expect(encodedInput["origin"] == nil)
    }
    #expect(transformRectangleCount == 2)
}

@Test
func rectangleValidationNamesCenterField() throws {
    let invalid = CADRectangleChallengeInput(
        center: CADPoint3D(x: .nan, y: 0, z: 0, unit: .millimeter),
        width: CADLength(value: 40, unit: .millimeter),
        height: CADLength(value: 20, unit: .millimeter),
        plane: .xy
    )

    do {
        try CADChallengeGeometryValidator.validate(.rectangle(invalid), caseID: "REC-001")
        Issue.record("Non-finite rectangle center must be rejected.")
    } catch let error as CADBenchmarkError {
        guard case let .invalidInput(_, reason) = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
        #expect(reason.contains("rectangle.center"))
    }
}

@Test
func completedLineExpectationDigestsRemainFrozenAfterRectangleCenterMigration() throws {
    let expected: [String: String] = [
        "LIN-001": "41f425437d9547d8a5c894c5c3309dc385c88d4bc8074e3cc6d84abf24ea3ea2",
        "LIN-002": "9ce14293d884fa3c71cee3708e91bd038a3059c7e65e40bacd7e03568caab971",
        "LIN-003": "5bb8fea3dc9e5ac3c86b63de452c28145c33530e1380dc49cc451cb44a14b195",
        "LIN-004": "43a59890ac0b759b9dfdbb63f1c1cd591a4afb8d5ac7f6e1e2449da86ef92ef9",
        "LIN-005": "524389d7b38f230b16e8af4620d768f36fa09bdf4e8495676044689e7aa8798d",
        "LIN-006": "6f87bd449219990276f4a0bf1c28a256c64c6f734517c46e6bae6d47ffbc8051",
        "LIN-007": "eaf2a872053f19dd17a060bdaf693834d44e838a7c79f9b78f30f91405f9a671",
        "LIN-008": "946353bc894ccd97977cdb82d5d63ab2823ddd37974948ff2fbc81a13bd71557",
        "LIN-009": "d6024a3a8de1666d4f017929c2c24ae927e2776f74caf219e393fd4a6467d510",
        "LIN-010": "da18add1cc70d564d16789f4768e57c1febf2d9fb3394ffc1d5620eaf757d478",
        "LIN-011": "541bbde631913cf52fe48c20e8696e60a4ea68b43ccc28e6f127a7f79c27aba3",
        "LIN-012": "e735845452f28ab367878416525596041afc8850c97f97d3d662d59975a730ab",
    ]
    let observed = Dictionary(uniqueKeysWithValues: try CADInternalCatalogStore.entries()
        .filter { $0.challenge.id.rawValue.hasPrefix("LIN-") }
        .map { ($0.challenge.id.rawValue, $0.expectationDigest) })
    #expect(observed == expected)
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
func candidateLineActionRoundTripsThroughThePublicAutomationPayload() throws {
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

private func requireDecodingFailure<Value>(_ operation: () throws -> Value) {
    do {
        _ = try operation()
        Issue.record("Legacy or invalid case ID wire data must be rejected.")
    } catch {
        // Both a non-string JSON value and an invalid validated ID are expected failures.
    }
}

private func requireEncodingFailure<Value>(_ operation: () throws -> Value) {
    do {
        _ = try operation()
        Issue.record("Invalid case ID must not be encoded.")
    } catch let error as CADBenchmarkError {
        guard case .invalidCaseID = error else {
            Issue.record("Unexpected typed error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected untyped error: \(error)")
    }
}
