import Foundation
import CryptoKit
import Testing
import RupaAgentCADBenchmark
@testable import RupaAgentCADBenchmarkJSONAdapter

@Suite(.serialized)
struct CADJSONAdapterTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func goldenLineAndRectangleExchangeUsesTheProductionRoute() async throws {
        let adapter = CADJSONAdapter()

        let lineRequest = try adapter.makeRequest(for: "LIN-001")
        let lineAction = lineAction(name: "LIN-001")
        let lineResponse = try CADJSONCandidateResponseEnvelope(
            caseID: lineRequest.caseID,
            context: lineRequest.context,
            decision: .action(lineAction)
        )
        let lineResponseData = try CADJSONBoundedCodec.encode(lineResponse)
        let lineJSON = try #require(String(data: lineResponseData, encoding: .utf8))
        #expect(lineJSON.contains("\"schema\":\"\(CADJSONAdapterSchema.candidateResponse)\""))
        #expect(lineJSON.contains("\"kind\":\"line\""))
        #expect(lineJSON.contains("\"caseID\":\"LIN-001\""))
        #expect(try CADJSONBoundedCodec.decode(
            CADJSONCandidateResponseEnvelope.self,
            from: lineResponseData
        ) == lineResponse)

        let lineEvaluation = try await adapter.evaluate(responseData: lineResponseData)
        #expect(lineEvaluation.result?.outcome == .realized)
        #expect(lineEvaluation.error == nil)
        let lineEvaluationData = try adapter.encodeEvaluation(lineEvaluation)
        #expect(try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: lineEvaluationData
        ) == lineEvaluation)

        let rectangleRequest = try adapter.makeRequest(for: "REC-001")
        let rectangleAction = rectangleAction(name: "REC-001")
        let rectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: rectangleRequest.caseID,
            context: rectangleRequest.context,
            decision: .action(rectangleAction)
        )
        let rectangleResponseData = try CADJSONBoundedCodec.encode(rectangleResponse)
        let rectangleJSON = try #require(String(data: rectangleResponseData, encoding: .utf8))
        #expect(rectangleJSON.contains("\"kind\":\"rectangle\""))
        #expect(rectangleJSON.contains("\"caseID\":\"REC-001\""))
        #expect(try CADJSONBoundedCodec.decode(
            CADJSONCandidateResponseEnvelope.self,
            from: rectangleResponseData
        ) == rectangleResponse)

        let rectangleEvaluation = try await adapter.evaluate(responseData: rectangleResponseData)
        #expect(rectangleEvaluation.result?.outcome == .realized)
        #expect(rectangleEvaluation.error == nil)
        #expect(try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: adapter.encodeEvaluation(rectangleEvaluation)
        ) == rectangleEvaluation)
    }

    @MainActor
    @Test
    func goldenWireFixturesMatchTheCompleteDeterministicDocument() throws {
        let adapter = CADJSONAdapter()
        let lineRequest = try adapter.makeRequest(for: "LIN-001")
        let rectangleRequest = try adapter.makeRequest(for: "REC-001")
        let lineResponse = try CADJSONCandidateResponseEnvelope(
            caseID: "LIN-001",
            context: lineRequest.context,
            decision: .action(lineAction(name: "LIN-001"))
        )
        let rectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: "REC-001",
            context: rectangleRequest.context,
            decision: .action(rectangleAction(name: "REC-001"))
        )

        let lineEvaluation = try CADJSONEvaluationEnvelope(
            caseID: "LIN-001",
            contextFingerprint: "f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf",
            result: CADCaseResult(id: "LIN-001", category: .line, outcome: .realized)
        )
        let rectangleEvaluation = try CADJSONEvaluationEnvelope(
            caseID: "REC-001",
            contextFingerprint: "73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5",
            result: CADCaseResult(id: "REC-001", category: .rectangle, outcome: .realized)
        )

        let lineRequestFixture = #"{"caseID":"LIN-001","context":{"capabilities":{"statuses":[{"available":true,"id":"cad.sketch.line","version":"1"}],"version":"agent-capabilities.v1"},"challenge":{"budget":{"maximumActions":32,"maximumReadRecords":64,"maximumRounds":16},"category":"LIN","id":"LIN-001","instruction":"Construct LIN-001 as a finite line segment of length 25.0 mm from (0.0, 0.0, 0.0) mm to (25.0, 0.0, 0.0) mm on the XY-oriented plane through (0.0, 0.0, 0.0) mm.","outputRoles":[{"description":"The requested finite line segment.","name":"segment"}],"requiredCapability":{"id":"cad.sketch.line","version":"1"}},"priorResults":[],"remainingActions":32,"remainingRounds":16},"contextFingerprint":"f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf","schema":"rupa.agent-cad-benchmark.request.v1"}"#
        let rectangleRequestFixture = #"{"caseID":"REC-001","context":{"capabilities":{"statuses":[{"available":true,"id":"cad.sketch.rectangle","version":"1"}],"version":"agent-capabilities.v1"},"challenge":{"budget":{"maximumActions":32,"maximumReadRecords":64,"maximumRounds":16},"category":"REC","id":"REC-001","instruction":"Construct REC-001 as a rectangle of width 40.0 mm and height 20.0 mm centered at (0.0, 0.0, 0.0) mm on the xy plane.","outputRoles":[{"description":"The requested closed rectangle.","name":"rectangle"}],"requiredCapability":{"id":"cad.sketch.rectangle","version":"1"}},"priorResults":[],"remainingActions":32,"remainingRounds":16},"contextFingerprint":"73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5","schema":"rupa.agent-cad-benchmark.request.v1"}"#
        let lineResponseFixture = #"{"caseID":"LIN-001","contextFingerprint":"f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf","decision":{"action":{"automation":{"kind":"sketch","sketch":{"end":{"unit":"millimeter","x":25,"y":0,"z":0},"kind":"line","name":"LIN-001","plane":"xy","start":{"unit":"millimeter","x":0,"y":0,"z":0}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v1"}"#
        let rectangleResponseFixture = #"{"caseID":"REC-001","contextFingerprint":"73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5","decision":{"action":{"automation":{"kind":"sketch","sketch":{"center":{"unit":"millimeter","x":0,"y":0,"z":0},"height":{"unit":"millimeter","value":20},"kind":"rectangle","name":"REC-001","plane":"xy","width":{"unit":"millimeter","value":40}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v1"}"#
        let lineEvaluationFixture = #"{"caseID":"LIN-001","contextFingerprint":"f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf","result":{"category":"LIN","id":"LIN-001","outcome":"realized"},"schema":"rupa.agent-cad-benchmark.evaluation.v1"}"#
        let rectangleEvaluationFixture = #"{"caseID":"REC-001","contextFingerprint":"73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5","result":{"category":"REC","id":"REC-001","outcome":"realized"},"schema":"rupa.agent-cad-benchmark.evaluation.v1"}"#

        #expect(String(decoding: try CADJSONBoundedCodec.encode(lineRequest), as: UTF8.self) == lineRequestFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(rectangleRequest), as: UTF8.self) == rectangleRequestFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(lineResponse), as: UTF8.self) == lineResponseFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(rectangleResponse), as: UTF8.self) == rectangleResponseFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(lineEvaluation), as: UTF8.self) == lineEvaluationFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(rectangleEvaluation), as: UTF8.self) == rectangleEvaluationFixture)
    }

    @MainActor
    @Test
    func legacyNestedCaseIDWireShapeIsRejected() throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "LIN-001")
        let requestData = try CADJSONBoundedCodec.encode(request)
        let legacyRequest = replacing(
            requestData,
            from: "\"category\":\"LIN\",\"id\":\"LIN-001\"",
            to: "\"category\":\"LIN\",\"id\":{\"rawValue\":\"LIN-001\"}"
        )
        expectAdapterError(.malformedJSON) {
            _ = try CADJSONBoundedCodec.decode(CADJSONRequestEnvelope.self, from: legacyRequest)
        }

        let evaluation = try CADJSONEvaluationEnvelope(
            caseID: request.caseID,
            contextFingerprint: request.contextFingerprint,
            result: CADCaseResult(id: request.caseID, category: .line, outcome: .realized)
        )
        let evaluationData = try CADJSONBoundedCodec.encode(evaluation)
        let legacyEvaluation = replacing(
            evaluationData,
            from: "\"result\":{\"category\":\"LIN\",\"id\":\"LIN-001\"",
            to: "\"result\":{\"category\":\"LIN\",\"id\":{\"rawValue\":\"LIN-001\"}"
        )
        expectAdapterError(.malformedJSON) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONEvaluationEnvelope.self,
                from: legacyEvaluation
            )
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func requestAndLiveContextsAreValueEqualAndAllTwentyRequestsStayBounded() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let adapter = CADJSONAdapter(executor: executor)
        var largestRequest = 0

        for caseID in executor.activatedCaseIDs {
            let request = try adapter.makeRequest(for: caseID)
            let liveContext = try executor.context(for: caseID)
            #expect(request.context == liveContext)
            #expect(request.caseID == caseID)
            let data = try CADJSONBoundedCodec.encode(request)
            largestRequest = max(largestRequest, data.count)
            #expect(data.count < 16_384)

            let action: CADCandidateAction
            if caseID.category == .line {
                action = lineAction(name: caseID.rawValue)
            } else {
                action = rectangleAction(name: caseID.rawValue)
            }
            let response = try CADJSONCandidateResponseEnvelope(
                caseID: caseID,
                context: request.context,
                decision: .action(action)
            )
            #expect(try CADJSONBoundedCodec.encode(response).count < 16_384)
        }

        #expect(executor.activatedCaseIDs.count == 20)
        #expect(largestRequest < 16_384)
    }

    @MainActor
    @Test
    func activatedRequestSequenceHasAStableLengthPrefixedAggregateDigest() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let adapter = CADJSONAdapter(executor: executor)
        let expectedIDs = (1...12).map { String(format: "LIN-%03d", $0) }
            + (1...8).map { String(format: "REC-%03d", $0) }
        #expect(executor.activatedCaseIDs.map(\.rawValue) == expectedIDs)

        // Each activated record is case ID, request byte count, and request SHA-256, all length-prefixed.
        var aggregate = Data()
        for caseID in executor.activatedCaseIDs {
            let request = try adapter.encodeRequest(for: caseID)
            appendLengthPrefixed(Data(caseID.rawValue.utf8), to: &aggregate)
            appendLengthPrefixed(bigEndianBytes(UInt64(request.count)), to: &aggregate)
            appendLengthPrefixed(Data(SHA256.hash(data: request)), to: &aggregate)
        }

        #expect(sha256Hex(aggregate) == "1989b5499be40d18b1f3b8a5381b9b0a0f28c53bf9de975d8c0251bc1a7e509e")
    }

    @MainActor
    @Test
    func contextFingerprintIsDomainSeparatedAndCanonical() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let context = try executor.context(for: "LIN-001")
        let first = try CADJSONContextFingerprint.value(for: context)
        let second = try CADJSONContextFingerprint.value(for: context)
        #expect(first == second)
        #expect(first.count == 64)
        #expect(first == first.lowercased())

        let changed = CADCandidateContext(
            challenge: context.challenge,
            capabilities: context.capabilities,
            priorResults: context.priorResults,
            remainingRounds: context.remainingRounds,
            remainingActions: context.remainingActions + 1
        )
        #expect(try CADJSONContextFingerprint.value(for: changed) != first)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongGeometryIsAValidatedResultAndDoesNotBecomeAdapterSuccess() async throws {
        let adapter = CADJSONAdapter()

        let lineRequest = try adapter.makeRequest(for: "LIN-001")
        let wrongLine = CADCandidateAction.automation(.sketch(.line(
            name: "wrong",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 24, y: 0, z: 0)
        )))
        let lineResponse = try CADJSONCandidateResponseEnvelope(
            caseID: "LIN-001",
            context: lineRequest.context,
            decision: .action(wrongLine)
        )
        let lineEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(lineResponse)
        )
        #expect(lineEvaluation.result?.outcome == .invalidSubmission)
        #expect(lineEvaluation.error == nil)

        let rectangleRequest = try adapter.makeRequest(for: "REC-001")
        let wrongRectangle = CADCandidateAction.automation(.sketch(.rectangle(
            name: "wrong",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0),
            width: CADLength(value: 20),
            height: CADLength(value: 40)
        )))
        let rectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: "REC-001",
            context: rectangleRequest.context,
            decision: .action(wrongRectangle)
        )
        let rectangleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(rectangleResponse)
        )
        #expect(rectangleEvaluation.result?.outcome == .invalidSubmission)
        #expect(rectangleEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func nonActionDecisionRemainsAnInvalidSubmissionResult() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "LIN-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .finish(CADOutputRoleBindings(bindings: []))
        )

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.result?.outcome == .invalidSubmission)
        #expect(evaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func preBindingSchemaCaseFingerprintAndInactiveFailuresAreTypedThrows() async throws {
        let adapter = CADJSONAdapter()
        let lineRequest = try adapter.makeRequest(for: "LIN-001")
        let action = lineAction(name: "LIN-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: lineRequest.caseID,
            context: lineRequest.context,
            decision: .action(action)
        )

        let validResponseData = try CADJSONBoundedCodec.encode(response)
        let unsupportedSchema = replacing(
            validResponseData,
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v0"
        )
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: unsupportedSchema
            )
        }

        do {
            _ = try await adapter.evaluate(response: response, for: "REC-001")
            Issue.record("A case mismatch must be rejected before executor evaluation.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .caseMismatch)
        }

        let wrongFingerprint = try CADJSONCandidateResponseEnvelope(
            schema: CADJSONAdapterSchema.candidateResponse,
            caseID: lineRequest.caseID,
            contextFingerprint: String(repeating: "0", count: 64),
            decision: .action(action)
        )
        do {
            _ = try await adapter.evaluate(response: wrongFingerprint)
            Issue.record("A fingerprint mismatch must be rejected before executor evaluation.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .fingerprintMismatch)
        }

        do {
            _ = try await adapter.evaluate(response: response, for: "REC-009")
            Issue.record("An inactive case must be rejected before context resolution.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .inactiveCase)
        }

        do {
            _ = try CADJSONCandidateResponseEnvelope(
                caseID: "REC-001",
                context: lineRequest.context,
                decision: .action(action)
            )
            Issue.record("A context/case mismatch must be rejected by the convenience initializer.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .caseMismatch)
        }
    }

    @Test
    func candidateRecomputesFingerprintAgainstLiveContext() async throws {
        let executor = await MainActor.run { DefaultCADActivatedCaseExecutor() }
        let request = try await MainActor.run {
            try executor.context(for: "LIN-001")
        }
        let action = lineAction(name: "LIN-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: "LIN-001",
            context: request,
            decision: .action(action)
        )
        let candidate = try CADJSONCandidate(response: response)
        let drifted = CADCandidateContext(
            challenge: request.challenge,
            capabilities: request.capabilities,
            priorResults: request.priorResults,
            remainingRounds: request.remainingRounds,
            remainingActions: request.remainingActions + 1
        )

        do {
            _ = try await candidate.decide(for: drifted)
            Issue.record("A live context drift must not be accepted by the candidate.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .fingerprintMismatch)
        }
    }

    @Test
    func malformedUTF8JSONTrailingDataAndLegacyDecisionShapesAreRejected() throws {
        let malformedUTF8 = Data([0x7B, 0xFF, 0x7D])
        expectAdapterError(.malformedUTF8) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: malformedUTF8
            )
        }

        expectAdapterError(.malformedJSON) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: Data(#"{"#.utf8)
            )
        }

        expectAdapterError(.trailingData) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: Data(#"{} {}"#.utf8)
            )
        }

        let legacy = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v1","caseID":"LIN-001","contextFingerprint":"0000000000000000000000000000000000000000000000000000000000000000","decision":{"action":{"automation":{"sketch":{"line":{"name":"legacy"}}}}}}"#.utf8)
        expectAdapterError(.invalidDecision) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: legacy
            )
        }

        let unknown = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v1","caseID":"LIN-001","contextFingerprint":"0000000000000000000000000000000000000000000000000000000000000000","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.invalidDecision) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: unknown
            )
        }
    }

    @Test
    func exactLimitAndLimitPlusOneAreRejectedBeforeDecode() throws {
        let tinyJSON = Data(#"{"schema":"rupa.agent-cad-benchmark.error.v1","code":"malformed_json","message":"Input is not valid JSON for the requested envelope."}"#.utf8)
        let exact = tinyJSON + Data(repeating: 0x20, count: CADJSONAdapterSchema.maximumDocumentBytes - tinyJSON.count)
        let decoded = try CADJSONBoundedCodec.decode(
            CADJSONErrorEnvelope.self,
            from: exact
        )
        #expect(decoded.caseID == nil)

        let over = exact + Data([0x20])
        expectAdapterError(.oversizedInput) {
            _ = try CADJSONBoundedCodec.decode(CADJSONErrorEnvelope.self, from: over)
        }
    }

    @Test
    func regularFileReaderRejectsDirectoriesAndPreservesOptionalCaseOnPreDecodeError() async throws {
        let directoryPath = FileManager.default.temporaryDirectory.path
        expectAdapterError(.directoryInput) {
            _ = try CADJSONBoundedCodec.readRegularFile(at: directoryPath)
        }

        expectAdapterError(.unsupportedInputSource) {
            _ = try CADJSONBoundedCodec.readRegularFile(at: "https://example.invalid/input.json")
        }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("rupa-json-adapter-\(UUID().uuidString)")
            .path
        defer {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                // The temporary file may already have been removed by the test host.
            }
        }
        let bytes = Data(repeating: 0x20, count: CADJSONAdapterSchema.maximumDocumentBytes + 1)
        guard FileManager.default.createFile(atPath: path, contents: bytes) else {
            Issue.record("The temporary bounded-input fixture could not be created.")
            return
        }
        expectAdapterError(.oversizedInput) {
            _ = try CADJSONBoundedCodec.readRegularFile(at: path)
        }

        let validPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("rupa-json-adapter-valid-\(UUID().uuidString)")
            .path
        defer {
            do {
                try FileManager.default.removeItem(atPath: validPath)
            } catch {
                // The temporary file may already have been removed by the test host.
            }
        }
        let validBytes = Data(#"{"ok":true}"#.utf8)
        guard FileManager.default.createFile(atPath: validPath, contents: validBytes) else {
            Issue.record("The temporary valid-input fixture could not be created.")
            return
        }
        #expect(try CADJSONBoundedCodec.readRegularFile(at: validPath) == validBytes)

        let exactPipe = Pipe()
        let exactBytes = Data(repeating: 0x20, count: CADJSONAdapterSchema.maximumDocumentBytes)
        let exactWriter = exactPipe.fileHandleForWriting
        let exactWrite = Task.detached {
            try exactWriter.write(contentsOf: exactBytes)
            try exactWriter.close()
        }
        #expect(
            try CADJSONBoundedCodec.readStandardInput(from: exactPipe.fileHandleForReading) == exactBytes
        )
        try await exactWrite.value

        let oversizedPipe = Pipe()
        let oversizedWriter = oversizedPipe.fileHandleForWriting
        let oversizedBytes = exactBytes + Data([0x20])
        let oversizedWrite = Task.detached {
            try oversizedWriter.write(contentsOf: oversizedBytes)
            try oversizedWriter.close()
        }
        var observedError: CADJSONAdapterError?
        do {
            _ = try CADJSONBoundedCodec.readStandardInput(from: oversizedPipe.fileHandleForReading)
        } catch let error as CADJSONAdapterError {
            observedError = error
        }
        try await oversizedWrite.value
        #expect(observedError == .oversizedInput)

        let standalone = try CADJSONErrorEnvelope(error: CADJSONAdapterError.malformedJSON)
        #expect(standalone.caseID == nil)
        let encoded = try CADJSONBoundedCodec.encode(standalone)
        let decoded = try CADJSONBoundedCodec.decode(CADJSONErrorEnvelope.self, from: encoded)
        #expect(decoded == standalone)
    }

    @MainActor
    @Test
    func outputEncodingAndPublicEvaluationRejectAnOversizedResponseBeforePublication() async throws {
        let baseExecutor = DefaultCADActivatedCaseExecutor()
        let context = try baseExecutor.context(for: "LIN-001")
        let recordingExecutor = RecordingCADActivatedCaseExecutor(context: context)
        let adapter = CADJSONAdapter(executor: recordingExecutor)
        let request = try adapter.makeRequest(for: "LIN-001")
        let oversizedName = String(
            repeating: "x",
            count: CADJSONAdapterSchema.maximumDocumentBytes
        )
        let action = CADCandidateAction.automation(.sketch(.line(
            name: oversizedName,
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 25, y: 0, z: 0)
        )))
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(action)
        )
        expectAdapterError(.outputOverflow) {
            _ = try CADJSONBoundedCodec.encode(response)
        }

        let unboundedEncoding = try JSONEncoder().encode(response)
        #expect(unboundedEncoding.count > CADJSONAdapterSchema.maximumDocumentBytes)
        do {
            _ = try await adapter.evaluate(responseData: unboundedEncoding)
            Issue.record("An oversized public response must not enter executor evaluation.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .oversizedInput)
        }
        #expect(recordingExecutor.evaluationCount == 0)
    }

    @Test
    func errorConstructionRejectsInvalidOptionalCaseIDs() {
        expectAdapterError(.malformedJSON) {
            _ = try CADJSONErrorEnvelope(
                code: .inputFailure,
                caseID: CADBenchmarkCaseID(rawValue: "LIN-999")
            )
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func fakeCandidateOracleAndInfrastructureFailuresAreSanitized() async throws {
        let baseExecutor = DefaultCADActivatedCaseExecutor()
        let context = try baseExecutor.context(for: "LIN-001")
        let action = lineAction(name: "LIN-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: "LIN-001",
            context: context,
            decision: .action(action)
        )

        let candidateFailureExecutor = FakeCADActivatedCaseExecutor(
            context: context,
            mode: .candidateFailure
        )
        let candidateFailure = CADJSONAdapter(executor: candidateFailureExecutor)
        let candidateEvaluation = try await candidateFailure.evaluate(response: response)
        #expect(candidateEvaluation.result == nil)
        #expect(candidateEvaluation.error?.code == .candidateFailure)
        let candidateFailureJSON = try CADJSONBoundedCodec.encode(candidateEvaluation)
        let candidateFailureText = try #require(String(data: candidateFailureJSON, encoding: .utf8))
        for forbidden in ["FeatureID", "diagnostics", "expectation", "workspace", "oracle diagnostic"] {
            #expect(candidateFailureText.contains(forbidden) == false)
        }

        let oracleFailureExecutor = FakeCADActivatedCaseExecutor(
            context: context,
            mode: .oracleResult
        )
        let oracleFailure = CADJSONAdapter(executor: oracleFailureExecutor)
        let oracleEvaluation = try await oracleFailure.evaluate(response: response)
        #expect(oracleEvaluation.result?.outcome == .oracleFailure)
        #expect(oracleEvaluation.error == nil)
        let oracleText = try #require(String(
            data: CADJSONBoundedCodec.encode(oracleEvaluation),
            encoding: .utf8
        ))
        #expect(oracleText.contains("diagnostic") == false)

        let infrastructureFailureExecutor = FakeCADActivatedCaseExecutor(
            context: context,
            mode: .infrastructureResult
        )
        let infrastructureFailure = CADJSONAdapter(executor: infrastructureFailureExecutor)
        let infrastructureEvaluation = try await infrastructureFailure.evaluate(response: response)
        #expect(infrastructureEvaluation.result?.outcome == .infrastructureFailure)
        #expect(infrastructureEvaluation.error == nil)
        let infrastructureText = try #require(String(
            data: CADJSONBoundedCodec.encode(infrastructureEvaluation),
            encoding: .utf8
        ))
        for forbidden in ["FeatureID", "diagnostics", "expectation", "workspace"] {
            #expect(infrastructureText.contains(forbidden) == false)
        }
    }

    @Test
    func evaluationRequiresExactlyOnePublicResultOrError() throws {
        let caseID: CADBenchmarkCaseID = "LIN-001"
        let fingerprint = String(repeating: "a", count: 64)
        let result = CADCaseResult(id: caseID, category: .line, outcome: .realized)
        let error = try CADJSONErrorEnvelope(code: .infrastructureFailure, caseID: caseID)
        let validResult = try CADJSONEvaluationEnvelope(
            caseID: caseID,
            contextFingerprint: fingerprint,
            result: result
        )
        let validError = try CADJSONEvaluationEnvelope(
            caseID: caseID,
            contextFingerprint: fingerprint,
            error: error
        )
        #expect(validResult.result != nil)
        #expect(validResult.error == nil)
        #expect(validError.result == nil)
        #expect(validError.error != nil)
        var bothObject = try #require(
            JSONSerialization.jsonObject(
                with: CADJSONBoundedCodec.encode(validResult),
                options: []
            ) as? [String: Any]
        )
        let errorObject = try #require(
            JSONSerialization.jsonObject(
                with: CADJSONBoundedCodec.encode(validError),
                options: []
            ) as? [String: Any]
        )
        bothObject["error"] = errorObject["error"]
        let both = try JSONSerialization.data(withJSONObject: bothObject, options: [])
        expectAdapterError(.malformedJSON) {
            _ = try CADJSONBoundedCodec.decode(CADJSONEvaluationEnvelope.self, from: both)
        }
    }
}

@MainActor
private struct FakeCADActivatedCaseExecutor: CADActivatedCaseExecuting {
    enum Mode: Sendable {
        case candidateFailure
        case oracleResult
        case infrastructureResult
    }

    let context: CADCandidateContext
    let mode: Mode

    var activatedCaseIDs: [CADBenchmarkCaseID] {
        [context.challenge.id]
    }

    func context(for caseID: CADBenchmarkCaseID) throws -> CADCandidateContext {
        guard caseID == context.challenge.id else {
            throw CADActivatedCaseExecutorError.inactiveCase(caseID)
        }
        return context
    }

    func evaluate(
        caseID: CADBenchmarkCaseID,
        candidate: any CADCandidateProtocol
    ) async throws -> CADCaseResult {
        _ = try await candidate.decide(for: context)
        switch mode {
        case .candidateFailure:
            throw CADActivatedCaseExecutorError.candidateFailure(caseID)
        case .oracleResult:
            return CADCaseResult(
                id: caseID,
                category: .line,
                outcome: .oracleFailure
            )
        case .infrastructureResult:
            return CADCaseResult(
                id: caseID,
                category: .line,
                outcome: .infrastructureFailure
            )
        }
    }
}

@MainActor
private final class RecordingCADActivatedCaseExecutor: CADActivatedCaseExecuting {
    let contextValue: CADCandidateContext
    private(set) var evaluationCount = 0

    init(context: CADCandidateContext) {
        self.contextValue = context
    }

    var activatedCaseIDs: [CADBenchmarkCaseID] {
        [contextValue.challenge.id]
    }

    func context(for caseID: CADBenchmarkCaseID) throws -> CADCandidateContext {
        guard caseID == contextValue.challenge.id else {
            throw CADActivatedCaseExecutorError.inactiveCase(caseID)
        }
        return contextValue
    }

    func evaluate(
        caseID: CADBenchmarkCaseID,
        candidate: any CADCandidateProtocol
    ) async throws -> CADCaseResult {
        evaluationCount += 1
        _ = try await candidate.decide(for: contextValue)
        return CADCaseResult(id: caseID, category: .line, outcome: .realized)
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

private func expectAdapterError(
    _ expected: CADJSONAdapterError,
    operation: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        try operation()
        Issue.record("Expected adapter error \(expected).", sourceLocation: sourceLocation)
    } catch let error as CADJSONAdapterError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Unexpected error type.", sourceLocation: sourceLocation)
    }
}

private func replacing(_ data: Data, from old: String, to new: String) -> Data {
    guard let text = String(data: data, encoding: .utf8) else {
        return data
    }
    return Data(text.replacingOccurrences(of: old, with: new).utf8)
}

private func appendLengthPrefixed(_ value: Data, to data: inout Data) {
    var length = UInt64(value.count).bigEndian
    withUnsafeBytes(of: &length) { bytes in
        data.append(contentsOf: bytes)
    }
    data.append(value)
}

private func bigEndianBytes(_ value: UInt64) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
