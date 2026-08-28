import Foundation
import CryptoKit
import Testing
import RupaAgentCADBenchmark
@testable import RupaAgentCADBenchmarkJSONAdapter

@Suite(.serialized)
struct CADJSONAdapterTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func goldenLineRectangleAndCircleExchangeUsesTheProductionRoute() async throws {
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

        let circleRequest = try adapter.makeRequest(for: "CIR-001")
        let circleAction = circleAction(name: "CIR-001")
        let circleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: circleRequest.caseID,
            context: circleRequest.context,
            decision: .action(circleAction)
        )
        let circleResponseData = try CADJSONBoundedCodec.encode(circleResponse)
        let circleJSON = try #require(String(data: circleResponseData, encoding: .utf8))
        #expect(circleJSON.contains("\"kind\":\"circle\""))
        #expect(circleJSON.contains("\"caseID\":\"CIR-001\""))
        let circleEvaluation = try await adapter.evaluate(responseData: circleResponseData)
        #expect(circleEvaluation.result?.outcome == .realized)
        #expect(circleEvaluation.error == nil)
        #expect(try CADJSONBoundedCodec.decode(
            CADJSONEvaluationEnvelope.self,
            from: adapter.encodeEvaluation(circleEvaluation)
        ) == circleEvaluation)

        let translatedCircleRequest = try adapter.makeRequest(for: "CIR-002")
        let translatedCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedCircleRequest.caseID,
            context: translatedCircleRequest.context,
            decision: .action(cir002CircleAction(name: "CIR-002"))
        )
        let translatedCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(translatedCircleResponse)
        )
        #expect(translatedCircleEvaluation.result?.outcome == .realized)
        #expect(translatedCircleEvaluation.error == nil)

        let xzCircleRequest = try adapter.makeRequest(for: "CIR-003")
        let xzCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: xzCircleRequest.caseID,
            context: xzCircleRequest.context,
            decision: .action(cir003CircleAction(name: "CIR-003"))
        )
        let xzCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(xzCircleResponse)
        )
        #expect(xzCircleEvaluation.result?.outcome == .realized)
        #expect(xzCircleEvaluation.error == nil)

        let inchRectangleRequest = try adapter.makeRequest(for: "REC-009")
        let inchRectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: inchRectangleRequest.caseID,
            context: inchRectangleRequest.context,
            decision: .action(rec009RectangleAction(name: "REC-009"))
        )
        let inchRectangleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(inchRectangleResponse)
        )
        #expect(inchRectangleEvaluation.result?.outcome == .realized)
        #expect(inchRectangleEvaluation.error == nil)

        let metreRectangleRequest = try adapter.makeRequest(for: "REC-010")
        let metreRectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: metreRectangleRequest.caseID,
            context: metreRectangleRequest.context,
            decision: .action(rec010RectangleAction(name: "REC-010"))
        )
        let metreRectangleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(metreRectangleResponse)
        )
        #expect(metreRectangleEvaluation.result?.outcome == .realized)
        #expect(metreRectangleEvaluation.error == nil)

        let squareRectangleRequest = try adapter.makeRequest(for: "REC-011")
        let squareRectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: squareRectangleRequest.caseID,
            context: squareRectangleRequest.context,
            decision: .action(rec011RectangleAction(name: "REC-011"))
        )
        let squareRectangleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(squareRectangleResponse)
        )
        #expect(squareRectangleEvaluation.result?.outcome == .realized)
        #expect(squareRectangleEvaluation.error == nil)

        let translatedRectangleRequest = try adapter.makeRequest(for: "REC-012")
        let translatedRectangleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedRectangleRequest.caseID,
            context: translatedRectangleRequest.context,
            decision: .action(rec012RectangleAction(name: "REC-012"))
        )
        let translatedRectangleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(translatedRectangleResponse)
        )
        #expect(translatedRectangleEvaluation.result?.outcome == .realized)
        #expect(translatedRectangleEvaluation.error == nil)
    }

    @MainActor
    @Test
    func goldenWireFixturesMatchTheCompleteDeterministicDocument() throws {
        let adapter = CADJSONAdapter()
        let lineRequest = try adapter.makeRequest(for: "LIN-001")
        let rectangleRequest = try adapter.makeRequest(for: "REC-001")
        let circleRequest = try adapter.makeRequest(for: "CIR-001")
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
        let circleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: "CIR-001",
            context: circleRequest.context,
            decision: .action(circleAction(name: "CIR-001"))
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
        let circleRequestFixture = #"{"caseID":"CIR-001","context":{"capabilities":{"statuses":[{"available":true,"id":"cad.sketch.circle","version":"1"}],"version":"agent-capabilities.v1"},"challenge":{"budget":{"maximumActions":32,"maximumReadRecords":64,"maximumRounds":16},"category":"CIR","id":"CIR-001","instruction":"Construct CIR-001 as a circle of radius 5.0 mm centered at (0.0, 0.0, 0.0) mm on the xy plane.","outputRoles":[{"description":"The requested analytic circle.","name":"circle"}],"requiredCapability":{"id":"cad.sketch.circle","version":"1"}},"priorResults":[],"remainingActions":32,"remainingRounds":16},"contextFingerprint":"934124a9a32a3830d1ae07b9b9ddffc9f21354f6edc6240cc8adc2850342a26a","schema":"rupa.agent-cad-benchmark.request.v1"}"#
        let lineResponseFixture = #"{"caseID":"LIN-001","contextFingerprint":"f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf","decision":{"action":{"automation":{"kind":"sketch","sketch":{"end":{"unit":"millimeter","x":25,"y":0,"z":0},"kind":"line","name":"LIN-001","plane":"xy","start":{"unit":"millimeter","x":0,"y":0,"z":0}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v2"}"#
        let rectangleResponseFixture = #"{"caseID":"REC-001","contextFingerprint":"73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5","decision":{"action":{"automation":{"kind":"sketch","sketch":{"center":{"unit":"millimeter","x":0,"y":0,"z":0},"height":{"unit":"millimeter","value":20},"kind":"rectangle","name":"REC-001","plane":"xy","width":{"unit":"millimeter","value":40}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v2"}"#
        let circleResponseFixture = #"{"caseID":"CIR-001","contextFingerprint":"934124a9a32a3830d1ae07b9b9ddffc9f21354f6edc6240cc8adc2850342a26a","decision":{"action":{"automation":{"kind":"sketch","sketch":{"center":{"unit":"millimeter","x":0,"y":0,"z":0},"kind":"circle","name":"CIR-001","plane":"xy","radius":{"unit":"millimeter","value":5}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v2"}"#
        let lineEvaluationFixture = #"{"caseID":"LIN-001","contextFingerprint":"f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf","result":{"category":"LIN","id":"LIN-001","outcome":"realized"},"schema":"rupa.agent-cad-benchmark.evaluation.v1"}"#
        let rectangleEvaluationFixture = #"{"caseID":"REC-001","contextFingerprint":"73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5","result":{"category":"REC","id":"REC-001","outcome":"realized"},"schema":"rupa.agent-cad-benchmark.evaluation.v1"}"#
        let circleEvaluationFixture = #"{"caseID":"CIR-001","contextFingerprint":"934124a9a32a3830d1ae07b9b9ddffc9f21354f6edc6240cc8adc2850342a26a","result":{"category":"CIR","id":"CIR-001","outcome":"realized"},"schema":"rupa.agent-cad-benchmark.evaluation.v1"}"#

        #expect(String(decoding: try CADJSONBoundedCodec.encode(lineRequest), as: UTF8.self) == lineRequestFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(rectangleRequest), as: UTF8.self) == rectangleRequestFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(circleRequest), as: UTF8.self) == circleRequestFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(lineResponse), as: UTF8.self) == lineResponseFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(rectangleResponse), as: UTF8.self) == rectangleResponseFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(circleResponse), as: UTF8.self) == circleResponseFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(lineEvaluation), as: UTF8.self) == lineEvaluationFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(rectangleEvaluation), as: UTF8.self) == rectangleEvaluationFixture)
        #expect(String(decoding: try CADJSONBoundedCodec.encode(
            try CADJSONEvaluationEnvelope(
                caseID: circleRequest.caseID,
                contextFingerprint: circleRequest.contextFingerprint,
                result: CADCaseResult(id: "CIR-001", category: .circle, outcome: .realized)
            )
        ), as: UTF8.self) == circleEvaluationFixture)
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
    func requestAndLiveContextsAreValueEqualAndAllTwentySevenRequestsStayBounded() throws {
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
            } else if caseID.category == .rectangle {
                action = rectangleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-002" {
                action = cir002CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-003" {
                action = cir003CircleAction(name: caseID.rawValue)
            } else {
                action = circleAction(name: caseID.rawValue)
            }
            let response = try CADJSONCandidateResponseEnvelope(
                caseID: caseID,
                context: request.context,
                decision: .action(action)
            )
            #expect(try CADJSONBoundedCodec.encode(response).count < 16_384)
        }

        #expect(executor.activatedCaseIDs.count == 27)
        #expect(largestRequest < 16_384)
    }

    @MainActor
    @Test
    func activatedRequestSequenceHasAStableLengthPrefixedAggregateDigest() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let adapter = CADJSONAdapter(executor: executor)
        let historicalIDs = (1...12).map { String(format: "LIN-%03d", $0) }
            + (1...8).map { String(format: "REC-%03d", $0) }
        let currentIDs = historicalIDs + ["REC-009", "REC-010", "REC-011", "REC-012", "CIR-001", "CIR-002", "CIR-003"]
        #expect(executor.activatedCaseIDs.map(\.rawValue) == currentIDs)

        // Each activated record is case ID, request byte count, and request SHA-256, all length-prefixed.
        var historicalAggregate = Data()
        for rawCaseID in historicalIDs {
            let caseID = CADBenchmarkCaseID(rawValue: rawCaseID)
            let request = try adapter.encodeRequest(for: caseID)
            appendLengthPrefixed(Data(caseID.rawValue.utf8), to: &historicalAggregate)
            appendLengthPrefixed(bigEndianBytes(UInt64(request.count)), to: &historicalAggregate)
            appendLengthPrefixed(Data(SHA256.hash(data: request)), to: &historicalAggregate)
        }
        #expect(sha256Hex(historicalAggregate) == "1989b5499be40d18b1f3b8a5381b9b0a0f28c53bf9de975d8c0251bc1a7e509e")

        var currentAggregate = historicalAggregate
        let rec009ID: CADBenchmarkCaseID = "REC-009"
        let rec009Request = try adapter.encodeRequest(for: rec009ID)
        appendLengthPrefixed(Data(rec009ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(rec009Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: rec009Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "2b16e65e4e608df5b53a01528b8978c09c0ca4c4df203deec5ff4ebdd34a7fd4")

        let rec010ID: CADBenchmarkCaseID = "REC-010"
        let rec010Request = try adapter.encodeRequest(for: rec010ID)
        appendLengthPrefixed(Data(rec010ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(rec010Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: rec010Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "bcc3e458c5af0b0f9f77682b999bd52d1e6856818579daf539b99d1076d67943")

        let rec011ID: CADBenchmarkCaseID = "REC-011"
        let rec011Request = try adapter.encodeRequest(for: rec011ID)
        appendLengthPrefixed(Data(rec011ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(rec011Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: rec011Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "96371a67956c5496aab1bb832d446bcbe3e2f2aa22d2612dbb2dec7dd3736f0f")

        let rec012ID: CADBenchmarkCaseID = "REC-012"
        let rec012Request = try adapter.encodeRequest(for: rec012ID)
        appendLengthPrefixed(Data(rec012ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(rec012Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: rec012Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "1d4190e85472aff255ce56003df4f571452be0eefb40ae2ebf3e0d54d4f0d61e")

        let cir001ID: CADBenchmarkCaseID = "CIR-001"
        let cir001Request = try adapter.encodeRequest(for: cir001ID)
        appendLengthPrefixed(Data(cir001ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir001Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir001Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "aee0de92d235870b031871fa822746738ebec7e070ed19fd92263fb10a336d84")

        let cir002ID: CADBenchmarkCaseID = "CIR-002"
        let cir002Request = try adapter.encodeRequest(for: cir002ID)
        appendLengthPrefixed(Data(cir002ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir002Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir002Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "c20b165d825b3333722f3b813af4392a9361d3dff9124d62cb3512ef4b870e40")

        let cir003ID: CADBenchmarkCaseID = "CIR-003"
        let cir003Request = try adapter.encodeRequest(for: cir003ID)
        appendLengthPrefixed(Data(cir003ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir003Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir003Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "9d9bde9eb7f520cecee220c7286b16e0c5347cd50219cfe08d780114f24cc975")
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
            _ = try await adapter.evaluate(response: response, for: "CIR-004")
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

        let legacy = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v2","caseID":"LIN-001","contextFingerprint":"0000000000000000000000000000000000000000000000000000000000000000","decision":{"action":{"automation":{"sketch":{"line":{"name":"legacy"}}}}}}"#.utf8)
        expectAdapterError(.invalidDecision) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: legacy
            )
        }

        let unknown = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v2","caseID":"LIN-001","contextFingerprint":"0000000000000000000000000000000000000000000000000000000000000000","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.invalidDecision) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: unknown
            )
        }
    }

    @MainActor
    @Test
    func candidateResponseV1IsRejectedAsUnsupportedSchema() throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "LIN-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(lineAction(name: "LIN-001"))
        )
        let legacy = replacing(
            try CADJSONBoundedCodec.encode(response),
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v1"
        )
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: legacy
            )
        }

        let legacyWithUnknownDecision = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v1","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: legacyWithUnknownDecision
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

    @Test
    func guaranteedInfrastructureFailureDocumentIsCanonicalBoundedAndDecodable() throws {
        let envelope = try CADJSONErrorEnvelope(code: .infrastructureFailure)
        let canonical = try CADJSONBoundedCodec.encode(envelope)
        let guaranteed = CADJSONBoundedCodec.guaranteedInfrastructureFailureDocument

        #expect(guaranteed == canonical)
        #expect(guaranteed.count <= CADJSONAdapterSchema.maximumDocumentBytes)
        #expect(
            try CADJSONBoundedCodec.decode(CADJSONErrorEnvelope.self, from: guaranteed)
                == envelope
        )
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

private func circleAction(name: String) -> CADCandidateAction {
    .automation(.sketch(.circle(
        name: name,
        plane: .xy,
        center: CADPoint3D(x: 0, y: 0, z: 0),
        radius: CADLength(value: 5)
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
