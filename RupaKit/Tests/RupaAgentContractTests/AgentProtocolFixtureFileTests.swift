import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import Testing
@testable import RupaAgent

@Suite("Semantic Agent protocol fixtures")
struct AgentProtocolFixtureFileTests {
    @Test func requestFixturesDecodeOnlySemanticRoutes() throws {
        let fixtures = try AgentProtocolFixtureFiles.loadJSONFiles(at: ["requests"])
        #expect(Set(fixtures.map(\.name)) == ["capability.invoke.json", "program.execute.json"])
        let codec = AgentMessageCodec()

        for fixture in fixtures {
            let envelope = try codec.decodeRequestEnvelope(from: fixture.data)
            #expect(envelope.method == fixture.method)
            switch envelope.params {
            case .invokeCapability(let request):
                #expect(fixture.method == "capability.invoke")
                #expect(request.request.schemaVersion == .init(major: 1, minor: 0, patch: 0))
                #expect(request.request.operationVersion == .init(major: 1, minor: 0, patch: 0))
            case .executeProgram(let request):
                #expect(fixture.method == "program.execute")
                #expect(request.program.schemaVersion == .init(major: 1, minor: 0, patch: 0))
            default:
                Issue.record("Semantic fixture decoded as a legacy request route.")
            }
        }
    }

    @Test func responseFixturesRoundTripSuccessAndTypedFailures() throws {
        let fixtures = try AgentProtocolFixtureFiles.loadJSONFiles(at: ["responses"])
        #expect(Set(fixtures.map(\.name)) == [
            "capability.invoke.success.json",
            "program.execute.committed-failure.json",
            "program.execute.prepublication-failure.json",
        ])
        let codec = AgentMessageCodec()

        for fixture in fixtures {
            let envelope = try codec.decodeResponseEnvelope(from: fixture.data)
            let response = try envelope.decodedResponse()
            #expect(envelope.method == fixture.method)
            #expect(envelope.id == fixture.id)

            do {
                _ = try codec.encode(response, id: fixture.id, method: fixture.method)
                Issue.record("A semantic fixture response was encoded without a response plan.")
            } catch let error as AgentResponseEncodingError {
                #expect(error == .responsePlanRequired(method: fixture.method))
            }

            let reservation = try codec.reserveResponse(
                requestID: fixture.id,
                method: fixture.method,
                authority: responseAuthority(response),
                requestedOutputs: [],
                resultCharge: emptyResultCharge
            )
            let encoded = try codec.encode(response, consuming: reservation)
            #expect(try codec.decodeResponse(
                from: encoded,
                expectedID: fixture.id,
                expectedMethod: fixture.method
            ) == response)
            #expect(reservation.isConsumed)
        }
    }

    private func responseAuthority(_ response: AgentResponse) -> AgentProjectAuthorityCoordinate {
        switch response {
        case .capabilityExecution(.success(.preview(let receipt))):
            return receipt.authority
        case .capabilityExecution(.success(.committed(let receipt))):
            return receipt.authority
        case .capabilityExecution(.committedFailure(let failure)):
            return failure.authority
        case .programExecution(.success(.preview(let receipt))):
            return receipt.authority
        case .programExecution(.success(.committed(let receipt))):
            return receipt.authority
        case .programExecution(.committedFailure(let failure)):
            return failure.authority
        case .capabilityExecution(.prepublicationFailure),
             .programExecution(.prepublicationFailure):
            return fixtureAuthority
        default:
            Issue.record("Expected a semantic fixture response.")
            return fixtureAuthority
        }
    }

    private var emptyResultCharge: SemanticResultCharge {
        SemanticResultCharge(
            requestedOutputCount: 0,
            diagnosticRecordCount: 0,
            diagnosticScalarCount: 0,
            diagnosticStringUTF8ByteCount: 0,
            telemetryRecordCount: 0,
            telemetryScalarCount: 0,
            telemetryStringUTF8ByteCount: 0
        )
    }

    private var fixtureAuthority: AgentProjectAuthorityCoordinate {
        AgentProjectAuthorityCoordinate(
            projectID: ProjectID(rawValue: "project.test"),
            documentGeneration: DocumentGeneration(0),
            transactionRevision: DocumentTransactionRevision(0),
            publicationSequence: 0,
            workspaceRevision: WorkspaceRevision(0)
        )
    }
}

private struct AgentProtocolFixtureFile: Sendable {
    let name: String
    let id: String
    let method: String
    let data: Data
}

private enum AgentProtocolFixtureFiles {
    static func loadJSONFiles(at components: [String]) throws -> [AgentProtocolFixtureFile] {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("SemanticProtocol")
        for component in components {
            directory.appendPathComponent(component)
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.map { url in
            let data = try Data(contentsOf: url)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return AgentProtocolFixtureFile(
                name: url.lastPathComponent,
                id: try #require(json["id"] as? String),
                method: try #require(json["method"] as? String),
                data: data
            )
        }
    }
}
