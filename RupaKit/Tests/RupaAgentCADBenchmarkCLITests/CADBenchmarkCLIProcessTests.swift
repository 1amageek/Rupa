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
    func requestEmitsBoundedLineAndRectangleObjectsAndRejectsInactiveCase() throws {
        for rawCaseID in ["LIN-001", "REC-001", "REC-009", "REC-010", "REC-011"] {
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

        let inactive = try runCADBenchmarkCLI(["request", "REC-012"])
        #expect(inactive.terminationStatus == 64)
        let error = try CADJSONBoundedCodec.decode(
            CADJSONErrorEnvelope.self,
            from: inactive.standardOutputData
        )
        #expect(error.code == .inactiveCase)
        #expect(error.caseID?.rawValue == "REC-012")
        #expect(isPrivateFree(inactive.standardOutput))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func validLineAndRectangleResponsesUseFileAndStandardInputRoutes() throws {
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

        let schemaMismatch = replacing(
            validResponse,
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v2"
        )
        let schemaResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: schemaMismatch
        )
        try assertError(schemaResult, code: .unsupportedSchema, exit: 64, caseID: nil)

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
            for: "REC-012",
            contextFingerprint: String(repeating: "0", count: 64),
            action: rectangleAction(name: "REC-012")
        )
        let inactiveResult = try runCADBenchmarkCLI(
            ["evaluate", "--response", "-"],
            standardInput: inactiveResponse
        )
        try assertError(inactiveResult, code: .inactiveCase, exit: 64, caseID: "REC-012")

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
