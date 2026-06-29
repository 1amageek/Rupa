import ArgumentParser
import Foundation
import Testing
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAgentTransport
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func cliExecutablePrintsCapabilities() async throws {
    let result = try await runCLI(["capabilities"])

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(result.standardOutput.contains("describeDocument"))
    #expect(result.standardOutput.contains("exportDocument"))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableValidatesClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-validate.swcad")
    try DocumentFileService().save(.empty(named: "Process Validate"), to: documentURL)

    let result = try await runCLI([
        "validate",
        documentURL.path,
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Validation finished.")
    #expect(response.generation == 0)
    #expect(!response.dirty)
    #expect(!response.saved)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableParameterSetPersistsClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-param.swcad")
    try DocumentFileService().save(.empty(named: "Process Parameter"), to: documentURL)

    let result = try await runCLI([
        "param",
        "set",
        documentURL.path,
        "width",
        "12",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let width = try #require(
        loaded.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    let resolved = try loaded.cadDocument.parameters.resolvedValue(for: width.expression)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Parameter width updated.")
    #expect(response.generation == 1)
    #expect(response.saved)
    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 0.012) < 0.000_000_000_001)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableParameterFormulaAndListClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-param-formula.swcad")
    try DocumentFileService().save(.empty(named: "Process Formula"), to: documentURL)

    let widthResult = try await runCLI([
        "param",
        "set",
        documentURL.path,
        "width",
        "10",
        "--unit",
        "millimeter",
        "--mode",
        "file",
    ])
    let heightResult = try await runCLI([
        "param",
        "set",
        documentURL.path,
        "height",
        "--expression",
        "width * 2",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let heightResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: heightResult.standardOutputData
    )
    let listResult = try await runCLI([
        "param",
        "list",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let listResponse = try JSONDecoder().decode(
        CLIParameterListResponse.self,
        from: listResult.standardOutputData
    )
    let height = try #require(listResponse.parameters.first { $0.name == "height" })

    #expect(widthResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: widthResult.standardError))
    #expect(heightResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: heightResult.standardError))
    #expect(heightResponse.message == "Parameter height updated.")
    #expect(heightResponse.generation == 1)
    #expect(heightResponse.saved)
    #expect(listResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: listResult.standardError))
    #expect(listResponse.message == "2 parameters.")
    #expect(listResponse.generation == 0)
    #expect(!listResponse.dirty)
    #expect(listResponse.parameters.map(\.name) == ["height", "width"])
    #expect(height.expression == "(width * 2)")
    #expect(height.resolvedKind == .length)
    #expect(abs((height.resolvedValue ?? 0.0) - 0.02) < 0.000_000_000_001)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableParameterDeleteClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-param-delete.swcad")
    try DocumentFileService().save(.empty(named: "Process Delete"), to: documentURL)

    let setResult = try await runCLI([
        "param",
        "set",
        documentURL.path,
        "width",
        "10",
        "--unit",
        "millimeter",
        "--mode",
        "file",
    ])
    let deleteResult = try await runCLI([
        "param",
        "delete",
        documentURL.path,
        "width",
        "--mode",
        "file",
        "--json",
    ])
    let deleteResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: deleteResult.standardOutputData
    )
    let listResult = try await runCLI([
        "param",
        "list",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let listResponse = try JSONDecoder().decode(
        CLIParameterListResponse.self,
        from: listResult.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)

    #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
    #expect(deleteResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: deleteResult.standardError))
    #expect(deleteResponse.message == "Parameter width deleted.")
    #expect(deleteResponse.generation == 1)
    #expect(deleteResponse.saved)
    #expect(listResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: listResult.standardError))
    #expect(listResponse.message == "0 parameters.")
    #expect(listResponse.parameters.isEmpty)
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableAutoParameterFormulaAndListUsesLiveSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-live-param-formula.swcad")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try DocumentFileService().save(.empty(named: "Persisted"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open Params"))
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    server.register(session: session, path: documentURL)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let setResult = try await runCLI([
            "param",
            "set",
            documentURL.path,
            "height",
            "--expression",
            "width * 3",
            "--unit",
            "millimeter",
            "--mode",
            "auto",
            "--expected-generation",
            "1",
            "--agent-socket",
            socketURL.path,
            "--json",
        ])
        #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
        let setOutputData = try #require(
            setResult.standardOutputData.isEmpty ? nil : setResult.standardOutputData,
            Comment(rawValue: "stdout was empty. stderr: \(setResult.standardError)")
        )
        let setResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: setOutputData
        )
        let listResult = try await runCLI([
            "param",
            "list",
            documentURL.path,
            "--mode",
            "auto",
            "--expected-generation",
            "2",
            "--agent-socket",
            socketURL.path,
            "--json",
        ])
        let listResponse = try JSONDecoder().decode(
            CLIParameterListResponse.self,
            from: listResult.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)
        let height = try #require(listResponse.parameters.first { $0.name == "height" })

        #expect(setResponse.message == "Parameter height updated.")
        #expect(setResponse.generation == 2)
        #expect(setResponse.dirty)
        #expect(!setResponse.saved)
        #expect(listResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: listResult.standardError))
        #expect(listResponse.dirty)
        #expect(listResponse.parameters.map(\.name) == ["height", "width"])
        #expect(height.expression == "(width * 3)")
        #expect(abs((height.resolvedValue ?? 0.0) - 0.03) < 0.000_000_000_001)
        #expect(loaded.cadDocument.parameters.parameters.isEmpty)
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableRenameFileModePersistsClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-rename.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try await runCLI([
        "rename",
        documentURL.path,
        "--name",
        "After",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Document renamed to After.")
    #expect(response.generation == 1)
    #expect(response.saved)
    #expect(loaded.cadDocument.metadata.name == "After")
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableRenameDryRunDoesNotPersistClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-rename-dry.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try await runCLI([
        "rename",
        documentURL.path,
        "--name",
        "Dry",
        "--mode",
        "file",
        "--dry-run",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Document renamed to Dry.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSketchLineClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-line.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try await runCLI([
        "sketch",
        "line",
        documentURL.path,
        "--name",
        "Process Line",
        "--start-x",
        "0",
        "--start-y",
        "0",
        "--end-x",
        "12",
        "--end-y",
        "6",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Line sketch Process Line created.")
    #expect(response.saved)
    #expect(loaded.cadDocument.designGraph.order.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSketchRectangleClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-rectangle.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try await runCLI([
        "sketch",
        "rectangle",
        documentURL.path,
        "--name",
        "Process Rectangle",
        "--width",
        "20",
        "--height",
        "10",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let featureID = try #require(loaded.cadDocument.designGraph.order.first)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Rectangle sketch Process Rectangle created.")
    #expect(response.saved)
    #expect(sketch.entities.count == 4)
    #expect(loaded.cadDocument.designGraph.order.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableModelEvaluateAndExportClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-box.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("process-box.stl")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let modelResult = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--name",
        "Process Box",
        "--width",
        "20",
        "--height",
        "10",
        "--depth",
        "5",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let modelResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: modelResult.standardOutputData
    )
    let loadedAfterModel = try DocumentFileService().load(from: documentURL)

    let evalResult = try await runCLI([
        "eval",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let evalResponse = try JSONDecoder().decode(
        CLIEvaluationResponse.self,
        from: evalResult.standardOutputData
    )

    let meshResult = try await runCLI([
        "mesh",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let meshResponse = try JSONDecoder().decode(
        CLIMeshSummaryResponse.self,
        from: meshResult.standardOutputData
    )

    let exportResult = try await runCLI([
        "export",
        documentURL.path,
        "--output",
        outputURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let exportResponse = try JSONDecoder().decode(
        CLIExportResponse.self,
        from: exportResult.standardOutputData
    )

    #expect(modelResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(modelResponse.message == "Extruded rectangle Process Box created.")
    #expect(modelResponse.saved)
    #expect(loadedAfterModel.cadDocument.designGraph.order.count == 2)
    #expect(evalResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: evalResult.standardError))
    #expect(evalResponse.status == .valid)
    #expect(evalResponse.bodyCount == 1)
    #expect(meshResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: meshResult.standardError))
    #expect(meshResponse.meshSummary.bodyCount == 1)
    #expect(meshResponse.meshSummary.vertexCount > 0)
    #expect(meshResponse.meshSummary.triangleCount > 0)
    #expect(exportResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: exportResult.standardError))
    #expect(exportResponse.format == "stl")
    #expect(exportResponse.outputPath == outputURL.path)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableModelExtrudeExistingProfilePersistsClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-extrude.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let sketchResult = try await runCLI([
        "sketch",
        "rectangle",
        documentURL.path,
        "--name",
        "Process Profile",
        "--width",
        "20",
        "--height",
        "10",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let loadedAfterSketch = try DocumentFileService().load(from: documentURL)
    let sketchFeatureID = try #require(loadedAfterSketch.cadDocument.designGraph.order.first)

    let extrudeResult = try await runCLI([
        "model",
        "extrude",
        documentURL.path,
        "--name",
        "Process Extrude",
        "--profile-feature-id",
        sketchFeatureID.description,
        "--distance",
        "5",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: extrudeResult.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let extrudeFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
    let extrudeFeature = try #require(loaded.cadDocument.designGraph.nodes[extrudeFeatureID])
    guard case let .extrude(extrude) = extrudeFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(sketchResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: sketchResult.standardError))
    #expect(extrudeResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: extrudeResult.standardError))
    #expect(response.message == "Profile extrude Process Extrude created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 2)
    #expect(loaded.cadDocument.designGraph.dependencies == [
        DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID),
    ])
    #expect(extrude.profile.featureID == sketchFeatureID)
}

@Suite(.serialized)
struct CLIModelCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableModelRevolvePersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-revolve.swcad")
        var document = DesignDocument.empty(named: "Process Revolve")
        let profileID = try document.createRectangleSketchFromCorners(
            name: "Revolve Profile",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(12.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "model",
            "revolve",
            documentURL.path,
            "--name",
            "CLI Revolve",
            "--profile-feature-id",
            profileID.description,
            "--profile-index",
            "0",
            "--axis-origin-x",
            "0",
            "--axis-origin-y",
            "0",
            "--axis-origin-z",
            "0",
            "--axis-unit",
            "millimeter",
            "--axis-direction-x",
            "0",
            "--axis-direction-y",
            "1",
            "--axis-direction-z",
            "0",
            "--angle",
            "180",
            "--angle-unit",
            "degree",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLIResponse.self,
            from: result.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)
        let revolveFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
        let feature = try #require(loaded.cadDocument.designGraph.nodes[revolveFeatureID])
        guard case let .revolve(revolve) = feature.operation else {
            #expect(Bool(false))
            return
        }

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Revolve CLI Revolve source created.")
        #expect(response.saved)
        #expect(!response.dirty)
        #expect(loaded.cadDocument.designGraph.order.count == 2)
        #expect(revolve.profile == ProfileReference(featureID: profileID))
        #expect(revolve.axis == RevolveAxis(origin: .origin, direction: .unitY))
        #expect(revolve.angle == .angle(180.0, .degree))
        #expect(feature.inputs == [FeatureInput(featureID: profileID, role: .profile)])
        #expect(loaded.productMetadata.sceneNodes.values.contains { $0.reference == .body(revolveFeatureID) })
    }

    @Test(.timeLimit(.minutes(1)))
    func executableModelSweepPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sweep.swcad")
        var document = DesignDocument.empty(named: "Process Sweep")
        let profileID = try document.createRectangleSketch(
            name: "Sweep Profile",
            plane: .xy,
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
        let pathID = try document.createLineSketch(
            name: "Sweep Path",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "model",
            "sweep",
            documentURL.path,
            "--name",
            "CLI Sweep",
            "--profile-feature-id",
            profileID.description,
            "--path-feature-id",
            pathID.description,
            "--twist-angle",
            "0",
            "--angle-unit",
            "degree",
            "--end-scale",
            "1",
            "--distance-fraction",
            "1",
            "--alignment",
            "normal",
            "--corner-style",
            "mitre",
            "--result-kind",
            "solid",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLIResponse.self,
            from: result.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)
        let sweepFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
        let feature = try #require(loaded.cadDocument.designGraph.nodes[sweepFeatureID])
        guard case let .sweep(sweep) = feature.operation else {
            #expect(Bool(false))
            return
        }

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sweep CLI Sweep source created.")
        #expect(response.saved)
        #expect(!response.dirty)
        #expect(loaded.cadDocument.designGraph.order.count == 3)
        #expect(sweep.sections == [.profile(ProfileReference(featureID: profileID))])
        #expect(sweep.path == SweepPathReference(featureID: pathID))
        #expect(sweep.options.resultKind == .solid)
        #expect(feature.inputs == [
            FeatureInput(featureID: profileID, role: .profile),
            FeatureInput(featureID: pathID, role: .path),
        ])
        #expect(loaded.productMetadata.sceneNodes.values.contains { $0.reference == .body(sweepFeatureID) })
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableModelBoxDryRunDoesNotPersistClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-box-dry.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--name",
        "Dry Box",
        "--width",
        "20",
        "--height",
        "10",
        "--depth",
        "5",
        "--mode",
        "file",
        "--dry-run",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Extruded rectangle Dry Box created.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableModelBoxCornersPersistsClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-box-corners.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try await runCLI([
        "model",
        "box-corners",
        documentURL.path,
        "--name",
        "Footprint Box",
        "--first-x",
        "2",
        "--first-y",
        "1",
        "--opposite-x",
        "4",
        "--opposite-y",
        "7",
        "--depth",
        "3",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Extruded rectangle Footprint Box created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 2)
    #expect(loaded.productMetadata.sceneNodes.values.contains { node in
        node.name == "Footprint Box" && node.reference?.kind == .body
    })
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableExportDryRunDoesNotWriteOutputAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-export-dry.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("dry.stl")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let modelResult = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--width",
        "10",
        "--height",
        "10",
        "--depth",
        "10",
        "--mode",
        "file",
    ])
    #expect(modelResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))

    let result = try await runCLI([
        "export",
        documentURL.path,
        "--output",
        outputURL.path,
        "--mode",
        "file",
        "--dry-run",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIExportResponse.self,
        from: result.standardOutputData
    )

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.dryRun)
    #expect(response.byteCount == 0)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableExportPresetAndVersionedPolicyAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let preset = ExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Process Preset")
    document.productMetadata = metadata
    let documentURL = temporaryDirectory.appendingPathComponent("process-preset.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("preset.stl")
    let versionedURL = temporaryDirectory.appendingPathComponent("preset-1.stl")
    try DocumentFileService().save(document, to: documentURL)
    try Data("existing".utf8).write(to: outputURL)

    let modelResult = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--width",
        "10",
        "--height",
        "10",
        "--depth",
        "10",
        "--mode",
        "file",
    ])
    let result = try await runCLI([
        "export",
        documentURL.path,
        "--output",
        outputURL.path,
        "--mode",
        "file",
        "--preset",
        "Print STL",
        "--destination-policy",
        "versioned",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIExportResponse.self,
        from: result.standardOutputData
    )
    let existingOutput = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)

    #expect(modelResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.presetName == "Print STL")
    #expect(response.outputUnit == "millimeter")
    #expect(response.destinationPolicy == "versioned")
    #expect(response.outputPath == versionedURL.path)
    #expect(existingOutput == "existing")
    #expect(FileManager.default.fileExists(atPath: versionedURL.path))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableListsAndAttachesOpenSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-open.swcad")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    try DocumentFileService().save(.empty(named: "Process Open"), to: documentURL)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Process Open")),
        path: documentURL,
        id: sessionID
    )
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let sessionsResult = try await runCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            CLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )
        let attachResult = try await runCLI([
            "attach",
            documentURL.path,
            "--socket",
            socketURL.path,
            "--json",
        ])
        let attachResponse = try JSONDecoder().decode(
            CLIAttachResponse.self,
            from: attachResult.standardOutputData
        )

        #expect(sessionsResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
        #expect(sessionsResponse.sessions.count == 1)
        #expect(sessionsResponse.sessions[0].id == sessionID)
        #expect(attachResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: attachResult.standardError))
        #expect(attachResponse.sessionID == sessionID)
        #expect(attachResponse.path == documentURL.path)
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableRenameLiveMutatesOpenSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = AgentCommandController()
    server.register(session: EditorSession(document: .empty(named: "Before Live")), id: sessionID)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let renameResult = try await runCLI([
            "rename-live",
            sessionID.uuidString,
            "--name",
            "After Live",
            "--expected-generation",
            "0",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let renameResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: renameResult.standardOutputData
        )
        let sessionsResult = try await runCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            CLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )

        #expect(renameResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: renameResult.standardError))
        #expect(renameResponse.message == "Document renamed to After Live.")
        #expect(renameResponse.generation == 1)
        #expect(renameResponse.dirty)
        #expect(!renameResponse.saved)
        #expect(sessionsResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
        #expect(sessionsResponse.sessions.first?.displayName == "After Live")
        #expect(sessionsResponse.sessions.first?.generation == DocumentGeneration(1))
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSelectionReferencesSelectsLiveSurfaceControlPointAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Selection Reference"))
    _ = try #require(session.createPolySplineSurface(
        name: "CLI Surface Reference",
        sourceMesh: cliPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))
    let generation = session.generation
    let wasDirty = session.isDirty
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let referenceData = try JSONEncoder().encode(controlPoint.selectionReference)
    let referenceJSON = String(decoding: referenceData, as: UTF8.self)
    server.register(session: session, id: sessionID)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try await runCLI([
            "selection",
            "references",
            "--session-id",
            sessionID.uuidString,
            "--reference",
            referenceJSON,
            "--expected-generation",
            "\(generation.value)",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLISelectionResponse.self,
            from: result.standardOutputData
        )

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "0 target(s), 1 reference(s) selected.")
        #expect(response.generation == generation.value)
        #expect(response.dirty == wasDirty)
        #expect(response.selectedTargetCount == 0)
        #expect(response.selectedReferenceCount == 1)
        #expect(response.selectedReferences == [controlPoint.selectionReference])
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableInspectsSketchTopologyAndCurvesAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-inspect.swcad")
    var document = DesignDocument.empty(named: "Process Inspect")
    _ = try document.createExtrudedRectangle(
        name: "Inspect Box",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(6.0, .millimeter),
        direction: .normal
    )
    try DocumentFileService().save(document, to: documentURL)

    let sketchesResult = try await runCLI([
        "inspect",
        "sketches",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let sketchesResponse = try JSONDecoder().decode(
        CLISketchEntitySummaryResponse.self,
        from: sketchesResult.standardOutputData
    )
    let topologyResult = try await runCLI([
        "inspect",
        "topology",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let topologyResponse = try JSONDecoder().decode(
        CLITopologySummaryResponse.self,
        from: topologyResult.standardOutputData
    )
    let curvesResult = try await runCLI([
        "inspect",
        "curves",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let curvesResponse = try JSONDecoder().decode(
        CLICurveAnalysisResponse.self,
        from: curvesResult.standardOutputData
    )

    #expect(sketchesResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: sketchesResult.standardError))
    #expect(sketchesResponse.sketchEntitySummary.counts.sketchCount == 1)
    #expect(sketchesResponse.sketchEntitySummary.counts.entityCount == 4)
    #expect(!sketchesResponse.sketchEntitySummary.entries.compactMap { $0.selectionTarget() }.isEmpty)
    #expect(!sketchesResponse.sketchEntitySummary.regions.compactMap { $0.selectionTarget() }.isEmpty)
    #expect(topologyResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: topologyResult.standardError))
    #expect(topologyResponse.topologySummary.counts.bodyCount == 1)
    #expect(topologyResponse.topologySummary.counts.faceCount > 0)
    #expect(topologyResponse.topologySummary.counts.edgeCount > 0)
    #expect(!topologyResponse.topologySummary.entries.compactMap { $0.selectionTarget() }.isEmpty)
    #expect(curvesResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: curvesResult.standardError))
    #expect(curvesResponse.curveAnalysis.counts.curveCount == 4)
    #expect(curvesResponse.curveAnalysis.counts.sampleCount > 0)
    #expect(curvesResponse.curveAnalysis.curves.contains { $0.selectionComponentID != nil && !$0.samples.isEmpty })
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableInspectsConstructionPlanesAndSnapAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-inspect-snap.swcad")
    var document = DesignDocument.empty(named: "Process Inspect Snap")
    let planeID = try document.createConstructionPlane(
        name: "CLI Work Plane",
        plane: .xy
    )
    try DocumentFileService().save(document, to: documentURL)

    let planesResult = try await runCLI([
        "inspect",
        "construction-planes",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let planesResponse = try JSONDecoder().decode(
        CLIConstructionPlaneSummaryResponse.self,
        from: planesResult.standardOutputData
    )
    let snapResult = try await runCLI([
        "inspect",
        "snap",
        documentURL.path,
        "--x",
        "1.2",
        "--y",
        "2.7",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let snapResponse = try JSONDecoder().decode(
        CLISnapResolutionResponse.self,
        from: snapResult.standardOutputData
    )

    #expect(planesResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: planesResult.standardError))
    #expect(planesResponse.constructionPlaneSummary.activePlaneID == planeID)
    #expect(planesResponse.constructionPlaneSummary.planes.count == 1)
    let plane = try #require(planesResponse.constructionPlaneSummary.planes.first)
    #expect(plane.name == "CLI Work Plane")
    #expect(plane.isActive)
    #expect(snapResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: snapResult.standardError))
    #expect(snapResponse.snapResolution.selectedCandidate?.kind == .grid)
    #expect(abs(snapResponse.snapResolution.originalPoint.x - 0.0012) < 0.000_000_000_001)
    #expect(abs(snapResponse.snapResolution.originalPoint.y - 0.0027) < 0.000_000_000_001)
    #expect(abs(snapResponse.snapResolution.resolvedPoint.x - 0.001) < 0.000_000_000_001)
    #expect(abs(snapResponse.snapResolution.resolvedPoint.y - 0.003) < 0.000_000_000_001)
}

@Suite(.serialized)
struct CLISketchCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableSketchCurvePrimitivesPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-curves.swcad")
        try DocumentFileService().save(.empty(named: "Process Sketch Curves"), to: documentURL)

        let arcResult = try await runCLI([
            "sketch",
            "arc",
            documentURL.path,
            "--name",
            "CLI Arc",
            "--center-x",
            "2",
            "--center-y",
            "3",
            "--radius",
            "4",
            "--start-angle",
            "0",
            "--end-angle",
            "90",
            "--unit",
            "millimeter",
            "--angle-unit",
            "degree",
            "--mode",
            "file",
            "--json",
        ])
        let arcResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: arcResult.standardOutputData
        )
        let splineResult = try await runCLI([
            "sketch",
            "spline",
            documentURL.path,
            "--name",
            "CLI Spline",
            "--control-point",
            "0,0",
            "--control-point",
            "2,4",
            "--control-point",
            "6,4",
            "--control-point",
            "8,0",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let splineResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: splineResult.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)
        let arcFeatureID = try #require(loaded.cadDocument.designGraph.order.first)
        let splineFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
        let arcFeature = try #require(loaded.cadDocument.designGraph.nodes[arcFeatureID])
        let splineFeature = try #require(loaded.cadDocument.designGraph.nodes[splineFeatureID])
        guard case let .sketch(arcSketch) = arcFeature.operation,
              case let .sketch(splineSketch) = splineFeature.operation else {
            #expect(Bool(false))
            return
        }
        let arcNode = try #require(loaded.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == arcFeatureID
        })
        let splineNode = try #require(loaded.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == splineFeatureID
        })

        #expect(arcResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: arcResult.standardError))
        #expect(splineResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: splineResult.standardError))
        #expect(arcResponse.message == "Arc sketch CLI Arc created.")
        #expect(splineResponse.message == "Spline sketch CLI Spline created.")
        #expect(arcResponse.saved)
        #expect(splineResponse.saved)
        #expect(loaded.cadDocument.designGraph.order.count == 2)
        #expect(arcSketch.entities.values.contains { entity in
            if case .arc = entity {
                return true
            }
            return false
        })
        #expect(splineSketch.entities.values.contains { entity in
            if case let .spline(spline) = entity {
                return spline.controlPoints.count == 4
            }
            return false
        })
        #expect(arcNode.object?.typeID == .arc)
        #expect(arcNode.object?.properties["radius"] == .length(0.004))
        #expect(arcNode.object?.properties["start.angle"] == .angle(0.0))
        #expect(arcNode.object?.properties["end.angle"] == .angle(90.0))
        #expect(splineNode.object?.typeID == .spline)
        #expect(splineNode.object?.properties["control.point.count"] == .integer(4))
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchPolygonPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-polygon.swcad")
        try DocumentFileService().save(.empty(named: "Process Sketch Polygon"), to: documentURL)

        let result = try await runCLI([
            "sketch",
            "polygon",
            documentURL.path,
            "--name",
            "CLI Hexagon",
            "--center-x",
            "1",
            "--center-y",
            "2",
            "--radius",
            "6",
            "--sides",
            "6",
            "--unit",
            "millimeter",
            "--sizing-mode",
            "inradius",
            "--inclination-mode",
            "horizontal",
            "--rotation-angle",
            "15",
            "--angle-unit",
            "degree",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLIResponse.self,
            from: result.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)
        let featureID = try #require(loaded.cadDocument.designGraph.order.first)
        let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
        guard case let .sketch(sketch) = feature.operation else {
            #expect(Bool(false))
            return
        }
        let lines = sketch.entities.values.compactMap { entity -> SketchLine? in
            guard case let .line(line) = entity else {
                return nil
            }
            return line
        }
        let node = try #require(loaded.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Polygon sketch CLI Hexagon created.")
        #expect(response.saved)
        #expect(!response.dirty)
        #expect(lines.count == 6)
        #expect(node.object?.typeID == .polygon)
        #expect(node.object?.properties["sides.x"] == .integer(6))
        #expect(node.object?.properties["radius.is.inradius"] == .boolean(true))
        #expect(node.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.horizontal.rawValue))
        #expect(node.object?.properties["sizing.radius"] == .length(0.006))
        #expect(node.object?.properties["angle"] == .angle(15.0))
    }
}

@Suite(.serialized)
struct CLISketchEditCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableSketchCurveEditCommandsPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-edits.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Edits")
        _ = try document.createLineSketch(
            name: "Editable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let initialLine = try sourceLine(in: document)
        let wholeTarget = try #require(initialLine.selectionTarget())
        let endTarget = try lineHandleTarget(initialLine, handle: .lineEnd)
        let extendResult = try await runCLI([
            "sketch",
            "extend",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(endTarget),
            "--distance",
            "2",
            "--unit",
            "millimeter",
            "--shape",
            "linear",
            "--mode",
            "file",
            "--json",
        ])
        let extendResponse = try JSONDecoder().decode(CLIResponse.self, from: extendResult.standardOutputData)
        let extended = try DocumentFileService().load(from: documentURL)
        let extendedLine = try sourceLine(in: extended)

        let reverseResult = try await runCLI([
            "sketch",
            "reverse",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(wholeTarget),
            "--mode",
            "file",
            "--json",
        ])
        let reverseResponse = try JSONDecoder().decode(CLIResponse.self, from: reverseResult.standardOutputData)
        let reversed = try DocumentFileService().load(from: documentURL)
        let reversedLine = try sourceLine(in: reversed)

        let splitResult = try await runCLI([
            "sketch",
            "split",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(wholeTarget),
            "--fraction",
            "0.5",
            "--mode",
            "file",
            "--json",
        ])
        let splitResponse = try JSONDecoder().decode(CLIResponse.self, from: splitResult.standardOutputData)
        let split = try DocumentFileService().load(from: documentURL)
        let splitSummary = try SketchEntitySummaryService().summarize(document: split)
        let trimEntry = try #require(splitSummary.entries.first { entry in
            entry.entityKind == "line" && entry.entityID != initialLine.entityID
        })
        let trimTarget = try #require(trimEntry.selectionTarget())

        let trimResult = try await runCLI([
            "sketch",
            "trim",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(trimTarget),
            "--mode",
            "file",
            "--json",
        ])
        let trimResponse = try JSONDecoder().decode(CLIResponse.self, from: trimResult.standardOutputData)
        let trimmed = try DocumentFileService().load(from: documentURL)
        let trimmedSummary = try SketchEntitySummaryService().summarize(document: trimmed)

        #expect(extendResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: extendResult.standardError))
        #expect(extendResponse.message == "Sketch curve extended.")
        #expect(extendResponse.saved)
        #expect(abs((extendedLine.end?.x ?? -1.0) - 0.014) < 0.000_000_000_001)
        #expect(reverseResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: reverseResult.standardError))
        #expect(reverseResponse.message == "Sketch curve direction reversed.")
        #expect(reverseResponse.saved)
        #expect(abs((reversedLine.start?.x ?? -1.0) - 0.014) < 0.000_000_000_001)
        #expect(abs((reversedLine.end?.x ?? -1.0) - 0.0) < 0.000_000_000_001)
        #expect(splitResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: splitResult.standardError))
        #expect(splitResponse.message == "Sketch curve segment split.")
        #expect(splitResponse.saved)
        #expect(splitSummary.entries.filter { $0.entityKind == "line" }.count == 2)
        #expect(trimResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: trimResult.standardError))
        #expect(trimResponse.message == "Sketch curve segment trimmed.")
        #expect(trimResponse.saved)
        #expect(trimmedSummary.entries.filter { $0.entityKind == "line" }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchSlotPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-slot.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Slot")
        _ = try document.createLineSketch(
            name: "Slot Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let source = try sourceLine(in: document)
        let target = try #require(source.selectionTarget())
        let result = try await runCLI([
            "sketch",
            "slot",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--width",
            "2",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let summary = try SketchEntitySummaryService().summarize(document: loaded)
        let slotFeature = try #require(
            loaded.cadDocument.designGraph.nodes.values.first { $0.name == "Slot Source Slot" }
        )
        let slotObject = try #require(
            loaded.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
                object.sourceFeatureID == slotFeature.id
            }
        )

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Slot sketch profile created.")
        #expect(response.saved)
        #expect(summary.counts.sketchCount == 2)
        #expect(summary.entries.filter { $0.sourceFeatureID == slotFeature.id.description && $0.entityKind == "line" }.count == 2)
        #expect(summary.entries.filter { $0.sourceFeatureID == slotFeature.id.description && $0.entityKind == "arc" }.count == 2)
        #expect(slotObject.typeID == .slot)
        #expect(slotObject.properties["width"] == .length(0.002))
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchJoinAndUnjoinPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-join.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Join")
        let featureID = try document.createLineSketch(
            name: "Join Sources",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let secondLineID = SketchEntityID()
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let firstLineID = sketch.entities.keys.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join CLI setup requires a line sketch."
            )
        }
        sketch.entities[secondLineID] = .line(
            SketchLine(
                start: SketchPoint(
                    x: .length(5.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(10.0, .millimeter),
                    y: .length(0.0, .millimeter)
                )
            )
        )
        sketch.constraints.append(.coincident(.lineEnd(firstLineID), .lineStart(secondLineID)))
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        try DocumentFileService().save(document, to: documentURL)

        let before = try SketchEntitySummaryService().summarize(document: document)
        let firstLine = try #require(before.entries.first { $0.entityID == firstLineID.description })
        let secondLine = try #require(before.entries.first { $0.entityID == secondLineID.description })
        let joinResult = try await runCLI([
            "sketch",
            "join",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(try #require(firstLine.selectionTarget())),
            "--adjacent-target",
            try encodedSelectionTarget(try #require(secondLine.selectionTarget())),
            "--mode",
            "file",
            "--json",
        ])
        let joinResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: joinResult.standardOutputData
        )
        let joined = try DocumentFileService().load(from: documentURL)
        let joinedSummary = try SketchEntitySummaryService().summarize(document: joined)
        let joinedLine = try #require(joinedSummary.entries.first { $0.entityID == firstLineID.description })

        let unjoinResult = try await runCLI([
            "sketch",
            "unjoin",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(try #require(joinedLine.selectionTarget())),
            "--mode",
            "file",
            "--json",
        ])
        let unjoinResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: unjoinResult.standardOutputData
        )
        let unjoined = try DocumentFileService().load(from: documentURL)
        let unjoinedSummary = try SketchEntitySummaryService().summarize(document: unjoined)

        #expect(joinResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: joinResult.standardError))
        #expect(joinResponse.message == "Sketch curves joined.")
        #expect(joinResponse.saved)
        #expect(joinedSummary.entries.filter {
            $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
        }.count == 1)
        #expect(joined.productMetadata.joinedCurveSources.count == 1)
        #expect(abs((joinedLine.start?.x ?? -1.0) - 0.0) < 1.0e-12)
        #expect(abs((joinedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
        #expect(unjoinResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: unjoinResult.standardError))
        #expect(unjoinResponse.message == "Sketch curve unjoined.")
        #expect(unjoinResponse.saved)
        #expect(unjoinedSummary.entries.filter {
            $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
        }.count == 2)
        #expect(unjoined.productMetadata.joinedCurveSources.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchJoinAndUnjoinPersistCompositeLineArcGroupAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-join-line-arc.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Join Line Arc")
        let featureID = try document.createLineSketch(
            name: "Join Line Arc Sources",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let lineID = SketchEntityID()
        let arcID = SketchEntityID()
        guard var feature = document.cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "CLI join line-arc setup requires a sketch feature."
            )
        }
        feature.operation = .sketch(Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .length(0.0, .meter),
                        y: .length(0.0, .meter)
                    ),
                    end: SketchPoint(
                        x: .length(0.010, .meter),
                        y: .length(0.0, .meter)
                    )
                )),
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .length(0.010, .meter),
                        y: .length(0.005, .meter)
                    ),
                    radius: .length(0.005, .meter),
                    startAngle: .angle(-Double.pi / 2.0, .radian),
                    endAngle: .angle(0.0, .radian)
                )),
            ],
            constraints: []
        ))
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        try DocumentFileService().save(document, to: documentURL)

        let before = try SketchEntitySummaryService().summarize(document: document)
        let line = try #require(before.entries.first { $0.entityID == lineID.description })
        let arc = try #require(before.entries.first { $0.entityID == arcID.description })
        let joinResult = try await runCLI([
            "sketch",
            "join",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(try #require(line.selectionTarget())),
            "--adjacent-target",
            try encodedSelectionTarget(try #require(arc.selectionTarget())),
            "--continuity",
            "g1",
            "--mode",
            "file",
            "--json",
        ])
        let joinResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: joinResult.standardOutputData
        )
        let joined = try DocumentFileService().load(from: documentURL)
        let joinedSummary = try SketchEntitySummaryService().summarize(document: joined)
        let joinedArc = try #require(joinedSummary.entries.first { $0.entityID == arcID.description })
        let joinedFeature = try #require(joined.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let joinedSketch) = joinedFeature.operation else {
            Issue.record("CLI joined line-arc feature must remain a sketch.")
            return
        }

        let unjoinResult = try await runCLI([
            "sketch",
            "unjoin",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(try #require(joinedArc.selectionTarget())),
            "--mode",
            "file",
            "--json",
        ])
        let unjoinResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: unjoinResult.standardOutputData
        )
        let unjoined = try DocumentFileService().load(from: documentURL)
        let unjoinedFeature = try #require(unjoined.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let unjoinedSketch) = unjoinedFeature.operation else {
            Issue.record("CLI unjoined line-arc feature must remain a sketch.")
            return
        }

        #expect(joinResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: joinResult.standardError))
        #expect(joinResponse.message == "Sketch curves joined.")
        #expect(joinResponse.saved)
        #expect(joinedSummary.entries.filter {
            $0.sourceFeatureID == featureID.description && ($0.entityKind == "line" || $0.entityKind == "arc")
        }.count == 2)
        #expect(joined.productMetadata.joinedCurveSources.isEmpty)
        #expect(joined.productMetadata.joinedCurveGroupSources.count == 1)
        let joinedSource = try #require(joined.productMetadata.joinedCurveGroupSources.values.first)
        #expect(joinedSource.continuity == .g1)
        #expect(joinedSketch.constraints.contains(.coincident(.lineEnd(lineID), .arcStart(arcID))))
        #expect(joinedSketch.constraints.contains(.tangent(lineID, arcID)))
        #expect(unjoinResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: unjoinResult.standardError))
        #expect(unjoinResponse.message == "Sketch curve unjoined.")
        #expect(unjoinResponse.saved)
        #expect(unjoined.productMetadata.joinedCurveSources.isEmpty)
        #expect(unjoined.productMetadata.joinedCurveGroupSources.isEmpty)
        #expect(!unjoinedSketch.constraints.contains(.coincident(.lineEnd(lineID), .arcStart(arcID))))
        #expect(!unjoinedSketch.constraints.contains(.tangent(lineID, arcID)))
    }

    private func sourceLine(in document: DesignDocument) throws -> SketchEntitySummaryResult.EntityEntry {
        let summary = try SketchEntitySummaryService().summarize(document: document)
        return try #require(summary.entries.first { $0.entityKind == "line" })
    }

    private func lineHandleTarget(
        _ line: SketchEntitySummaryResult.EntityEntry,
        handle: SketchEntityPointHandle
    ) throws -> SelectionTarget {
        let wholeTarget = try #require(line.selectionTarget())
        let handleEntry = try #require(line.pointHandles.first { $0.handle == handle })
        return SelectionTarget(
            sceneNodeID: wholeTarget.sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: handleEntry.selectionComponentID))
        )
    }
}

@Suite(.serialized)
struct CLISketchOffsetCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableSketchOffsetPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-offset.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Offset")
        _ = try document.createLineSketch(
            name: "Offset Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let sourceLine = try #require(try SketchEntitySummaryService().summarize(document: document).entries.first {
            $0.entityKind == "line"
        })
        let target = try #require(sourceLine.selectionTarget())
        let result = try await runCLI([
            "sketch",
            "offset",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--distance",
            "2",
            "--unit",
            "millimeter",
            "--gap-fill",
            "natural",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let summary = try SketchEntitySummaryService().summarize(document: loaded)
        let lines = summary.entries.filter { $0.entityKind == "line" }
        let offsetLine = try #require(lines.first { entry in
            abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12
                && abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
        })

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sketch curve offset created.")
        #expect(response.saved)
        #expect(summary.counts.sketchCount == 2)
        #expect(lines.count == 2)
        #expect(offsetLine.sourceFeatureID != sourceLine.sourceFeatureID)
        #expect(abs((offsetLine.start?.x ?? -1.0) - 0.0) < 1.0e-12)
        #expect(abs((offsetLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchOffsetRegionsPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-offset-region.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Offset Region")
        _ = try document.createRectangleSketchFromCorners(
            name: "Offset Source Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let before = try SketchEntitySummaryService().summarize(document: document)
        let sourceRegion = try #require(before.regions.first)
        let target = try #require(sourceRegion.selectionTarget())
        let result = try await runCLI([
            "sketch",
            "offset-regions",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--distance",
            "1",
            "--unit",
            "millimeter",
            "--gap-fill",
            "natural",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let after = try SketchEntitySummaryService().summarize(document: loaded)
        let newRegion = try #require(after.regions.first { region in
            region.sourceFeatureID != sourceRegion.sourceFeatureID
        })

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sketch regions offset created.")
        #expect(response.saved)
        #expect(after.counts.regionCount == before.counts.regionCount + 1)
        #expect(newRegion.boundaryPointCount == 4)
        #expect(abs(newRegion.areaSquareMeters - 0.000_096) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchCornerTreatmentPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-corner-treatment.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Corner Treatment")
        _ = try document.createRectangleSketchFromCorners(
            name: "Source Fillet Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)

        let before = try SketchEntitySummaryService().summarize(document: document)
        let bottomLine = try #require(bottomRectangleLine(in: before))
        let target = try lineHandleTarget(bottomLine, handle: .lineEnd)
        let result = try await runCLI([
            "sketch",
            "corner-treatment",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--treatment",
            "fillet",
            "--distance",
            "2",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let after = try SketchEntitySummaryService().summarize(document: loaded)
        let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
        let arcs = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc" }
        let filletArc = try #require(arcs.first)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sketch corner fillet applied.")
        #expect(response.saved)
        #expect(lines.count == 4)
        #expect(arcs.count == 1)
        #expect(abs((filletArc.center?.x ?? -1.0) - 0.008) < 1.0e-12)
        #expect(abs((filletArc.center?.y ?? -1.0) - 0.002) < 1.0e-12)
        #expect(abs((filletArc.radius ?? -1.0) - 0.002) < 1.0e-12)
    }

    private func bottomRectangleLine(
        in summary: SketchEntitySummaryResult
    ) -> SketchEntitySummaryResult.EntityEntry? {
        summary.entries.first { entry in
            entry.entityKind == "line"
                && abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12
                && abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
        }
    }

    private func lineHandleTarget(
        _ line: SketchEntitySummaryResult.EntityEntry,
        handle: SketchEntityPointHandle
    ) throws -> SelectionTarget {
        let wholeTarget = try #require(line.selectionTarget())
        let handleEntry = try #require(line.pointHandles.first { $0.handle == handle })
        return SelectionTarget(
            sceneNodeID: wholeTarget.sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: handleEntry.selectionComponentID))
        )
    }
}

@Suite(.serialized)
struct CLISketchAdvancedCurveEditCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableSketchConvertCommandsPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }

        let arcURL = temporaryDirectory.appendingPathComponent("process-sketch-convert-arc.swcad")
        var arcDocument = DesignDocument.empty(named: "Process Sketch Convert Arc")
        _ = try arcDocument.createLineSketch(
            name: "Bendable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        try DocumentFileService().save(arcDocument, to: arcURL)
        let arcSource = try namedSketchEntity("Bendable Line", kind: "line", in: arcDocument)
        let arcResult = try await runCLI([
            "sketch",
            "convert-line-to-arc",
            arcURL.path,
            "--target",
            try encodedSelectionTarget(try #require(arcSource.selectionTarget())),
            "--sagitta",
            "2",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let arcResponse = try JSONDecoder().decode(CLIResponse.self, from: arcResult.standardOutputData)
        let arcLoaded = try DocumentFileService().load(from: arcURL)
        let convertedArc = try namedSketchEntity("Bendable Line", kind: "arc", in: arcLoaded)

        let splineURL = temporaryDirectory.appendingPathComponent("process-sketch-convert-spline.swcad")
        var splineDocument = DesignDocument.empty(named: "Process Sketch Convert Spline")
        _ = try splineDocument.createLineSketch(
            name: "Spline Convertible Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        try DocumentFileService().save(splineDocument, to: splineURL)
        let splineSource = try namedSketchEntity("Spline Convertible Line", kind: "line", in: splineDocument)
        let splineResult = try await runCLI([
            "sketch",
            "convert-line-to-spline",
            splineURL.path,
            "--target",
            try encodedSelectionTarget(try #require(splineSource.selectionTarget())),
            "--mode",
            "file",
            "--json",
        ])
        let splineResponse = try JSONDecoder().decode(CLIResponse.self, from: splineResult.standardOutputData)
        let splineLoaded = try DocumentFileService().load(from: splineURL)
        let convertedSpline = try namedSketchEntity("Spline Convertible Line", kind: "spline", in: splineLoaded)

        #expect(arcResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: arcResult.standardError))
        #expect(arcResponse.message == "Sketch line converted to an arc.")
        #expect(arcResponse.saved)
        #expect(convertedArc.entityID == arcSource.entityID)
        #expect(abs((convertedArc.radius ?? -1.0) - 0.00725) < 1.0e-12)
        #expect(splineResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: splineResult.standardError))
        #expect(splineResponse.message == "Sketch line converted to a spline.")
        #expect(splineResponse.saved)
        #expect(convertedSpline.entityID == splineSource.entityID)
        #expect(convertedSpline.controlPoints.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchSplineInsertionAndRebuildPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-spline-rebuild.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Spline Rebuild")
        _ = try document.createSplineSketch(
            name: "Editable Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(0.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
        try DocumentFileService().save(document, to: documentURL)
        let source = try namedSketchEntity("Editable Spline", kind: "spline", in: document)
        let target = try #require(source.selectionTarget())

        let insertResult = try await runCLI([
            "sketch",
            "insert-control-point",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--fraction",
            "0.5",
            "--mode",
            "file",
            "--json",
        ])
        let insertResponse = try JSONDecoder().decode(CLIResponse.self, from: insertResult.standardOutputData)
        let inserted = try DocumentFileService().load(from: documentURL)
        let insertedSpline = try namedSketchEntity("Editable Spline", kind: "spline", in: inserted)

        let rebuildResult = try await runCLI([
            "sketch",
            "rebuild",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--method",
            "points",
            "--control-point-count",
            "4",
            "--mode",
            "file",
            "--json",
        ])
        let rebuildResponse = try JSONDecoder().decode(CLIResponse.self, from: rebuildResult.standardOutputData)
        let rebuilt = try DocumentFileService().load(from: documentURL)
        let rebuiltSpline = try namedSketchEntity("Editable Spline", kind: "spline", in: rebuilt)

        #expect(insertResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: insertResult.standardError))
        #expect(insertResponse.message == "Sketch spline control point inserted.")
        #expect(insertResponse.saved)
        #expect(insertedSpline.controlPoints.count == 7)
        #expect(abs(insertedSpline.controlPoints[3].x - 0.004) < 1.0e-12)
        #expect(abs(insertedSpline.controlPoints[3].y - 0.003) < 1.0e-12)
        #expect(rebuildResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: rebuildResult.standardError))
        #expect(rebuildResponse.message == "Sketch curve rebuilt.")
        #expect(rebuildResponse.saved)
        #expect(rebuiltSpline.entityID == source.entityID)
        #expect(rebuiltSpline.controlPoints.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchConstraintAddPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-constraint-add.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Constraint Add")
        let featureID = try document.createLineSketch(
            name: "Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
        let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let sketch) = feature.operation,
              let lineID = sketch.entities.keys.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Constraint CLI setup requires a line sketch."
            )
        }
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "sketch",
            "constraint-add",
            documentURL.path,
            "--feature-id",
            featureID.description,
            "--constraint",
            try encodedSketchConstraint(.horizontal(lineID)),
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let loadedFeature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let loadedSketch) = loadedFeature.operation,
              case .line(let loadedLine) = try #require(loadedSketch.entities[lineID]) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Constraint CLI result requires the constrained line."
            )
        }
        let summary = try SketchEntitySummaryService().summarize(document: loaded)
        let line = try #require(summary.entries.first { $0.entityID == lineID.description })

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sketch constraint added to \(featureID.description).")
        #expect(response.saved)
        #expect(loadedSketch.constraints == [.horizontal(lineID)])
        #expect(abs(try cliLength(loadedLine.start.x, in: loaded)) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.start.y, in: loaded)) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.end.x, in: loaded) - 0.010) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.end.y, in: loaded)) < 1.0e-12)
        #expect(abs((line.start?.x ?? -1.0) - 0.0) < 1.0e-12)
        #expect(abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12)
        #expect(abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12)
        #expect(abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchConstraintAddTypedOptionsPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-constraint-add-typed.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Constraint Add Typed")
        let featureID = try document.createLineSketch(
            name: "Typed Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
        let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let sketch) = feature.operation,
              let lineID = sketch.entities.keys.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Typed constraint CLI setup requires a line sketch."
            )
        }
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "sketch",
            "constraint-add",
            documentURL.path,
            "--feature-id",
            featureID.description,
            "--kind",
            "horizontal",
            "--entity-id",
            lineID.description,
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let loadedFeature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let loadedSketch) = loadedFeature.operation,
              case .line(let loadedLine) = try #require(loadedSketch.entities[lineID]) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Typed constraint CLI result requires the constrained line."
            )
        }

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sketch constraint added to \(featureID.description).")
        #expect(response.saved)
        #expect(loadedSketch.constraints == [.horizontal(lineID)])
        #expect(abs(try cliLength(loadedLine.start.x, in: loaded)) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.start.y, in: loaded)) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.end.x, in: loaded) - 0.010) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.end.y, in: loaded)) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchConstraintRemoveTypedOptionsPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-constraint-remove-typed.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Constraint Remove Typed")
        let featureID = try document.createLineSketch(
            name: "Typed Constraint Removal Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let sketch) = feature.operation,
              let lineID = sketch.entities.keys.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Typed constraint removal CLI setup requires a line sketch."
            )
        }
        try document.addSketchConstraint(featureID: featureID, constraint: .horizontal(lineID))
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "sketch",
            "constraint-remove",
            documentURL.path,
            "--feature-id",
            featureID.description,
            "--kind",
            "horizontal",
            "--entity-id",
            lineID.description,
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let loadedFeature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
        guard case .sketch(let loadedSketch) = loadedFeature.operation,
              case .line(let loadedLine) = try #require(loadedSketch.entities[lineID]) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Typed constraint removal CLI result requires the constrained line."
            )
        }

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Sketch constraint removed from \(featureID.description).")
        #expect(response.saved)
        #expect(loadedSketch.constraints.isEmpty)
        #expect(abs(try cliLength(loadedLine.start.x, in: loaded)) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.start.y, in: loaded)) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.end.x, in: loaded) - 0.008) < 1.0e-12)
        #expect(abs(try cliLength(loadedLine.end.y, in: loaded)) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchCutPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-cut.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Cut")
        _ = try document.createLineSketch(
            name: "Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        _ = try document.createLineSketch(
            name: "Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        )
        try DocumentFileService().save(document, to: documentURL)
        let targetLine = try namedSketchEntity("Cut Target", kind: "line", in: document)
        let cutterLine = try namedSketchEntity("Cut Cutter", kind: "line", in: document)
        let result = try await runCLI([
            "sketch",
            "cut",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(try #require(targetLine.selectionTarget())),
            "--cutter",
            try encodedSelectionTarget(try #require(cutterLine.selectionTarget())),
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let summary = try SketchEntitySummaryService().summarize(document: loaded)
        let targetSegments = summary.entries.filter { $0.sourceFeatureName == "Cut Target" }
        let cutterSegments = summary.entries.filter { $0.sourceFeatureName == "Cut Cutter" }

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Cut Curve applied.")
        #expect(response.saved)
        #expect(targetSegments.count == 2)
        #expect(cutterSegments.count == 1)
        #expect(targetSegments.contains { entry in
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12
                && abs((entry.end?.x ?? -1.0) - 0.004) < 1.0e-12
        })
        #expect(targetSegments.contains { entry in
            abs((entry.start?.x ?? -1.0) - 0.004) < 1.0e-12
                && abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchBridgePersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-bridge.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Bridge")
        let featureID = try document.createLineSketch(
            name: "Bridge Sources",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(3.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let secondLineID = SketchEntityID()
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let firstLineID = sketch.entities.keys.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge CLI setup requires a line sketch."
            )
        }
        sketch.entities[secondLineID] = .line(
            SketchLine(
                start: SketchPoint(
                    x: .length(6.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(6.0, .millimeter),
                    y: .length(6.0, .millimeter)
                )
            )
        )
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "sketch",
            "bridge",
            documentURL.path,
            "--feature-id",
            featureID.description,
            "--first-endpoint",
            try encodedBridgeCurveEndpoint(
                BridgeCurveEndpoint(reference: .lineEnd(firstLineID))
            ),
            "--second-endpoint",
            try encodedBridgeCurveEndpoint(
                BridgeCurveEndpoint(reference: .lineStart(secondLineID))
            ),
            "--continuity",
            "g1",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let summary = try SketchEntitySummaryService().summarize(document: loaded)
        let bridgeSpline = try #require(summary.entries.first { entry in
            entry.sourceFeatureID == featureID.description && entry.entityKind == "spline"
        })
        let source = try #require(loaded.productMetadata.bridgeCurveSources.values.first)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Bridge curve created in sketch \(featureID.description).")
        #expect(response.saved)
        #expect(bridgeSpline.controlPoints.count == 7)
        #expect(source.featureID == featureID)
        #expect(source.entityID.description == bridgeSpline.entityID)
        #expect(source.firstEndpoint.reference == .lineEnd(firstLineID))
        #expect(source.secondEndpoint.reference == .lineStart(secondLineID))
        #expect(source.continuity == .g1)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchBridgeUpdatePersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-bridge-update.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Bridge Update")
        let featureID = try document.createLineSketch(
            name: "Bridge Update Sources",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(3.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let secondLineID = SketchEntityID()
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let firstLineID = sketch.entities.keys.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge update CLI setup requires a line sketch."
            )
        }
        sketch.entities[secondLineID] = .line(
            SketchLine(
                start: SketchPoint(
                    x: .length(6.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(6.0, .millimeter),
                    y: .length(6.0, .millimeter)
                )
            )
        )
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        _ = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(firstLineID)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(secondLineID)),
            continuity: .g1
        )
        let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
        try DocumentFileService().save(document, to: documentURL)
        let firstEndpoint = BridgeCurveEndpoint(
            reference: .lineEnd(firstLineID),
            tension: BridgeCurveTension(
                first: .scalar(1.2),
                second: .scalar(0.8),
                third: .scalar(2.0)
            )
        )

        let result = try await runCLI([
            "sketch",
            "bridge-update",
            documentURL.path,
            "--source-id",
            source.id.description,
            "--first-endpoint",
            try encodedBridgeCurveEndpoint(firstEndpoint),
            "--continuity",
            "g0",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let updatedSource = try #require(loaded.productMetadata.bridgeCurveSources[source.id])

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Bridge curve \(source.id.description) updated.")
        #expect(response.saved)
        #expect(updatedSource.firstEndpoint == firstEndpoint)
        #expect(updatedSource.secondEndpoint.reference == .lineStart(secondLineID))
        #expect(updatedSource.continuity == .g0)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSketchDisplayCommandsPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-display.swcad")
        var document = DesignDocument.empty(named: "Process Sketch Display")
        _ = try document.createCircleSketch(
            name: "Curvature Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
        _ = try document.createSplineSketch(
            name: "Point Display Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
        try DocumentFileService().save(document, to: documentURL)
        let circleTarget = try #require(
            try namedSketchEntity("Curvature Circle", kind: "circle", in: document).selectionTarget()
        )
        let splineTarget = try #require(
            try namedSketchEntity("Point Display Spline", kind: "spline", in: document).selectionTarget()
        )
        let circleComponentID = try sketchEntityComponentID(from: circleTarget)
        let splineComponentID = try sketchEntityComponentID(from: splineTarget)

        let curvatureResult = try await runCLI([
            "sketch",
            "curvature-display",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(circleTarget),
            "--show",
            "--comb-scale",
            "0.25",
            "--mode",
            "file",
            "--json",
        ])
        let curvatureResponse = try JSONDecoder().decode(CLIResponse.self, from: curvatureResult.standardOutputData)
        let loadedAfterCurvature = try DocumentFileService().load(from: documentURL)

        let pointResult = try await runCLI([
            "sketch",
            "point-display",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(splineTarget),
            "--hide",
            "--mode",
            "file",
            "--json",
        ])
        let pointResponse = try JSONDecoder().decode(CLIResponse.self, from: pointResult.standardOutputData)
        let loadedAfterPoint = try DocumentFileService().load(from: documentURL)

        #expect(curvatureResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: curvatureResult.standardError))
        #expect(curvatureResponse.message == "Curve curvature display enabled at comb scale 0.25.")
        #expect(curvatureResponse.saved)
        #expect(loadedAfterCurvature.productMetadata.curveCurvatureDisplays[circleComponentID]?.combScale == 0.25)
        #expect(pointResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: pointResult.standardError))
        #expect(pointResponse.message == "Point display hidden.")
        #expect(pointResponse.saved)
        #expect(loadedAfterPoint.productMetadata.pointDisplays[splineComponentID]?.isVisible == false)
    }

    private func namedSketchEntity(
        _ name: String,
        kind: String,
        in document: DesignDocument
    ) throws -> SketchEntitySummaryResult.EntityEntry {
        let summary = try SketchEntitySummaryService().summarize(document: document)
        return try #require(summary.entries.first { entry in
            entry.sourceFeatureName == name && entry.entityKind == kind
        })
    }

    private func sketchEntityComponentID(from target: SelectionTarget) throws -> SelectionComponentID {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Expected a sketch entity selection target."
            )
        }
        return componentID
    }
}

@Suite(.serialized)
struct CLIModelDirectEditCommandTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executableModelFaceOffsetPersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let fixture = try cliDefaultBoxFixture()
        let documentURL = temporaryDirectory.appendingPathComponent("process-model-face-offset.swcad")
        try DocumentFileService().save(fixture.document, to: documentURL)
        let beforeBounds = try cliProfileBounds(forBody: fixture.bodyFeatureID, in: fixture.document)
        let target = SelectionTarget(sceneNodeID: fixture.bodyNodeID, component: .face(.bodyFaceRight))

        let result = try await runCLI([
            "model",
            "face-offset",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--distance",
            "2",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let afterBounds = try cliProfileBounds(forBody: fixture.bodyFeatureID, in: loaded)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Body face offset applied.")
        #expect(response.saved)
        #expect(cliNearlyEqual(afterBounds.minX, beforeBounds.minX))
        #expect(cliNearlyEqual(afterBounds.maxX, beforeBounds.maxX + 0.002))
        #expect(cliNearlyEqual(afterBounds.minY, beforeBounds.minY))
        #expect(cliNearlyEqual(afterBounds.maxY, beforeBounds.maxY))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executableModelEdgeEditsPersistClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }

        let chamferFixture = try cliDefaultBoxFixture()
        let chamferURL = temporaryDirectory.appendingPathComponent("process-model-edge-chamfer.swcad")
        try DocumentFileService().save(chamferFixture.document, to: chamferURL)
        let chamferTarget = SelectionTarget(sceneNodeID: chamferFixture.bodyNodeID, component: .edge(.bodyEdgeRightTop))
        let chamferResult = try await runCLI([
            "model",
            "edge-chamfer",
            chamferURL.path,
            "--target",
            try encodedSelectionTarget(chamferTarget),
            "--distance",
            "1",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let chamferResponse = try JSONDecoder().decode(CLIResponse.self, from: chamferResult.standardOutputData)
        let chamfered = try DocumentFileService().load(from: chamferURL)

        let filletFixture = try cliDefaultBoxFixture()
        let filletURL = temporaryDirectory.appendingPathComponent("process-model-edge-fillet.swcad")
        try DocumentFileService().save(filletFixture.document, to: filletURL)
        let filletTarget = SelectionTarget(sceneNodeID: filletFixture.bodyNodeID, component: .edge(.bodyEdgeRightTop))
        let filletResult = try await runCLI([
            "model",
            "edge-fillet",
            filletURL.path,
            "--target",
            try encodedSelectionTarget(filletTarget),
            "--radius",
            "1",
            "--unit",
            "millimeter",
            "--segment-count",
            "8",
            "--mode",
            "file",
            "--json",
        ])
        let filletResponse = try JSONDecoder().decode(CLIResponse.self, from: filletResult.standardOutputData)
        let filleted = try DocumentFileService().load(from: filletURL)

        #expect(chamferResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: chamferResult.standardError))
        #expect(chamferResponse.message == "Body edge chamfer applied.")
        #expect(chamferResponse.saved)
        #expect(try cliProfileLineCount(forBody: chamferFixture.bodyFeatureID, in: chamfered) == 5)
        #expect(try cliProfileArcCount(forBody: chamferFixture.bodyFeatureID, in: chamfered) == 0)
        #expect(filletResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: filletResult.standardError))
        #expect(filletResponse.message == "Body edge fillet applied.")
        #expect(filletResponse.saved)
        #expect(try cliProfileLineCount(forBody: filletFixture.bodyFeatureID, in: filleted) == 4)
        #expect(try cliProfileArcCount(forBody: filletFixture.bodyFeatureID, in: filleted) == 1)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executableModelVertexMovePersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let fixture = try cliDefaultBoxFixture()
        let documentURL = temporaryDirectory.appendingPathComponent("process-model-vertex-move.swcad")
        try DocumentFileService().save(fixture.document, to: documentURL)
        let beforeBounds = try cliProfileBounds(forBody: fixture.bodyFeatureID, in: fixture.document)
        let componentID = try #require(
            try GeneratedTopologySelectionResolver().componentID(
                for: fixture.bodyNodeID,
                cornerVertex: .frontTopRight,
                in: fixture.document
            )
        )
        let target = SelectionTarget(sceneNodeID: fixture.bodyNodeID, component: .vertex(componentID))

        let result = try await runCLI([
            "model",
            "vertex-move",
            documentURL.path,
            "--target",
            try encodedSelectionTarget(target),
            "--delta-x",
            "1",
            "--delta-y",
            "2",
            "--unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(CLIResponse.self, from: result.standardOutputData)
        let loaded = try DocumentFileService().load(from: documentURL)
        let afterBounds = try cliProfileBounds(forBody: fixture.bodyFeatureID, in: loaded)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Body vertex moved.")
        #expect(response.saved)
        #expect(cliNearlyEqual(afterBounds.minX, beforeBounds.minX))
        #expect(cliNearlyEqual(afterBounds.minY, beforeBounds.minY))
        #expect(cliNearlyEqual(afterBounds.maxX, beforeBounds.maxX + 0.001))
        #expect(cliNearlyEqual(afterBounds.maxY, beforeBounds.maxY + 0.002))
    }
}

@Suite(.serialized)
struct CLICommandApplyTests {
    @Test(.timeLimit(.minutes(1)))
    func executableAppliesAutomationCommandPayloadsAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-command-apply.swcad")
        let commandURL = temporaryDirectory.appendingPathComponent("rename-plane-command.json")
        try DocumentFileService().save(.empty(named: "Process Command Apply"), to: documentURL)

        let createCommand = AutomationCommand.createConstructionPlane(
            name: "Applied Plane",
            plane: .xy,
            activates: true
        )
        let createPayload = String(
            decoding: try JSONEncoder().encode(createCommand),
            as: UTF8.self
        )
        let createResult = try await runCLI([
            "command",
            "apply",
            documentURL.path,
            "--command",
            createPayload,
            "--mode",
            "file",
            "--json",
        ])
        let createResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: createResult.standardOutputData
        )
        let loadedAfterCreate = try DocumentFileService().load(from: documentURL)
        let createdPlane = try #require(
            loadedAfterCreate.productMetadata.constructionPlanes.values.first { $0.name == "Applied Plane" }
        )

        let renameCommand = AutomationCommand.renameConstructionPlane(
            id: createdPlane.id,
            name: "Applied Plane Renamed"
        )
        try JSONEncoder().encode(renameCommand).write(to: commandURL)
        let renameResult = try await runCLI([
            "command",
            "apply",
            documentURL.path,
            "--command-file",
            commandURL.path,
            "--mode",
            "file",
            "--json",
        ])
        let renameResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: renameResult.standardOutputData
        )
        let loadedAfterRename = try DocumentFileService().load(from: documentURL)

        #expect(createResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: createResult.standardError))
        #expect(createResponse.message == "Construction plane Applied Plane created.")
        #expect(createResponse.saved)
        #expect(loadedAfterCreate.productMetadata.activeConstructionPlaneID == createdPlane.id)
        #expect(renameResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: renameResult.standardError))
        #expect(renameResponse.message == "Construction plane renamed to Applied Plane Renamed.")
        #expect(renameResponse.saved)
        #expect(loadedAfterRename.productMetadata.constructionPlanes[createdPlane.id]?.name == "Applied Plane Renamed")
    }
}

@Suite(.serialized)
struct CLIPlaneCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableConstructionPlaneCommandsMutateClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-plane-commands.swcad")
        try DocumentFileService().save(.empty(named: "Process Planes"), to: documentURL)

        let createResult = try await runCLI([
            "plane",
            "create",
            documentURL.path,
            "--name",
            "Base XY",
            "--plane",
            "xy",
            "--mode",
            "file",
            "--json",
        ])
        let createResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: createResult.standardOutputData
        )
        let loadedAfterCreate = try DocumentFileService().load(from: documentURL)
        let basePlane = try #require(
            loadedAfterCreate.productMetadata.constructionPlanes.values.first { $0.name == "Base XY" }
        )

        let createViewResult = try await runCLI([
            "plane",
            "create-view",
            documentURL.path,
            "--name",
            "Camera Plane",
            "--origin-x",
            "10",
            "--origin-y",
            "20",
            "--origin-z",
            "30",
            "--unit",
            "millimeter",
            "--normal-x",
            "0",
            "--normal-y",
            "0",
            "--normal-z",
            "1",
            "--mode",
            "file",
            "--json",
        ])
        let createViewResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: createViewResult.standardOutputData
        )
        let loadedAfterView = try DocumentFileService().load(from: documentURL)
        let viewPlane = try #require(
            loadedAfterView.productMetadata.constructionPlanes.values.first { $0.name == "Camera Plane" }
        )

        let setActiveResult = try await runCLI([
            "plane",
            "set-active",
            documentURL.path,
            "--id",
            basePlane.id.description,
            "--mode",
            "file",
            "--json",
        ])
        let setActiveResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: setActiveResult.standardOutputData
        )

        let renameResult = try await runCLI([
            "plane",
            "rename",
            documentURL.path,
            "--id",
            viewPlane.id.description,
            "--name",
            "Renamed View Plane",
            "--mode",
            "file",
            "--json",
        ])
        let renameResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: renameResult.standardOutputData
        )

        let inspectResult = try await runCLI([
            "inspect",
            "construction-planes",
            documentURL.path,
            "--mode",
            "file",
            "--json",
        ])
        let inspectResponse = try JSONDecoder().decode(
            CLIConstructionPlaneSummaryResponse.self,
            from: inspectResult.standardOutputData
        )

        #expect(createResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: createResult.standardError))
        #expect(createResponse.message == "Construction plane Base XY created.")
        #expect(createResponse.saved)
        #expect(loadedAfterCreate.productMetadata.activeConstructionPlaneID == basePlane.id)
        #expect(createViewResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: createViewResult.standardError))
        #expect(createViewResponse.message == "View-aligned construction plane Camera Plane created.")
        #expect(createViewResponse.saved)
        #expect(loadedAfterView.productMetadata.activeConstructionPlaneID == viewPlane.id)
        #expect(setActiveResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setActiveResult.standardError))
        #expect(setActiveResponse.message == "Active construction plane set to Base XY.")
        #expect(setActiveResponse.saved)
        #expect(renameResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: renameResult.standardError))
        #expect(renameResponse.message == "Construction plane renamed to Renamed View Plane.")
        #expect(renameResponse.saved)
        #expect(inspectResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: inspectResult.standardError))
        #expect(inspectResponse.constructionPlaneSummary.activePlaneID == basePlane.id)
        #expect(inspectResponse.constructionPlaneSummary.planes.map(\.name) == ["Base XY", "Renamed View Plane"])
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executableConstructionPlaneTargetCommandsMutateClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let fixture = try cliDefaultBoxFixture()
        let documentURL = temporaryDirectory.appendingPathComponent("process-plane-target-commands.swcad")
        try DocumentFileService().save(fixture.document, to: documentURL)
        let topology = try TopologySummaryService().summarize(document: fixture.document)
        let faceTarget = try #require(topology.entries.first { entry in
            entry.kind == .face && entry.selectionTarget() != nil
        }?.selectionTarget())
        let facePair = try parallelFaceTargets(in: topology)

        let targetResult = try await runCLI([
            "plane",
            "create-target",
            documentURL.path,
            "--name",
            "Top Face Plane",
            "--target",
            try encodedSelectionTarget(faceTarget),
            "--mode",
            "file",
            "--json",
        ])
        let targetResponse = try JSONDecoder().decode(CLIResponse.self, from: targetResult.standardOutputData)
        let loadedAfterTarget = try DocumentFileService().load(from: documentURL)
        let topFacePlane = try #require(
            loadedAfterTarget.productMetadata.constructionPlanes.values.first { $0.name == "Top Face Plane" }
        )

        let targetsResult = try await runCLI([
            "plane",
            "create-targets",
            documentURL.path,
            "--name",
            "Left Right Midplane",
            "--target",
            try encodedSelectionTarget(facePair.first),
            "--target",
            try encodedSelectionTarget(facePair.second),
            "--mode",
            "file",
            "--json",
        ])
        let targetsResponse = try JSONDecoder().decode(CLIResponse.self, from: targetsResult.standardOutputData)
        let loadedAfterTargets = try DocumentFileService().load(from: documentURL)
        let midplane = try #require(
            loadedAfterTargets.productMetadata.constructionPlanes.values.first { $0.name == "Left Right Midplane" }
        )

        #expect(targetResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: targetResult.standardError))
        #expect(targetResponse.message.hasPrefix("Construction plane Top Face Plane created from target"))
        #expect(targetResponse.saved)
        #expect(loadedAfterTarget.productMetadata.activeConstructionPlaneID == topFacePlane.id)
        if case .plane = topFacePlane.plane {
            #expect(true)
        } else {
            Issue.record("Top face construction plane should be stored as a custom plane.")
        }
        #expect(targetsResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: targetsResult.standardError))
        #expect(targetsResponse.message == "Construction plane Left Right Midplane created from 2 targets.")
        #expect(targetsResponse.saved)
        #expect(loadedAfterTargets.productMetadata.activeConstructionPlaneID == midplane.id)
        #expect(loadedAfterTargets.productMetadata.constructionPlanes.count == 2)
        if case .plane = midplane.plane {
            #expect(true)
        } else {
            Issue.record("Generated face midplane should be stored as a custom plane.")
        }
    }

    private func parallelFaceTargets(
        in topology: TopologySummaryResult
    ) throws -> (first: SelectionTarget, second: SelectionTarget) {
        let faces = topology.entries.filter { $0.kind == .face }
        for firstIndex in faces.indices {
            let first = faces[firstIndex]
            guard let firstCenter = first.center,
                  let firstNormal = first.normal,
                  let firstTarget = first.selectionTarget() else {
                continue
            }
            for second in faces.dropFirst(firstIndex + 1) {
                guard let secondCenter = second.center,
                      let secondNormal = second.normal,
                      let secondTarget = second.selectionTarget() else {
                    continue
                }
                let dot = firstNormal.x * secondNormal.x
                    + firstNormal.y * secondNormal.y
                    + firstNormal.z * secondNormal.z
                let deltaX = secondCenter.x - firstCenter.x
                let deltaY = secondCenter.y - firstCenter.y
                let deltaZ = secondCenter.z - firstCenter.z
                let separation = deltaX * firstNormal.x
                    + deltaY * firstNormal.y
                    + deltaZ * firstNormal.z
                guard abs(abs(dot) - 1.0) <= 1.0e-8,
                      abs(separation) > 1.0e-9 else {
                    continue
                }
                return (firstTarget, secondTarget)
            }
        }
        throw EditorError(
            code: .referenceUnresolved,
            message: "CLI plane test setup requires two separated parallel face targets."
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceSourcesReturnsSelectionReferencesAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-sources.swcad")
    var document = DesignDocument.empty(named: "Process Surface Sources")
    _ = try document.createPolySplineSurface(
        name: "CLI Source Surface",
        sourceMesh: cliPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    try DocumentFileService().save(document, to: documentURL)

    let result = try await runCLI([
        "surface",
        "sources",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLISurfaceSourceSummaryResponse.self,
        from: result.standardOutputData
    )
    let analysisResult = try await runCLI([
        "inspect",
        "surfaces",
        documentURL.path,
        "--sample-density",
        "standard",
        "--mode",
        "file",
        "--json",
    ])
    let analysisResponse = try JSONDecoder().decode(
        CLISurfaceAnalysisResponse.self,
        from: analysisResult.standardOutputData
    )
    let continuityResult = try await runCLI([
        "inspect",
        "surface-continuity",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let continuityResponse = try JSONDecoder().decode(
        CLISurfaceContinuitySummaryResponse.self,
        from: continuityResult.standardOutputData
    )
    let topologyResult = try await runCLI([
        "inspect",
        "topology",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let topologyResponse = try JSONDecoder().decode(
        CLITopologySummaryResponse.self,
        from: topologyResult.standardOutputData
    )
    let facePersistentName = try #require(
        topologyResponse.topologySummary.entries.first { $0.kind == .face }?.persistentName
    )
    let frameQueryJSON = try encodedSurfaceFrameQuery(
        SurfaceFrameQuery(
            facePersistentName: facePersistentName,
            u: 0.5,
            v: 0.5
        )
    )
    let frameResult = try await runCLI([
        "inspect",
        "surface-frames",
        documentURL.path,
        "--query",
        frameQueryJSON,
        "--mode",
        "file",
        "--json",
    ])
    let frameResponse = try JSONDecoder().decode(
        CLISurfaceFramesResponse.self,
        from: frameResult.standardOutputData
    )
    let patch = try #require(response.surfaceSourceSummary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let measurementQueryJSON = try encodedSelectionMeasurementQuery(
        CADAgentMeasurementQuery(kind: .point, first: controlPoint.selectionReference)
    )
    let selectionMeasurementResult = try await runCLI([
        "inspect",
        "selection-measurement",
        documentURL.path,
        "--query",
        measurementQueryJSON,
        "--mode",
        "file",
        "--json",
    ])
    let selectionMeasurementResponse = try JSONDecoder().decode(
        CLISelectionMeasurementResponse.self,
        from: selectionMeasurementResult.standardOutputData
    )
    guard case .point(let measuredPoint) = selectionMeasurementResponse.selectionMeasurement else {
        Issue.record("Selection measurement must return a point result.")
        return
    }
    let frame = try #require(frameResponse.surfaceFrames.frames.first)

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.surfaceSourceSummary.counts.sourceCount == 1)
    #expect(response.surfaceSourceSummary.counts.patchCount == 2)
    #expect(response.surfaceSourceSummary.counts.controlPointCount > 0)
    #expect(patch.basis.uKnotVector.map(\.id).contains("uKnot:3"))
    #expect(patch.basis.uSpans.first?.id == "uSpan:0")
    #expect(controlPoint.weight == 1.0)
    #expect(controlPoint.isEditable)
    #expect(analysisResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: analysisResult.standardError))
    #expect(analysisResponse.surfaceAnalysis.counts.bSplineFaceCount == 2)
    #expect(analysisResponse.surfaceAnalysis.counts.sampleCount == 50)
    #expect(analysisResponse.surfaceAnalysis.counts.trimBoundaryCount == 2)
    #expect(analysisResponse.surfaceAnalysis.counts.trimBoundaryEdgeCount == 8)
    #expect(continuityResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: continuityResult.standardError))
    #expect(continuityResponse.surfaceContinuitySummary.counts.bSplineFaceCount == 2)
    #expect(continuityResponse.surfaceContinuitySummary.counts.sharedEdgeCount == 1)
    #expect(continuityResponse.surfaceContinuitySummary.counts.g1AdjacencyCount == 0)
    #expect(continuityResponse.surfaceContinuitySummary.counts.g2AdjacencyCount == 1)
    #expect(topologyResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: topologyResult.standardError))
    #expect(frameResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: frameResult.standardError))
    #expect(frameResponse.surfaceFrames.frames.count == 1)
    #expect(frame.facePersistentNames.contains(facePersistentName))
    #expect(frame.u == 0.5)
    #expect(frame.v == 0.5)
    #expect(abs(abs(frame.handedness) - 1.0) < 0.000_000_01)
    #expect(
        selectionMeasurementResult.terminationStatus == CLIExitCode.success.rawValue,
        Comment(rawValue: selectionMeasurementResult.standardError)
    )
    #expect(abs(measuredPoint.point.x - controlPoint.point.x) <= 1.0e-12)
    #expect(abs(measuredPoint.point.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(measuredPoint.point.z - controlPoint.point.z) <= 1.0e-12)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceMoveControlPointMutatesClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-move.swcad")
    var document = DesignDocument.empty(named: "Process Surface Move")
    _ = try document.createPolySplineSurface(
        name: "CLI Move Surface",
        sourceMesh: cliPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let referenceJSON = try encodedSelectionReference(controlPoint.selectionReference)
    try DocumentFileService().save(document, to: documentURL)

    let result = try await runCLI([
        "surface",
        "move-control-point",
        documentURL.path,
        "--reference",
        referenceJSON,
        "--delta-z",
        "1",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let movedSummary = try SurfaceSourceSummaryService().summarize(document: loaded)
    let movedPatch = try #require(movedSummary.sources.first?.patches.first)
    let movedControlPoint = try #require(movedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Surface control point moved.")
    #expect(response.saved)
    #expect(abs(movedControlPoint.point.z - (controlPoint.point.z + 0.001)) < 0.000_000_000_001)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceMoveControlPointsInFrameMutatesClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-frame-move.swcad")
    var document = DesignDocument.empty(named: "Process Surface Frame Move")
    _ = try document.createPolySplineSurface(
        name: "CLI Frame Move Surface",
        sourceMesh: cliPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let referenceJSON = try encodedSelectionReference(controlPoint.selectionReference)
    let frameQuery = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)
    let frameQueryJSON = try encodedSurfaceFrameQuery(frameQuery)
    try DocumentFileService().save(document, to: documentURL)

    let frameResult = try await runCLI([
        "inspect",
        "surface-frames",
        documentURL.path,
        "--query",
        frameQueryJSON,
        "--mode",
        "file",
        "--json",
    ])
    let frameResponse = try JSONDecoder().decode(
        CLISurfaceFramesResponse.self,
        from: frameResult.standardOutputData
    )
    let frame = try #require(frameResponse.surfaceFrames.frames.first)
    let result = try await runCLI([
        "surface",
        "move-control-points-in-frame",
        documentURL.path,
        "--reference",
        referenceJSON,
        "--frame-query",
        frameQueryJSON,
        "--u-distance",
        "1",
        "--v-distance",
        "2",
        "--normal-distance",
        "3",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let movedSummary = try SurfaceSourceSummaryService().summarize(document: loaded)
    let movedPatch = try #require(movedSummary.sources.first?.patches.first)
    let movedControlPoint = try #require(movedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let expectedX = controlPoint.point.x
        + frame.uAxis.x * 0.001
        + frame.vAxis.x * 0.002
        + frame.normal.x * 0.003
    let expectedY = controlPoint.point.y
        + frame.uAxis.y * 0.001
        + frame.vAxis.y * 0.002
        + frame.normal.y * 0.003
    let expectedZ = controlPoint.point.z
        + frame.uAxis.z * 0.001
        + frame.vAxis.z * 0.002
        + frame.normal.z * 0.003

    #expect(frameResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: frameResult.standardError))
    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Surface control points moved in frame.")
    #expect(response.saved)
    #expect(abs(movedControlPoint.point.x - expectedX) < 0.000_000_000_001)
    #expect(abs(movedControlPoint.point.y - expectedY) < 0.000_000_000_001)
    #expect(abs(movedControlPoint.point.z - expectedZ) < 0.000_000_000_001)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceWeightAndKnotCommandsMutateClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-weight-knot.swcad")
    var document = DesignDocument.empty(named: "Process Surface Weight Knot")
    let sourceSurface = cliDirectBSplineSurfaceWithInteriorKnots()
    let featureID = try document.createBSplineSurface(
        name: "CLI Editable B-spline Surface",
        surface: sourceSurface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let editableKnot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    let editableSpan = try #require(patch.basis.uSpans.first { $0.index == 0 })
    let controlPointJSON = try encodedSelectionReference(controlPoint.selectionReference)
    let knotJSON = try encodedSelectionReference(try #require(editableKnot.selectionReference))
    let spanJSON = try encodedSelectionReference(try #require(editableSpan.selectionReference))
    try DocumentFileService().save(document, to: documentURL)

    let weightResult = try await runCLI([
        "surface",
        "set-control-point-weight",
        documentURL.path,
        "--reference",
        controlPointJSON,
        "--weight",
        "2.5",
        "--mode",
        "file",
        "--json",
    ])
    let weightResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: weightResult.standardOutputData
    )
    let weightLoaded = try DocumentFileService().load(from: documentURL)
    let weightedFeature = try #require(weightLoaded.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(weightedSurfaceFeature) = weightedFeature.operation else {
        Issue.record("Expected a weighted direct B-spline surface feature.")
        return
    }
    let knotResult = try await runCLI([
        "surface",
        "set-knot-value",
        documentURL.path,
        "--reference",
        knotJSON,
        "--value",
        "0.4",
        "--mode",
        "file",
        "--json",
    ])
    let knotResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: knotResult.standardOutputData
    )
    let insertionResult = try await runCLI([
        "surface",
        "insert-knot",
        documentURL.path,
        "--reference",
        spanJSON,
        "--value",
        "0.25",
        "--mode",
        "file",
        "--json",
    ])
    let insertionResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: insertionResult.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }

    #expect(weightResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: weightResult.standardError))
    #expect(knotResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: knotResult.standardError))
    #expect(insertionResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: insertionResult.standardError))
    #expect(weightResponse.message == "Surface control point weight updated.")
    #expect(knotResponse.message == "Surface knot value updated.")
    #expect(insertionResponse.message == "Surface knot inserted.")
    #expect(weightResponse.saved)
    #expect(knotResponse.saved)
    #expect(insertionResponse.saved)
    #expect(weightedSurfaceFeature.surface.weights[1][1] == 2.5)
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.25, 0.4, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vKnots == sourceSurface.vKnots)
    #expect(surfaceFeature.surface.uControlPointCount == sourceSurface.uControlPointCount + 1)
    #expect(surfaceFeature.surface.vControlPointCount == sourceSurface.vControlPointCount)
    #expect(surfaceFeature.surface.weights.flatMap { $0 }.contains { abs($0 - 1.0) > 1.0e-12 })
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceKnotMultiplicityCommandMutatesClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-knot-multiplicity.swcad")
    var document = DesignDocument.empty(named: "Process Surface Knot Multiplicity")
    let sourceSurface = cliDirectBSplineSurfaceWithInteriorKnots()
    let featureID = try document.createBSplineSurface(
        name: "CLI Explicit Multiplicity B-spline Surface",
        surface: sourceSurface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableKnot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    let knotJSON = try encodedSelectionReference(try #require(editableKnot.selectionReference))
    try DocumentFileService().save(document, to: documentURL)

    let result = try await runCLI([
        "surface",
        "set-knot-multiplicity",
        documentURL.path,
        "--reference",
        knotJSON,
        "--multiplicity",
        "2",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Surface knot multiplicity updated.")
    #expect(response.saved)
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vKnots == sourceSurface.vKnots)
    #expect(surfaceFeature.surface.uControlPointCount == sourceSurface.uControlPointCount + 1)
    #expect(surfaceFeature.surface.vControlPointCount == sourceSurface.vControlPointCount)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceSpanSplitMutatesClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-span-split.swcad")
    var document = DesignDocument.empty(named: "Process Surface Span Split")
    let sourceSurface = cliDirectBSplineSurfaceWithInteriorKnots()
    let featureID = try document.createBSplineSurface(
        name: "CLI Split Span B-spline Surface",
        surface: sourceSurface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableSpan = try #require(patch.basis.vSpans.first { $0.index == 1 })
    let spanJSON = try encodedSelectionReference(try #require(editableSpan.selectionReference))
    try DocumentFileService().save(document, to: documentURL)

    let splitResult = try await runCLI([
        "surface",
        "split-span",
        documentURL.path,
        "--reference",
        spanJSON,
        "--fraction",
        "0.25",
        "--mode",
        "file",
        "--json",
    ])
    let splitResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: splitResult.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }

    #expect(splitResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: splitResult.standardError))
    #expect(splitResponse.message == "Surface span split.")
    #expect(splitResponse.saved)
    #expect(surfaceFeature.surface.uKnots == sourceSurface.uKnots)
    #expect(surfaceFeature.surface.vKnots == [0.0, 0.0, 0.0, 0.5, 0.625, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vControlPointCount == sourceSurface.vControlPointCount + 1)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceBoundaryContinuityCommandMutatesClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-boundary-continuity.swcad")
    var document = DesignDocument.empty(named: "Process Surface Boundary Continuity")
    let referenceFeatureID = try document.createBSplineSurface(
        name: "CLI Reference Boundary Surface",
        surface: cliDirectBSplineSurface()
    )
    let targetFeatureID = try document.createBSplineSurface(
        name: "CLI Target Boundary Surface",
        surface: cliOffsetDirectBSplineSurface()
    )
    let referenceTrim = try cliSurfaceTrimReference(
        featureID: referenceFeatureID,
        edgeIndex: 2,
        in: document
    )
    let targetTrim = try cliSurfaceTrimReference(
        featureID: targetFeatureID,
        edgeIndex: 0,
        in: document
    )
    try DocumentFileService().save(document, to: documentURL)

    let result = try await runCLI([
        "surface",
        "match-boundary-continuity",
        documentURL.path,
        "--target",
        try encodedSelectionReference(targetTrim),
        "--reference",
        try encodedSelectionReference(referenceTrim),
        "--level",
        "g1",
        "--match-side",
        "opposite",
        "--reference-direction",
        "forward",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let targetFeature = try #require(loaded.cadDocument.designGraph.nodes[targetFeatureID])
    let referenceFeature = try #require(loaded.cadDocument.designGraph.nodes[referenceFeatureID])
    guard case let .bSplineSurface(targetSurfaceFeature) = targetFeature.operation,
          case let .bSplineSurface(referenceSurfaceFeature) = referenceFeature.operation else {
        Issue.record("Expected direct B-spline surface features.")
        return
    }

    let referenceBoundary = referenceSurfaceFeature.surface.controlPoints[3][1]
    let referenceInward = referenceSurfaceFeature.surface.controlPoints[2][1] - referenceBoundary
    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Surface boundary continuity matched.")
    #expect(response.saved)
    #expect(targetSurfaceFeature.surface.controlPoints[0][1].isApproximatelyEqual(
        to: referenceBoundary,
        tolerance: 1.0e-12
    ))
    #expect(targetSurfaceFeature.surface.controlPoints[1][1].isApproximatelyEqual(
        to: referenceBoundary + (-referenceInward),
        tolerance: 1.0e-12
    ))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSurfaceBoundaryContinuityCompatibilityInspectsClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-surface-boundary-compatibility.swcad")
    var document = DesignDocument.empty(named: "Process Surface Boundary Compatibility")
    let referenceFeatureID = try document.createBSplineSurface(
        name: "CLI Reference Compatibility Surface",
        surface: cliDirectBSplineSurface()
    )
    let targetFeatureID = try document.createBSplineSurface(
        name: "CLI Target Compatibility Surface",
        surface: cliOffsetDirectBSplineSurface()
    )
    let referenceTrim = try cliSurfaceTrimReference(
        featureID: referenceFeatureID,
        edgeIndex: 2,
        in: document
    )
    let targetTrim = try cliSurfaceTrimReference(
        featureID: targetFeatureID,
        edgeIndex: 0,
        in: document
    )
    try DocumentFileService().save(document, to: documentURL)

    let result = try await runCLI([
        "inspect",
        "surface-boundary-continuity-compatibility",
        documentURL.path,
        "--target",
        try encodedSelectionReference(targetTrim),
        "--reference",
        try encodedSelectionReference(referenceTrim),
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        CLISurfaceBoundaryContinuityCompatibilityResponse.self,
        from: result.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let targetFeature = try #require(loaded.cadDocument.designGraph.nodes[targetFeatureID])
    guard case let .bSplineSurface(targetSurfaceFeature) = targetFeature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(response.message == "Surface boundary continuity compatibility: compatible, maximum G2.")
    #expect(response.dirty == false)
    #expect(response.surfaceBoundaryContinuityCompatibility.status == .compatible)
    #expect(response.surfaceBoundaryContinuityCompatibility.maximumSupportedContinuityLevel == .g2)
    #expect(response.surfaceBoundaryContinuityCompatibility.recommendedMatchSide == .opposite)
    #expect(targetSurfaceFeature.surface.controlPoints[0][1].isApproximatelyEqual(
        to: cliOffsetDirectBSplineSurface().controlPoints[0][1],
        tolerance: 1.0e-12
    ))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableSketchDimensionSummaryAndSetMutateClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-sketch-dimension.swcad")
    var document = DesignDocument.empty(named: "Process Sketch Dimension")
    _ = try document.createLineSketch(
        name: "Dimension Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let sketchSummary = try SketchEntitySummaryService().summarize(document: document)
    let line = try #require(sketchSummary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let targetJSON = try encodedSelectionTarget(target)
    try DocumentFileService().save(document, to: documentURL)

    let summaryResult = try await runCLI([
        "dimension",
        "sketch-summary",
        documentURL.path,
        "--target",
        targetJSON,
        "--mode",
        "file",
        "--json",
    ])
    let summaryResponse = try JSONDecoder().decode(
        CLISketchDimensionSummaryResponse.self,
        from: summaryResult.standardOutputData
    )
    let setResult = try await runCLI([
        "dimension",
        "set-sketch",
        documentURL.path,
        "--target",
        targetJSON,
        "--kind",
        "length",
        "--value",
        "20",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let setResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: setResult.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let updatedSummary = try SketchDimensionSummaryService().summarize(
        document: loaded,
        targets: [target]
    )
    let updatedLength = try #require(updatedSummary.entries.first { $0.kind == .length })

    #expect(summaryResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: summaryResult.standardError))
    #expect(summaryResponse.sketchDimensionSummary.counts.entryCount == 2)
    #expect(summaryResponse.sketchDimensionSummary.entries.map(\.kind) == [.length, .angle])
    #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
    #expect(setResponse.message == "Sketch entity dimension updated.")
    #expect(setResponse.saved)
    #expect(abs(updatedLength.resolvedValue - 0.020) < 0.000_000_000_001)
}

@Suite(.serialized)
struct CLISelectionDimensionCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func executableSelectionDimensionLifecyclePersistsClosedDocumentAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-selection-dimension.swcad")
        var document = DesignDocument.empty(named: "Process Selection Dimension")
        let featureID = try document.createLineSketch(
            name: "Measured Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let endpoints = try cliLineEndpointTargets(in: document, featureID: featureID)
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "dimension",
            "add-selection",
            documentURL.path,
            "--name",
            "CLI Line Length",
            "--kind",
            "distance",
            "--first-target",
            try encodedSelectionTarget(endpoints.start),
            "--second-target",
            try encodedSelectionTarget(endpoints.end),
            "--target-value",
            "10",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLISelectionDimensionAddResponse.self,
            from: result.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)
        let dimensionID = try #require(response.selectionDimensionID)
        let dimension = try #require(loaded.cadDocument.selectionDimensions.first { $0.id == dimensionID })
        let evaluation = try SelectionDimensionService().evaluate(
            document: loaded,
            dimensionID: dimensionID
        )
        let measurement = try #require(evaluation.measurements.first)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Selection dimension added.")
        #expect(response.saved)
        #expect(!response.dirty)
        #expect(dimension.name == "CLI Line Length")
        #expect(dimension.kind == .distance)
        #expect(evaluation.measurements.count == 1)
        #expect(measurement.dimension.id == dimensionID)
        #expect(measurement.measured == .length(0.010, unit: .meter))
        #expect(abs(measurement.residual.value) <= 1.0e-12)
        #expect(try measurement.isSatisfied())

        let setResult = try await runCLI([
            "dimension",
            "set-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--kind",
            "distance",
            "--target-value",
            "8",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let setResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: setResult.standardOutputData
        )
        let setLoaded = try DocumentFileService().load(from: documentURL)
        let setEvaluation = try SelectionDimensionService().evaluate(
            document: setLoaded,
            dimensionID: dimensionID
        )
        let setMeasurement = try #require(setEvaluation.measurements.first)

        #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
        #expect(setResponse.message == "Selection dimension target updated.")
        #expect(setResponse.saved)
        #expect(!setResponse.dirty)
        #expect(setLoaded.cadDocument.selectionDimensions.first?.target == .length(8.0, .millimeter))
        #expect(setMeasurement.measured == .length(0.010, unit: .meter))
        #expect(setMeasurement.target == .length(0.008, unit: .meter))
        #expect(abs(setMeasurement.residual.value - 0.002) <= 1.0e-12)

        let applyResult = try await runCLI([
            "dimension",
            "apply-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--mode",
            "file",
            "--json",
        ])
        guard applyResult.terminationStatus == CLIExitCode.success.rawValue else {
            Issue.record(
                "Selection dimension apply failed: \(applyResult.standardError)\(applyResult.standardOutput)"
            )
            return
        }
        let applyResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: applyResult.standardOutputData
        )
        let appliedLoaded = try DocumentFileService().load(from: documentURL)
        let appliedEvaluation = try SelectionDimensionService().evaluate(
            document: appliedLoaded,
            dimensionID: dimensionID
        )
        let appliedMeasurement = try #require(appliedEvaluation.measurements.first)

        #expect(applyResponse.message == "Selection dimension target applied.")
        #expect(applyResponse.saved)
        #expect(!applyResponse.dirty)
        #expect(appliedMeasurement.measured == .length(0.008, unit: .meter))
        #expect(appliedMeasurement.target == .length(0.008, unit: .meter))
        #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)

        let removeResult = try await runCLI([
            "dimension",
            "remove-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--mode",
            "file",
            "--json",
        ])
        let removeResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: removeResult.standardOutputData
        )
        let removedLoaded = try DocumentFileService().load(from: documentURL)

        #expect(removeResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: removeResult.standardError))
        #expect(removeResponse.message == "Selection dimension removed.")
        #expect(removeResponse.saved)
        #expect(!removeResponse.dirty)
        #expect(removedLoaded.cadDocument.selectionDimensions.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSelectionDimensionApplySolvesArcEndpointDistanceAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-selection-arc-endpoint-dimension.swcad")
        var document = DesignDocument.empty(named: "Process Selection Arc Endpoint Dimension")
        let arcFeatureID = try document.createArcSketch(
            name: "Measured Arc Endpoint",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(6.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
        let anchorFeatureID = try document.createLineSketch(
            name: "Anchor Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
        let arcTargets = try cliArcEndpointTargets(in: document, featureID: arcFeatureID)
        let anchorTargets = try cliLineEndpointTargets(in: document, featureID: anchorFeatureID)
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "dimension",
            "add-selection",
            documentURL.path,
            "--name",
            "CLI Arc Endpoint Distance",
            "--kind",
            "distance",
            "--first-target",
            try encodedSelectionTarget(arcTargets.start),
            "--second-target",
            try encodedSelectionTarget(anchorTargets.start),
            "--target-value",
            "\(sqrt(72.0))",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLISelectionDimensionAddResponse.self,
            from: result.standardOutputData
        )
        let dimensionID = try #require(response.selectionDimensionID)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Selection dimension added.")
        #expect(response.saved)
        #expect(!response.dirty)

        let setResult = try await runCLI([
            "dimension",
            "set-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--kind",
            "distance",
            "--target-value",
            "6",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let setResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: setResult.standardOutputData
        )

        #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
        #expect(setResponse.message == "Selection dimension target updated.")
        #expect(setResponse.saved)
        #expect(!setResponse.dirty)

        let applyResult = try await runCLI([
            "dimension",
            "apply-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--mode",
            "file",
            "--json",
        ])
        guard applyResult.terminationStatus == CLIExitCode.success.rawValue else {
            Issue.record(
                "Arc endpoint selection dimension apply failed: \(applyResult.standardError)\(applyResult.standardOutput)"
            )
            return
        }
        let applyResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: applyResult.standardOutputData
        )
        let appliedLoaded = try DocumentFileService().load(from: documentURL)
        let appliedEvaluation = try SelectionDimensionService().evaluate(
            document: appliedLoaded,
            dimensionID: dimensionID
        )
        let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
        let startAngle = try cliArcStartAngle(in: appliedLoaded, featureID: arcFeatureID)

        #expect(applyResponse.message == "Selection dimension target applied.")
        #expect(applyResponse.saved)
        #expect(!applyResponse.dirty)
        #expect(abs(startAngle - Double.pi / 6.0) <= 1.0e-12)
        #expect(appliedMeasurement.measured.kind == .length)
        #expect(abs(appliedMeasurement.measured.value - 0.006) <= 1.0e-12)
        #expect(appliedMeasurement.target.kind == .length)
        #expect(abs(appliedMeasurement.target.value - 0.006) <= 1.0e-12)
        #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
        #expect(try appliedMeasurement.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSelectionDimensionApplyMovesSplineControlPointAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-selection-spline-cv-dimension.swcad")
        var document = DesignDocument.empty(named: "Process Selection Spline CV Dimension")
        let splineFeatureID = try document.createSplineSketch(
            name: "Measured Spline CV",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(12.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(14.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(16.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
        let anchorFeatureID = try document.createLineSketch(
            name: "Anchor Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
        let splineTargets = try cliSplineControlPointTargets(in: document, featureID: splineFeatureID)
        let anchorTargets = try cliLineEndpointTargets(in: document, featureID: anchorFeatureID)
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "dimension",
            "add-selection",
            documentURL.path,
            "--name",
            "CLI Spline CV Distance",
            "--kind",
            "distance",
            "--first-target",
            try encodedSelectionTarget(splineTargets[0]),
            "--second-target",
            try encodedSelectionTarget(anchorTargets.start),
            "--target-value",
            "10",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLISelectionDimensionAddResponse.self,
            from: result.standardOutputData
        )
        let dimensionID = try #require(response.selectionDimensionID)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Selection dimension added.")
        #expect(response.saved)
        #expect(!response.dirty)

        let setResult = try await runCLI([
            "dimension",
            "set-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--kind",
            "distance",
            "--target-value",
            "6",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let setResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: setResult.standardOutputData
        )

        #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
        #expect(setResponse.message == "Selection dimension target updated.")
        #expect(setResponse.saved)
        #expect(!setResponse.dirty)

        let applyResult = try await runCLI([
            "dimension",
            "apply-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--mode",
            "file",
            "--json",
        ])
        guard applyResult.terminationStatus == CLIExitCode.success.rawValue else {
            Issue.record(
                "Spline control-point selection dimension apply failed: \(applyResult.standardError)\(applyResult.standardOutput)"
            )
            return
        }
        let applyResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: applyResult.standardOutputData
        )
        let appliedLoaded = try DocumentFileService().load(from: documentURL)
        let appliedEvaluation = try SelectionDimensionService().evaluate(
            document: appliedLoaded,
            dimensionID: dimensionID
        )
        let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
        let controlPoints = try cliSplineControlPoints(in: appliedLoaded, featureID: splineFeatureID)

        #expect(applyResponse.message == "Selection dimension target applied.")
        #expect(applyResponse.saved)
        #expect(!applyResponse.dirty)
        #expect(abs(controlPoints[0].x - 0.006) <= 1.0e-12)
        #expect(abs(controlPoints[0].y) <= 1.0e-12)
        #expect(abs(controlPoints[1].x - 0.012) <= 1.0e-12)
        #expect(abs(controlPoints[1].y - 0.003) <= 1.0e-12)
        #expect(appliedMeasurement.measured.kind == .length)
        #expect(abs(appliedMeasurement.measured.value - 0.006) <= 1.0e-12)
        #expect(appliedMeasurement.target.kind == .length)
        #expect(abs(appliedMeasurement.target.value - 0.006) <= 1.0e-12)
        #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
        #expect(try appliedMeasurement.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func executableSelectionDimensionApplyMovesStandaloneSketchPointAsJSON() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("process-selection-standalone-point-dimension.swcad")
        var document = DesignDocument.empty(named: "Process Selection Standalone Point Dimension")
        let pointFeatureID = try createCLIStandalonePointSketch(
            in: &document,
            name: "Measured Point",
            plane: .xy,
            point: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
        let anchorFeatureID = try document.createLineSketch(
            name: "Anchor Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
        let pointTarget = try cliStandalonePointTarget(in: document, featureID: pointFeatureID)
        let anchorTargets = try cliLineEndpointTargets(in: document, featureID: anchorFeatureID)
        try DocumentFileService().save(document, to: documentURL)

        let result = try await runCLI([
            "dimension",
            "add-selection",
            documentURL.path,
            "--name",
            "CLI Point Distance",
            "--kind",
            "distance",
            "--first-target",
            try encodedSelectionTarget(pointTarget),
            "--second-target",
            try encodedSelectionTarget(anchorTargets.start),
            "--target-value",
            "10",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLISelectionDimensionAddResponse.self,
            from: result.standardOutputData
        )
        let dimensionID = try #require(response.selectionDimensionID)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.message == "Selection dimension added.")
        #expect(response.saved)
        #expect(!response.dirty)

        let setResult = try await runCLI([
            "dimension",
            "set-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--kind",
            "distance",
            "--target-value",
            "6",
            "--length-unit",
            "millimeter",
            "--mode",
            "file",
            "--json",
        ])
        let setResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: setResult.standardOutputData
        )

        #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
        #expect(setResponse.message == "Selection dimension target updated.")
        #expect(setResponse.saved)
        #expect(!setResponse.dirty)

        let applyResult = try await runCLI([
            "dimension",
            "apply-selection",
            documentURL.path,
            "--dimension-id",
            dimensionID.description,
            "--mode",
            "file",
            "--json",
        ])
        guard applyResult.terminationStatus == CLIExitCode.success.rawValue else {
            Issue.record(
                "Standalone point selection dimension apply failed: \(applyResult.standardError)\(applyResult.standardOutput)"
            )
            return
        }
        let applyResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: applyResult.standardOutputData
        )
        let appliedLoaded = try DocumentFileService().load(from: documentURL)
        let appliedEvaluation = try SelectionDimensionService().evaluate(
            document: appliedLoaded,
            dimensionID: dimensionID
        )
        let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
        let movedPoint = try cliStandalonePoint(in: appliedLoaded, featureID: pointFeatureID)

        #expect(applyResponse.message == "Selection dimension target applied.")
        #expect(applyResponse.saved)
        #expect(!applyResponse.dirty)
        #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
        #expect(abs(movedPoint.y) <= 1.0e-12)
        #expect(appliedMeasurement.measured.kind == .length)
        #expect(abs(appliedMeasurement.measured.value - 0.006) <= 1.0e-12)
        #expect(appliedMeasurement.target.kind == .length)
        #expect(abs(appliedMeasurement.target.value - 0.006) <= 1.0e-12)
        #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)
        #expect(try appliedMeasurement.isSatisfied())
        guard case .sketchPoint(let point) = appliedMeasurement.dimension.first else {
            Issue.record("Expected standalone point selection reference")
            return
        }
        #expect(point.featureID == pointFeatureID)
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableObjectDimensionSummaryAndSetMutateClosedDocumentAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-object-dimension.swcad")
    try DocumentFileService().save(.empty(named: "Process Object Dimension"), to: documentURL)

    let modelResult = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--width",
        "10",
        "--height",
        "12",
        "--depth",
        "8",
        "--mode",
        "file",
    ])
    let modeled = try DocumentFileService().load(from: documentURL)
    let bodyFeatureID = try #require(modeled.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(modeled.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    let target = SelectionTarget(sceneNodeID: bodyNodeID)
    let targetJSON = try encodedSelectionTarget(target)
    let summaryResult = try await runCLI([
        "dimension",
        "object-summary",
        documentURL.path,
        "--target",
        targetJSON,
        "--mode",
        "file",
        "--json",
    ])
    let summaryResponse = try JSONDecoder().decode(
        CLIObjectDimensionSummaryResponse.self,
        from: summaryResult.standardOutputData
    )
    let setResult = try await runCLI([
        "dimension",
        "set-object",
        documentURL.path,
        "--target",
        targetJSON,
        "--kind",
        "sizeX",
        "--value",
        "30",
        "--unit",
        "millimeter",
        "--mode",
        "file",
        "--json",
    ])
    let setResponse = try JSONDecoder().decode(
        CLIResponse.self,
        from: setResult.standardOutputData
    )
    let loaded = try DocumentFileService().load(from: documentURL)
    let updatedSummary = try ObjectDimensionSummaryService().summarize(
        document: loaded,
        targets: [target]
    )
    let updatedSizeX = try #require(updatedSummary.entries.first { $0.kind == .sizeX })

    #expect(modelResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(summaryResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: summaryResult.standardError))
    #expect(summaryResponse.objectDimensionSummary.counts.entryCount == 3)
    #expect(summaryResponse.objectDimensionSummary.entries.map(\.kind) == [.sizeX, .sizeY, .sizeZ])
    #expect(setResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
    #expect(setResponse.message == "Object dimension updated.")
    #expect(setResponse.saved)
    #expect(abs(updatedSizeX.resolvedMeters - 0.030) < 0.000_000_000_001)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableAutoEvaluateUsesLiveSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-live-eval.swcad")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try DocumentFileService().save(.empty(named: "Persisted"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Live Eval Box",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try await runCLI([
            "eval",
            documentURL.path,
            "--mode",
            "auto",
            "--expected-generation",
            "1",
            "--agent-socket",
            socketURL.path,
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLIEvaluationResponse.self,
            from: result.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.status == .valid)
        #expect(response.evaluatedGeneration == 1)
        #expect(response.bodyCount == 1)
        #expect(response.dirty)
        #expect(loaded.cadDocument.designGraph.order.isEmpty)
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableAutoSavePersistsLiveSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-live-save.swcad")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try DocumentFileService().save(.empty(named: "Before Save"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: try DocumentFileService().load(from: documentURL))
    _ = try session.execute(
        .renameDocument(name: "Saved From Process"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: documentURL)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try await runCLI([
            "save",
            documentURL.path,
            "--mode",
            "auto",
            "--expected-generation",
            "1",
            "--agent-socket",
            socketURL.path,
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLISaveResponse.self,
            from: result.standardOutputData
        )
        let sessionsResult = try await runCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            CLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.path == documentURL.path)
        #expect(response.generation == 1)
        #expect(response.saved)
        #expect(!response.dirty)
        #expect(sessionsResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
        #expect(sessionsResponse.sessions.first?.displayName == "Saved From Process")
        #expect(sessionsResponse.sessions.first?.dirty == false)
        #expect(loaded.cadDocument.metadata.name == "Saved From Process")
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableAutoExportUsesLiveSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-live-export.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("live-export.stl")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try DocumentFileService().save(.empty(named: "Persisted"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Live Export Box",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try await runCLI([
            "export",
            documentURL.path,
            "--output",
            outputURL.path,
            "--mode",
            "auto",
            "--expected-generation",
            "1",
            "--agent-socket",
            socketURL.path,
            "--json",
        ])
        let response = try JSONDecoder().decode(
            CLIExportResponse.self,
            from: result.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)

        #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.format == "stl")
        #expect(response.dirty)
        #expect(response.outputPath == outputURL.path)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(loaded.cadDocument.designGraph.order.isEmpty)
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableFileModeRejectsOpenDocumentConflictAndForceOverridesAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-conflict.swcad")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try DocumentFileService().save(.empty(named: "Before Conflict"), to: documentURL)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open Conflict")),
        path: documentURL
    )
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let rejected = try await runCLI([
            "rename",
            documentURL.path,
            "--name",
            "Rejected",
            "--mode",
            "file",
            "--agent-socket",
            socketURL.path,
        ])
        let unchanged = try DocumentFileService().load(from: documentURL)
        let forced = try await runCLI([
            "rename",
            documentURL.path,
            "--name",
            "Forced",
            "--mode",
            "file",
            "--agent-socket",
            socketURL.path,
            "--force-file-edit",
            "--json",
        ])
        let forcedResponse = try JSONDecoder().decode(
            CLIResponse.self,
            from: forced.standardOutputData
        )
        let sessionsResult = try await runCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            CLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )
        let loaded = try DocumentFileService().load(from: documentURL)

        #expect(rejected.terminationStatus == CLIExitCode.data.rawValue)
        #expect(unchanged.cadDocument.metadata.name == "Before Conflict")
        #expect(forced.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: forced.standardError))
        #expect(forcedResponse.message == "Document renamed to Forced.")
        #expect(forcedResponse.saved)
        #expect(sessionsResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
        #expect(sessionsResponse.sessions.first?.displayName == "Open Conflict")
        #expect(loaded.cadDocument.metadata.name == "Forced")
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUsageExitForInvalidArguments() async throws {
    let result = try await runCLI([
        "attach",
        "--session",
        "not-a-uuid",
    ])

    #expect(result.terminationStatus == CLIExitCode.usage.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUsageExitForInvalidModelUnit() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("invalid-unit.swcad")
    try DocumentFileService().save(.empty(named: "Invalid Unit"), to: documentURL)

    let result = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--width",
        "1",
        "--height",
        "1",
        "--depth",
        "1",
        "--unit",
        "parsec",
        "--mode",
        "file",
    ])

    #expect(result.terminationStatus == CLIExitCode.usage.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsSoftwareExitForUnsupportedExportFormat() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("unsupported-export.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("unsupported.xyz")
    try DocumentFileService().save(.empty(named: "Unsupported Export"), to: documentURL)
    let modelResult = try await runCLI([
        "model",
        "box",
        documentURL.path,
        "--width",
        "1",
        "--height",
        "1",
        "--depth",
        "1",
        "--mode",
        "file",
    ])

    let result = try await runCLI([
        "export",
        documentURL.path,
        "--output",
        outputURL.path,
        "--mode",
        "file",
    ])

    #expect(modelResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(result.terminationStatus == CLIExitCode.software.rawValue)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUsageExitForUnknownCommand() async throws {
    let result = try await runCLI(["does-not-exist"])

    #expect(result.terminationStatus == CLIExitCode.usage.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutablePrintsHelpSuccessfully() async throws {
    let result = try await runCLI(["--help"])

    #expect(result.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
    #expect(result.standardOutput.contains("USAGE: rupa"))
    #expect(result.standardOutput.contains("SUBCOMMANDS:"))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsInputOutputExitForMissingDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("missing.swcad")

    let result = try await runCLI([
        "validate",
        documentURL.path,
    ])

    #expect(result.terminationStatus == CLIExitCode.inputOutput.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUnavailableExitForMissingAgentSocket() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("missing.sock")

    let result = try await runCLI([
        "agent",
        "status",
        "--socket",
        socketURL.path,
    ])

    #expect(result.terminationStatus == CLIExitCode.unavailable.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsDataExitForLiveGenerationMismatch() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, id: sessionID)
    let listener = AgentSocketListener(
        controller: server,
        socketPath: AgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try await runCLI([
            "rename-live",
            sessionID.uuidString,
            "--name",
            "Rejected",
            "--expected-generation",
            "9",
            "--socket",
            socketURL.path,
        ])

        #expect(result.terminationStatus == CLIExitCode.data.rawValue)
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test func cliResponseEncodesStableJSONFields() async throws {
    let response = CLIResponse(
        message: "Renamed",
        generation: 1,
        dirty: false,
        diagnostics: [
            EditorDiagnostic(
                severity: .info,
                message: "Document is valid."
            ),
        ]
    )

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(CLIResponse.self, from: data)

    #expect(decoded.message == "Renamed")
    #expect(decoded.generation == 1)
    #expect(!decoded.dirty)
    #expect(!decoded.saved)
    #expect(decoded.diagnostics.first?.severity == .info)
}

@Test func cliServiceReportsAgentStatus() async throws {
    let server = AgentCommandController(socketPath: "/tmp/rupa.sock")
    _ = server.register(session: EditorSession(document: .empty(named: "Open")))

    let response = try CLIService().agentStatus(client: server)

    #expect(response.running)
    #expect(response.socketPath == "/tmp/rupa.sock")
    #expect(response.sessionCount == 1)
}

@Test func cliExitCodeMapsTypedEditorErrors() async throws {
    #expect(
        CLIExitCode.value(
            for: EditorError(code: .commandInvalid, message: "Invalid")
        ) == .usage
    )
    #expect(
        CLIExitCode.value(
            for: EditorError(code: .documentOpenInApp, message: "Open")
        ) == .data
    )
    #expect(
        CLIExitCode.value(
            for: EditorError(code: .sessionNotFound, message: "Missing")
        ) == .data
    )
    #expect(
        CLIExitCode.value(
            for: EditorError(code: .documentLoadFailed, message: "Load")
        ) == .inputOutput
    )
    #expect(
        CLIExitCode.value(
            for: EditorError(code: .agentConnectionFailed, message: "Agent")
        ) == .unavailable
    )
    #expect(
        CLIExitCode.value(
            for: EditorError(code: .evaluationFailed, message: "Evaluation")
        ) == .software
    )
    #expect(
        CLIExitCode.value(
            for: ValidationError("Invalid argument")
        ) == .usage
    )
}

@Test func cliServiceListsAgentSessions() async throws {
    let server = AgentCommandController()
    let id = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: id
    )

    let response = try CLIService().sessions(client: server)

    #expect(response.sessions.count == 1)
    #expect(response.sessions[0].id == id)
    #expect(response.sessions[0].displayName == "Open")
}

@Test func cliServiceAttachResolvesFileBackedSession() async throws {
    let server = AgentCommandController()
    let id = UUID()
    let url = URL(fileURLWithPath: "/tmp/open-attach.swcad")
    let session = EditorSession(document: .empty(named: "Attach File"))
    server.register(
        session: session,
        path: url,
        id: id
    )

    let response = try CLIService().attach(
        target: CLIDocumentTarget(fileURL: url),
        client: server
    )

    #expect(response.sessionID == id)
    #expect(response.path == url.path)
    #expect(response.displayName == "Attach File")
    #expect(response.generation == 0)
}

@Test func cliServiceAttachResolvesExplicitSessionID() async throws {
    let server = AgentCommandController()
    let id = UUID()
    let session = EditorSession(document: .empty(named: "Attach Session"))
    server.register(session: session, id: id)

    let response = try CLIService().attach(
        target: CLIDocumentTarget(sessionID: id),
        client: server
    )

    #expect(response.sessionID == id)
    #expect(response.path == nil)
    #expect(response.displayName == "Attach Session")
}

@Test func cliServiceAttachRejectsMissingOpenSession() async throws {
    let server = AgentCommandController()
    let url = URL(fileURLWithPath: "/tmp/missing-attach.swcad")

    var caught: EditorError?
    do {
        _ = try CLIService().attach(
            target: CLIDocumentTarget(fileURL: url),
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .sessionNotFound)
}

@Test func cliServiceAttachRejectsAmbiguousTarget() async throws {
    let server = AgentCommandController()
    let id = UUID()
    let url = URL(fileURLWithPath: "/tmp/ambiguous-attach.swcad")
    server.register(
        session: EditorSession(document: .empty(named: "Attach")),
        path: url,
        id: id
    )

    var caught: EditorError?
    do {
        _ = try CLIService().attach(
            target: CLIDocumentTarget(
                fileURL: url,
                sessionID: id
            ),
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func cliServiceRenamesLiveSessionThroughAgent() async throws {
    let server = AgentCommandController()
    let id = UUID()
    let session = EditorSession()
    server.register(session: session, id: id)

    let response = try CLIService().renameLiveSession(
        sessionID: id,
        name: "Live",
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    #expect(response.message == "Document renamed to Live.")
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.metadata.name == "Live")
}

@MainActor
@Test func cliServiceSelectsTargetsInLiveSessionThroughAgent() async throws {
    let server = AgentCommandController()
    let id = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceTop))
    server.register(session: session, id: id)

    let response = try CLIService().selectTargetsLiveSession(
        sessionID: id,
        targets: [target],
        expectedGeneration: generation,
        client: server
    )

    #expect(response.message == "1 target(s), 0 reference(s) selected.")
    #expect(response.generation == generation.value)
    #expect(response.selectedTargetCount == 1)
    #expect(response.selectedReferenceCount == 0)
    #expect(response.selectedTargets == [target])
    #expect(session.selection.selectedTargets == [target])
    #expect(session.generation == generation)
}

@MainActor
@Test func cliServiceSelectsReferencesInLiveSessionThroughAgent() async throws {
    let server = AgentCommandController()
    let id = UUID()
    let session = EditorSession(document: .empty(named: "Service Reference Selection"))
    _ = try #require(session.createPolySplineSurface(
        name: "CLI Service Surface Reference",
        sourceMesh: cliPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))
    let generation = session.generation
    let dirty = session.isDirty
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    server.register(session: session, id: id)

    let response = try CLIService().selectReferencesLiveSession(
        sessionID: id,
        references: [controlPoint.selectionReference],
        expectedGeneration: generation,
        client: server
    )

    #expect(response.message == "0 target(s), 1 reference(s) selected.")
    #expect(response.generation == generation.value)
    #expect(response.dirty == dirty)
    #expect(response.selectedTargetCount == 0)
    #expect(response.selectedReferenceCount == 1)
    #expect(response.selectedReferences == [controlPoint.selectionReference])
    #expect(session.selection.selectedReferences == [controlPoint.selectionReference])
    #expect(session.generation == generation)
}

@Test func cliServiceAutoRenameUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-auto.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().renameDocument(
        target: CLIDocumentTarget(fileURL: url),
        name: "Auto Live",
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Document renamed to Auto Live.")
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.metadata.name == "Auto Live")
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceAutoRenameUsesFileWhenNoOpenSessionMatches() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("closed-auto.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().renameDocument(
        target: CLIDocumentTarget(fileURL: url),
        name: "Auto File",
        mode: .auto,
        client: AgentCommandController()
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Document renamed to Auto File.")
    #expect(response.saved)
    #expect(loaded.cadDocument.metadata.name == "Auto File")
}

@Test func cliServiceFileModeRejectsOpenDocumentConflict() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-file-mode.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: EditorError?
    do {
        _ = try CLIService().renameDocument(
            target: CLIDocumentTarget(fileURL: url),
            name: "Rejected",
            mode: .file,
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    let loaded = try DocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceLiveModeResolvesFilePathToOpenSession() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("live-path.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().renameDocument(
        target: CLIDocumentTarget(fileURL: url),
        name: "Live Path",
        mode: .live,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Document renamed to Live Path.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.metadata.name == "Live Path")
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceLiveModeRequiresAgentClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("missing-client.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    var caught: EditorError?
    do {
        _ = try CLIService().renameDocument(
            target: CLIDocumentTarget(fileURL: url),
            name: "No Client",
            mode: .live
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func cliServiceRejectsFileEditWhenAgentReportsOpenDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: EditorError?
    do {
        _ = try CLIService().renameFile(
            at: url,
            name: "Rejected",
            conflictClient: server
        )
    } catch let error as EditorError {
        caught = error
    }

    let loaded = try DocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceDryRunDoesNotPersistFileRename() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("dry-run.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().renameFile(
        at: url,
        name: "Dry Run",
        dryRun: true
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Document renamed to Dry Run.")
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceFileRenamePersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("closed.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().renameFile(
        at: url,
        name: "After"
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Document renamed to After.")
    #expect(response.generation == 1)
    #expect(!response.dirty)
    #expect(response.saved)
    #expect(loaded.cadDocument.metadata.name == "After")
}

@Test func cliServiceFileParameterSetPersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("parameter.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().setParameter(
        target: CLIDocumentTarget(fileURL: url),
        name: "width",
        expression: .constant(.length(25.0, unit: .millimeter)),
        kind: .length,
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    let parameter = try #require(
        loaded.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    #expect(response.message == "Parameter width updated.")
    #expect(response.saved)
    #expect(parameter.kind == .length)
}

@Test func cliServiceAutoParameterSetUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-parameter.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().setParameter(
        target: CLIDocumentTarget(fileURL: url),
        name: "liveWidth",
        expression: .constant(.length(12.0, unit: .millimeter)),
        kind: .length,
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Parameter liveWidth updated.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.parameters.parameters.values.contains { $0.name == "liveWidth" })
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test func cliServiceFileParameterDeletePersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("parameter-delete.swcad")
    var document = DesignDocument.empty(named: "Before")
    try document.upsertParameter(
        name: "width",
        expression: .constant(.length(25.0, unit: .millimeter)),
        kind: .length
    )
    try DocumentFileService().save(document, to: url)

    let response = try CLIService().deleteParameter(
        target: CLIDocumentTarget(fileURL: url),
        name: "width",
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Parameter width deleted.")
    #expect(response.saved)
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test func cliServiceAutoParameterDeleteUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-parameter-delete.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .upsertParameter(
            name: "liveWidth",
            expression: .constant(.length(12.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: url)

    let response = try CLIService().deleteParameter(
        target: CLIDocumentTarget(fileURL: url),
        name: "liveWidth",
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Parameter liveWidth deleted.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test func cliServiceParameterFileModeRejectsOpenDocumentConflict() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-parameter-file.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: EditorError?
    do {
        _ = try CLIService().setParameter(
            target: CLIDocumentTarget(fileURL: url),
            name: "rejected",
            expression: .constant(.length(1.0, unit: .meter)),
            kind: .length,
            mode: .file,
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    let loaded = try DocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test func cliServiceFileParameterExpressionPersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("parameter-expression.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    _ = try CLIService().setParameter(
        target: CLIDocumentTarget(fileURL: url),
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length,
        mode: .file
    )

    let response = try CLIService().setParameterExpression(
        target: CLIDocumentTarget(fileURL: url),
        name: "height",
        expression: "width * 2 + 5mm",
        kind: .length,
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    let height = try #require(
        loaded.cadDocument.parameters.parameters.values.first { $0.name == "height" }
    )
    let resolved = try loaded.cadDocument.parameters.resolvedValue(for: height.expression)
    #expect(response.message == "Parameter height updated.")
    #expect(response.saved)
    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 0.025) < 0.000_000_000_001)
}

@MainActor
@Test func cliServiceAutoParameterExpressionUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-parameter-expression.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    server.register(session: session, path: url)

    let response = try CLIService().setParameterExpression(
        target: CLIDocumentTarget(fileURL: url),
        name: "height",
        expression: "width * 2",
        kind: .length,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    let height = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "height" }
    )
    let resolved = try session.document.cadDocument.parameters.resolvedValue(for: height.expression)
    #expect(response.message == "Parameter height updated.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(abs(resolved.value - 0.02) < 0.000_000_000_001)
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test func cliServiceFileParameterListReportsResolvedExpressions() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("parameter-list.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    _ = try CLIService().setParameter(
        target: CLIDocumentTarget(fileURL: url),
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length,
        mode: .file
    )
    _ = try CLIService().setParameterExpression(
        target: CLIDocumentTarget(fileURL: url),
        name: "height",
        expression: "width * 2",
        kind: .length,
        mode: .file
    )

    let response = try CLIService().listParameters(
        target: CLIDocumentTarget(fileURL: url),
        mode: .file
    )
    let height = try #require(response.parameters.first { $0.name == "height" })

    #expect(response.message == "2 parameters.")
    #expect(response.parameters.map(\.name) == ["height", "width"])
    #expect(height.expression == "(width * 2)")
    #expect(height.resolvedKind == .length)
}

@MainActor
@Test func cliServiceAutoParameterListUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-parameter-list.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .upsertParameter(
            name: "liveWidth",
            expression: .constant(.length(5.0, unit: .millimeter)),
            kind: .length
        )
    )
    server.register(session: session, path: url)

    let response = try CLIService().listParameters(
        target: CLIDocumentTarget(fileURL: url),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    #expect(response.dirty)
    #expect(response.parameters.map(\.name) == ["liveWidth"])
}

@Test func cliServiceFileModelBoxPersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("box.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Box",
        plane: .xy,
        width: .length(40.0, .millimeter),
        height: .length(20.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Extruded rectangle CLI Box created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 2)
    #expect(loaded.productMetadata.sceneNodes.values.contains { $0.reference != nil })
}

@Test func cliServiceFileModelBoxCornersPersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("box-corners.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().createExtrudedRectangleFromCorners(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Footprint Box",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(2.0, .millimeter),
            y: .length(1.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(8.0, .millimeter),
            y: .length(5.0, .millimeter)
        ),
        depth: .length(3.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    let bodyFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(loaded.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("CLI box-corners should create an extrude feature.")
        return
    }

    #expect(response.message == "Extruded rectangle CLI Footprint Box created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 2)
    #expect(extrude.profile.featureID == loaded.cadDocument.designGraph.order.first)
    #expect(loaded.productMetadata.sceneNodes.values.contains { $0.reference == .body(bodyFeatureID) })
}

@Test func cliServiceFileModelCylinderPersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("cylinder.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().createExtrudedCircle(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Cylinder",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(8.0, .millimeter),
        depth: .length(12.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Extruded circle CLI Cylinder created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 2)
    #expect(loaded.productMetadata.sceneNodes.values.contains { $0.reference != nil })
}

@Test func cliServiceFileModelExtrudeExistingProfilePersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("extrude.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    _ = try CLIService().createRectangleSketch(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Profile",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        mode: .file
    )
    let loadedAfterSketch = try DocumentFileService().load(from: url)
    let sketchFeatureID = try #require(loadedAfterSketch.cadDocument.designGraph.order.first)

    let response = try CLIService().extrudeProfile(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Extrude",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    let extrudeFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
    let extrudeFeature = try #require(loaded.cadDocument.designGraph.nodes[extrudeFeatureID])
    guard case let .extrude(extrude) = extrudeFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(response.message == "Profile extrude CLI Extrude created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 2)
    #expect(loaded.productMetadata.sceneNodes.values.contains { $0.reference == .body(extrudeFeatureID) })
    #expect(extrude.profile.featureID == sketchFeatureID)
}

@Test func cliServiceAutoModelBoxUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-box.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: url),
        name: "Live Box",
        plane: .xy,
        width: .length(12.0, .millimeter),
        height: .length(6.0, .millimeter),
        depth: .length(3.0, .millimeter),
        direction: .normal,
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Extruded rectangle Live Box created.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceAutoModelBoxCornersUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-box-corners.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().createExtrudedRectangleFromCorners(
        target: CLIDocumentTarget(fileURL: url),
        name: "Live Footprint Box",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(1.0, .millimeter),
            y: .length(1.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(6.0, .millimeter),
            y: .length(4.0, .millimeter)
        ),
        depth: .length(2.0, .millimeter),
        direction: .normal,
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Extruded rectangle Live Footprint Box created.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceAutoModelExtrudeExistingProfileUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-extrude.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createRectangleSketch(
            name: "Live Profile",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter)
        )
    )
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    server.register(session: session, path: url)

    let response = try CLIService().extrudeProfile(
        target: CLIDocumentTarget(fileURL: url),
        name: "Live Extrude",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(5.0, .millimeter),
        direction: .normal,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    let extrudeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let extrudeFeature = try #require(session.document.cadDocument.designGraph.nodes[extrudeFeatureID])
    guard case let .extrude(extrude) = extrudeFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(response.message == "Profile extrude Live Extrude created.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
    #expect(extrude.profile.featureID == sketchFeatureID)
}

@Test func cliServiceFileSketchLinePersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("line.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().createLineSketch(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        ),
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    let featureID = try #require(loaded.cadDocument.designGraph.order.first)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let entity = try #require(sketch.entities.values.first)
    guard case .line = entity else {
        #expect(Bool(false))
        return
    }

    #expect(response.message == "Line sketch CLI Line created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(loaded.cadDocument.designGraph.order.count == 1)
}

@Test func cliServiceFileSketchRectanglePersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("rectangle.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try CLIService().createRectangleSketch(
        target: CLIDocumentTarget(fileURL: url),
        name: "CLI Rectangle",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        mode: .file
    )

    let loaded = try DocumentFileService().load(from: url)
    let featureID = try #require(loaded.cadDocument.designGraph.order.first)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(response.message == "Rectangle sketch CLI Rectangle created.")
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(sketch.entities.count == 4)
    #expect(loaded.cadDocument.designGraph.order.count == 1)
}

@Test func cliServiceAutoSketchCircleUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-circle.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().createCircleSketch(
        target: CLIDocumentTarget(fileURL: url),
        name: "Live Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(1.0, .millimeter),
            y: .length(2.0, .millimeter)
        ),
        radius: .length(3.0, .millimeter),
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Circle sketch Live Circle created.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceAutoSketchRectangleUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-rectangle.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try CLIService().createRectangleSketch(
        target: CLIDocumentTarget(fileURL: url),
        name: "Live Rectangle",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try DocumentFileService().load(from: url)
    #expect(response.message == "Rectangle sketch Live Rectangle created.")
    #expect(response.dirty)
    #expect(!response.saved)
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceModelBoxFileModeRejectsOpenDocumentConflict() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-box-file.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: EditorError?
    do {
        _ = try CLIService().createExtrudedRectangle(
            target: CLIDocumentTarget(fileURL: url),
            name: "Rejected Box",
            plane: .xy,
            width: .length(1.0, .millimeter),
            height: .length(1.0, .millimeter),
            depth: .length(1.0, .millimeter),
            direction: .normal,
            mode: .file,
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    let loaded = try DocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceFileExportWritesClosedDocumentArtifact() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("export-source.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("exported.stl")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: documentURL),
        name: "Export Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try CLIService().exportDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .file
    )

    #expect(response.format == "stl")
    #expect(response.outputPath == outputURL.path)
    #expect(response.byteCount == 84 + 12 * 50)
    #expect(!response.dirty)
    #expect(!response.dryRun)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func cliServiceFileExportUsesPresetAndVersionedPolicy() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let preset = ExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Preset Source")
    document.productMetadata = metadata

    let documentURL = temporaryDirectory.appendingPathComponent("preset-source.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("preset-export.stl")
    let versionedURL = temporaryDirectory.appendingPathComponent("preset-export-1.stl")
    try DocumentFileService().save(document, to: documentURL)
    try Data("existing".utf8).write(to: outputURL)
    _ = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: documentURL),
        name: "Preset Export Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try CLIService().exportDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .file,
        options: ExportOptions(
            presetName: "Print STL",
            destinationPolicy: .versioned
        )
    )

    #expect(response.presetName == "Print STL")
    #expect(response.outputUnit == "millimeter")
    #expect(response.destinationPolicy == "versioned")
    #expect(response.outputPath == versionedURL.path)
    #expect(response.byteCount == 84 + 12 * 50)
    #expect(String(decoding: try Data(contentsOf: outputURL), as: UTF8.self) == "existing")
    #expect(FileManager.default.fileExists(atPath: versionedURL.path))
}

@Test func cliServiceFileExportDryRunDoesNotWriteOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("dry-export-source.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("dry-exported.stl")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: documentURL),
        name: "Dry Export Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try CLIService().exportDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .file,
        dryRun: true
    )

    #expect(response.dryRun)
    #expect(response.byteCount == 0)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@MainActor
@Test func cliServiceAutoExportUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-export.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("open-export.stl")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Export",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)

    let response = try CLIService().exportDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(response.format == "stl")
    #expect(response.byteCount == 84 + 12 * 50)
    #expect(response.dirty)
    #expect(!response.dryRun)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func cliServiceAutoExportPassesPresetOptionsToLiveSession() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let preset = ExportPreset(
        name: "Micro STL",
        format: .stl,
        outputUnit: .micrometer,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Open Preset Source")
    document.productMetadata = metadata

    let documentURL = temporaryDirectory.appendingPathComponent("open-preset-export.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("open-preset-export.stl")
    try DocumentFileService().save(document, to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: document)
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Preset Export",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)

    let response = try CLIService().exportDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        options: ExportOptions(presetName: "Micro STL"),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    let header = String(decoding: try Data(contentsOf: outputURL).prefix(80), as: UTF8.self)
    #expect(response.presetName == "Micro STL")
    #expect(response.outputUnit == "micrometer")
    #expect(response.destinationPolicy == "overwrite")
    #expect(response.dirty)
    #expect(header.contains("unit=micrometer"))
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceExportFileModeRejectsOpenDocumentConflict() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-export-file.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("rejected-export.stl")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: documentURL
    )

    var caught: EditorError?
    do {
        _ = try CLIService().exportDocument(
            target: CLIDocumentTarget(fileURL: documentURL),
            outputURL: outputURL,
            mode: .file,
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .documentOpenInApp)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func cliServiceFileEvaluateReturnsSnapshotForClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("eval-source.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: documentURL),
        name: "Eval Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try CLIService().evaluateDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .file
    )

    #expect(response.status == .valid)
    #expect(response.evaluatedGeneration == 0)
    #expect(response.bodyCount == 1)
    #expect(!response.dirty)
}

@MainActor
@Test func cliServiceAutoEvaluateUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-eval.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Eval",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)

    let response = try CLIService().evaluateDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(response.status == .valid)
    #expect(response.evaluatedGeneration == 1)
    #expect(response.bodyCount == 1)
    #expect(response.dirty)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func cliServiceAutoInspectUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-inspect.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open Inspect"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Inspect",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)

    let sketchResponse = try CLIService().sketchEntitySummary(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )
    let topologyResponse = try CLIService().topologySummary(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )
    let curveResponse = try CLIService().curveAnalysis(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(sketchResponse.generation == 1)
    #expect(sketchResponse.dirty)
    #expect(sketchResponse.sketchEntitySummary.counts.entityCount == 4)
    #expect(topologyResponse.generation == 1)
    #expect(topologyResponse.dirty)
    #expect(topologyResponse.topologySummary.counts.bodyCount == 1)
    #expect(curveResponse.generation == 1)
    #expect(curveResponse.dirty)
    #expect(curveResponse.curveAnalysis.counts.curveCount == 4)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceFileMeasureReturnsStructuredResultForClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("measure-source.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: documentURL),
        name: "Measure Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try CLIService().measureDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .file
    )

    #expect(response.generation == 0)
    #expect(!response.dirty)
    #expect(response.measurement.counts.sourceFeatures == 2)
    #expect(response.measurement.counts.solids == 1)
    #expect(abs(response.measurement.totals.profileAreaSquareMeters - 0.0002) < 0.000_000_000_001)
    #expect(abs(response.measurement.totals.solidVolumeCubicMeters - 0.000001) < 0.000_000_000_001)
    let solid = try #require(response.measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.005) < 0.000_000_000_001)
    #expect(response.message.contains("Measurement summary"))
}

@MainActor
@Test func cliServiceAutoMeasureUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-measure.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Measure",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)

    let response = try CLIService().measureDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(response.measurement.counts.sourceFeatures == 2)
    #expect(response.measurement.counts.solids == 1)
    #expect(abs(response.measurement.totals.solidVolumeCubicMeters - 0.000000216) < 0.000_000_000_001)
    let solid = try #require(response.measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.003) < 0.000_000_000_001)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func cliServiceAutoMeasureUsesLiveSelectionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-selected-measure.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Selected Measure",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    #expect(session.selectSceneNode(bodyNodeID))
    server.register(session: session, path: documentURL)

    let response = try CLIService().measureDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(response.measurement.scope == .selection)
    #expect(response.measurement.counts.sourceFeatures == 2)
    #expect(response.measurement.counts.solids == 1)
    #expect(abs(response.measurement.totals.solidVolumeCubicMeters - 0.000000216) < 0.000_000_000_001)
    let solid = try #require(response.measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.003) < 0.000_000_000_001)
    #expect(response.message.contains("Selection measurement"))
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceFileMeshSummaryReturnsStructuredResultForClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("mesh-source.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try CLIService().createExtrudedRectangle(
        target: CLIDocumentTarget(fileURL: documentURL),
        name: "Mesh Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try CLIService().meshSummary(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .file
    )
    let bounds = try #require(response.meshSummary.bounds)

    #expect(response.generation == 0)
    #expect(!response.dirty)
    #expect(response.meshSummary.bodyCount == 1)
    #expect(response.meshSummary.vertexCount > 0)
    #expect(response.meshSummary.triangleCount > 0)
    #expect(response.meshSummary.indexedElementCount == response.meshSummary.triangleCount * 3)
    #expect(abs(bounds.sizeX - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.01) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.005) < 0.000_000_000_001)
    #expect(response.message.contains("Mesh summary"))
}

@MainActor
@Test func cliServiceAutoMeshSummaryUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-mesh.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Unsaved Mesh",
            plane: .xy,
            width: .length(12.0, .millimeter),
            height: .length(6.0, .millimeter),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, path: documentURL)

    let response = try CLIService().meshSummary(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(response.meshSummary.bodyCount == 1)
    #expect(response.meshSummary.vertexCount > 0)
    #expect(response.meshSummary.triangleCount > 0)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceFileSavePersistsClosedDocumentWithoutChangingGeneration() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("file-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let response = try CLIService().saveDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .file
    )

    #expect(response.path == documentURL.path)
    #expect(response.generation == 0)
    #expect(response.saved)
    #expect(!response.dirty)
}

@MainActor
@Test func cliServiceAutoSaveUsesLiveSessionForOpenFileAndMarksClean() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    let session = EditorSession(document: try DocumentFileService().load(from: documentURL))
    _ = try session.execute(
        .renameDocument(name: "Saved By Auto"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: documentURL)

    let response = try CLIService().saveDocument(
        target: CLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try DocumentFileService().load(from: documentURL)
    #expect(response.path == documentURL.path)
    #expect(response.generation == 1)
    #expect(response.saved)
    #expect(!response.dirty)
    #expect(!session.isDirty)
    #expect(loaded.cadDocument.metadata.name == "Saved By Auto")
}

@Test func cliServiceSaveFileModeRejectsOpenDocumentConflict() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-save-file.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = AgentCommandController()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: documentURL
    )

    var caught: EditorError?
    do {
        _ = try CLIService().saveDocument(
            target: CLIDocumentTarget(fileURL: documentURL),
            mode: .file,
            client: server
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .documentOpenInApp)
}

private func makeTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    return temporaryDirectory
}

private func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}

private func cliPolySplinePatchNetworkMesh(centerZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}

private func cliDirectBSplineSurfaceWithInteriorKnots() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: base.controlPoints,
        weights: base.weights
    )
}

private func cliDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func cliOffsetDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.04, z: 0.002),
        bottomRight: Point3D(x: 0.02, y: 0.04, z: -0.002),
        topRight: Point3D(x: 0.02, y: 0.06, z: 0.001),
        topLeft: Point3D(x: 0.0, y: 0.06, z: 0.003)
    )
}

private func cliSurfaceTrimReference(
    featureID: FeatureID,
    edgeIndex: Int,
    in document: DesignDocument
) throws -> SelectionReference {
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first { $0.featureID == featureID.description })
    let trimLoop = try #require(source.patches.first?.trimLoops.first)
    guard trimLoop.selectionReferences.indices.contains(edgeIndex) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "CLI surface trim reference is missing."
        )
    }
    return trimLoop.selectionReferences[edgeIndex]
}

@MainActor
private func cliDefaultBoxFixture() throws -> (
    document: DesignDocument,
    bodyFeatureID: FeatureID,
    bodyNodeID: SceneNodeID
) {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(cliBodySceneNodeID(for: bodyFeatureID, in: session.document))
    return (session.document, bodyFeatureID, bodyNodeID)
}

private func cliBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func cliProfileBounds(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let sketch = try cliProfileSketch(forBody: featureID, in: document)
    var points: [(x: Double, y: Double)] = []
    for entity in sketch.entities.values {
        guard case .line(let line) = entity else {
            continue
        }
        points.append((try cliLength(line.start.x, in: document), try cliLength(line.start.y, in: document)))
        points.append((try cliLength(line.end.x, in: document), try cliLength(line.end.y, in: document)))
    }
    let first = try #require(points.first)
    return points.dropFirst().reduce(
        (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    ) { bounds, point in
        (
            minX: min(bounds.minX, point.x),
            minY: min(bounds.minY, point.y),
            maxX: max(bounds.maxX, point.x),
            maxY: max(bounds.maxY, point.y)
        )
    }
}

private func cliProfileLineCount(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Int {
    try cliProfileSketch(forBody: featureID, in: document).entities.values.filter { entity in
        if case .line = entity {
            return true
        }
        return false
    }.count
}

private func cliProfileArcCount(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Int {
    try cliProfileSketch(forBody: featureID, in: document).entities.values.filter { entity in
        if case .arc = entity {
            return true
        }
        return false
    }.count
}

private func cliProfileSketch(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Sketch {
    let extrude = try cliExtrudeFeature(for: featureID, in: document)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case .sketch(let sketch) = profileFeature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Body profile must be a sketch."
        )
    }
    return sketch
}

private func cliExtrudeFeature(
    for featureID: FeatureID,
    in document: DesignDocument
) throws -> ExtrudeFeature {
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .extrude(let extrude) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Feature must be an extrude."
        )
    }
    return extrude
}

private func cliLength(
    _ expression: CADExpression,
    in document: DesignDocument
) throws -> Double {
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func cliNearlyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func cliLineEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: SelectionTarget, end: SelectionTarget) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .lineStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .lineEnd })
    return (
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

private func cliArcEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: SelectionTarget, end: SelectionTarget) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "arc"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .arcStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .arcEnd })
    return (
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

private func createCLIStandalonePointSketch(
    in document: inout DesignDocument,
    name: String,
    plane: SketchPlane,
    point: SketchPoint
) throws -> FeatureID {
    let featureID = try document.createLineSketch(
        name: name,
        plane: plane,
        start: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
        end: SketchPoint(x: .length(1.0, .millimeter), y: .length(0.0, .millimeter))
    )
    let pointID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "CLI standalone point test requires a sketch feature."
        )
    }
    sketch.entities[pointID] = .point(point)
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return featureID
}

private func cliStandalonePointTarget(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "point"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let pointHandle = try #require(entry.pointHandles.first { $0.handle == .point })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeUUID),
        component: .sketchEntity(SelectionComponentID(rawValue: pointHandle.selectionComponentID))
    )
}

private func cliSplineControlPointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> [SelectionTarget] {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "spline"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    return entry.controlPointTargets
        .sorted { $0.index < $1.index }
        .map { controlPoint in
            SelectionTarget(
                sceneNodeID: sceneNodeID,
                component: .sketchEntity(SelectionComponentID(rawValue: controlPoint.selectionComponentID))
            )
        }
}

private func cliArcStartAngle(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .arc(arc) = sketch.entities.values.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected one source arc."
        )
    }
    let quantity = try document.cadDocument.parameters.resolvedValue(for: arc.startAngle)
    #expect(quantity.kind == .angle)
    return quantity.value
}

private func cliSplineControlPoints(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> [(x: Double, y: Double)] {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          case let .spline(spline) = sketch.entities.values.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected one source spline."
        )
    }
    return try spline.controlPoints.map { controlPoint in
        (
            x: try cliLength(controlPoint.x, in: document),
            y: try cliLength(controlPoint.y, in: document)
        )
    }
}

private func cliStandalonePoint(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (x: Double, y: Double) {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation,
          let pointEntity = sketch.entities.values.first(where: { entity in
              if case .point = entity {
                  return true
              }
              return false
          }),
          case let .point(point) = pointEntity else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected one standalone source point."
        )
    }
    return (
        x: try cliLength(point.x, in: document),
        y: try cliLength(point.y, in: document)
    )
}

private func encodedSelectionReference(_ reference: SelectionReference) throws -> String {
    let data = try JSONEncoder().encode(reference)
    return String(decoding: data, as: UTF8.self)
}

private func encodedSelectionTarget(_ target: SelectionTarget) throws -> String {
    let data = try JSONEncoder().encode(target)
    return String(decoding: data, as: UTF8.self)
}

private func encodedBridgeCurveEndpoint(_ endpoint: BridgeCurveEndpoint) throws -> String {
    let data = try JSONEncoder().encode(endpoint)
    return String(decoding: data, as: UTF8.self)
}

private func encodedSketchConstraint(_ constraint: SketchConstraint) throws -> String {
    let data = try JSONEncoder().encode(constraint)
    return String(decoding: data, as: UTF8.self)
}

private func encodedSurfaceFrameQuery(_ query: SurfaceFrameQuery) throws -> String {
    let data = try JSONEncoder().encode(query)
    return String(decoding: data, as: UTF8.self)
}

private func encodedSelectionMeasurementQuery(_ query: CADAgentMeasurementQuery) throws -> String {
    let data = try JSONEncoder().encode(query)
    return String(decoding: data, as: UTF8.self)
}
