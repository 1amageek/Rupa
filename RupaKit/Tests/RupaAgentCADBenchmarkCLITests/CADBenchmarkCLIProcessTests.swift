import Foundation
import Testing
import RupaAgentCADBenchmark
import RupaAgentCADBenchmarkJSONAdapter

@Suite(.serialized)
struct CADBenchmarkCLIProcessTests {
    @Test
    func usageFailuresExit64WhileExplicitHelpRemainsMetadata() throws {
        for arguments in [[], ["unknown"], ["evaluate"], ["request"]] {
            let result = try runCADBenchmarkCLI(arguments)
            #expect(result.terminationStatus == 64)
            #expect(result.standardOutput.isEmpty)
            #expect(result.standardError.isEmpty == false)
        }

        let help = try runCADBenchmarkCLI(["--help"])
        #expect(help.terminationStatus == 0)
        #expect(help.standardOutput.contains("USAGE:"))
        #expect(help.standardError.isEmpty)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func con001UsesBoundedRequestFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-001"])
        #expect(requestResult.terminationStatus == 0)
        #expect(requestResult.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        let request = try CADJSONBoundedCodec.decode(
            CADJSONRequestEnvelope.self,
            from: requestResult.standardOutputData
        )
        #expect(request.caseID == "CON-001")
        #expect(request.context.challenge.instruction.contains("coincident relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(
            for: "CON-001",
            action: constraint001Action(name: "CON-001")
        )
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-001")
        let standardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: exact
        )
        try assertRealizedEvaluation(standardInputResult, caseID: "CON-001")

        let wrong = try responseData(
            for: "CON-001",
            action: constraint001Action(name: "CON-001.wrong", firstStartX: 10)
        )
        let wrongResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrong
        )
        let wrongEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongResult.standardOutputData
        )
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let invalid = try responseData(
            for: "CON-001",
            action: constraint001Action(name: "CON-001.invalid", secondEndY: 19)
        )
        let invalidResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: invalid
        )
        let invalidEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: invalidResult.standardOutputData
        )
        #expect(invalidResult.terminationStatus == 2)
        #expect(invalidEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(invalidResult.standardOutput))

        let legacy = replacing(
            exact,
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v5"
        )
        let legacyResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: legacy
        )
        try assertError(legacyResult, code: .unsupportedSchema, exit: 64, caseID: nil)

        let inactive = try runCADBenchmarkCLI(["request", "TRN-003"])
        try assertError(inactive, code: .inactiveCase, exit: 64, caseID: "TRN-003")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func trn001UsesBoundedRequestFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "TRN-001"])
        #expect(requestResult.terminationStatus == 0)
        #expect(requestResult.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        let request = try CADJSONBoundedCodec.decode(
            CADJSONRequestEnvelope.self,
            from: requestResult.standardOutputData
        )
        #expect(request.caseID == "TRN-001")
        #expect(request.context.challenge.category == .transform)
        #expect(request.context.challenge.instruction.contains("first rotating line"))
        #expect(request.context.challenge.instruction.contains("then translating"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(
            for: "TRN-001",
            action: transform001Action()
        )
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "TRN-001")

        let standardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: exact
        )
        try assertRealizedEvaluation(standardInputResult, caseID: "TRN-001")

        let wrong = try responseData(
            for: "TRN-001",
            action: transform001Action(translationX: 26)
        )
        let wrongResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrong
        )
        let wrongEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongResult.standardOutputData
        )
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.caseID == "TRN-001")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let zeroAxis = try responseData(
            for: "TRN-001",
            action: transform001Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        let zeroAxisResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: zeroAxis
        )
        let zeroAxisEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: zeroAxisResult.standardOutputData
        )
        #expect(zeroAxisResult.terminationStatus == 2)
        #expect(zeroAxisEvaluation.caseID == "TRN-001")
        #expect(zeroAxisEvaluation.result?.outcome == .invalidSubmission)
        #expect(zeroAxisEvaluation.error == nil)
        #expect(isPrivateFree(zeroAxisResult.standardOutput))

        let unsupportedSchema = replacing(
            exact,
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v6"
        )
        let unsupportedSchemaResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: unsupportedSchema
        )
        try assertError(unsupportedSchemaResult, code: .unsupportedSchema, exit: 64, caseID: nil)

        let inactive = try runCADBenchmarkCLI(["request", "TRN-003"])
        try assertError(inactive, code: .inactiveCase, exit: 64, caseID: "TRN-003")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func trn002UsesBoundedRequestFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "TRN-002"])
        #expect(requestResult.terminationStatus == 0)
        #expect(requestResult.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        let request = try CADJSONBoundedCodec.decode(
            CADJSONRequestEnvelope.self,
            from: requestResult.standardOutputData
        )
        #expect(request.caseID == "TRN-002")
        #expect(request.context.challenge.category == .transform)
        #expect(request.context.challenge.instruction.contains("rectangle width 40.0 mm height 20.0 mm"))
        #expect(request.context.challenge.instruction.contains("then translating the rotated result by (0.0, 25.0, 0.0) mm"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(
            for: "TRN-002",
            action: transform002Action()
        )
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "TRN-002")

        let standardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: exact
        )
        try assertRealizedEvaluation(standardInputResult, caseID: "TRN-002")

        let wrongOrder = try responseData(
            for: "TRN-002",
            action: transform002Action(
                translationX: -17.67766952966369,
                translationY: 17.67766952966369
            )
        )
        let wrongResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongOrder
        )
        let wrongEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongResult.standardOutputData
        )
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.caseID == "TRN-002")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let invalid = try responseData(
            for: "TRN-002",
            action: transform002Action(axis: CADDirection3D(x: 0, y: 0, z: 0))
        )
        let invalidResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: invalid
        )
        let invalidEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: invalidResult.standardOutputData
        )
        #expect(invalidResult.terminationStatus == 2)
        #expect(invalidEvaluation.caseID == "TRN-002")
        #expect(invalidEvaluation.result?.outcome == .invalidSubmission)
        #expect(invalidEvaluation.error == nil)
        #expect(isPrivateFree(invalidResult.standardOutput))

        let unsupportedSchema = replacing(
            exact,
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v6"
        )
        let unsupportedSchemaResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: unsupportedSchema
        )
        try assertError(unsupportedSchemaResult, code: .unsupportedSchema, exit: 64, caseID: nil)

        let inactive = try runCADBenchmarkCLI(["request", "TRN-003"])
        try assertError(inactive, code: .inactiveCase, exit: 64, caseID: "TRN-003")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func con002UsesBoundedStandardInputProductionRoute() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-002"])
        #expect(requestResult.terminationStatus == 0)
        #expect(requestResult.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        let request = try CADJSONBoundedCodec.decode(
            CADJSONRequestEnvelope.self,
            from: requestResult.standardOutputData
        )
        #expect(request.caseID == "CON-002")
        #expect(request.context.challenge.instruction.contains("parallel relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(
            for: "CON-002",
            action: constraint002Action(name: "CON-002")
        )
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-002")
        let exactResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: exact
        )
        try assertRealizedEvaluation(exactResult, caseID: "CON-002")

        let wrong = try responseData(
            for: "CON-002",
            action: constraint002Action(name: "CON-002.wrong", relation: .perpendicular)
        )
        let wrongResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrong
        )
        let wrongEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongResult.standardOutputData
        )
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func con003UsesBoundedFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-003"])
        #expect(requestResult.terminationStatus == 0)
        let request = try CADJSONBoundedCodec.decode(
            CADJSONRequestEnvelope.self,
            from: requestResult.standardOutputData
        )
        #expect(request.caseID == "CON-003")
        #expect(request.context.challenge.instruction.contains("perpendicular relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(
            for: "CON-003",
            action: constraint003Action(name: "CON-003")
        )
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-003")
        let standardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: exact
        )
        try assertRealizedEvaluation(standardInputResult, caseID: "CON-003")

        let wrong = try responseData(
            for: "CON-003",
            action: constraint003Action(name: "CON-003.wrong", relation: .parallel)
        )
        let wrongResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrong
        )
        let evaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongResult.standardOutputData
        )
        #expect(wrongResult.terminationStatus == 2)
        #expect(evaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let invalid = try responseData(
            for: "CON-005",
            action: constraint005Action(name: "CON-005.invalid", includeSecond: true)
        )
        let invalidResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: invalid)
        let invalidEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: invalidResult.standardOutputData
        )
        #expect(invalidResult.terminationStatus == 2)
        #expect(invalidEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(invalidResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2))) @MainActor
    func con004UsesBoundedFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-004"])
        #expect(requestResult.terminationStatus == 0)
        let request = try CADJSONBoundedCodec.decode(CADJSONRequestEnvelope.self, from: requestResult.standardOutputData)
        #expect(request.caseID == "CON-004")
        #expect(request.context.challenge.instruction.contains("horizontal relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(for: "CON-004", action: constraint004Action(name: "CON-004"))
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-004")
        let stdinResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: exact)
        try assertRealizedEvaluation(stdinResult, caseID: "CON-004")

        let wrong = try responseData(
            for: "CON-004",
            action: constraint004Action(name: "CON-004.wrong", relation: .vertical)
        )
        let wrongResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: wrong)
        let evaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: wrongResult.standardOutputData)
        #expect(wrongResult.terminationStatus == 2)
        #expect(evaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2))) @MainActor
    func con005UsesBoundedFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-005"])
        #expect(requestResult.terminationStatus == 0)
        let request = try CADJSONBoundedCodec.decode(CADJSONRequestEnvelope.self, from: requestResult.standardOutputData)
        #expect(request.caseID == "CON-005")
        #expect(request.context.challenge.instruction.contains("vertical relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(for: "CON-005", action: constraint005Action(name: "CON-005"))
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-005")
        let stdinResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: exact)
        try assertRealizedEvaluation(stdinResult, caseID: "CON-005")

        let wrong = try responseData(
            for: "CON-005",
            action: constraint005Action(name: "CON-005.wrong", relation: .horizontal)
        )
        let wrongResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: wrong)
        let evaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: wrongResult.standardOutputData)
        #expect(wrongResult.terminationStatus == 2)
        #expect(evaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2))) @MainActor
    func con006UsesBoundedFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-006"])
        #expect(requestResult.terminationStatus == 0)
        let request = try CADJSONBoundedCodec.decode(CADJSONRequestEnvelope.self, from: requestResult.standardOutputData)
        #expect(request.caseID == "CON-006")
        #expect(request.context.challenge.instruction.contains("equalLength relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(for: "CON-006", action: constraint006Action(name: "CON-006"))
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-006")
        let stdinResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: exact)
        try assertRealizedEvaluation(stdinResult, caseID: "CON-006")

        let wrong = try responseData(
            for: "CON-006",
            action: constraint006Action(name: "CON-006.wrong", relation: .parallel)
        )
        let wrongResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: wrong)
        let wrongEvaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: wrongResult.standardOutputData)
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let invalid = try responseData(
            for: "CON-006",
            action: constraint006Action(name: "CON-006.invalid", secondEndX: 0)
        )
        let invalidResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: invalid)
        let invalidEvaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: invalidResult.standardOutputData)
        #expect(invalidResult.terminationStatus == 2)
        #expect(invalidEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(invalidResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2))) @MainActor
    func con007UsesBoundedFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-007"])
        #expect(requestResult.terminationStatus == 0)
        let request = try CADJSONBoundedCodec.decode(CADJSONRequestEnvelope.self, from: requestResult.standardOutputData)
        #expect(request.caseID == "CON-007")
        #expect(request.context.challenge.instruction.contains("concentric relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(for: "CON-007", action: constraint007Action(name: "CON-007"))
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-007")
        let stdinResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: exact)
        try assertRealizedEvaluation(stdinResult, caseID: "CON-007")

        let wrong = try responseData(
            for: "CON-007",
            action: constraint007Action(name: "CON-007.wrong", relation: .equalRadius, secondRadius: 10)
        )
        let wrongResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: wrong)
        let wrongEvaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: wrongResult.standardOutputData)
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let invalid = try responseData(
            for: "CON-007",
            action: constraint007Action(name: "CON-007.invalid", firstRadius: 0)
        )
        let invalidResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: invalid)
        let invalidEvaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: invalidResult.standardOutputData)
        #expect(invalidResult.terminationStatus == 2)
        #expect(invalidEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(invalidResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2))) @MainActor
    func con008UsesBoundedFileAndStandardInputProductionRoutes() throws {
        let requestResult = try runCADBenchmarkCLI(["request", "CON-008"])
        #expect(requestResult.terminationStatus == 0)
        let request = try CADJSONBoundedCodec.decode(CADJSONRequestEnvelope.self, from: requestResult.standardOutputData)
        #expect(request.caseID == "CON-008")
        #expect(request.context.challenge.instruction.contains("equalRadius relation"))
        #expect(isPrivateFree(requestResult.standardOutput))

        let exact = try responseData(for: "CON-008", action: constraint008Action(name: "CON-008"))
        let fileResult = try withTemporaryData(exact) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(fileResult, caseID: "CON-008")
        let stdinResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: exact)
        try assertRealizedEvaluation(stdinResult, caseID: "CON-008")

        let wrong = try responseData(
            for: "CON-008",
            action: constraint008Action(name: "CON-008.wrong", relation: .concentric, secondCenterX: 0)
        )
        let wrongResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: wrong)
        let wrongEvaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: wrongResult.standardOutputData)
        #expect(wrongResult.terminationStatus == 2)
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(wrongResult.standardOutput))

        let invalid = try responseData(
            for: "CON-008",
            action: constraint008Action(name: "CON-008.invalid", secondRadius: 0)
        )
        let invalidResult = try runCADBenchmarkCLI(["evaluate", "--response", "-"], standardInput: invalid)
        let invalidEvaluation = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: invalidResult.standardOutputData)
        #expect(invalidResult.terminationStatus == 2)
        #expect(invalidEvaluation.result?.outcome == .invalidSubmission)
        #expect(isPrivateFree(invalidResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func requestEmitsBoundedReviewedObjectsAndRejectsInactiveCase() throws {
        for rawCaseID in ["LIN-001", "REC-001", "REC-009", "REC-010", "REC-011", "REC-012", "CIR-001", "CIR-002", "CIR-003", "CIR-004", "CIR-005", "CIR-006", "CIR-007", "CIR-008", "CIR-009", "CIR-010", "CIR-011", "CIR-012", "ANG-001", "ANG-002", "ANG-003", "ANG-004", "ANG-005", "ANG-006", "ANG-007", "ANG-008", "ANG-009", "ANG-010", "ANG-011", "ANG-012", "ANG-013", "ANG-014", "ANG-015", "ANG-016", "BOX-001", "BOX-002", "BOX-003", "BOX-004", "BOX-005", "BOX-006", "BOX-007", "BOX-008", "BOX-009", "BOX-010", "BOX-011", "BOX-012", "CYL-001", "CYL-002", "CYL-003", "CYL-004", "CYL-005", "CYL-006", "CYL-007", "CYL-008", "CON-001", "CON-002", "CON-003", "CON-004", "CON-005", "CON-006", "CON-007", "CON-008", "TRN-001", "TRN-002"] {
            let result = try runCADBenchmarkCLI(["request", rawCaseID])
            #expect(result.terminationStatus == 0, Comment(rawValue: result.standardError))
            #expect(result.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
            let request = try CADJSONBoundedCodec.decode(
                CADJSONRequestEnvelope.self,
                from: result.standardOutputData
            )
            #expect(request.caseID.rawValue == rawCaseID)
            #expect(isSingleJSONObject(result.standardOutputData))
            #expect(result.standardError.isEmpty)
        }

        let inactive = try runCADBenchmarkCLI(["request", "TRN-003"])
        #expect(inactive.terminationStatus == 64)
        let error = try CADJSONBoundedCodec.decode(
            CADJSONErrorEnvelope.self,
            from: inactive.standardOutputData
        )
        #expect(error.code == .inactiveCase)
        #expect(error.caseID?.rawValue == "TRN-003")
        #expect(isPrivateFree(inactive.standardOutput))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func validReviewedResponsesUseFileAndStandardInputRoutes() throws {
        let lineResponse = try responseData(
            for: "LIN-001",
            action: lineAction(name: "LIN-001")
        )
        let rectangleResponse = try responseData(
            for: "REC-001",
            action: rectangleAction(name: "REC-001")
        )
        let inchRectangleResponse = try responseData(
            for: "REC-009",
            action: rec009RectangleAction(name: "REC-009")
        )
        let circleResponse = try responseData(
            for: "CIR-001",
            action: circleAction(name: "CIR-001")
        )
        let translatedCircleResponse = try responseData(
            for: "CIR-002",
            action: cir002CircleAction(name: "CIR-002")
        )
        let xzCircleResponse = try responseData(
            for: "CIR-003",
            action: cir003CircleAction(name: "CIR-003")
        )

        let lineFileResult = try withTemporaryData(lineResponse) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(lineFileResult, caseID: "LIN-001")

        let rectangleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: rectangleResponse
        )
        try assertRealizedEvaluation(rectangleStandardInputResult, caseID: "REC-001")

        let inchRectangleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: inchRectangleResponse
        )
        try assertRealizedEvaluation(inchRectangleStandardInputResult, caseID: "REC-009")

        let circleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: circleResponse
        )
        try assertRealizedEvaluation(circleStandardInputResult, caseID: "CIR-001")

        let translatedCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedCircleResponse
        )
        try assertRealizedEvaluation(translatedCircleStandardInputResult, caseID: "CIR-002")

        let xzCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: xzCircleResponse
        )
        try assertRealizedEvaluation(xzCircleStandardInputResult, caseID: "CIR-003")

        let yzCircleResponse = try responseData(
            for: "CIR-004",
            action: cir004CircleAction(name: "CIR-004")
        )
        let yzCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: yzCircleResponse
        )
        try assertRealizedEvaluation(yzCircleStandardInputResult, caseID: "CIR-004")

        let largeCircleResponse = try responseData(
            for: "CIR-005",
            action: cir005CircleAction(name: "CIR-005")
        )
        let largeCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: largeCircleResponse
        )
        try assertRealizedEvaluation(largeCircleStandardInputResult, caseID: "CIR-005")

        let centimeterCircleResponse = try responseData(
            for: "CIR-006",
            action: cir006CircleAction(name: "CIR-006")
        )
        let centimeterCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: centimeterCircleResponse
        )
        try assertRealizedEvaluation(centimeterCircleStandardInputResult, caseID: "CIR-006")

        let metreCircleResponse = try responseData(
            for: "CIR-007",
            action: cir007CircleAction(name: "CIR-007")
        )
        let metreCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: metreCircleResponse
        )
        try assertRealizedEvaluation(metreCircleStandardInputResult, caseID: "CIR-007")

        let inchCircleResponse = try responseData(
            for: "CIR-008",
            action: cir008CircleAction(name: "CIR-008")
        )
        let inchCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: inchCircleResponse
        )
        try assertRealizedEvaluation(inchCircleStandardInputResult, caseID: "CIR-008")

        let negativeZCircleResponse = try responseData(
            for: "CIR-009",
            action: cir009CircleAction(name: "CIR-009")
        )
        let negativeZCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: negativeZCircleResponse
        )
        try assertRealizedEvaluation(negativeZCircleStandardInputResult, caseID: "CIR-009")

        let largeMetreCircleResponse = try responseData(
            for: "CIR-010",
            action: cir010CircleAction(name: "CIR-010")
        )
        let largeMetreCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: largeMetreCircleResponse
        )
        try assertRealizedEvaluation(largeMetreCircleStandardInputResult, caseID: "CIR-010")

        let fractionalRadiusCircleResponse = try responseData(
            for: "CIR-011",
            action: cir011CircleAction(name: "CIR-011")
        )
        let fractionalRadiusCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: fractionalRadiusCircleResponse
        )
        try assertRealizedEvaluation(fractionalRadiusCircleStandardInputResult, caseID: "CIR-011")

        let terminalCircleResponse = try responseData(
            for: "CIR-012",
            action: cir012CircleAction(name: "CIR-012")
        )
        let terminalCircleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: terminalCircleResponse
        )
        try assertRealizedEvaluation(terminalCircleStandardInputResult, caseID: "CIR-012")

        let metreRectangleResponse = try responseData(
            for: "REC-010",
            action: rec010RectangleAction(name: "REC-010")
        )
        let metreRectangleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: metreRectangleResponse
        )
        try assertRealizedEvaluation(metreRectangleStandardInputResult, caseID: "REC-010")

        let squareRectangleResponse = try responseData(
            for: "REC-011",
            action: rec011RectangleAction(name: "REC-011")
        )
        let squareRectangleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: squareRectangleResponse
        )
        try assertRealizedEvaluation(squareRectangleStandardInputResult, caseID: "REC-011")

        let translatedRectangleResponse = try responseData(
            for: "REC-012",
            action: rec012RectangleAction(name: "REC-012")
        )
        let translatedRectangleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedRectangleResponse
        )
        try assertRealizedEvaluation(translatedRectangleStandardInputResult, caseID: "REC-012")

        let angleResponse = try responseData(
            for: "ANG-001",
            action: angleAction(name: "ANG-001")
        )
        let angleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: angleResponse
        )
        try assertRealizedEvaluation(angleStandardInputResult, caseID: "ANG-001")

        let translatedAngleResponse = try responseData(
            for: "ANG-002",
            action: angle002Action(name: "ANG-002")
        )
        let translatedAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedAngleResponse
        )
        try assertRealizedEvaluation(translatedAngleStandardInputResult, caseID: "ANG-002")

        let translatedSixtyDegreeAngleResponse = try responseData(
            for: "ANG-003",
            action: angle003Action(name: "ANG-003")
        )
        let translatedSixtyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedSixtyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            translatedSixtyDegreeAngleStandardInputResult,
            caseID: "ANG-003"
        )

        let translatedSeventyFiveDegreeAngleResponse = try responseData(
            for: "ANG-004",
            action: angle004Action(name: "ANG-004")
        )
        let translatedSeventyFiveDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedSeventyFiveDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            translatedSeventyFiveDegreeAngleStandardInputResult,
            caseID: "ANG-004"
        )

        let orthogonalAngleResponse = try responseData(
            for: "ANG-005",
            action: angle005Action(name: "ANG-005")
        )
        let orthogonalAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: orthogonalAngleResponse
        )
        try assertRealizedEvaluation(
            orthogonalAngleStandardInputResult,
            caseID: "ANG-005"
        )

        let negativePlacementAngleResponse = try responseData(
            for: "ANG-006",
            action: angle006Action(name: "ANG-006")
        )
        let negativePlacementAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: negativePlacementAngleResponse
        )
        try assertRealizedEvaluation(
            negativePlacementAngleStandardInputResult,
            caseID: "ANG-006"
        )

        let translatedOneHundredTwentyDegreeAngleResponse = try responseData(
            for: "ANG-007",
            action: angle007Action(name: "ANG-007")
        )
        let translatedOneHundredTwentyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedOneHundredTwentyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            translatedOneHundredTwentyDegreeAngleStandardInputResult,
            caseID: "ANG-007"
        )

        let originOneHundredThirtyFiveDegreeAngleResponse = try responseData(
            for: "ANG-008",
            action: angle008Action(name: "ANG-008")
        )
        let originOneHundredThirtyFiveDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: originOneHundredThirtyFiveDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            originOneHundredThirtyFiveDegreeAngleStandardInputResult,
            caseID: "ANG-008"
        )

        let translatedOneHundredFiftyDegreeAngleResponse = try responseData(
            for: "ANG-009",
            action: angle009Action(name: "ANG-009")
        )
        let translatedOneHundredFiftyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedOneHundredFiftyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            translatedOneHundredFiftyDegreeAngleStandardInputResult,
            caseID: "ANG-009"
        )

        let negativePlacementOneHundredSixtyFiveDegreeAngleResponse = try responseData(
            for: "ANG-010",
            action: angle010Action(name: "ANG-010")
        )
        let negativePlacementOneHundredSixtyFiveDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: negativePlacementOneHundredSixtyFiveDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            negativePlacementOneHundredSixtyFiveDegreeAngleStandardInputResult,
            caseID: "ANG-010"
        )

        let xzFortyFiveDegreeAngleResponse = try responseData(
            for: "ANG-011",
            action: angle011Action(name: "ANG-011")
        )
        let xzFortyFiveDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: xzFortyFiveDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            xzFortyFiveDegreeAngleStandardInputResult,
            caseID: "ANG-011"
        )

        let yzSixtyDegreeAngleResponse = try responseData(
            for: "ANG-012",
            action: angle012Action(name: "ANG-012")
        )
        let yzSixtyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: yzSixtyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            yzSixtyDegreeAngleStandardInputResult,
            caseID: "ANG-012"
        )

        let xzNinetyDegreeAngleResponse = try responseData(
            for: "ANG-013",
            action: angle013Action(name: "ANG-013")
        )
        let xzNinetyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: xzNinetyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            xzNinetyDegreeAngleStandardInputResult,
            caseID: "ANG-013"
        )

        let yzOneHundredTwentyDegreeAngleResponse = try responseData(
            for: "ANG-014",
            action: angle014Action(name: "ANG-014")
        )
        let yzOneHundredTwentyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: yzOneHundredTwentyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            yzOneHundredTwentyDegreeAngleStandardInputResult,
            caseID: "ANG-014"
        )

        let xzOneHundredThirtyFiveDegreeAngleResponse = try responseData(
            for: "ANG-015",
            action: angle015Action(name: "ANG-015")
        )
        let xzOneHundredThirtyFiveDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: xzOneHundredThirtyFiveDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            xzOneHundredThirtyFiveDegreeAngleStandardInputResult,
            caseID: "ANG-015"
        )

        let yzOneHundredFiftyDegreeAngleResponse = try responseData(
            for: "ANG-016",
            action: angle016Action(name: "ANG-016")
        )
        let yzOneHundredFiftyDegreeAngleStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: yzOneHundredFiftyDegreeAngleResponse
        )
        try assertRealizedEvaluation(
            yzOneHundredFiftyDegreeAngleStandardInputResult,
            caseID: "ANG-016"
        )

        let boxResponse = try responseData(
            for: "BOX-001",
            action: box001Action(name: "BOX-001")
        )
        let boxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: boxResponse
        )
        try assertRealizedEvaluation(boxStandardInputResult, caseID: "BOX-001")

        let translatedBoxResponse = try responseData(
            for: "BOX-002",
            action: box002Action(name: "BOX-002")
        )
        let translatedBoxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedBoxResponse
        )
        try assertRealizedEvaluation(translatedBoxStandardInputResult, caseID: "BOX-002")

        let rectangularBoxResponse = try responseData(
            for: "BOX-003",
            action: box003Action(name: "BOX-003")
        )
        let rectangularBoxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: rectangularBoxResponse
        )
        try assertRealizedEvaluation(rectangularBoxStandardInputResult, caseID: "BOX-003")

        let translatedRectangularBoxResponse = try responseData(
            for: "BOX-004",
            action: box004Action(name: "BOX-004")
        )
        let translatedRectangularBoxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedRectangularBoxResponse
        )
        try assertRealizedEvaluation(
            translatedRectangularBoxStandardInputResult,
            caseID: "BOX-004"
        )

        let largeRectangularBoxResponse = try responseData(
            for: "BOX-005",
            action: box005Action(name: "BOX-005")
        )
        let largeRectangularBoxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: largeRectangularBoxResponse
        )
        try assertRealizedEvaluation(
            largeRectangularBoxStandardInputResult,
            caseID: "BOX-005"
        )

        let meterScaleBoxResponse = try responseData(
            for: "BOX-006",
            action: box006Action(name: "BOX-006")
        )
        let meterScaleBoxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: meterScaleBoxResponse
        )
        try assertRealizedEvaluation(
            meterScaleBoxStandardInputResult,
            caseID: "BOX-006"
        )

        let imperialBoxResponse = try responseData(
            for: "BOX-007",
            action: box007Action(name: "BOX-007")
        )
        let imperialBoxStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: imperialBoxResponse
        )
        try assertRealizedEvaluation(
            imperialBoxStandardInputResult,
            caseID: "BOX-007"
        )

        let translatedCubeResponse = try responseData(
            for: "BOX-008",
            action: box008Action(name: "BOX-008")
        )
        let translatedCubeStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedCubeResponse
        )
        try assertRealizedEvaluation(
            translatedCubeStandardInputResult,
            caseID: "BOX-008"
        )

        let negativePlacementCubeResponse = try responseData(
            for: "BOX-009",
            action: box009Action(name: "BOX-009")
        )
        let negativePlacementCubeStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: negativePlacementCubeResponse
        )
        try assertRealizedEvaluation(
            negativePlacementCubeStandardInputResult,
            caseID: "BOX-009"
        )

        let rectangularSolidResponse = try responseData(
            for: "BOX-010",
            action: box010Action(name: "BOX-010")
        )
        let rectangularSolidStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: rectangularSolidResponse
        )
        try assertRealizedEvaluation(
            rectangularSolidStandardInputResult,
            caseID: "BOX-010"
        )

        let metreCubeResponse = try responseData(
            for: "BOX-011",
            action: box011Action(name: "BOX-011")
        )
        let metreCubeStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: metreCubeResponse
        )
        try assertRealizedEvaluation(
            metreCubeStandardInputResult,
            caseID: "BOX-011"
        )

        let millimeterSolidResponse = try responseData(
            for: "BOX-012",
            action: box012Action(name: "BOX-012")
        )
        let millimeterSolidStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: millimeterSolidResponse
        )
        try assertRealizedEvaluation(
            millimeterSolidStandardInputResult,
            caseID: "BOX-012"
        )

        let cylinderResponse = try responseData(
            for: "CYL-001",
            action: cylinder001Action(name: "CYL-001")
        )
        let cylinderFileResult = try withTemporaryData(cylinderResponse) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        try assertRealizedEvaluation(cylinderFileResult, caseID: "CYL-001")

        let translatedCylinderResponse = try responseData(
            for: "CYL-002",
            action: cylinder002Action(name: "CYL-002")
        )
        let translatedCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: translatedCylinderResponse
        )
        try assertRealizedEvaluation(
            translatedCylinderStandardInputResult,
            caseID: "CYL-002"
        )

        let yAxisCylinderResponse = try responseData(
            for: "CYL-003",
            action: cylinder003Action(name: "CYL-003")
        )
        let yAxisCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: yAxisCylinderResponse
        )
        try assertRealizedEvaluation(yAxisCylinderStandardInputResult, caseID: "CYL-003")

        let negativeZCylinderResponse = try responseData(
            for: "CYL-004",
            action: cylinder004Action(name: "CYL-004")
        )
        let negativeZCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: negativeZCylinderResponse
        )
        try assertRealizedEvaluation(negativeZCylinderStandardInputResult, caseID: "CYL-004")

        let diagonalCylinderResponse = try responseData(
            for: "CYL-005",
            action: cylinder005Action(name: "CYL-005")
        )
        let diagonalCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: diagonalCylinderResponse
        )
        try assertRealizedEvaluation(diagonalCylinderStandardInputResult, caseID: "CYL-005")

        let yzCylinderResponse = try responseData(
            for: "CYL-006",
            action: cylinder006Action(name: "CYL-006")
        )
        let yzCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: yzCylinderResponse
        )
        try assertRealizedEvaluation(yzCylinderStandardInputResult, caseID: "CYL-006")

        let inchNegativeXCylinderResponse = try responseData(
            for: "CYL-007",
            action: cylinder007Action(name: "CYL-007")
        )
        let inchNegativeXCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: inchNegativeXCylinderResponse
        )
        try assertRealizedEvaluation(inchNegativeXCylinderStandardInputResult, caseID: "CYL-007")

        let threeAxisCylinderResponse = try responseData(
            for: "CYL-008",
            action: cylinder008Action(name: "CYL-008")
        )
        let threeAxisCylinderStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: threeAxisCylinderResponse
        )
        try assertRealizedEvaluation(threeAxisCylinderStandardInputResult, caseID: "CYL-008")

        let constraintResponse = try responseData(
            for: "CON-001",
            action: constraint001Action(name: "CON-001")
        )
        let constraintStandardInputResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: constraintResponse
        )
        try assertRealizedEvaluation(constraintStandardInputResult, caseID: "CON-001")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func wrongGeometryIsNonRealizedWithoutRetry() throws {
        let request = try CADJSONAdapter().makeRequest(for: "LIN-001")
        let wrongLine = CADCandidateAction.automation(.sketch(.line(
            name: "wrong",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 24, y: 0, z: 0)
        )))
        let response = try responseData(
            for: "LIN-001",
            contextFingerprint: request.contextFingerprint,
            action: wrongLine
        )
        let result = try withTemporaryData(response) { path in
            try runCADBenchmarkCLI(["evaluate", "--response", path])
        }
        let evaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: result.standardOutputData
        )
        #expect(result.terminationStatus == 2)
        #expect(evaluation.result?.outcome == .invalidSubmission)
        #expect(evaluation.error == nil)
        #expect(isSingleJSONObject(result.standardOutputData))
        #expect(isPrivateFree(result.standardOutput))

        let wrongBox = try responseData(
            for: "BOX-001",
            action: box001Action(name: "BOX-001.wrong-width", width: 12)
        )
        let boxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongBox
        )
        let boxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: boxResult.standardOutputData
        )
        #expect(boxResult.terminationStatus == 2)
        #expect(boxEvaluation.caseID == "BOX-001")
        #expect(boxEvaluation.result?.outcome == .invalidSubmission)
        #expect(boxEvaluation.error == nil)
        #expect(isSingleJSONObject(boxResult.standardOutputData))
        #expect(isPrivateFree(boxResult.standardOutput))

        let wrongCylinder = try responseData(
            for: "CYL-001",
            action: cylinder001Action(name: "CYL-001.wrong-radius", radius: 6)
        )
        let cylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongCylinder
        )
        let cylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: cylinderResult.standardOutputData
        )
        #expect(cylinderResult.terminationStatus == 2)
        #expect(cylinderEvaluation.caseID == "CYL-001")
        #expect(cylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(cylinderEvaluation.error == nil)
        #expect(isPrivateFree(cylinderResult.standardOutput))

        let wrongTranslatedCylinder = try responseData(
            for: "CYL-002",
            action: cylinder002Action(
                name: "CYL-002.wrong-axis",
                axis: CADDirection3D(x: 0, y: 0, z: 1)
            )
        )
        let translatedCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongTranslatedCylinder
        )
        let translatedCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: translatedCylinderResult.standardOutputData
        )
        #expect(translatedCylinderResult.terminationStatus == 2)
        #expect(translatedCylinderEvaluation.caseID == "CYL-002")
        #expect(translatedCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(translatedCylinderEvaluation.error == nil)
        #expect(isPrivateFree(translatedCylinderResult.standardOutput))

        let wrongYAxisCylinder = try responseData(
            for: "CYL-003",
            action: cylinder003Action(
                name: "CYL-003.wrong-axis",
                axis: CADDirection3D(x: 0, y: 0, z: 1)
            )
        )
        let wrongYAxisCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongYAxisCylinder
        )
        let wrongYAxisCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongYAxisCylinderResult.standardOutputData
        )
        #expect(wrongYAxisCylinderResult.terminationStatus == 2)
        #expect(wrongYAxisCylinderEvaluation.caseID == "CYL-003")
        #expect(wrongYAxisCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongYAxisCylinderEvaluation.error == nil)
        #expect(isPrivateFree(wrongYAxisCylinderResult.standardOutput))

        let reversedZCylinder = try responseData(
            for: "CYL-004",
            action: cylinder004Action(
                name: "CYL-004.reversed-axis",
                axis: CADDirection3D(x: 0, y: 0, z: 1)
            )
        )
        let reversedZCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: reversedZCylinder
        )
        let reversedZCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: reversedZCylinderResult.standardOutputData
        )
        #expect(reversedZCylinderResult.terminationStatus == 2)
        #expect(reversedZCylinderEvaluation.caseID == "CYL-004")
        #expect(reversedZCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(reversedZCylinderEvaluation.error == nil)
        #expect(isPrivateFree(reversedZCylinderResult.standardOutput))

        let wrongDiagonalCylinder = try responseData(
            for: "CYL-005",
            action: cylinder005Action(
                name: "CYL-005.wrong-axis",
                axis: CADDirection3D(x: 1, y: 0, z: 0)
            )
        )
        let wrongDiagonalCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongDiagonalCylinder
        )
        let wrongDiagonalCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongDiagonalCylinderResult.standardOutputData
        )
        #expect(wrongDiagonalCylinderResult.terminationStatus == 2)
        #expect(wrongDiagonalCylinderEvaluation.caseID == "CYL-005")
        #expect(wrongDiagonalCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongDiagonalCylinderEvaluation.error == nil)
        #expect(isPrivateFree(wrongDiagonalCylinderResult.standardOutput))

        let wrongYZCylinder = try responseData(
            for: "CYL-006",
            action: cylinder006Action(
                name: "CYL-006.wrong-axis",
                axis: CADDirection3D(x: 0, y: 1, z: 0)
            )
        )
        let wrongYZCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongYZCylinder
        )
        let wrongYZCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongYZCylinderResult.standardOutputData
        )
        #expect(wrongYZCylinderResult.terminationStatus == 2)
        #expect(wrongYZCylinderEvaluation.caseID == "CYL-006")
        #expect(wrongYZCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongYZCylinderEvaluation.error == nil)
        #expect(isPrivateFree(wrongYZCylinderResult.standardOutput))

        let wrongUnitCylinder = try responseData(
            for: "CYL-007",
            action: cylinder007Action(
                name: "CYL-007.wrong-unit",
                unit: .millimeter
            )
        )
        let wrongUnitCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongUnitCylinder
        )
        let wrongUnitCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongUnitCylinderResult.standardOutputData
        )
        #expect(wrongUnitCylinderResult.terminationStatus == 2)
        #expect(wrongUnitCylinderEvaluation.caseID == "CYL-007")
        #expect(wrongUnitCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongUnitCylinderEvaluation.error == nil)
        #expect(isPrivateFree(wrongUnitCylinderResult.standardOutput))

        let wrongThreeAxisCylinder = try responseData(
            for: "CYL-008",
            action: cylinder008Action(
                name: "CYL-008.wrong-axis",
                axis: CADDirection3D(
                    x: 0.57735026919,
                    y: 0.57735026919,
                    z: -0.57735026919
                )
            )
        )
        let wrongThreeAxisCylinderResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongThreeAxisCylinder
        )
        let wrongThreeAxisCylinderEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongThreeAxisCylinderResult.standardOutputData
        )
        #expect(wrongThreeAxisCylinderResult.terminationStatus == 2)
        #expect(wrongThreeAxisCylinderEvaluation.caseID == "CYL-008")
        #expect(wrongThreeAxisCylinderEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongThreeAxisCylinderEvaluation.error == nil)
        #expect(isPrivateFree(wrongThreeAxisCylinderResult.standardOutput))

        let wrongConstraint = try responseData(
            for: "CON-001",
            action: constraint001Action(name: "CON-001.wrong", firstStartX: 10)
        )
        let wrongConstraintResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongConstraint
        )
        let wrongConstraintEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongConstraintResult.standardOutputData
        )
        #expect(wrongConstraintResult.terminationStatus == 2)
        #expect(wrongConstraintEvaluation.caseID == "CON-001")
        #expect(wrongConstraintEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongConstraintEvaluation.error == nil)
        #expect(isPrivateFree(wrongConstraintResult.standardOutput))

        let wrongTranslatedBox = try responseData(
            for: "BOX-002",
            action: box002Action(name: "BOX-002.wrong-origin", originX: 25)
        )
        let wrongTranslatedBoxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongTranslatedBox
        )
        let wrongTranslatedBoxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongTranslatedBoxResult.standardOutputData
        )
        #expect(wrongTranslatedBoxResult.terminationStatus == 2)
        #expect(wrongTranslatedBoxEvaluation.caseID == "BOX-002")
        #expect(wrongTranslatedBoxEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongTranslatedBoxEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongTranslatedBoxResult.standardOutputData))
        #expect(isPrivateFree(wrongTranslatedBoxResult.standardOutput))

        let wrongRectangularBox = try responseData(
            for: "BOX-003",
            action: box003Action(
                name: "BOX-003.wrong-depth-height",
                depth: 20,
                height: 30
            )
        )
        let wrongRectangularBoxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongRectangularBox
        )
        let wrongRectangularBoxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongRectangularBoxResult.standardOutputData
        )
        #expect(wrongRectangularBoxResult.terminationStatus == 2)
        #expect(wrongRectangularBoxEvaluation.caseID == "BOX-003")
        #expect(wrongRectangularBoxEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongRectangularBoxEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongRectangularBoxResult.standardOutputData))
        #expect(isPrivateFree(wrongRectangularBoxResult.standardOutput))

        let wrongTranslatedRectangularBox = try responseData(
            for: "BOX-004",
            action: box004Action(name: "BOX-004.wrong-origin-z", originZ: 0)
        )
        let wrongTranslatedRectangularBoxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongTranslatedRectangularBox
        )
        let wrongTranslatedRectangularBoxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongTranslatedRectangularBoxResult.standardOutputData
        )
        #expect(wrongTranslatedRectangularBoxResult.terminationStatus == 2)
        #expect(wrongTranslatedRectangularBoxEvaluation.caseID == "BOX-004")
        #expect(wrongTranslatedRectangularBoxEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongTranslatedRectangularBoxEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongTranslatedRectangularBoxResult.standardOutputData))
        #expect(isPrivateFree(wrongTranslatedRectangularBoxResult.standardOutput))

        let wrongLargeRectangularBox = try responseData(
            for: "BOX-005",
            action: box005Action(name: "BOX-005.wrong-height", height: 100)
        )
        let wrongLargeRectangularBoxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongLargeRectangularBox
        )
        let wrongLargeRectangularBoxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongLargeRectangularBoxResult.standardOutputData
        )
        #expect(wrongLargeRectangularBoxResult.terminationStatus == 2)
        #expect(wrongLargeRectangularBoxEvaluation.caseID == "BOX-005")
        #expect(wrongLargeRectangularBoxEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongLargeRectangularBoxEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongLargeRectangularBoxResult.standardOutputData))
        #expect(isPrivateFree(wrongLargeRectangularBoxResult.standardOutput))

        let wrongMeterScaleBox = try responseData(
            for: "BOX-006",
            action: box006Action(
                name: "BOX-006.wrong-unit",
                unit: .centimeter
            )
        )
        let wrongMeterScaleBoxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongMeterScaleBox
        )
        let wrongMeterScaleBoxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongMeterScaleBoxResult.standardOutputData
        )
        #expect(wrongMeterScaleBoxResult.terminationStatus == 2)
        #expect(wrongMeterScaleBoxEvaluation.caseID == "BOX-006")
        #expect(wrongMeterScaleBoxEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongMeterScaleBoxEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongMeterScaleBoxResult.standardOutputData))
        #expect(isPrivateFree(wrongMeterScaleBoxResult.standardOutput))

        let wrongImperialBox = try responseData(
            for: "BOX-007",
            action: box007Action(
                name: "BOX-007.wrong-unit",
                unit: .millimeter
            )
        )
        let wrongImperialBoxResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongImperialBox
        )
        let wrongImperialBoxEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongImperialBoxResult.standardOutputData
        )
        #expect(wrongImperialBoxResult.terminationStatus == 2)
        #expect(wrongImperialBoxEvaluation.caseID == "BOX-007")
        #expect(wrongImperialBoxEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongImperialBoxEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongImperialBoxResult.standardOutputData))
        #expect(isPrivateFree(wrongImperialBoxResult.standardOutput))

        let wrongTranslatedCube = try responseData(
            for: "BOX-008",
            action: box008Action(
                name: "BOX-008.wrong-origin",
                originX: 0
            )
        )
        let wrongTranslatedCubeResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongTranslatedCube
        )
        let wrongTranslatedCubeEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongTranslatedCubeResult.standardOutputData
        )
        #expect(wrongTranslatedCubeResult.terminationStatus == 2)
        #expect(wrongTranslatedCubeEvaluation.caseID == "BOX-008")
        #expect(wrongTranslatedCubeEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongTranslatedCubeEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongTranslatedCubeResult.standardOutputData))
        #expect(isPrivateFree(wrongTranslatedCubeResult.standardOutput))

        let wrongNegativePlacementCube = try responseData(
            for: "BOX-009",
            action: box009Action(
                name: "BOX-009.wrong-height",
                height: 10
            )
        )
        let wrongNegativePlacementCubeResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongNegativePlacementCube
        )
        let wrongNegativePlacementCubeEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongNegativePlacementCubeResult.standardOutputData
        )
        #expect(wrongNegativePlacementCubeResult.terminationStatus == 2)
        #expect(wrongNegativePlacementCubeEvaluation.caseID == "BOX-009")
        #expect(wrongNegativePlacementCubeEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongNegativePlacementCubeEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongNegativePlacementCubeResult.standardOutputData))
        #expect(isPrivateFree(wrongNegativePlacementCubeResult.standardOutput))

        let wrongRectangularSolid = try responseData(
            for: "BOX-010",
            action: box010Action(
                name: "BOX-010.swapped-width-depth",
                width: 200,
                depth: 400
            )
        )
        let wrongRectangularSolidResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongRectangularSolid
        )
        let wrongRectangularSolidEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongRectangularSolidResult.standardOutputData
        )
        #expect(wrongRectangularSolidResult.terminationStatus == 2)
        #expect(wrongRectangularSolidEvaluation.caseID == "BOX-010")
        #expect(wrongRectangularSolidEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongRectangularSolidEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongRectangularSolidResult.standardOutputData))
        #expect(isPrivateFree(wrongRectangularSolidResult.standardOutput))

        let wrongMetreCube = try responseData(
            for: "BOX-011",
            action: box011Action(
                name: "BOX-011.wrong-unit",
                unit: .centimeter
            )
        )
        let wrongMetreCubeResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongMetreCube
        )
        let wrongMetreCubeEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongMetreCubeResult.standardOutputData
        )
        #expect(wrongMetreCubeResult.terminationStatus == 2)
        #expect(wrongMetreCubeEvaluation.caseID == "BOX-011")
        #expect(wrongMetreCubeEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongMetreCubeEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongMetreCubeResult.standardOutputData))
        #expect(isPrivateFree(wrongMetreCubeResult.standardOutput))

        let wrongMillimeterSolid = try responseData(
            for: "BOX-012",
            action: box012Action(
                name: "BOX-012.wrong-z",
                originZ: -50
            )
        )
        let wrongMillimeterSolidResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: wrongMillimeterSolid
        )
        let wrongMillimeterSolidEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: wrongMillimeterSolidResult.standardOutputData
        )
        #expect(wrongMillimeterSolidResult.terminationStatus == 2)
        #expect(wrongMillimeterSolidEvaluation.caseID == "BOX-012")
        #expect(wrongMillimeterSolidEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongMillimeterSolidEvaluation.error == nil)
        #expect(isSingleJSONObject(wrongMillimeterSolidResult.standardOutputData))
        #expect(isPrivateFree(wrongMillimeterSolidResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func malformedOversizeSchemaFingerprintInactiveAndNonActionResponsesHaveStableOutcomes() throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "LIN-001")
        let validResponse = try responseData(
            for: "LIN-001",
            contextFingerprint: request.contextFingerprint,
            action: lineAction(name: "LIN-001")
        )

        let malformed = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: Data("{".utf8)
        )
        try assertError(malformed, code: .malformedJSON, exit: 64, caseID: nil)

        let oversize = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: Data(repeating: 0x20, count: CADJSONAdapterSchema.maximumDocumentBytes + 1)
        )
        try assertError(oversize, code: .oversizedInput, exit: 64, caseID: nil)

        for legacySchema in [
            "rupa.agent-cad-benchmark.candidate-response.v1",
            "rupa.agent-cad-benchmark.candidate-response.v2",
            "rupa.agent-cad-benchmark.candidate-response.v3",
            "rupa.agent-cad-benchmark.candidate-response.v4",
            "rupa.agent-cad-benchmark.candidate-response.v5",
            "rupa.agent-cad-benchmark.candidate-response.v6",
        ] {
            let schemaMismatch = replacing(
                validResponse,
                from: CADJSONAdapterSchema.candidateResponse,
                to: legacySchema
            )
            let schemaResult = try runCADBenchmarkCLI(
                ["evaluate", "--response", "-"],
                standardInput: schemaMismatch
            )
            try assertError(schemaResult, code: .unsupportedSchema, exit: 64, caseID: nil)
        }

        let fingerprintMismatch = try responseData(
            for: "LIN-001",
            contextFingerprint: String(repeating: "0", count: 64),
            action: lineAction(name: "LIN-001")
        )
        let fingerprintResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: fingerprintMismatch
        )
        try assertError(fingerprintResult, code: .fingerprintMismatch, exit: 64, caseID: "LIN-001")

        let inactiveResponse = try responseData(
            for: "TRN-003",
            contextFingerprint: String(repeating: "0", count: 64),
            action: constraint001Action(name: "TRN-003")
        )
        let inactiveResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: inactiveResponse
        )
        try assertError(inactiveResult, code: .inactiveCase, exit: 64, caseID: "TRN-003")

        let finishResponse = try finishResponseData(for: request)
        let finishResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: finishResponse
        )
        let finishEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: finishResult.standardOutputData
        )
        #expect(finishResult.terminationStatus == 2)
        #expect(finishEvaluation.result?.outcome == .invalidSubmission)
        #expect(finishEvaluation.error == nil)
        #expect(isPrivateFree(finishResult.standardOutput))

        let unsupportedResponse = try unsupportedResponseData(for: request)
        let unsupportedResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: unsupportedResponse
        )
        let unsupportedEvaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: unsupportedResult.standardOutputData
        )
        #expect(unsupportedResult.terminationStatus == 2)
        #expect(unsupportedEvaluation.result?.outcome == .invalidSubmission)
        #expect(unsupportedEvaluation.error == nil)
        #expect(isPrivateFree(unsupportedResult.standardOutput))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func malformedUTF8TrailingDirectoryAndMissingInputRemainBoundedPrivateFreeErrors() throws {
        let malformedUTF8 = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: Data([0xFF])
        )
        try assertError(malformedUTF8, code: .malformedUTF8, exit: 64, caseID: nil)

        let trailing = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: Data(#"{} {}"#.utf8)
        )
        try assertError(trailing, code: .trailingData, exit: 64, caseID: nil)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rupa-agent-cad-benchmark-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("Failed to remove temporary CLI directory.")
            }
        }
        let directoryResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", directory.path]
        )
        try assertError(directoryResult, code: .directoryInput, exit: 64, caseID: nil)

        let missingResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", directory.appendingPathComponent("missing.json").path]
        )
        try assertError(missingResult, code: .inputFailure, exit: 64, caseID: nil)
    }

    @MainActor
    private func responseData(
        for rawCaseID: String,
        action: CADCandidateAction
    ) throws -> Data {
        let request = try CADJSONAdapter().makeRequest(
            for: CADBenchmarkCaseID(validating: rawCaseID)
        )
        return try responseData(
            for: rawCaseID,
            contextFingerprint: request.contextFingerprint,
            action: action
        )
    }

    @MainActor
    private func responseData(
        for rawCaseID: String,
        contextFingerprint: String,
        action: CADCandidateAction
    ) throws -> Data {
        try responseData(
            for: rawCaseID,
            contextFingerprint: contextFingerprint,
            decision: .action(action)
        )
    }

    @MainActor
    private func responseData(
        for rawCaseID: String,
        contextFingerprint: String,
        decision: CADCandidateDecision
    ) throws -> Data {
        let response = try CADJSONCandidateResponseEnvelope(
            schema: CADJSONAdapterSchema.candidateResponse,
            caseID: try CADBenchmarkCaseID(validating: rawCaseID),
            contextFingerprint: contextFingerprint,
            decision: decision
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(response)
    }

    @MainActor
    private func finishResponseData(
        for request: CADJSONRequestEnvelope
    ) throws -> Data {
        try responseData(
            for: request.caseID.rawValue,
            contextFingerprint: request.contextFingerprint,
            decision: .finish(CADOutputRoleBindings(bindings: []))
        )
    }

    @MainActor
    private func unsupportedResponseData(
        for request: CADJSONRequestEnvelope
    ) throws -> Data {
        try responseData(
            for: request.caseID.rawValue,
            contextFingerprint: request.contextFingerprint,
            decision: .unsupported(CADUnsupportedDeclaration(
                capabilityID: request.context.challenge.requiredCapability.id,
                capabilityVersion: request.context.challenge.requiredCapability.version,
                reason: .capabilityUnavailable
            ))
        )
    }

    private func assertRealizedEvaluation(
        _ process: CADBenchmarkCLIProcessResult,
        caseID: String
    ) throws {
        #expect(process.terminationStatus == 0, Comment(rawValue: process.standardError))
        #expect(process.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        let evaluation = try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: process.standardOutputData
        )
        #expect(evaluation.caseID.rawValue == caseID)
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)
        #expect(isSingleJSONObject(process.standardOutputData))
        #expect(isPrivateFree(process.standardOutput))
    }

    private func assertError(
        _ process: CADBenchmarkCLIProcessResult,
        code: CADJSONErrorCode,
        exit: Int32,
        caseID: String?
    ) throws {
        #expect(process.terminationStatus == exit, Comment(rawValue: process.standardError))
        #expect(process.standardOutputData.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        let error = try CADJSONBoundedCodec.decode(
            CADJSONErrorEnvelope.self,
            from: process.standardOutputData
        )
        #expect(error.code == code)
        #expect(error.caseID?.rawValue == caseID)
        #expect(isSingleJSONObject(process.standardOutputData))
        #expect(isPrivateFree(process.standardOutput))
    }

    private func withTemporaryData<Result>(
        _ data: Data,
        _ body: (String) throws -> Result
    ) throws -> Result {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("rupa-agent-cad-benchmark-response-\(UUID().uuidString).json")
        try data.write(to: path, options: .atomic)
        defer {
            do {
                try FileManager.default.removeItem(at: path)
            } catch {
                Issue.record("Failed to remove temporary CLI response.")
            }
        }
        return try body(path.path)
    }
}

private func transform001Action(
    translationX: Double = 25,
    axis: CADDirection3D = CADDirection3D(x: 0, y: 0, z: 1)
) -> CADCandidateAction {
    .automation(.transform(CADTransformAction(
        translation: CADPoint3D(x: translationX, y: 0, z: 0, unit: .millimeter),
        axisPoint: CADPoint3D(x: 50, y: 0, z: 0, unit: .millimeter),
        rotationAxis: axis,
        rotation: CADAngle(value: 30, unit: .degree)
    )))
}

private func transform002Action(
    translationX: Double = 0,
    translationY: Double = 25,
    axis: CADDirection3D = CADDirection3D(x: 0, y: 0, z: 1)
) -> CADCandidateAction {
    .automation(.transform(CADTransformAction(
        translation: CADPoint3D(
            x: translationX,
            y: translationY,
            z: 0,
            unit: .millimeter
        ),
        axisPoint: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        rotationAxis: axis,
        rotation: CADAngle(value: 45, unit: .degree)
    )))
}

private func box001Action(name: String, width: Double = 10) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: 10, unit: .millimeter),
        height: CADLength(value: 10, unit: .millimeter)
    )))
}

private func cylinder001Action(
    name: String,
    radius: Double = 5,
    depth: Double = 20
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
        axis: CADDirection3D(x: 0, y: 0, z: 1),
        radius: CADLength(value: radius, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter)
    )))
}

private func cylinder002Action(
    name: String,
    axis: CADDirection3D = CADDirection3D(x: 1, y: 0, z: 0)
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: 25, y: -25, z: 0, unit: .millimeter),
        axis: axis,
        radius: CADLength(value: 10, unit: .millimeter),
        depth: CADLength(value: 50, unit: .millimeter)
    )))
}

private func cylinder003Action(
    name: String,
    axis: CADDirection3D = CADDirection3D(x: 0, y: 1, z: 0)
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: -50, y: 20, z: 10, unit: .millimeter),
        axis: axis,
        radius: CADLength(value: 25, unit: .millimeter),
        depth: CADLength(value: 100, unit: .millimeter)
    )))
}

private func cylinder004Action(
    name: String,
    axis: CADDirection3D = CADDirection3D(x: 0, y: 0, z: -1)
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: 0, y: 0, z: -100, unit: .millimeter),
        axis: axis,
        radius: CADLength(value: 50, unit: .millimeter),
        depth: CADLength(value: 250, unit: .millimeter)
    )))
}

private func cylinder005Action(
    name: String,
    axis: CADDirection3D = CADDirection3D(
        x: 0.707106781187,
        y: 0.707106781187,
        z: 0
    )
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: 0, y: 0, z: 0, unit: .centimeter),
        axis: axis,
        radius: CADLength(value: 2, unit: .centimeter),
        depth: CADLength(value: 10, unit: .centimeter)
    )))
}

private func cylinder006Action(
    name: String,
    axis: CADDirection3D = CADDirection3D(
        x: 0,
        y: 0.707106781187,
        z: 0.707106781187
    )
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: -0.1, y: 0.05, z: 0, unit: .meter),
        axis: axis,
        radius: CADLength(value: 0.05, unit: .meter),
        depth: CADLength(value: 0.2, unit: .meter)
    )))
}

private func cylinder007Action(
    name: String,
    unit: CADLengthUnit = .inch,
    axis: CADDirection3D = CADDirection3D(x: -1, y: 0, z: 0)
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: 2, y: 3, z: -1, unit: unit),
        axis: axis,
        radius: CADLength(value: 1, unit: unit),
        depth: CADLength(value: 4, unit: unit)
    )))
}

private func cylinder008Action(
    name: String,
    axis: CADDirection3D = CADDirection3D(
        x: 0.57735026919,
        y: 0.57735026919,
        z: 0.57735026919
    )
) -> CADCandidateAction {
    .automation(.solid(.cylinder(
        name: name,
        baseCenter: CADPoint3D(x: 100, y: 100, z: 100, unit: .millimeter),
        axis: axis,
        radius: CADLength(value: 75, unit: .millimeter),
        depth: CADLength(value: 150, unit: .millimeter)
    )))
}

private func constraint001Action(
    name: String,
    firstStartX: Double = 20,
    secondEndY: Double = 20
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: .coincident,
        first: .line(
            start: CADPoint3D(x: firstStartX, y: 0, z: 0),
            end: CADPoint3D(x: 0, y: 20, z: 0)
        ),
        second: .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 0, y: secondEndY, z: 0)
        )
    ))))
}

private func constraint002Action(
    name: String,
    relation: CADConstraintRelation = .parallel
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 40, y: 0, z: 0)
        ),
        second: .line(
            start: CADPoint3D(x: 0, y: 10, z: 0),
            end: CADPoint3D(x: 50, y: 10, z: 0)
        )
    ))))
}

private func constraint003Action(
    name: String,
    relation: CADConstraintRelation = .perpendicular,
    firstEndX: Double = 30
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: firstEndX, y: 0, z: 0)
        ),
        second: .line(
            start: CADPoint3D(x: 0, y: 15, z: 0),
            end: CADPoint3D(x: 0, y: 45, z: 0)
        )
    ))))
}

private func constraint004Action(
    name: String,
    relation: CADConstraintRelation = .horizontal
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 25, y: 0, z: 0)
        )
    ))))
}

private func constraint005Action(
    name: String,
    relation: CADConstraintRelation = .vertical,
    includeSecond: Bool = false
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 0, y: 25, z: 0)
        ),
        second: includeSecond ? .line(
            start: CADPoint3D(x: 10, y: 0, z: 0),
            end: CADPoint3D(x: 10, y: 25, z: 0)
        ) : nil
    ))))
}

private func constraint006Action(
    name: String,
    relation: CADConstraintRelation = .equalLength,
    secondEndX: Double = 50
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .line(
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 50, y: 0, z: 0)
        ),
        second: .line(
            start: CADPoint3D(x: 0, y: 10, z: 0),
            end: CADPoint3D(x: secondEndX, y: 10, z: 0)
        )
    ))))
}

private func constraint007Action(
    name: String,
    relation: CADConstraintRelation = .concentric,
    firstRadius: Double = 10,
    secondRadius: Double = 25
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .circle(
            center: CADPoint3D(x: 0, y: 0, z: 0),
            radius: CADLength(value: firstRadius, unit: .millimeter)
        ),
        second: .circle(
            center: CADPoint3D(x: 0, y: 0, z: 0),
            radius: CADLength(value: secondRadius, unit: .millimeter)
        )
    ))))
}

private func constraint008Action(
    name: String,
    relation: CADConstraintRelation = .equalRadius,
    secondCenterX: Double = 50,
    secondRadius: Double = 15
) -> CADCandidateAction {
    .automation(.sketch(.constraint(CADConstraintAction(
        name: name,
        plane: .xy,
        relation: relation,
        first: .circle(
            center: CADPoint3D(x: 0, y: 0, z: 0),
            radius: CADLength(value: 15, unit: .millimeter)
        ),
        second: .circle(
            center: CADPoint3D(x: secondCenterX, y: 0, z: 0),
            radius: CADLength(value: secondRadius, unit: .millimeter)
        )
    ))))
}

private func box002Action(
    name: String,
    originX: Double = 20,
    originY: Double = -20,
    originZ: Double = 0,
    width: Double = 25,
    depth: Double = 25,
    height: Double = 25
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box003Action(
    name: String,
    originX: Double = -25,
    originY: Double = 15,
    originZ: Double = 5,
    width: Double = 50,
    depth: Double = 30,
    height: Double = 20
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box004Action(
    name: String,
    originX: Double = 0,
    originY: Double = 0,
    originZ: Double = -25,
    width: Double = 100,
    depth: Double = 50,
    height: Double = 75
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box005Action(
    name: String,
    originX: Double = -125,
    originY: Double = -50,
    originZ: Double = 0,
    width: Double = 250,
    depth: Double = 100,
    height: Double = 125
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box006Action(
    name: String,
    unit: CADLengthUnit = .meter,
    originX: Double = 0,
    originY: Double = 0,
    originZ: Double = 0,
    width: Double = 0.1,
    depth: Double = 0.05,
    height: Double = 0.025
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: unit),
        width: CADLength(value: width, unit: unit),
        depth: CADLength(value: depth, unit: unit),
        height: CADLength(value: height, unit: unit)
    )))
}

private func box007Action(
    name: String,
    unit: CADLengthUnit = .inch,
    originX: Double = -1,
    originY: Double = -1,
    originZ: Double = 0,
    width: Double = 1,
    depth: Double = 2,
    height: Double = 3
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: unit),
        width: CADLength(value: width, unit: unit),
        depth: CADLength(value: depth, unit: unit),
        height: CADLength(value: height, unit: unit)
    )))
}

private func box008Action(
    name: String,
    originX: Double = 100,
    originY: Double = 100,
    originZ: Double = 100,
    width: Double = 300,
    depth: Double = 300,
    height: Double = 300
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box009Action(
    name: String,
    originX: Double = -12,
    originY: Double = 0,
    originZ: Double = 0,
    width: Double = 12,
    depth: Double = 12,
    height: Double = 12
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box010Action(
    name: String,
    originX: Double = 0,
    originY: Double = -100,
    originZ: Double = 50,
    width: Double = 400,
    depth: Double = 200,
    height: Double = 50
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func box011Action(
    name: String,
    unit: CADLengthUnit = .meter,
    originX: Double = -0.25,
    originY: Double = -0.25,
    originZ: Double = 0,
    width: Double = 0.5,
    depth: Double = 0.5,
    height: Double = 0.5
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: unit),
        width: CADLength(value: width, unit: unit),
        depth: CADLength(value: depth, unit: unit),
        height: CADLength(value: height, unit: unit)
    )))
}

private func box012Action(
    name: String,
    originX: Double = 25,
    originY: Double = 25,
    originZ: Double = -75,
    width: Double = 75,
    depth: Double = 125,
    height: Double = 175
) -> CADCandidateAction {
    .automation(.solid(.box(
        name: name,
        origin: CADPoint3D(x: originX, y: originY, z: originZ, unit: .millimeter),
        width: CADLength(value: width, unit: .millimeter),
        depth: CADLength(value: depth, unit: .millimeter),
        height: CADLength(value: height, unit: .millimeter)
    )))
}

private func lineAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.line(
        name: name,
        plane: .xy,
        start: CADPoint3D(x: 0, y: 0, z: 0),
        end: CADPoint3D(x: 25, y: 0, z: 0)
    )))
}

private func rectangleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.rectangle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 0, y: 0, z: 0),
        width: CADLength(value: 40),
        height: CADLength(value: 20)
    )))
}

private func circleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 0, y: 0, z: 0),
        radius: CADLength(value: 5)
    )))
}

private func angleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter),
        firstEnd: CADPoint3D(x: 15, y: 0, z: 35, unit: .millimeter),
        secondStart: CADPoint3D(x: 0, y: 0, z: 35, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 25 * 0.866025403784,
            y: 12.5,
            z: 35,
            unit: .millimeter
        )
    )))
}

private func angle002Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 10, y: -10, z: 50, unit: .millimeter),
        firstEnd: CADPoint3D(x: 40, y: -10, z: 50, unit: .millimeter),
        secondStart: CADPoint3D(x: 10, y: -10, z: 50, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 10 + 50 * 0.707106781187,
            y: -10 + 50 * 0.707106781187,
            z: 50,
            unit: .millimeter
        )
    )))
}

private func angle003Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: -25, y: 15, z: 125, unit: .millimeter),
        firstEnd: CADPoint3D(x: 20, y: 15, z: 125, unit: .millimeter),
        secondStart: CADPoint3D(x: -25, y: 15, z: 125, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: -25 + 75 * 0.5,
            y: 15 + 75 * 0.866025403784,
            z: 125,
            unit: .millimeter
        )
    )))
}

private func angle004Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 30, y: 25, z: 150, unit: .millimeter),
        firstEnd: CADPoint3D(x: 90, y: 25, z: 150, unit: .millimeter),
        secondStart: CADPoint3D(x: 30, y: 25, z: 150, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 30 + 100 * 0.258819045103,
            y: 25 + 100 * 0.965925826289,
            z: 150,
            unit: .millimeter
        )
    )))
}

private func angle005Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 0, y: 0, z: 200, unit: .millimeter),
        firstEnd: CADPoint3D(x: 75, y: 0, z: 200, unit: .millimeter),
        secondStart: CADPoint3D(x: 0, y: 0, z: 200, unit: .millimeter),
        secondEnd: CADPoint3D(x: 0, y: 125, z: 200, unit: .millimeter)
    )))
}

private func angle006Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: -50, y: 40, z: 250, unit: .millimeter),
        firstEnd: CADPoint3D(x: 40, y: 40, z: 250, unit: .millimeter),
        secondStart: CADPoint3D(x: -50, y: 40, z: 250, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: -50 - 150 * 0.258819045103,
            y: 40 + 150 * 0.965925826289,
            z: 250,
            unit: .millimeter
        )
    )))
}

private func angle007Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 20, y: -35, z: 300, unit: .millimeter),
        firstEnd: CADPoint3D(x: 125, y: -35, z: 300, unit: .millimeter),
        secondStart: CADPoint3D(x: 20, y: -35, z: 300, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 20 - 200 * 0.5,
            y: -35 + 200 * 0.866025403784,
            z: 300,
            unit: .millimeter
        )
    )))
}

private func angle008Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 0, y: 0, z: 350, unit: .millimeter),
        firstEnd: CADPoint3D(x: 120, y: 0, z: 350, unit: .millimeter),
        secondStart: CADPoint3D(x: 0, y: 0, z: 350, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: -250 * 0.707106781187,
            y: 250 * 0.707106781187,
            z: 350,
            unit: .millimeter
        )
    )))
}

private func angle009Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: 75, y: 50, z: 400, unit: .millimeter),
        firstEnd: CADPoint3D(x: 210, y: 50, z: 400, unit: .millimeter),
        secondStart: CADPoint3D(x: 75, y: 50, z: 400, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 75 - 300 * 0.866025403784,
            y: 50 + 300 * 0.5,
            z: 400,
            unit: .millimeter
        )
    )))
}

private func angle010Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xy,
        firstStart: CADPoint3D(x: -75, y: -50, z: 450, unit: .millimeter),
        firstEnd: CADPoint3D(x: 75, y: -50, z: 450, unit: .millimeter),
        secondStart: CADPoint3D(x: -75, y: -50, z: 450, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: -75 - 350 * 0.965925826289,
            y: -50 + 350 * 0.258819045103,
            z: 450,
            unit: .millimeter
        )
    )))
}

private func angle011Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xz,
        firstStart: CADPoint3D(x: 0, y: 0, z: 80, unit: .millimeter),
        firstEnd: CADPoint3D(x: 30, y: 0, z: 80, unit: .millimeter),
        secondStart: CADPoint3D(x: 0, y: 0, z: 80, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 60 * 0.707106781187,
            y: 0,
            z: 80 + 60 * 0.707106781187,
            unit: .millimeter
        )
    )))
}

private func angle012Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .yz,
        firstStart: CADPoint3D(x: 10, y: -20, z: 120, unit: .millimeter),
        firstEnd: CADPoint3D(x: 10, y: 20, z: 120, unit: .millimeter),
        secondStart: CADPoint3D(x: 10, y: -20, z: 120, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 10,
            y: -20 + 100 * 0.5,
            z: 120 + 100 * 0.866025403784,
            unit: .millimeter
        )
    )))
}

private func angle013Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xz,
        firstStart: CADPoint3D(x: -15, y: 25, z: 180, unit: .millimeter),
        firstEnd: CADPoint3D(x: 35, y: 25, z: 180, unit: .millimeter),
        secondStart: CADPoint3D(x: -15, y: 25, z: 180, unit: .millimeter),
        secondEnd: CADPoint3D(x: -15, y: 25, z: 330, unit: .millimeter)
    )))
}

private func angle014Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .yz,
        firstStart: CADPoint3D(x: -25, y: 30, z: 275, unit: .millimeter),
        firstEnd: CADPoint3D(x: -25, y: 105, z: 275, unit: .millimeter),
        secondStart: CADPoint3D(x: -25, y: 30, z: 275, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: -25,
            y: 30 - 225 * 0.5,
            z: 275 + 225 * 0.866025403784,
            unit: .millimeter
        )
    )))
}

private func angle015Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .xz,
        firstStart: CADPoint3D(x: 40, y: -40, z: 325, unit: .millimeter),
        firstEnd: CADPoint3D(x: 140, y: -40, z: 325, unit: .millimeter),
        secondStart: CADPoint3D(x: 40, y: -40, z: 325, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 40 - 300 * 0.707106781187,
            y: -40,
            z: 325 + 300 * 0.707106781187,
            unit: .millimeter
        )
    )))
}

private func angle016Action(name: String) -> CADCandidateAction {
    .automation(.sketch(.angle(
        name: name,
        plane: .yz,
        firstStart: CADPoint3D(x: 60, y: 60, z: 425, unit: .millimeter),
        firstEnd: CADPoint3D(x: 60, y: 185, z: 425, unit: .millimeter),
        secondStart: CADPoint3D(x: 60, y: 60, z: 425, unit: .millimeter),
        secondEnd: CADPoint3D(
            x: 60,
            y: 60 - 375 * 0.866025403784,
            z: 425 + 375 * 0.5,
            unit: .millimeter
        )
    )))
}

private func cir002CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 25, y: -10, z: 0, unit: .millimeter),
        radius: CADLength(value: 12.5, unit: .millimeter)
    )))
}

private func cir003CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xz,
        center: CADPoint3D(x: 0, y: 0, z: 50, unit: .millimeter),
        radius: CADLength(value: 25, unit: .millimeter)
    )))
}

private func cir004CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .yz,
        center: CADPoint3D(x: -75, y: 0, z: 0, unit: .millimeter),
        radius: CADLength(value: 50, unit: .millimeter)
    )))
}

private func cir005CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 100, y: 100, z: 0, unit: .millimeter),
        radius: CADLength(value: 100, unit: .millimeter)
    )))
}

private func cir006CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xz,
        center: CADPoint3D(x: 0, y: 0, z: 20, unit: .centimeter),
        radius: CADLength(value: 2, unit: .centimeter)
    )))
}

private func cir007CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .yz,
        center: CADPoint3D(x: 0, y: -0.1, z: 0, unit: .meter),
        radius: CADLength(value: 0.1, unit: .meter)
    )))
}

private func cir008CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: -2, y: 3, z: 0, unit: .inch),
        radius: CADLength(value: 1, unit: .inch)
    )))
}

private func cir009CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xz,
        center: CADPoint3D(x: 0, y: 0, z: -125, unit: .millimeter),
        radius: CADLength(value: 250, unit: .millimeter)
    )))
}

private func cir010CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 0.5, y: -0.5, z: 0, unit: .meter),
        radius: CADLength(value: 0.5, unit: .meter)
    )))
}

private func cir011CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .yz,
        center: CADPoint3D(x: 20, y: 0, z: 30, unit: .millimeter),
        radius: CADLength(value: 7.25, unit: .millimeter)
    )))
}

private func cir012CircleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: -80, y: 45, z: 0, unit: .millimeter),
        radius: CADLength(value: 42, unit: .millimeter)
    )))
}

private func rec009RectangleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.rectangle(
        name: name,
        plane: .xz,
        center: CADPoint3D(x: 0, y: 0, z: 0, unit: .inch),
        width: CADLength(value: 1, unit: .inch),
        height: CADLength(value: 0.5, unit: .inch)
    )))
}

private func rec010RectangleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.rectangle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 0, y: 0, z: 0, unit: .meter),
        width: CADLength(value: 2, unit: .meter),
        height: CADLength(value: 1, unit: .meter)
    )))
}

private func rec011RectangleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.rectangle(
        name: name,
        plane: .yz,
        center: CADPoint3D(x: 0, y: 15, z: -15, unit: .millimeter),
        width: CADLength(value: 35, unit: .millimeter),
        height: CADLength(value: 35, unit: .millimeter)
    )))
}

private func rec012RectangleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.rectangle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: -100, y: -40, z: 0, unit: .millimeter),
        width: CADLength(value: 750, unit: .millimeter),
        height: CADLength(value: 80, unit: .millimeter)
    )))
}

private func replacing(_ data: Data, from: String, to: String) -> Data {
    Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: from, with: to).utf8)
}

private func isSingleJSONObject(_ data: Data) -> Bool {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        return false
    }
    return object is [String: Any]
}

private func isPrivateFree(_ output: String) -> Bool {
    ["FeatureID", "diagnostics", "telemetry", "expectation", "workspace", "sourceSnapshot", "oracle"].allSatisfy {
        output.localizedCaseInsensitiveContains($0) == false
    }
}
