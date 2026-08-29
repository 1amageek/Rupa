import Foundation
import CryptoKit
import Testing
import RupaAgentCADBenchmark
@testable import RupaAgentCADBenchmarkJSONAdapter

@Suite(.serialized)
struct CADJSONAdapterTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func goldenLineRectangleCircleAndAngleExchangeUsesTheProductionRoute() async throws {
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

        let yzCircleRequest = try adapter.makeRequest(for: "CIR-004")
        let yzCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: yzCircleRequest.caseID,
            context: yzCircleRequest.context,
            decision: .action(cir004CircleAction(name: "CIR-004"))
        )
        let yzCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(yzCircleResponse)
        )
        #expect(yzCircleEvaluation.result?.outcome == .realized)
        #expect(yzCircleEvaluation.error == nil)

        let largeCircleRequest = try adapter.makeRequest(for: "CIR-005")
        let largeCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: largeCircleRequest.caseID,
            context: largeCircleRequest.context,
            decision: .action(cir005CircleAction(name: "CIR-005"))
        )
        let largeCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(largeCircleResponse)
        )
        #expect(largeCircleEvaluation.result?.outcome == .realized)
        #expect(largeCircleEvaluation.error == nil)

        let centimeterCircleRequest = try adapter.makeRequest(for: "CIR-006")
        let centimeterCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: centimeterCircleRequest.caseID,
            context: centimeterCircleRequest.context,
            decision: .action(cir006CircleAction(name: "CIR-006"))
        )
        let centimeterCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(centimeterCircleResponse)
        )
        #expect(centimeterCircleEvaluation.result?.outcome == .realized)
        #expect(centimeterCircleEvaluation.error == nil)

        let metreCircleRequest = try adapter.makeRequest(for: "CIR-007")
        let metreCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: metreCircleRequest.caseID,
            context: metreCircleRequest.context,
            decision: .action(cir007CircleAction(name: "CIR-007"))
        )
        let metreCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(metreCircleResponse)
        )
        #expect(metreCircleEvaluation.result?.outcome == .realized)
        #expect(metreCircleEvaluation.error == nil)

        let inchCircleRequest = try adapter.makeRequest(for: "CIR-008")
        let inchCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: inchCircleRequest.caseID,
            context: inchCircleRequest.context,
            decision: .action(cir008CircleAction(name: "CIR-008"))
        )
        let inchCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(inchCircleResponse)
        )
        #expect(inchCircleEvaluation.result?.outcome == .realized)
        #expect(inchCircleEvaluation.error == nil)

        let negativeZCircleRequest = try adapter.makeRequest(for: "CIR-009")
        let negativeZCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: negativeZCircleRequest.caseID,
            context: negativeZCircleRequest.context,
            decision: .action(cir009CircleAction(name: "CIR-009"))
        )
        let negativeZCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(negativeZCircleResponse)
        )
        #expect(negativeZCircleEvaluation.result?.outcome == .realized)
        #expect(negativeZCircleEvaluation.error == nil)

        let largeMetreCircleRequest = try adapter.makeRequest(for: "CIR-010")
        let largeMetreCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: largeMetreCircleRequest.caseID,
            context: largeMetreCircleRequest.context,
            decision: .action(cir010CircleAction(name: "CIR-010"))
        )
        let largeMetreCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(largeMetreCircleResponse)
        )
        #expect(largeMetreCircleEvaluation.result?.outcome == .realized)
        #expect(largeMetreCircleEvaluation.error == nil)

        let fractionalRadiusCircleRequest = try adapter.makeRequest(for: "CIR-011")
        let fractionalRadiusCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: fractionalRadiusCircleRequest.caseID,
            context: fractionalRadiusCircleRequest.context,
            decision: .action(cir011CircleAction(name: "CIR-011"))
        )
        let fractionalRadiusCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(fractionalRadiusCircleResponse)
        )
        #expect(fractionalRadiusCircleEvaluation.result?.outcome == .realized)
        #expect(fractionalRadiusCircleEvaluation.error == nil)

        let terminalCircleRequest = try adapter.makeRequest(for: "CIR-012")
        let terminalCircleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: terminalCircleRequest.caseID,
            context: terminalCircleRequest.context,
            decision: .action(cir012CircleAction(name: "CIR-012"))
        )
        let terminalCircleEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(terminalCircleResponse)
        )
        #expect(terminalCircleEvaluation.result?.outcome == .realized)
        #expect(terminalCircleEvaluation.error == nil)

        let angleRequest = try adapter.makeRequest(for: "ANG-001")
        let angleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: angleRequest.caseID,
            context: angleRequest.context,
            decision: .action(angleAction(name: "ANG-001"))
        )
        let angleResponseData = try CADJSONBoundedCodec.encode(angleResponse)
        let angleJSON = try #require(String(data: angleResponseData, encoding: .utf8))
        #expect(angleJSON.contains("\"kind\":\"angle\""))
        #expect(angleJSON.contains("\"caseID\":\"ANG-001\""))
        let angleEvaluation = try await adapter.evaluate(responseData: angleResponseData)
        #expect(angleEvaluation.result?.outcome == .realized)
        #expect(angleEvaluation.error == nil)

        let translatedAngleRequest = try adapter.makeRequest(for: "ANG-002")
        let translatedAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedAngleRequest.caseID,
            context: translatedAngleRequest.context,
            decision: .action(angle002Action(name: "ANG-002"))
        )
        let translatedAngleResponseData = try CADJSONBoundedCodec.encode(translatedAngleResponse)
        let translatedAngleJSON = try #require(String(data: translatedAngleResponseData, encoding: .utf8))
        #expect(translatedAngleJSON.contains("\"kind\":\"angle\""))
        #expect(translatedAngleJSON.contains("\"caseID\":\"ANG-002\""))
        let translatedAngleEvaluation = try await adapter.evaluate(
            responseData: translatedAngleResponseData
        )
        #expect(translatedAngleEvaluation.result?.outcome == .realized)
        #expect(translatedAngleEvaluation.error == nil)

        let translatedSixtyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-003")
        let translatedSixtyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedSixtyDegreeAngleRequest.caseID,
            context: translatedSixtyDegreeAngleRequest.context,
            decision: .action(angle003Action(name: "ANG-003"))
        )
        let translatedSixtyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            translatedSixtyDegreeAngleResponse
        )
        let translatedSixtyDegreeAngleJSON = try #require(
            String(data: translatedSixtyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(translatedSixtyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(translatedSixtyDegreeAngleJSON.contains("\"caseID\":\"ANG-003\""))
        let translatedSixtyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: translatedSixtyDegreeAngleResponseData
        )
        #expect(translatedSixtyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(translatedSixtyDegreeAngleEvaluation.error == nil)

        let translatedSeventyFiveDegreeAngleRequest = try adapter.makeRequest(for: "ANG-004")
        let translatedSeventyFiveDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedSeventyFiveDegreeAngleRequest.caseID,
            context: translatedSeventyFiveDegreeAngleRequest.context,
            decision: .action(angle004Action(name: "ANG-004"))
        )
        let translatedSeventyFiveDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            translatedSeventyFiveDegreeAngleResponse
        )
        let translatedSeventyFiveDegreeAngleJSON = try #require(
            String(data: translatedSeventyFiveDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(translatedSeventyFiveDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(translatedSeventyFiveDegreeAngleJSON.contains("\"caseID\":\"ANG-004\""))
        let translatedSeventyFiveDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: translatedSeventyFiveDegreeAngleResponseData
        )
        #expect(translatedSeventyFiveDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(translatedSeventyFiveDegreeAngleEvaluation.error == nil)

        let orthogonalAngleRequest = try adapter.makeRequest(for: "ANG-005")
        let orthogonalAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: orthogonalAngleRequest.caseID,
            context: orthogonalAngleRequest.context,
            decision: .action(angle005Action(name: "ANG-005"))
        )
        let orthogonalAngleResponseData = try CADJSONBoundedCodec.encode(
            orthogonalAngleResponse
        )
        let orthogonalAngleJSON = try #require(
            String(data: orthogonalAngleResponseData, encoding: .utf8)
        )
        #expect(orthogonalAngleJSON.contains("\"kind\":\"angle\""))
        #expect(orthogonalAngleJSON.contains("\"caseID\":\"ANG-005\""))
        let orthogonalAngleEvaluation = try await adapter.evaluate(
            responseData: orthogonalAngleResponseData
        )
        #expect(orthogonalAngleEvaluation.result?.outcome == .realized)
        #expect(orthogonalAngleEvaluation.error == nil)

        let negativePlacementAngleRequest = try adapter.makeRequest(for: "ANG-006")
        let negativePlacementAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: negativePlacementAngleRequest.caseID,
            context: negativePlacementAngleRequest.context,
            decision: .action(angle006Action(name: "ANG-006"))
        )
        let negativePlacementAngleResponseData = try CADJSONBoundedCodec.encode(
            negativePlacementAngleResponse
        )
        let negativePlacementAngleJSON = try #require(
            String(data: negativePlacementAngleResponseData, encoding: .utf8)
        )
        #expect(negativePlacementAngleJSON.contains("\"kind\":\"angle\""))
        #expect(negativePlacementAngleJSON.contains("\"caseID\":\"ANG-006\""))
        let negativePlacementAngleEvaluation = try await adapter.evaluate(
            responseData: negativePlacementAngleResponseData
        )
        #expect(negativePlacementAngleEvaluation.result?.outcome == .realized)
        #expect(negativePlacementAngleEvaluation.error == nil)

        let translatedOneHundredTwentyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-007")
        let translatedOneHundredTwentyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedOneHundredTwentyDegreeAngleRequest.caseID,
            context: translatedOneHundredTwentyDegreeAngleRequest.context,
            decision: .action(angle007Action(name: "ANG-007"))
        )
        let translatedOneHundredTwentyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            translatedOneHundredTwentyDegreeAngleResponse
        )
        let translatedOneHundredTwentyDegreeAngleJSON = try #require(
            String(data: translatedOneHundredTwentyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(translatedOneHundredTwentyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(translatedOneHundredTwentyDegreeAngleJSON.contains("\"caseID\":\"ANG-007\""))
        let translatedOneHundredTwentyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: translatedOneHundredTwentyDegreeAngleResponseData
        )
        #expect(translatedOneHundredTwentyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(translatedOneHundredTwentyDegreeAngleEvaluation.error == nil)

        let originOneHundredThirtyFiveDegreeAngleRequest = try adapter.makeRequest(for: "ANG-008")
        let originOneHundredThirtyFiveDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: originOneHundredThirtyFiveDegreeAngleRequest.caseID,
            context: originOneHundredThirtyFiveDegreeAngleRequest.context,
            decision: .action(angle008Action(name: "ANG-008"))
        )
        let originOneHundredThirtyFiveDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            originOneHundredThirtyFiveDegreeAngleResponse
        )
        let originOneHundredThirtyFiveDegreeAngleJSON = try #require(
            String(data: originOneHundredThirtyFiveDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(originOneHundredThirtyFiveDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(originOneHundredThirtyFiveDegreeAngleJSON.contains("\"caseID\":\"ANG-008\""))
        let originOneHundredThirtyFiveDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: originOneHundredThirtyFiveDegreeAngleResponseData
        )
        #expect(originOneHundredThirtyFiveDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(originOneHundredThirtyFiveDegreeAngleEvaluation.error == nil)

        let translatedOneHundredFiftyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-009")
        let translatedOneHundredFiftyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: translatedOneHundredFiftyDegreeAngleRequest.caseID,
            context: translatedOneHundredFiftyDegreeAngleRequest.context,
            decision: .action(angle009Action(name: "ANG-009"))
        )
        let translatedOneHundredFiftyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            translatedOneHundredFiftyDegreeAngleResponse
        )
        let translatedOneHundredFiftyDegreeAngleJSON = try #require(
            String(data: translatedOneHundredFiftyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(translatedOneHundredFiftyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(translatedOneHundredFiftyDegreeAngleJSON.contains("\"caseID\":\"ANG-009\""))
        let translatedOneHundredFiftyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: translatedOneHundredFiftyDegreeAngleResponseData
        )
        #expect(translatedOneHundredFiftyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(translatedOneHundredFiftyDegreeAngleEvaluation.error == nil)

        let negativePlacementOneHundredSixtyFiveDegreeAngleRequest = try adapter.makeRequest(for: "ANG-010")
        let negativePlacementOneHundredSixtyFiveDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: negativePlacementOneHundredSixtyFiveDegreeAngleRequest.caseID,
            context: negativePlacementOneHundredSixtyFiveDegreeAngleRequest.context,
            decision: .action(angle010Action(name: "ANG-010"))
        )
        let negativePlacementOneHundredSixtyFiveDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            negativePlacementOneHundredSixtyFiveDegreeAngleResponse
        )
        let negativePlacementOneHundredSixtyFiveDegreeAngleJSON = try #require(
            String(data: negativePlacementOneHundredSixtyFiveDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(negativePlacementOneHundredSixtyFiveDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(negativePlacementOneHundredSixtyFiveDegreeAngleJSON.contains("\"caseID\":\"ANG-010\""))
        let negativePlacementOneHundredSixtyFiveDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: negativePlacementOneHundredSixtyFiveDegreeAngleResponseData
        )
        #expect(negativePlacementOneHundredSixtyFiveDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(negativePlacementOneHundredSixtyFiveDegreeAngleEvaluation.error == nil)

        let xzFortyFiveDegreeAngleRequest = try adapter.makeRequest(for: "ANG-011")
        let xzFortyFiveDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: xzFortyFiveDegreeAngleRequest.caseID,
            context: xzFortyFiveDegreeAngleRequest.context,
            decision: .action(angle011Action(name: "ANG-011"))
        )
        let xzFortyFiveDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            xzFortyFiveDegreeAngleResponse
        )
        let xzFortyFiveDegreeAngleJSON = try #require(
            String(data: xzFortyFiveDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(xzFortyFiveDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(xzFortyFiveDegreeAngleJSON.contains("\"caseID\":\"ANG-011\""))
        let xzFortyFiveDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: xzFortyFiveDegreeAngleResponseData
        )
        #expect(xzFortyFiveDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(xzFortyFiveDegreeAngleEvaluation.error == nil)

        let yzSixtyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-012")
        let yzSixtyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: yzSixtyDegreeAngleRequest.caseID,
            context: yzSixtyDegreeAngleRequest.context,
            decision: .action(angle012Action(name: "ANG-012"))
        )
        let yzSixtyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            yzSixtyDegreeAngleResponse
        )
        let yzSixtyDegreeAngleJSON = try #require(
            String(data: yzSixtyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(yzSixtyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(yzSixtyDegreeAngleJSON.contains("\"caseID\":\"ANG-012\""))
        let yzSixtyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: yzSixtyDegreeAngleResponseData
        )
        #expect(yzSixtyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(yzSixtyDegreeAngleEvaluation.error == nil)

        let xzNinetyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-013")
        let xzNinetyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: xzNinetyDegreeAngleRequest.caseID,
            context: xzNinetyDegreeAngleRequest.context,
            decision: .action(angle013Action(name: "ANG-013"))
        )
        let xzNinetyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            xzNinetyDegreeAngleResponse
        )
        let xzNinetyDegreeAngleJSON = try #require(
            String(data: xzNinetyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(xzNinetyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(xzNinetyDegreeAngleJSON.contains("\"caseID\":\"ANG-013\""))
        let xzNinetyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: xzNinetyDegreeAngleResponseData
        )
        #expect(xzNinetyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(xzNinetyDegreeAngleEvaluation.error == nil)

        let yzOneHundredTwentyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-014")
        let yzOneHundredTwentyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: yzOneHundredTwentyDegreeAngleRequest.caseID,
            context: yzOneHundredTwentyDegreeAngleRequest.context,
            decision: .action(angle014Action(name: "ANG-014"))
        )
        let yzOneHundredTwentyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            yzOneHundredTwentyDegreeAngleResponse
        )
        let yzOneHundredTwentyDegreeAngleJSON = try #require(
            String(data: yzOneHundredTwentyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(yzOneHundredTwentyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(yzOneHundredTwentyDegreeAngleJSON.contains("\"caseID\":\"ANG-014\""))
        let yzOneHundredTwentyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: yzOneHundredTwentyDegreeAngleResponseData
        )
        #expect(yzOneHundredTwentyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(yzOneHundredTwentyDegreeAngleEvaluation.error == nil)

        let xzOneHundredThirtyFiveDegreeAngleRequest = try adapter.makeRequest(for: "ANG-015")
        let xzOneHundredThirtyFiveDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: xzOneHundredThirtyFiveDegreeAngleRequest.caseID,
            context: xzOneHundredThirtyFiveDegreeAngleRequest.context,
            decision: .action(angle015Action(name: "ANG-015"))
        )
        let xzOneHundredThirtyFiveDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            xzOneHundredThirtyFiveDegreeAngleResponse
        )
        let xzOneHundredThirtyFiveDegreeAngleJSON = try #require(
            String(data: xzOneHundredThirtyFiveDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(xzOneHundredThirtyFiveDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(xzOneHundredThirtyFiveDegreeAngleJSON.contains("\"caseID\":\"ANG-015\""))
        let xzOneHundredThirtyFiveDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: xzOneHundredThirtyFiveDegreeAngleResponseData
        )
        #expect(xzOneHundredThirtyFiveDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(xzOneHundredThirtyFiveDegreeAngleEvaluation.error == nil)

        let yzOneHundredFiftyDegreeAngleRequest = try adapter.makeRequest(for: "ANG-016")
        let yzOneHundredFiftyDegreeAngleResponse = try CADJSONCandidateResponseEnvelope(
            caseID: yzOneHundredFiftyDegreeAngleRequest.caseID,
            context: yzOneHundredFiftyDegreeAngleRequest.context,
            decision: .action(angle016Action(name: "ANG-016"))
        )
        let yzOneHundredFiftyDegreeAngleResponseData = try CADJSONBoundedCodec.encode(
            yzOneHundredFiftyDegreeAngleResponse
        )
        let yzOneHundredFiftyDegreeAngleJSON = try #require(
            String(data: yzOneHundredFiftyDegreeAngleResponseData, encoding: .utf8)
        )
        #expect(yzOneHundredFiftyDegreeAngleJSON.contains("\"kind\":\"angle\""))
        #expect(yzOneHundredFiftyDegreeAngleJSON.contains("\"caseID\":\"ANG-016\""))
        let yzOneHundredFiftyDegreeAngleEvaluation = try await adapter.evaluate(
            responseData: yzOneHundredFiftyDegreeAngleResponseData
        )
        #expect(yzOneHundredFiftyDegreeAngleEvaluation.result?.outcome == .realized)
        #expect(yzOneHundredFiftyDegreeAngleEvaluation.error == nil)

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
    @Test(.timeLimit(.minutes(1)))
    func box001WireActionExecutesTheProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box001Action(name: "BOX-001"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON == #"{"caseID":"BOX-001","context":{"capabilities":{"statuses":[{"available":true,"id":"cad.solid.box","version":"1"}],"version":"agent-capabilities.v1"},"challenge":{"budget":{"maximumActions":32,"maximumReadRecords":64,"maximumRounds":16},"category":"BOX","id":"BOX-001","instruction":"Construct BOX-001 as a closed box with width 10.0 mm, depth 10.0 mm, and height 10.0 mm from origin (0.0, 0.0, 0.0) mm.","outputRoles":[{"description":"The requested closed box solid.","name":"solid"}],"requiredCapability":{"id":"cad.solid.box","version":"1"}},"priorResults":[],"remainingActions":32,"remainingRounds":16},"contextFingerprint":"cc334ec24aa58b08c216422200eeaba6040f82763b49cc4106b58e72e9b19290","schema":"rupa.agent-cad-benchmark.request.v1"}"#)
        #expect(responseJSON == #"{"caseID":"BOX-001","contextFingerprint":"cc334ec24aa58b08c216422200eeaba6040f82763b49cc4106b58e72e9b19290","decision":{"action":{"automation":{"kind":"solid","solid":{"depth":{"unit":"millimeter","value":10},"height":{"unit":"millimeter","value":10},"kind":"box","name":"BOX-001","origin":{"unit":"millimeter","x":0,"y":0,"z":0},"width":{"unit":"millimeter","value":10}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v5"}"#)

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-001")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box001Action(name: "BOX-001.wrong-width", width: 12))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-001")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder001WireActionExecutesProductionAnalyticSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "CYL-001")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(cylinder001Action(name: "CYL-001"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"CYL-001\""))
        #expect(requestJSON.contains("radius 5.0 mm and depth 20.0 mm"))
        #expect(responseJSON.contains("\"schema\":\"rupa.agent-cad-benchmark.candidate-response.v5\""))
        #expect(responseJSON.contains("\"kind\":\"cylinder\""))
        #expect(responseJSON.contains("\"baseCenter\""))
        #expect(responseJSON.contains("\"axis\":{\"x\":0,\"y\":0,\"z\":1}"))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "CYL-001")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(cylinder001Action(name: "CYL-001.wrong-radius", radius: 6))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)

    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cylinder002WireActionExecutesTranslatedXAxisProductionRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "CYL-002")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(cylinder002Action(name: "CYL-002"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"CYL-002\""))
        #expect(requestJSON.contains("base center (25.0, -25.0, 0.0) mm"))
        #expect(requestJSON.contains("radius 10.0 mm and depth 50.0 mm"))
        #expect(responseJSON.contains("\"schema\":\"rupa.agent-cad-benchmark.candidate-response.v5\""))
        #expect(responseJSON.contains("\"axis\":{\"x\":1,\"y\":0,\"z\":0}"))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "CYL-002")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(cylinder002Action(
                name: "CYL-002.wrong-axis",
                axis: CADDirection3D(x: 0, y: 0, z: 1)
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "CYL-002")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)

        do {
            _ = try adapter.makeRequest(for: "CYL-003")
            Issue.record("CYL-003 must remain inactive.")
        } catch let error as CADJSONAdapterError {
            #expect(error == .inactiveCase)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box002WireActionExecutesTheTranslatedProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-002")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box002Action(name: "BOX-002"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-002\""))
        #expect(requestJSON.contains("origin (20.0, -20.0, 0.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-002\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":25"))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-002")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box002Action(name: "BOX-002.wrong-origin", originX: 25))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-002")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box003WireActionExecutesTheTranslatedProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-003")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box003Action(name: "BOX-003"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-003\""))
        #expect(requestJSON.contains("origin (-25.0, 15.0, 5.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-003\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":50"))
        #expect(responseJSON.contains("\"value\":30"))
        #expect(responseJSON.contains("\"value\":20"))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-003")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box003Action(
                name: "BOX-003.wrong-depth-height",
                depth: 20,
                height: 30
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-003")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box004WireActionExecutesTheTranslatedProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-004")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box004Action(name: "BOX-004"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-004\""))
        #expect(requestJSON.contains("origin (0.0, 0.0, -25.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-004\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":100"))
        #expect(responseJSON.contains("\"value\":50"))
        #expect(responseJSON.contains("\"value\":75"))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-004")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box004Action(
                name: "BOX-004.wrong-origin-z",
                originZ: 0
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-004")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box005WireActionExecutesTheTranslatedProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-005")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box005Action(name: "BOX-005"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-005\""))
        #expect(requestJSON.contains("origin (-125.0, -50.0, 0.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-005\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":250"))
        #expect(responseJSON.contains("\"value\":100"))
        #expect(responseJSON.contains("\"value\":125"))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-005")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box005Action(
                name: "BOX-005.wrong-height",
                height: 100
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-005")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box006WireActionExecutesTheMeterScaleProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-006")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box006Action(name: "BOX-006"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-006\""))
        #expect(requestJSON.contains("origin (0.0, 0.0, 0.0) m"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-006\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":0.1"))
        #expect(responseJSON.contains("\"value\":0.05"))
        #expect(responseJSON.contains("\"value\":0.025"))
        #expect(responseJSON.contains("\"unit\":\"meter\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-006")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box006Action(
                name: "BOX-006.wrong-unit",
                unit: .centimeter
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-006")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box007WireActionExecutesTheImperialProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-007")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box007Action(name: "BOX-007"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-007\""))
        #expect(requestJSON.contains("origin (-1.0, -1.0, 0.0) in"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-007\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":1"))
        #expect(responseJSON.contains("\"value\":2"))
        #expect(responseJSON.contains("\"value\":3"))
        #expect(responseJSON.contains("\"unit\":\"inch\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-007")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box007Action(
                name: "BOX-007.wrong-unit",
                unit: .millimeter
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-007")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box008WireActionExecutesTheTranslatedCubeProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-008")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box008Action(name: "BOX-008"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-008\""))
        #expect(requestJSON.contains("origin (100.0, 100.0, 100.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-008\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":300"))
        #expect(responseJSON.contains("\"unit\":\"millimeter\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-008")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box008Action(
                name: "BOX-008.wrong-origin",
                originX: 0
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-008")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box009WireActionExecutesTheNegativePlacementCubeProductionSolidRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-009")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box009Action(name: "BOX-009"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-009\""))
        #expect(requestJSON.contains("origin (-12.0, 0.0, 0.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-009\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":12"))
        #expect(responseJSON.contains("\"unit\":\"millimeter\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-009")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box009Action(
                name: "BOX-009.wrong-height",
                height: 10
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-009")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box010WireActionExecutesTheRectangularSolidProductionRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-010")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box010Action(name: "BOX-010"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-010\""))
        #expect(requestJSON.contains("origin (0.0, -100.0, 50.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-010\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":400"))
        #expect(responseJSON.contains("\"value\":200"))
        #expect(responseJSON.contains("\"value\":50"))
        #expect(responseJSON.contains("\"unit\":\"millimeter\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-010")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box010Action(
                name: "BOX-010.swapped-width-depth",
                width: 200,
                depth: 400
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-010")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box011WireActionExecutesTheMetreCubeProductionRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-011")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box011Action(name: "BOX-011"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-011\""))
        #expect(requestJSON.contains("origin (-0.25, -0.25, 0.0) m"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-011\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":0.5"))
        #expect(responseJSON.contains("\"unit\":\"meter\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-011")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box011Action(
                name: "BOX-011.wrong-unit",
                unit: .centimeter
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-011")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box012WireActionExecutesTheMillimeterSolidProductionRoute() async throws {
        let adapter = CADJSONAdapter()
        let request = try adapter.makeRequest(for: "BOX-012")
        let response = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box012Action(name: "BOX-012"))
        )
        let requestJSON = String(decoding: try CADJSONBoundedCodec.encode(request), as: UTF8.self)
        let responseJSON = String(decoding: try CADJSONBoundedCodec.encode(response), as: UTF8.self)

        #expect(requestJSON.contains("\"caseID\":\"BOX-012\""))
        #expect(requestJSON.contains("origin (25.0, 25.0, -75.0) mm"))
        #expect(responseJSON.contains("\"caseID\":\"BOX-012\""))
        #expect(responseJSON.contains("\"kind\":\"solid\""))
        #expect(responseJSON.contains("\"kind\":\"box\""))
        #expect(responseJSON.contains("\"value\":75"))
        #expect(responseJSON.contains("\"value\":125"))
        #expect(responseJSON.contains("\"value\":175"))
        #expect(responseJSON.contains("\"unit\":\"millimeter\""))

        let evaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(response)
        )
        #expect(evaluation.caseID == "BOX-012")
        #expect(evaluation.result?.outcome == .realized)
        #expect(evaluation.error == nil)

        let wrongResponse = try CADJSONCandidateResponseEnvelope(
            caseID: request.caseID,
            context: request.context,
            decision: .action(box012Action(
                name: "BOX-012.wrong-z",
                originZ: -50
            ))
        )
        let wrongEvaluation = try await adapter.evaluate(
            responseData: CADJSONBoundedCodec.encode(wrongResponse)
        )
        #expect(wrongEvaluation.caseID == "BOX-012")
        #expect(wrongEvaluation.result?.outcome == .invalidSubmission)
        #expect(wrongEvaluation.error == nil)
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
        let lineResponseFixture = #"{"caseID":"LIN-001","contextFingerprint":"f339619e0f34caca2a5a08eaf48080ffe7d783ce7bcf228197f494a86657eaaf","decision":{"action":{"automation":{"kind":"sketch","sketch":{"end":{"unit":"millimeter","x":25,"y":0,"z":0},"kind":"line","name":"LIN-001","plane":"xy","start":{"unit":"millimeter","x":0,"y":0,"z":0}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v5"}"#
        let rectangleResponseFixture = #"{"caseID":"REC-001","contextFingerprint":"73e04af4c7a56666e42a84e0c10c3413e5cb860df59b74d707e7c504c05d7ea5","decision":{"action":{"automation":{"kind":"sketch","sketch":{"center":{"unit":"millimeter","x":0,"y":0,"z":0},"height":{"unit":"millimeter","value":20},"kind":"rectangle","name":"REC-001","plane":"xy","width":{"unit":"millimeter","value":40}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v5"}"#
        let circleResponseFixture = #"{"caseID":"CIR-001","contextFingerprint":"934124a9a32a3830d1ae07b9b9ddffc9f21354f6edc6240cc8adc2850342a26a","decision":{"action":{"automation":{"kind":"sketch","sketch":{"center":{"unit":"millimeter","x":0,"y":0,"z":0},"kind":"circle","name":"CIR-001","plane":"xy","radius":{"unit":"millimeter","value":5}}},"kind":"automation"},"kind":"action"},"schema":"rupa.agent-cad-benchmark.candidate-response.v5"}"#
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
    func requestAndLiveContextsAreValueEqualAndAllSixtySixRequestsStayBounded() throws {
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
            } else if caseID.rawValue == "BOX-002" {
                action = box002Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-003" {
                action = box003Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-004" {
                action = box004Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-005" {
                action = box005Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-006" {
                action = box006Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-007" {
                action = box007Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-008" {
                action = box008Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-009" {
                action = box009Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-010" {
                action = box010Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-011" {
                action = box011Action(name: caseID.rawValue)
            } else if caseID.rawValue == "BOX-012" {
                action = box012Action(name: caseID.rawValue)
            } else if caseID.category == .box {
                action = box001Action(name: caseID.rawValue)
            } else if caseID.rawValue == "CYL-002" {
                action = cylinder002Action(name: caseID.rawValue)
            } else if caseID.category == .cylinder {
                action = cylinder001Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-002" {
                action = angle002Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-003" {
                action = angle003Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-004" {
                action = angle004Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-005" {
                action = angle005Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-006" {
                action = angle006Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-007" {
                action = angle007Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-008" {
                action = angle008Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-009" {
                action = angle009Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-010" {
                action = angle010Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-011" {
                action = angle011Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-012" {
                action = angle012Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-013" {
                action = angle013Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-014" {
                action = angle014Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-015" {
                action = angle015Action(name: caseID.rawValue)
            } else if caseID.rawValue == "ANG-016" {
                action = angle016Action(name: caseID.rawValue)
            } else if caseID.category == .angle {
                action = angleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-002" {
                action = cir002CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-003" {
                action = cir003CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-004" {
                action = cir004CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-005" {
                action = cir005CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-006" {
                action = cir006CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-007" {
                action = cir007CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-008" {
                action = cir008CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-009" {
                action = cir009CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-010" {
                action = cir010CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-011" {
                action = cir011CircleAction(name: caseID.rawValue)
            } else if caseID.rawValue == "CIR-012" {
                action = cir012CircleAction(name: caseID.rawValue)
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

        #expect(executor.activatedCaseIDs.count == 66)
        #expect(largestRequest < 16_384)
    }

    @MainActor
    @Test
    func activatedRequestSequenceHasAStableLengthPrefixedAggregateDigest() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let adapter = CADJSONAdapter(executor: executor)
        let historicalIDs = (1...12).map { String(format: "LIN-%03d", $0) }
            + (1...8).map { String(format: "REC-%03d", $0) }
        let currentIDs = historicalIDs + ["REC-009", "REC-010", "REC-011", "REC-012", "CIR-001", "CIR-002", "CIR-003", "CIR-004", "CIR-005", "CIR-006", "CIR-007", "CIR-008", "CIR-009", "CIR-010", "CIR-011", "CIR-012", "ANG-001", "ANG-002", "ANG-003", "ANG-004", "ANG-005", "ANG-006", "ANG-007", "ANG-008", "ANG-009", "ANG-010", "ANG-011", "ANG-012", "ANG-013", "ANG-014", "ANG-015", "ANG-016", "BOX-001", "BOX-002", "BOX-003", "BOX-004", "BOX-005", "BOX-006", "BOX-007", "BOX-008", "BOX-009", "BOX-010", "BOX-011", "BOX-012", "CYL-001", "CYL-002"]
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

        let cir004ID: CADBenchmarkCaseID = "CIR-004"
        let cir004Request = try adapter.encodeRequest(for: cir004ID)
        appendLengthPrefixed(Data(cir004ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir004Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir004Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "2be3d440bd56644efc614c520ffac49cad8a5cd4eb1d0629447e620dcf9e48fc")

        let cir005ID: CADBenchmarkCaseID = "CIR-005"
        let cir005Request = try adapter.encodeRequest(for: cir005ID)
        appendLengthPrefixed(Data(cir005ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir005Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir005Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "986346014f5b9028d60a2b861f11b082192366c329911d25acfbd8de4d4e8b87")

        let cir006ID: CADBenchmarkCaseID = "CIR-006"
        let cir006Request = try adapter.encodeRequest(for: cir006ID)
        appendLengthPrefixed(Data(cir006ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir006Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir006Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "bc8aa8e33085d405126a86a4a78b8ae212566e0660c6325b23033d2120a156f8")

        let cir007ID: CADBenchmarkCaseID = "CIR-007"
        let cir007Request = try adapter.encodeRequest(for: cir007ID)
        appendLengthPrefixed(Data(cir007ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir007Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir007Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "7469957587756d1f498f45f8718aa5b16d16261ed9a9f73c14afbd1802e77c81")

        let cir008ID: CADBenchmarkCaseID = "CIR-008"
        let cir008Request = try adapter.encodeRequest(for: cir008ID)
        appendLengthPrefixed(Data(cir008ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir008Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir008Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "d73110c966919f5583df9ff7987fd9cd25a899a588031031f4880be220bf1f22")

        let cir009ID: CADBenchmarkCaseID = "CIR-009"
        let cir009Request = try adapter.encodeRequest(for: cir009ID)
        appendLengthPrefixed(Data(cir009ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir009Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir009Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "0a2348cfddafa83d023bda2ee635a84ab3f9990c08aff969edfa1e4ba02987e5")

        let cir010ID: CADBenchmarkCaseID = "CIR-010"
        let cir010Request = try adapter.encodeRequest(for: cir010ID)
        appendLengthPrefixed(Data(cir010ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir010Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir010Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "e03c0148b189dc10b41ced6de9718846d3c20ee76c148b561d0108c1ba4c57e5")

        let cir011ID: CADBenchmarkCaseID = "CIR-011"
        let cir011Request = try adapter.encodeRequest(for: cir011ID)
        appendLengthPrefixed(Data(cir011ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir011Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir011Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "27927a87226c9931ec4337b2ef653e08f2edd8217b95646bcea78d58d6c270e6")

        let cir012ID: CADBenchmarkCaseID = "CIR-012"
        let cir012Request = try adapter.encodeRequest(for: cir012ID)
        appendLengthPrefixed(Data(cir012ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cir012Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cir012Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "5c8cd7cbe83738f91459b1103d291194143042bde7e6f9c8415aa91f66ce5a28")

        let ang001ID: CADBenchmarkCaseID = "ANG-001"
        let ang001Request = try adapter.encodeRequest(for: ang001ID)
        appendLengthPrefixed(Data(ang001ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang001Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang001Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "b66ed71a2efccf115a81033c3bda0e9335c0a2a4c695ba5c58b49c9df7341b4e")

        let ang002ID: CADBenchmarkCaseID = "ANG-002"
        let ang002Request = try adapter.encodeRequest(for: ang002ID)
        appendLengthPrefixed(Data(ang002ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang002Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang002Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "6bd274e57fae5345c067f63a5191b60ccfbf35a76d794491b7a10df9a0c985d6")

        let ang003ID: CADBenchmarkCaseID = "ANG-003"
        let ang003Request = try adapter.encodeRequest(for: ang003ID)
        appendLengthPrefixed(Data(ang003ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang003Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang003Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "83f7c7b54c95ed2fc0304b98c455d3981dcd51380da7414f397de191333b5e6a")

        let ang004ID: CADBenchmarkCaseID = "ANG-004"
        let ang004Request = try adapter.encodeRequest(for: ang004ID)
        appendLengthPrefixed(Data(ang004ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang004Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang004Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "e2f928ac390783e8bcf5fdbb4e368156a188e3b49e81fee845d72602fd1d0649")

        let ang005ID: CADBenchmarkCaseID = "ANG-005"
        let ang005Request = try adapter.encodeRequest(for: ang005ID)
        appendLengthPrefixed(Data(ang005ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang005Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang005Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "fb0228298f5bd1b38ddcafeeda2632236e487f2be8600e3abffed335f9f3df6d")

        let ang006ID: CADBenchmarkCaseID = "ANG-006"
        let ang006Request = try adapter.encodeRequest(for: ang006ID)
        appendLengthPrefixed(Data(ang006ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang006Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang006Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "a15fbc50a8f6476bd353b9508a10c88b6da03377aa173b413987e829642f16eb")

        let ang007ID: CADBenchmarkCaseID = "ANG-007"
        let ang007Request = try adapter.encodeRequest(for: ang007ID)
        appendLengthPrefixed(Data(ang007ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang007Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang007Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "b276bc61ebd50a39b603ba627890f6342121c2889f906b8349140f4bb932fbcd")

        let ang008ID: CADBenchmarkCaseID = "ANG-008"
        let ang008Request = try adapter.encodeRequest(for: ang008ID)
        appendLengthPrefixed(Data(ang008ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang008Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang008Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "47914bc2ecec829f01c24bfd62626a41e4a605a0a14c945bf6fc15913231d82c")

        let ang009ID: CADBenchmarkCaseID = "ANG-009"
        let ang009Request = try adapter.encodeRequest(for: ang009ID)
        appendLengthPrefixed(Data(ang009ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang009Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang009Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "6c9014e08de0670558528695d21790d489f0bc9516a6e1febefc6c3437b69c87")

        let ang010ID: CADBenchmarkCaseID = "ANG-010"
        let ang010Request = try adapter.encodeRequest(for: ang010ID)
        appendLengthPrefixed(Data(ang010ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang010Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang010Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "4f4f451db3ab64d9d5f5d657cb7b0ebe3c79a02d370ab2b56070b1d7e3396e65")

        let ang011ID: CADBenchmarkCaseID = "ANG-011"
        let ang011Request = try adapter.encodeRequest(for: ang011ID)
        appendLengthPrefixed(Data(ang011ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang011Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang011Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "08a9f3fa73e242fe7116dfb904e5d254fabe3a1cb61c2004021e239f42cde3de")

        let ang012ID: CADBenchmarkCaseID = "ANG-012"
        let ang012Request = try adapter.encodeRequest(for: ang012ID)
        appendLengthPrefixed(Data(ang012ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang012Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang012Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "f7476b4da91164043c29215821395b37b98537441e1d3e99542973809eea9efd")

        let ang013ID: CADBenchmarkCaseID = "ANG-013"
        let ang013Request = try adapter.encodeRequest(for: ang013ID)
        appendLengthPrefixed(Data(ang013ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang013Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang013Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "9164bb6b90dffb05f5c443b7918d273bb83de8ecbc90f4feebfbc31139193b3e")

        let ang014ID: CADBenchmarkCaseID = "ANG-014"
        let ang014Request = try adapter.encodeRequest(for: ang014ID)
        appendLengthPrefixed(Data(ang014ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang014Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang014Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "fde5e108d41d194197b4a2f0b88eb31b110ad3372d53bdddef51e29c8dc021ee")

        let ang015ID: CADBenchmarkCaseID = "ANG-015"
        let ang015Request = try adapter.encodeRequest(for: ang015ID)
        appendLengthPrefixed(Data(ang015ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang015Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang015Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "8a5baed7294693f150ce8e67494112f521b0667bfe1d4f6e45db0661e83d6f07")

        let ang016ID: CADBenchmarkCaseID = "ANG-016"
        let ang016Request = try adapter.encodeRequest(for: ang016ID)
        appendLengthPrefixed(Data(ang016ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(ang016Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: ang016Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "53836e6352b776f1b2a0eccd81cc17d7046a489782a5ad678236d920e36f8a7a")

        let box001ID: CADBenchmarkCaseID = "BOX-001"
        let box001Request = try adapter.encodeRequest(for: box001ID)
        appendLengthPrefixed(Data(box001ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box001Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box001Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "dd12c2cc346e37ec4f3dcecb396aa46bcfe69a82923a41041c36739b826d0b79")

        let box002ID: CADBenchmarkCaseID = "BOX-002"
        let box002Request = try adapter.encodeRequest(for: box002ID)
        appendLengthPrefixed(Data(box002ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box002Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box002Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "36bf68952c6a605df9e9bb4187929752ee42317f0a45506f9847bc265ac065ec")

        let box003ID: CADBenchmarkCaseID = "BOX-003"
        let box003Request = try adapter.encodeRequest(for: box003ID)
        appendLengthPrefixed(Data(box003ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box003Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box003Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "74353ca8a790b520689404973dbc370b59ec77f50ec81ac3a48c4387b94862c3")

        let box004ID: CADBenchmarkCaseID = "BOX-004"
        let box004Request = try adapter.encodeRequest(for: box004ID)
        appendLengthPrefixed(Data(box004ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box004Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box004Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "dc4c6fa1f96ae4181f54d48b34ae77b95d2548bc90935a3c7f0d7c51743efd9a")

        let box005ID: CADBenchmarkCaseID = "BOX-005"
        let box005Request = try adapter.encodeRequest(for: box005ID)
        appendLengthPrefixed(Data(box005ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box005Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box005Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "a7ae81207efbb6d315d2a11b61f7cbfa17d997e59ca74db7404c310bbecc24bb")

        let box006ID: CADBenchmarkCaseID = "BOX-006"
        let box006Request = try adapter.encodeRequest(for: box006ID)
        appendLengthPrefixed(Data(box006ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box006Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box006Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "1f0ecb07744e6525d6e68df789fb529ff3ad91220ff515603ea26a2f123d88d9")

        let box007ID: CADBenchmarkCaseID = "BOX-007"
        let box007Request = try adapter.encodeRequest(for: box007ID)
        appendLengthPrefixed(Data(box007ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box007Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box007Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "22a57a1631712e9cc4cac3a50c5d2886909e804d2e44338b15911637318b74be")

        let box008ID: CADBenchmarkCaseID = "BOX-008"
        let box008Request = try adapter.encodeRequest(for: box008ID)
        appendLengthPrefixed(Data(box008ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box008Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box008Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "6f7467cbe5f511521c5a1ba79811fb38fc60a9f77c8585a1950eff7ea9033f81")

        let box009ID: CADBenchmarkCaseID = "BOX-009"
        let box009Request = try adapter.encodeRequest(for: box009ID)
        appendLengthPrefixed(Data(box009ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box009Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box009Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "01837d577b9eaecc860279b474e8190c852777cf359910ced4196a1ca5c2e403")

        let box010ID: CADBenchmarkCaseID = "BOX-010"
        let box010Request = try adapter.encodeRequest(for: box010ID)
        appendLengthPrefixed(Data(box010ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box010Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box010Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "7cce27a557abbfed9b6d8f1f020e14fff0b366497b79373071c7df625aa2078b")

        let box011ID: CADBenchmarkCaseID = "BOX-011"
        let box011Request = try adapter.encodeRequest(for: box011ID)
        appendLengthPrefixed(Data(box011ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box011Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box011Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "404f138058b2e8826a582a2f957ffc6fae0174ef4a11b6f0820dccb14378917a")

        let box012ID: CADBenchmarkCaseID = "BOX-012"
        let box012Request = try adapter.encodeRequest(for: box012ID)
        appendLengthPrefixed(Data(box012ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(box012Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: box012Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "e7f1f8084f0c61855d28fe7e7e28a0860eba3ab6993ae5b9859d28448948618c")

        let cylinder001ID: CADBenchmarkCaseID = "CYL-001"
        let cylinder001Request = try adapter.encodeRequest(for: cylinder001ID)
        appendLengthPrefixed(Data(cylinder001ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cylinder001Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cylinder001Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "ad9d6ca086b3be46bcd2d778eb22beaa3b506a4f84216e0195f11aafbbef19e0")

        let cylinder002ID: CADBenchmarkCaseID = "CYL-002"
        let cylinder002Request = try adapter.encodeRequest(for: cylinder002ID)
        appendLengthPrefixed(Data(cylinder002ID.rawValue.utf8), to: &currentAggregate)
        appendLengthPrefixed(bigEndianBytes(UInt64(cylinder002Request.count)), to: &currentAggregate)
        appendLengthPrefixed(Data(SHA256.hash(data: cylinder002Request)), to: &currentAggregate)
        #expect(sha256Hex(currentAggregate) == "53b35fd441b1bbb210c20c55e4913e5bcea19213dba1b684ab1cf9b916797702")
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

        let inactiveResponse = try CADJSONCandidateResponseEnvelope(
            schema: CADJSONAdapterSchema.candidateResponse,
            caseID: "CYL-003",
            contextFingerprint: String(repeating: "0", count: 64),
            decision: .action(cylinder002Action(name: "CYL-003"))
        )
        do {
            _ = try await adapter.evaluate(response: inactiveResponse)
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

        let legacy = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v5","caseID":"LIN-001","contextFingerprint":"0000000000000000000000000000000000000000000000000000000000000000","decision":{"action":{"automation":{"sketch":{"line":{"name":"legacy"}}}}}}"#.utf8)
        expectAdapterError(.invalidDecision) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: legacy
            )
        }

        let unknown = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v5","caseID":"LIN-001","contextFingerprint":"0000000000000000000000000000000000000000000000000000000000000000","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.invalidDecision) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: unknown
            )
        }
    }

    @MainActor
    @Test
    func candidateResponseV1ThroughV4AreRejectedBeforeDecisionDecode() throws {
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

        let prior = replacing(
            try CADJSONBoundedCodec.encode(response),
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v2"
        )
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: prior
            )
        }

        let previous = replacing(
            try CADJSONBoundedCodec.encode(response),
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v3"
        )
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: previous
            )
        }

        let previousWithUnknownDecision = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v3","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: previousWithUnknownDecision
            )
        }

        let v4 = replacing(
            try CADJSONBoundedCodec.encode(response),
            from: CADJSONAdapterSchema.candidateResponse,
            to: "rupa.agent-cad-benchmark.candidate-response.v4"
        )
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: v4
            )
        }

        let v4WithUnknownDecision = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v4","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: v4WithUnknownDecision
            )
        }

        let priorWithUnknownDecision = Data(#"{"schema":"rupa.agent-cad-benchmark.candidate-response.v2","decision":{"kind":"future"}}"#.utf8)
        expectAdapterError(.unsupportedSchema) {
            _ = try CADJSONBoundedCodec.decode(
                CADJSONCandidateResponseEnvelope.self,
                from: priorWithUnknownDecision
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
