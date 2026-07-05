import Foundation
import Testing
import RupaCore
@testable import RupaAgent

@Suite("Automation protocol fixture files")
struct AgentProtocolFixtureFileTests {
    @Test func requestFixturesCoverEveryAgentMethod() throws {
        let fixtures = try AgentProtocolFixtureFiles.loadJSONFiles(at: ["requests"])
        let fixtureMethods = Set(fixtures.map(\.stem))

        #expect(fixtureMethods == Self.allRequestMethods)

        let codec = AgentMessageCodec()
        for fixture in fixtures {
            let envelope = try codec.decodeRequestEnvelope(from: fixture.data)
            #expect(envelope.method == fixture.stem)
            #expect(envelope.params.methodName == fixture.stem)
        }
    }

    @Test func successResponseFixturesDecodeAsFlatResults() throws {
        let fixtures = try AgentProtocolFixtureFiles.loadJSONFiles(at: ["responses", "success"])
        let codec = AgentMessageCodec()

        #expect(Set(fixtures.map(\.stem)) == ["agent.status", "command.apply", "parameter.setExpression"])

        for fixture in fixtures {
            let envelope = try codec.decodeResponseEnvelope(from: fixture.data)
            let response = try envelope.decodedResponse()
            #expect(envelope.method == fixture.stem)
            #expect(envelope.result != nil)
            switch fixture.stem {
            case "agent.status":
                guard case .status(let status) = response else {
                    Issue.record("agent.status fixture must decode as AgentResponse.status.")
                    continue
                }
                #expect(status.running)
                #expect(status.sessionCount == 2)
            case "command.apply":
                guard case .command(let result) = response else {
                    Issue.record("command.apply fixture must decode as AgentResponse.command.")
                    continue
                }
                #expect(result.commandName == "setRulerConfiguration")
                #expect(result.generation == DocumentGeneration(4))
                #expect(result.didMutate)
                #expect(result.workspaceScale?.matchedPreset == .sitePlanning)
                #expect(result.workspaceScale?.displayUnit == .kilometer)
                #expect(result.workspaceInteractionScale?.operationStep.meters == 100.0)
                #expect(result.workspaceInteractionScale?.operationStep.displayValue == 0.1)
                #expect(result.workspaceInteractionScale?.operationStep.displayUnitSymbol == "km")
                #expect(result.workspaceInteractionScale?.slotWidth.meters == 200.0)
                #expect(result.workspaceBounds?.maximumSpan == 25_000.0)
                #expect(result.viewportGridSettings?.visualSpacingMode == .adaptive)
                #expect(result.viewportGridScale?.snapStep.meters == 100.0)
                #expect(result.viewportGridScale?.snapStep.displayValue == 0.1)
                #expect(result.viewportGridScale?.snapStep.displayUnitSymbol == "km")
                #expect(result.viewportGridScale?.configuredMajorStep.text == "1 km")
                #expect(result.viewportGridScale?.workspaceSpan.text == "100 km")
            case "parameter.setExpression":
                guard case .command(let result) = response else {
                    Issue.record("parameter.setExpression fixture must decode as AgentResponse.command.")
                    continue
                }
                #expect(result.commandName == "upsertParameter")
                #expect(result.generation == DocumentGeneration(10))
            default:
                Issue.record("Unexpected success response fixture: \(fixture.name).")
            }
        }
    }

    @Test func errorResponseFixturesDecodeAsFailures() throws {
        let fixtures = try AgentProtocolFixtureFiles.loadJSONFiles(at: ["responses", "error"])
        let codec = AgentMessageCodec()

        #expect(Set(fixtures.map(\.stem)) == ["command.apply"])

        for fixture in fixtures {
            let envelope = try codec.decodeResponseEnvelope(from: fixture.data)
            let response = try envelope.decodedResponse()
            #expect(envelope.method == fixture.stem)
            #expect(envelope.error != nil)
            guard case .failure(let error) = response else {
                Issue.record("Error fixture must decode as AgentResponse.failure.")
                continue
            }
            #expect(error.code == .documentGenerationMismatch)
        }
    }

    @Test func invalidFixturesAreRejected() throws {
        let fixtures = try AgentProtocolFixtureFiles.loadJSONFiles(at: ["invalid"])
        let codec = AgentMessageCodec()

        #expect(fixtures.isEmpty == false)

        for fixture in fixtures {
            var caught: EditorError?
            do {
                _ = try codec.decodeRequestEnvelope(from: fixture.data)
            } catch let error as EditorError {
                caught = error
            }
            #expect(caught?.code == .commandInvalid)
        }
    }

    private static let allRequestMethods: Set<String> = [
        "agent.capabilities",
        "agent.status",
        "agent.cadInteractionQualityAssessment",
        "sessions.list",
        "command.apply",
        "parameter.setExpression",
        "document.setSurfaceFrameDisplay",
        "document.movePolySplineSurfaceVertex",
        "document.parameters",
        "document.evaluate",
        "document.measure",
        "selection.measure",
        "snap.resolve",
        "document.constructionPlaneSummary",
        "document.designDisplaySnapshot",
        "document.patternArraySummary",
        "document.meshSummary",
        "document.polySplineMeshAnalysis",
        "document.sketchEntitySummary",
        "document.sketchDimensionSummary",
        "selection.dimensionEvaluation",
        "document.curveAnalysis",
        "document.topologySummary",
        "document.sweepEvaluationPlan",
        "document.booleanEvaluationPlan",
        "document.objectDimensionSummary",
        "document.surfaceSourceSummary",
        "document.surfaceAnalysis",
        "document.surfaceFrames",
        "document.surfaceContinuitySummary",
        "document.surfaceBoundaryContinuityCompatibility",
        "selection.selectTargets",
        "document.save",
        "document.export",
    ]
}

private struct AgentProtocolFixtureFile: Sendable {
    var name: String
    var stem: String
    var data: Data
}

private enum AgentProtocolFixtureFiles {
    static func loadJSONFiles(at components: [String]) throws -> [AgentProtocolFixtureFile] {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("AutomationProtocol")
        for component in components {
            directory.appendPathComponent(component)
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in lhs.lastPathComponent < rhs.lastPathComponent }

        return try files.map { url in
            AgentProtocolFixtureFile(
                name: url.lastPathComponent,
                stem: url.deletingPathExtension().lastPathComponent,
                data: try Data(contentsOf: url)
            )
        }
    }
}
