import Foundation
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADActivatedCaseExecutorTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorActivatesOnlyReviewedLineRectangleCircleAndAngleCases() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let expected = (1...12).map { String(format: "LIN-%03d", $0) }
            + (1...12).map { String(format: "REC-%03d", $0) }
            + ["CIR-001", "CIR-002", "CIR-003", "CIR-004", "CIR-005", "CIR-006", "CIR-007", "CIR-008", "CIR-009", "CIR-010", "CIR-011", "CIR-012", "ANG-001", "ANG-002", "ANG-003", "ANG-004", "ANG-005", "ANG-006", "ANG-007", "ANG-008", "ANG-009", "ANG-010", "ANG-011", "ANG-012", "ANG-013", "ANG-014", "ANG-015", "ANG-016"]
        #expect(executor.activatedCaseIDs.map(\.rawValue) == expected)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func requestContextMatchesTheLiveHarnessContext() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let caseID: CADBenchmarkCaseID = "LIN-001"
        let requestContext = try executor.context(for: caseID)

        let result = try await executor.evaluate(
            caseID: caseID,
            candidate: ContextCheckingCandidate(expected: requestContext)
        )

        #expect(result.outcome == .realized)

        let rectangleID: CADBenchmarkCaseID = "REC-001"
        let rectangleContext = try executor.context(for: rectangleID)
        let rectangleResult = try await executor.evaluate(
            caseID: rectangleID,
            candidate: RectangleContextCheckingCandidate(expected: rectangleContext)
        )
        #expect(rectangleResult.outcome == .realized)

        let metreRectangleID: CADBenchmarkCaseID = "REC-010"
        let metreRectangleContext = try executor.context(for: metreRectangleID)
        let metreRectangleResult = try await executor.evaluate(
            caseID: metreRectangleID,
            candidate: RectangleContextCheckingCandidate(expected: metreRectangleContext)
        )
        #expect(metreRectangleResult.outcome == .realized)

        let squareRectangleID: CADBenchmarkCaseID = "REC-011"
        let squareRectangleContext = try executor.context(for: squareRectangleID)
        let squareRectangleResult = try await executor.evaluate(
            caseID: squareRectangleID,
            candidate: RectangleContextCheckingCandidate(expected: squareRectangleContext)
        )
        #expect(squareRectangleResult.outcome == .realized)

        let translatedRectangleID: CADBenchmarkCaseID = "REC-012"
        let translatedRectangleContext = try executor.context(for: translatedRectangleID)
        let translatedRectangleResult = try await executor.evaluate(
            caseID: translatedRectangleID,
            candidate: RectangleContextCheckingCandidate(expected: translatedRectangleContext)
        )
        #expect(translatedRectangleResult.outcome == .realized)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func activatedLineAndRectangleCandidatesUseProductionLifecycle() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        let line = try await executor.evaluate(
            caseID: "LIN-001",
            candidate: ReferenceLineCandidate()
        )
        #expect(line.id == "LIN-001")
        #expect(line.category == .line)
        #expect(line.outcome == .realized)
        try line.validate()

        let rectangle = try await executor.evaluate(
            caseID: "REC-001",
            candidate: ReferenceRectangleCandidate()
        )
        #expect(rectangle.id == "REC-001")
        #expect(rectangle.category == .rectangle)
        #expect(rectangle.outcome == .realized)
        try rectangle.validate()

        let metreRectangle = try await executor.evaluate(
            caseID: "REC-010",
            candidate: ReferenceRectangleCandidate()
        )
        #expect(metreRectangle.id == "REC-010")
        #expect(metreRectangle.category == .rectangle)
        #expect(metreRectangle.outcome == .realized)
        try metreRectangle.validate()
        let encoded = try canonicalJSON(metreRectangle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(encoded.contains(forbidden) == false)
        }

        let squareRectangle = try await executor.evaluate(
            caseID: "REC-011",
            candidate: ReferenceRectangleCandidate()
        )
        #expect(squareRectangle.id == "REC-011")
        #expect(squareRectangle.category == .rectangle)
        #expect(squareRectangle.outcome == .realized)
        try squareRectangle.validate()
        let squareEncoded = try canonicalJSON(squareRectangle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(squareEncoded.contains(forbidden) == false)
        }

        let translatedRectangle = try await executor.evaluate(
            caseID: "REC-012",
            candidate: ReferenceRectangleCandidate()
        )
        #expect(translatedRectangle.id == "REC-012")
        #expect(translatedRectangle.category == .rectangle)
        #expect(translatedRectangle.outcome == .realized)
        try translatedRectangle.validate()
        let translatedEncoded = try canonicalJSON(translatedRectangle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(translatedEncoded.contains(forbidden) == false)
        }

        let angle = try await executor.evaluate(
            caseID: "ANG-002",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(angle.id == "ANG-002")
        #expect(angle.category == .angle)
        #expect(angle.outcome == .realized)
        try angle.validate()
        let angleEncoded = try canonicalJSON(angle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(angleEncoded.contains(forbidden) == false)
        }

        let nextAngle = try await executor.evaluate(
            caseID: "ANG-003",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(nextAngle.id == "ANG-003")
        #expect(nextAngle.category == .angle)
        #expect(nextAngle.outcome == .realized)
        try nextAngle.validate()
        let nextAngleEncoded = try canonicalJSON(nextAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(nextAngleEncoded.contains(forbidden) == false)
        }

        let terminalAngle = try await executor.evaluate(
            caseID: "ANG-004",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(terminalAngle.id == "ANG-004")
        #expect(terminalAngle.category == .angle)
        #expect(terminalAngle.outcome == .realized)
        try terminalAngle.validate()
        let terminalAngleEncoded = try canonicalJSON(terminalAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(terminalAngleEncoded.contains(forbidden) == false)
        }

        let activatedAngle = try await executor.evaluate(
            caseID: "ANG-005",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(activatedAngle.id == "ANG-005")
        #expect(activatedAngle.category == .angle)
        #expect(activatedAngle.outcome == .realized)
        try activatedAngle.validate()
        let activatedAngleEncoded = try canonicalJSON(activatedAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(activatedAngleEncoded.contains(forbidden) == false)
        }

        let nextActivatedAngle = try await executor.evaluate(
            caseID: "ANG-006",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(nextActivatedAngle.id == "ANG-006")
        #expect(nextActivatedAngle.category == .angle)
        #expect(nextActivatedAngle.outcome == .realized)
        try nextActivatedAngle.validate()
        let nextActivatedAngleEncoded = try canonicalJSON(nextActivatedAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(nextActivatedAngleEncoded.contains(forbidden) == false)
        }

        let translatedAngle = try await executor.evaluate(
            caseID: "ANG-007",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(translatedAngle.id == "ANG-007")
        #expect(translatedAngle.category == .angle)
        #expect(translatedAngle.outcome == .realized)
        try translatedAngle.validate()
        let translatedAngleEncoded = try canonicalJSON(translatedAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(translatedAngleEncoded.contains(forbidden) == false)
        }

        let originAngle = try await executor.evaluate(
            caseID: "ANG-008",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(originAngle.id == "ANG-008")
        #expect(originAngle.category == .angle)
        #expect(originAngle.outcome == .realized)
        try originAngle.validate()
        let originAngleEncoded = try canonicalJSON(originAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(originAngleEncoded.contains(forbidden) == false)
        }

        let translatedPlacementAngle = try await executor.evaluate(
            caseID: "ANG-009",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(translatedPlacementAngle.id == "ANG-009")
        #expect(translatedPlacementAngle.category == .angle)
        #expect(translatedPlacementAngle.outcome == .realized)
        try translatedPlacementAngle.validate()
        let translatedPlacementAngleEncoded = try canonicalJSON(translatedPlacementAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(translatedPlacementAngleEncoded.contains(forbidden) == false)
        }

        let negativePlacementAngle = try await executor.evaluate(
            caseID: "ANG-010",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(negativePlacementAngle.id == "ANG-010")
        #expect(negativePlacementAngle.category == .angle)
        #expect(negativePlacementAngle.outcome == .realized)
        try negativePlacementAngle.validate()
        let negativePlacementAngleEncoded = try canonicalJSON(negativePlacementAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(negativePlacementAngleEncoded.contains(forbidden) == false)
        }

        let xzAngle = try await executor.evaluate(
            caseID: "ANG-011",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(xzAngle.id == "ANG-011")
        #expect(xzAngle.category == .angle)
        #expect(xzAngle.outcome == .realized)
        try xzAngle.validate()
        let xzAngleEncoded = try canonicalJSON(xzAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(xzAngleEncoded.contains(forbidden) == false)
        }

        let yzAngle = try await executor.evaluate(
            caseID: "ANG-012",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(yzAngle.id == "ANG-012")
        #expect(yzAngle.category == .angle)
        #expect(yzAngle.outcome == .realized)
        try yzAngle.validate()
        let yzAngleEncoded = try canonicalJSON(yzAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(yzAngleEncoded.contains(forbidden) == false)
        }

        let xzRightAngle = try await executor.evaluate(
            caseID: "ANG-013",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(xzRightAngle.id == "ANG-013")
        #expect(xzRightAngle.category == .angle)
        #expect(xzRightAngle.outcome == .realized)
        try xzRightAngle.validate()
        let xzRightAngleEncoded = try canonicalJSON(xzRightAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(xzRightAngleEncoded.contains(forbidden) == false)
        }

        let yzOneHundredTwentyDegreeAngle = try await executor.evaluate(
            caseID: "ANG-014",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(yzOneHundredTwentyDegreeAngle.id == "ANG-014")
        #expect(yzOneHundredTwentyDegreeAngle.category == .angle)
        #expect(yzOneHundredTwentyDegreeAngle.outcome == .realized)
        try yzOneHundredTwentyDegreeAngle.validate()
        let yzOneHundredTwentyDegreeAngleEncoded = try canonicalJSON(yzOneHundredTwentyDegreeAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(yzOneHundredTwentyDegreeAngleEncoded.contains(forbidden) == false)
        }

        let xzOneHundredThirtyFiveDegreeAngle = try await executor.evaluate(
            caseID: "ANG-015",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(xzOneHundredThirtyFiveDegreeAngle.id == "ANG-015")
        #expect(xzOneHundredThirtyFiveDegreeAngle.category == .angle)
        #expect(xzOneHundredThirtyFiveDegreeAngle.outcome == .realized)
        try xzOneHundredThirtyFiveDegreeAngle.validate()
        let xzOneHundredThirtyFiveDegreeAngleEncoded = try canonicalJSON(xzOneHundredThirtyFiveDegreeAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(xzOneHundredThirtyFiveDegreeAngleEncoded.contains(forbidden) == false)
        }

        let yzOneHundredFiftyDegreeAngle = try await executor.evaluate(
            caseID: "ANG-016",
            candidate: CADAngleReferenceCandidate()
        )
        #expect(yzOneHundredFiftyDegreeAngle.id == "ANG-016")
        #expect(yzOneHundredFiftyDegreeAngle.category == .angle)
        #expect(yzOneHundredFiftyDegreeAngle.outcome == .realized)
        try yzOneHundredFiftyDegreeAngle.validate()
        let yzOneHundredFiftyDegreeAngleEncoded = try canonicalJSON(yzOneHundredFiftyDegreeAngle)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(yzOneHundredFiftyDegreeAngleEncoded.contains(forbidden) == false)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongGeometryIsReturnedAsValidatedInvalidSubmission() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        let line = try await executor.evaluate(
            caseID: "LIN-001",
            candidate: WrongLineCandidate()
        )
        #expect(line.outcome == .invalidSubmission)
        try line.validate()
        let encoded = try canonicalJSON(line)
        for forbidden in ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace"] {
            #expect(encoded.contains(forbidden) == false)
        }

        let rectangle = try await executor.evaluate(
            caseID: "REC-001",
            candidate: WrongRectangleCandidate()
        )
        #expect(rectangle.outcome == .invalidSubmission)
        try rectangle.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func nonActionDecisionsAreSanitizedBeforePublication() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        let finish = try await executor.evaluate(
            caseID: "LIN-001",
            candidate: FinishCandidate()
        )
        #expect(finish.outcome == .invalidSubmission)
        #expect(finish.durationMilliseconds != nil)
        try finish.validate()

        let unsupported = try await executor.evaluate(
            caseID: "REC-001",
            candidate: UnsupportedCandidate()
        )
        #expect(unsupported.outcome == .invalidSubmission)
        try unsupported.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func nonActionDecisionsDoNotPublishOrLeakRegistrations() async throws {
        let line = try await CADLineCaseRunner(case: .lin001)
            .run(candidate: FinishCandidate())
        #expect(line.outcome == .invalidSubmission)
        #expect(line.routeEvidence.didPublish == false)
        #expect(line.routeEvidence.remainingRegistrationCount == 0)
        #expect(line.routeEvidence.cleanupCompleted)

        let rectangle = try await CADRectangleCaseRunner(case: .rec001)
            .run(candidate: UnsupportedCandidate())
        #expect(rectangle.outcome == .invalidSubmission)
        #expect(rectangle.routeEvidence.didPublish == false)
        #expect(rectangle.routeEvidence.remainingRegistrationCount == 0)
        #expect(rectangle.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func candidateFailureIsTypedAndNeverProjectedAsSuccess() async throws {
        let executor = DefaultCADActivatedCaseExecutor()

        do {
            _ = try await executor.evaluate(
                caseID: "LIN-001",
                candidate: ThrowingCandidate()
            )
            Issue.record("Candidate failure must be thrown.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .candidateFailure("LIN-001"))
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringCandidatePlanningIsProjectedAsCancellation() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let signal = CandidateStartSignal()
        let task = Task { @MainActor in
            try await executor.evaluate(
                caseID: "LIN-001",
                candidate: CancellationAwareCandidate(signal: signal)
            )
        }

        await signal.waitUntilStarted()
        task.cancel()
        let result = try await task.value

        #expect(result.outcome == .cancellation)
        #expect(result.durationMilliseconds != nil)
        try result.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func inactiveCaseIsRejectedBeforeCategoryDispatch() async throws {
        let executor = DefaultCADActivatedCaseExecutor()
        do {
            _ = try executor.context(for: "BOX-001")
            Issue.record("Inactive case must be rejected.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("BOX-001"))
        }
    }

    @Test
    func candidateCodableUsesExplicitDiscriminatorsAndNamedPayloads() throws {
        let line = CADCandidateAction.automation(.sketch(.line(
            name: "segment",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 25, y: 0, z: 0)
        )))
        let rectangle = CADCandidateAction.automation(.sketch(.rectangle(
            name: "frame",
            plane: .xy,
            center: CADPoint3D(x: 10, y: 20, z: 0),
            width: CADLength(value: 40),
            height: CADLength(value: 20)
        )))
        let circle = CADCandidateAction.automation(.sketch(.circle(
            name: "round",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0),
            radius: CADLength(value: 5)
        )))
        let angle = CADCandidateAction.automation(.sketch(.angle(
            name: "angle",
            plane: .xy,
            firstStart: CADPoint3D(x: 0, y: 0, z: 35),
            firstEnd: CADPoint3D(x: 15, y: 0, z: 35),
            secondStart: CADPoint3D(x: 0, y: 0, z: 35),
            secondEnd: CADPoint3D(x: 21.6506350946, y: 12.5, z: 35)
        )))

        let lineJSON = try canonicalJSON(line)
        let rectangleJSON = try canonicalJSON(rectangle)
        let circleJSON = try canonicalJSON(circle)
        let angleJSON = try canonicalJSON(angle)
        let actionDecisionJSON = try canonicalJSON(CADCandidateDecision.action(line))
        let finishJSON = try canonicalJSON(
            CADCandidateDecision.finish(CADOutputRoleBindings(bindings: []))
        )

        #expect(lineJSON == "{\"automation\":{\"kind\":\"sketch\",\"sketch\":{\"end\":{\"unit\":\"millimeter\",\"x\":25,\"y\":0,\"z\":0},\"kind\":\"line\",\"name\":\"segment\",\"plane\":\"xy\",\"start\":{\"unit\":\"millimeter\",\"x\":0,\"y\":0,\"z\":0}}},\"kind\":\"automation\"}")
        #expect(rectangleJSON == "{\"automation\":{\"kind\":\"sketch\",\"sketch\":{\"center\":{\"unit\":\"millimeter\",\"x\":10,\"y\":20,\"z\":0},\"height\":{\"unit\":\"millimeter\",\"value\":20},\"kind\":\"rectangle\",\"name\":\"frame\",\"plane\":\"xy\",\"width\":{\"unit\":\"millimeter\",\"value\":40}}},\"kind\":\"automation\"}")
        #expect(circleJSON == "{\"automation\":{\"kind\":\"sketch\",\"sketch\":{\"center\":{\"unit\":\"millimeter\",\"x\":0,\"y\":0,\"z\":0},\"kind\":\"circle\",\"name\":\"round\",\"plane\":\"xy\",\"radius\":{\"unit\":\"millimeter\",\"value\":5}}},\"kind\":\"automation\"}")
        #expect(angleJSON == "{\"automation\":{\"kind\":\"sketch\",\"sketch\":{\"firstEnd\":{\"unit\":\"millimeter\",\"x\":15,\"y\":0,\"z\":35},\"firstStart\":{\"unit\":\"millimeter\",\"x\":0,\"y\":0,\"z\":35},\"kind\":\"angle\",\"name\":\"angle\",\"plane\":\"xy\",\"secondEnd\":{\"unit\":\"millimeter\",\"x\":21.6506350946,\"y\":12.5,\"z\":35},\"secondStart\":{\"unit\":\"millimeter\",\"x\":0,\"y\":0,\"z\":35}}},\"kind\":\"automation\"}")
        #expect(actionDecisionJSON == "{\"action\":{\"automation\":{\"kind\":\"sketch\",\"sketch\":{\"end\":{\"unit\":\"millimeter\",\"x\":25,\"y\":0,\"z\":0},\"kind\":\"line\",\"name\":\"segment\",\"plane\":\"xy\",\"start\":{\"unit\":\"millimeter\",\"x\":0,\"y\":0,\"z\":0}}},\"kind\":\"automation\"},\"kind\":\"action\"}")
        #expect(finishJSON == "{\"finish\":{\"bindings\":[]},\"kind\":\"finish\"}")

        #expect(try JSONDecoder().decode(CADCandidateAction.self, from: Data(lineJSON.utf8)) == line)
        #expect(try JSONDecoder().decode(CADCandidateAction.self, from: Data(rectangleJSON.utf8)) == rectangle)
        #expect(try JSONDecoder().decode(CADCandidateAction.self, from: Data(circleJSON.utf8)) == circle)
        #expect(try JSONDecoder().decode(CADCandidateAction.self, from: Data(angleJSON.utf8)) == angle)
    }

    @Test
    func legacyUnknownAndMissingDiscriminatorsAreRejected() throws {
        let legacy = Data(#"{"automation":{"sketch":{"line":{"name":"segment","plane":"xy","start":{"x":0,"y":0,"z":0,"unit":"millimeter"},"end":{"x":25,"y":0,"z":0,"unit":"millimeter"}}}}}"#.utf8)
        let unknown = Data(#"{"kind":"future","automation":{}}"#.utf8)
        let missing = Data(#"{"automation":{"kind":"sketch","sketch":{"kind":"line"}}}"#.utf8)

        for data in [legacy, unknown, missing] {
            do {
                _ = try JSONDecoder().decode(CADCandidateAction.self, from: data)
                Issue.record("Invalid discriminator payload was accepted.")
            } catch {
                // Expected typed decoding failure.
            }
        }
    }

    @Test
    func outputRoleSelectorUsesExplicitDiscriminator() throws {
        #expect(try canonicalJSON(CADOutputRoleSelector.primary) == "{\"kind\":\"primary\"}")
        #expect(try canonicalJSON(CADOutputRoleSelector.created(index: 2)) == "{\"index\":2,\"kind\":\"created\"}")

        let unknown = Data(#"{"kind":"future"}"#.utf8)
        do {
            _ = try JSONDecoder().decode(CADOutputRoleSelector.self, from: unknown)
            Issue.record("Unknown output role selector kind was accepted.")
        } catch {
            // Expected typed decoding failure.
        }
    }
}

private struct ReferenceLineCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        try await CADLineReferenceCandidate().decide(for: context)
    }
}

private struct ReferenceRectangleCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        try await CADRectangleReferenceCandidate().decide(for: context)
    }
}

private struct ContextCheckingCandidate: CADCandidateProtocol {
    let expected: CADCandidateContext

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        guard context == expected else {
            throw ContextMismatch()
        }
        return try await CADLineReferenceCandidate().decide(for: context)
    }
}

private struct RectangleContextCheckingCandidate: CADCandidateProtocol {
    let expected: CADCandidateContext

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        guard context == expected else {
            throw ContextMismatch()
        }
        return try await CADRectangleReferenceCandidate().decide(for: context)
    }
}

private struct WrongLineCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(.automation(.sketch(.line(
            name: "wrong-line",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 30, y: 0, z: 0)
        ))))
    }
}

private struct WrongRectangleCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        let projection = try CADRectangleChallengeProjection.decode(context.challenge)
        return .action(.automation(.sketch(.rectangle(
            name: "wrong-rectangle",
            plane: projection.orientation,
            center: projection.center,
            width: CADLength(value: 1),
            height: CADLength(value: 1)
        ))))
    }
}

private struct FinishCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .finish(CADOutputRoleBindings(bindings: []))
    }
}

private struct UnsupportedCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .unsupported(CADUnsupportedDeclaration(
            capabilityID: context.challenge.requiredCapability.id,
            capabilityVersion: context.challenge.requiredCapability.version,
            reason: .capabilityUnavailable
        ))
    }
}

private struct ThrowingCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        throw CandidateFailure()
    }
}

private struct CancellationAwareCandidate: CADCandidateProtocol {
    let signal: CandidateStartSignal

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        await signal.markStarted()
        try await Task.sleep(for: .seconds(60))
        return .finish(CADOutputRoleBindings(bindings: []))
    }
}

private actor CandidateStartSignal {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pending {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            if started {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}

private struct ContextMismatch: Error, Sendable {}
private struct CandidateFailure: Error, Sendable {}

private func canonicalJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
