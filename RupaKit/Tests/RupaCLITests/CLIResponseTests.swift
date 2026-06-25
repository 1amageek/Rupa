import ArgumentParser
import Foundation
import Testing
import RupaAgent
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
        #expect(response.message == "1 reference selected.")
        #expect(response.generation == generation.value)
        #expect(!response.dirty)
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
    #expect(controlPoint.isEditable)
    #expect(analysisResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: analysisResult.standardError))
    #expect(analysisResponse.surfaceAnalysis.counts.bSplineFaceCount == 2)
    #expect(analysisResponse.surfaceAnalysis.counts.sampleCount == 50)
    #expect(analysisResponse.surfaceAnalysis.counts.trimBoundaryCount == 2)
    #expect(analysisResponse.surfaceAnalysis.counts.trimBoundaryEdgeCount == 8)
    #expect(continuityResult.terminationStatus == CLIExitCode.success.rawValue, Comment(rawValue: continuityResult.standardError))
    #expect(continuityResponse.surfaceContinuitySummary.counts.bSplineFaceCount == 2)
    #expect(continuityResponse.surfaceContinuitySummary.counts.sharedEdgeCount == 1)
    #expect(continuityResponse.surfaceContinuitySummary.counts.g1AdjacencyCount == 1)
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

    #expect(response.message == "1 target selected.")
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

    #expect(response.message == "1 reference selected.")
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

private func encodedSelectionReference(_ reference: SelectionReference) throws -> String {
    let data = try JSONEncoder().encode(reference)
    return String(decoding: data, as: UTF8.self)
}

private func encodedSelectionTarget(_ target: SelectionTarget) throws -> String {
    let data = try JSONEncoder().encode(target)
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

private struct CLIProcessResult {
    var terminationStatus: Int32
    var standardOutputData: Data
    var standardErrorData: Data

    var standardOutput: String {
        String(decoding: standardOutputData, as: UTF8.self)
    }

    var standardError: String {
        String(decoding: standardErrorData, as: UTF8.self)
    }
}

private actor CLIProcessGate {
    static let shared = CLIProcessGate()

    func run(_ arguments: [String]) throws -> CLIProcessResult {
        try runCLIProcess(arguments)
    }
}

private func runCLI(_ arguments: [String]) async throws -> CLIProcessResult {
    try await CLIProcessGate.shared.run(arguments)
}

private func runCLIProcess(_ arguments: [String]) throws -> CLIProcessResult {
    let executableURL = try rupaExecutableURL()
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let outputData = try standardOutput.fileHandleForReading.readToEnd() ?? Data()
    let errorData = try standardError.fileHandleForReading.readToEnd() ?? Data()

    return CLIProcessResult(
        terminationStatus: process.terminationStatus,
        standardOutputData: outputData,
        standardErrorData: errorData
    )
}

private func rupaExecutableURL() throws -> URL {
    let fileManager = FileManager.default
    var candidates: [URL] = []
    let environment = ProcessInfo.processInfo.environment
    for key in ["BUILT_PRODUCTS_DIR", "TARGET_BUILD_DIR"] {
        guard let buildProductsDirectory = environment[key] else {
            continue
        }
        candidates.append(
            URL(fileURLWithPath: buildProductsDirectory)
                .appendingPathComponent("rupa")
        )
    }
    if let buildProductPaths = environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] {
        for path in buildProductPaths.split(separator: ":") {
            candidates.append(
                URL(fileURLWithPath: String(path))
                    .appendingPathComponent("rupa")
            )
        }
    }
    candidates.append(
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("rupa")
    )
    if let mainExecutableURL = Bundle.main.executableURL {
        let macOSDirectory = mainExecutableURL.deletingLastPathComponent()
        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        let bundleDirectory = contentsDirectory.deletingLastPathComponent()
        candidates.append(
            bundleDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("rupa")
        )
    }
    if let testExecutablePath = CommandLine.arguments.first {
        let testExecutableURL = URL(fileURLWithPath: testExecutablePath)
        let macOSDirectory = testExecutableURL.deletingLastPathComponent()
        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        let testBundleDirectory = contentsDirectory.deletingLastPathComponent()
        let productsDirectory = testBundleDirectory.deletingLastPathComponent()
        candidates.append(productsDirectory.appendingPathComponent("rupa"))
    }

    for candidate in candidates {
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }

    throw EditorError(
        code: .commandFailed,
        message: "Could not locate the rupa executable in test build products. Checked: \(candidates.map(\.path).joined(separator: ", "))"
    )
}
