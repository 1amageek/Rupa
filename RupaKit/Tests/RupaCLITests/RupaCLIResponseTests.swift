import ArgumentParser
import Foundation
import Testing
import RupaAgent
import RupaCore
import SwiftCAD
@testable import RupaCLIKit

@Test(.timeLimit(.minutes(1)))
func cliExecutablePrintsCapabilities() async throws {
    let result = try runRupaCLI(["capabilities"])

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Process Validate"), to: documentURL)

    let result = try runRupaCLI([
        "validate",
        documentURL.path,
        "--json",
    ])
    let response = try JSONDecoder().decode(
        RupaCLIResponse.self,
        from: result.standardOutputData
    )

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Process Parameter"), to: documentURL)

    let result = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)
    let width = try #require(
        loaded.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    let resolved = try loaded.cadDocument.parameters.resolvedValue(for: width.expression)

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Process Formula"), to: documentURL)

    let widthResult = try runRupaCLI([
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
    let heightResult = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: heightResult.standardOutputData
    )
    let listResult = try runRupaCLI([
        "param",
        "list",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let listResponse = try JSONDecoder().decode(
        RupaCLIParameterListResponse.self,
        from: listResult.standardOutputData
    )
    let height = try #require(listResponse.parameters.first { $0.name == "height" })

    #expect(widthResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: widthResult.standardError))
    #expect(heightResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: heightResult.standardError))
    #expect(heightResponse.message == "Parameter height updated.")
    #expect(heightResponse.generation == 1)
    #expect(heightResponse.saved)
    #expect(listResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: listResult.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Process Delete"), to: documentURL)

    let setResult = try runRupaCLI([
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
    let deleteResult = try runRupaCLI([
        "param",
        "delete",
        documentURL.path,
        "width",
        "--mode",
        "file",
        "--json",
    ])
    let deleteResponse = try JSONDecoder().decode(
        RupaCLIResponse.self,
        from: deleteResult.standardOutputData
    )
    let listResult = try runRupaCLI([
        "param",
        "list",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let listResponse = try JSONDecoder().decode(
        RupaCLIParameterListResponse.self,
        from: listResult.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)

    #expect(setResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
    #expect(deleteResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: deleteResult.standardError))
    #expect(deleteResponse.message == "Parameter width deleted.")
    #expect(deleteResponse.generation == 1)
    #expect(deleteResponse.saved)
    #expect(listResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: listResult.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Persisted"), to: documentURL)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open Params"))
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    server.register(session: session, path: documentURL)
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let setResult = try runRupaCLI([
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
        let setResponse = try JSONDecoder().decode(
            RupaCLIResponse.self,
            from: setResult.standardOutputData
        )
        let listResult = try runRupaCLI([
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
            RupaCLIParameterListResponse.self,
            from: listResult.standardOutputData
        )
        let loaded = try RupaDocumentFileService().load(from: documentURL)
        let height = try #require(listResponse.parameters.first { $0.name == "height" })

        #expect(setResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: setResult.standardError))
        #expect(setResponse.message == "Parameter height updated.")
        #expect(setResponse.generation == 2)
        #expect(setResponse.dirty)
        #expect(!setResponse.saved)
        #expect(listResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: listResult.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try runRupaCLI([
        "rename",
        documentURL.path,
        "--name",
        "After",
        "--mode",
        "file",
        "--json",
    ])
    let response = try JSONDecoder().decode(
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)
    let featureID = try #require(loaded.cadDocument.designGraph.order.first)
    let feature = try #require(loaded.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let modelResult = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: modelResult.standardOutputData
    )
    let loadedAfterModel = try RupaDocumentFileService().load(from: documentURL)

    let evalResult = try runRupaCLI([
        "eval",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let evalResponse = try JSONDecoder().decode(
        RupaCLIEvaluationResponse.self,
        from: evalResult.standardOutputData
    )

    let meshResult = try runRupaCLI([
        "mesh",
        documentURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let meshResponse = try JSONDecoder().decode(
        RupaCLIMeshSummaryResponse.self,
        from: meshResult.standardOutputData
    )

    let exportResult = try runRupaCLI([
        "export",
        documentURL.path,
        "--output",
        outputURL.path,
        "--mode",
        "file",
        "--json",
    ])
    let exportResponse = try JSONDecoder().decode(
        RupaCLIExportResponse.self,
        from: exportResult.standardOutputData
    )

    #expect(modelResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(modelResponse.message == "Extruded rectangle Process Box created.")
    #expect(modelResponse.saved)
    #expect(loadedAfterModel.cadDocument.designGraph.order.count == 2)
    #expect(evalResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: evalResult.standardError))
    #expect(evalResponse.status == .valid)
    #expect(evalResponse.bodyCount == 1)
    #expect(meshResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: meshResult.standardError))
    #expect(meshResponse.meshSummary.bodyCount == 1)
    #expect(meshResponse.meshSummary.vertexCount > 0)
    #expect(meshResponse.meshSummary.triangleCount > 0)
    #expect(exportResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: exportResult.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let sketchResult = try runRupaCLI([
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
    let loadedAfterSketch = try RupaDocumentFileService().load(from: documentURL)
    let sketchFeatureID = try #require(loadedAfterSketch.cadDocument.designGraph.order.first)

    let extrudeResult = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: extrudeResult.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)
    let extrudeFeatureID = try #require(loaded.cadDocument.designGraph.order.last)
    let extrudeFeature = try #require(loaded.cadDocument.designGraph.nodes[extrudeFeatureID])
    guard case let .extrude(extrude) = extrudeFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(sketchResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: sketchResult.standardError))
    #expect(extrudeResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: extrudeResult.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let result = try runRupaCLI([
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
        RupaCLIResponse.self,
        from: result.standardOutputData
    )
    let loaded = try RupaDocumentFileService().load(from: documentURL)

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let modelResult = try runRupaCLI([
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
    #expect(modelResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))

    let result = try runRupaCLI([
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
        RupaCLIExportResponse.self,
        from: result.standardOutputData
    )

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    let preset = RupaExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        destinationPolicy: .overwrite
    )
    var metadata = RupaProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = RupaDocument.empty(named: "Process Preset")
    document.productMetadata = metadata
    let documentURL = temporaryDirectory.appendingPathComponent("process-preset.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("preset.stl")
    let versionedURL = temporaryDirectory.appendingPathComponent("preset-1.stl")
    try RupaDocumentFileService().save(document, to: documentURL)
    try Data("existing".utf8).write(to: outputURL)

    let modelResult = try runRupaCLI([
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
    let result = try runRupaCLI([
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
        RupaCLIExportResponse.self,
        from: result.standardOutputData
    )
    let existingOutput = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)

    #expect(modelResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Process Open"), to: documentURL)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Process Open")),
        path: documentURL,
        id: sessionID
    )
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let sessionsResult = try runRupaCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            RupaCLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )
        let attachResult = try runRupaCLI([
            "attach",
            documentURL.path,
            "--socket",
            socketURL.path,
            "--json",
        ])
        let attachResponse = try JSONDecoder().decode(
            RupaCLIAttachResponse.self,
            from: attachResult.standardOutputData
        )

        #expect(sessionsResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
        #expect(sessionsResponse.sessions.count == 1)
        #expect(sessionsResponse.sessions[0].id == sessionID)
        #expect(attachResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: attachResult.standardError))
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
    let server = RupaAgentServer()
    server.register(session: EditorSession(document: .empty(named: "Before Live")), id: sessionID)
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let renameResult = try runRupaCLI([
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
            RupaCLIResponse.self,
            from: renameResult.standardOutputData
        )
        let sessionsResult = try runRupaCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            RupaCLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )

        #expect(renameResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: renameResult.standardError))
        #expect(renameResponse.message == "Document renamed to After Live.")
        #expect(renameResponse.generation == 1)
        #expect(renameResponse.dirty)
        #expect(!renameResponse.saved)
        #expect(sessionsResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
        #expect(sessionsResponse.sessions.first?.displayName == "After Live")
        #expect(sessionsResponse.sessions.first?.generation == DocumentGeneration(1))
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableAutoEvaluateUsesLiveSessionThroughSocketAsJSON() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("process-live-eval.swcad")
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try RupaDocumentFileService().save(.empty(named: "Persisted"), to: documentURL)
    let server = RupaAgentServer()
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
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try runRupaCLI([
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
            RupaCLIEvaluationResponse.self,
            from: result.standardOutputData
        )
        let loaded = try RupaDocumentFileService().load(from: documentURL)

        #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before Save"), to: documentURL)
    let server = RupaAgentServer()
    let session = EditorSession(document: try RupaDocumentFileService().load(from: documentURL))
    _ = try session.execute(
        .renameDocument(name: "Saved From Process"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: documentURL)
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try runRupaCLI([
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
            RupaCLISaveResponse.self,
            from: result.standardOutputData
        )
        let sessionsResult = try runRupaCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            RupaCLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )
        let loaded = try RupaDocumentFileService().load(from: documentURL)

        #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
        #expect(response.path == documentURL.path)
        #expect(response.generation == 1)
        #expect(response.saved)
        #expect(!response.dirty)
        #expect(sessionsResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Persisted"), to: documentURL)
    let server = RupaAgentServer()
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
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try runRupaCLI([
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
            RupaCLIExportResponse.self,
            from: result.standardOutputData
        )
        let loaded = try RupaDocumentFileService().load(from: documentURL)

        #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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
    try RupaDocumentFileService().save(.empty(named: "Before Conflict"), to: documentURL)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open Conflict")),
        path: documentURL
    )
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let rejected = try runRupaCLI([
            "rename",
            documentURL.path,
            "--name",
            "Rejected",
            "--mode",
            "file",
            "--agent-socket",
            socketURL.path,
        ])
        let unchanged = try RupaDocumentFileService().load(from: documentURL)
        let forced = try runRupaCLI([
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
            RupaCLIResponse.self,
            from: forced.standardOutputData
        )
        let sessionsResult = try runRupaCLI([
            "sessions",
            "--socket",
            socketURL.path,
            "--json",
        ])
        let sessionsResponse = try JSONDecoder().decode(
            RupaCLISessionsResponse.self,
            from: sessionsResult.standardOutputData
        )
        let loaded = try RupaDocumentFileService().load(from: documentURL)

        #expect(rejected.terminationStatus == RupaCLIExitCode.data.rawValue)
        #expect(unchanged.cadDocument.metadata.name == "Before Conflict")
        #expect(forced.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: forced.standardError))
        #expect(forcedResponse.message == "Document renamed to Forced.")
        #expect(forcedResponse.saved)
        #expect(sessionsResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: sessionsResult.standardError))
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
    let result = try runRupaCLI([
        "attach",
        "--session",
        "not-a-uuid",
    ])

    #expect(result.terminationStatus == RupaCLIExitCode.usage.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUsageExitForInvalidModelUnit() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("invalid-unit.swcad")
    try RupaDocumentFileService().save(.empty(named: "Invalid Unit"), to: documentURL)

    let result = try runRupaCLI([
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

    #expect(result.terminationStatus == RupaCLIExitCode.usage.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsSoftwareExitForUnsupportedExportFormat() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let documentURL = temporaryDirectory.appendingPathComponent("unsupported-export.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("unsupported.xyz")
    try RupaDocumentFileService().save(.empty(named: "Unsupported Export"), to: documentURL)
    let modelResult = try runRupaCLI([
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

    let result = try runRupaCLI([
        "export",
        documentURL.path,
        "--output",
        outputURL.path,
        "--mode",
        "file",
    ])

    #expect(modelResult.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: modelResult.standardError))
    #expect(result.terminationStatus == RupaCLIExitCode.software.rawValue)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUsageExitForUnknownCommand() async throws {
    let result = try runRupaCLI(["does-not-exist"])

    #expect(result.terminationStatus == RupaCLIExitCode.usage.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutablePrintsHelpSuccessfully() async throws {
    let result = try runRupaCLI(["--help"])

    #expect(result.terminationStatus == RupaCLIExitCode.success.rawValue, Comment(rawValue: result.standardError))
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

    let result = try runRupaCLI([
        "validate",
        documentURL.path,
    ])

    #expect(result.terminationStatus == RupaCLIExitCode.inputOutput.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsUnavailableExitForMissingAgentSocket() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("missing.sock")

    let result = try runRupaCLI([
        "agent",
        "status",
        "--socket",
        socketURL.path,
    ])

    #expect(result.terminationStatus == RupaCLIExitCode.unavailable.rawValue)
}

@Test(.timeLimit(.minutes(1)))
func cliExecutableReturnsDataExitForLiveGenerationMismatch() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, id: sessionID)
    let listener = RupaAgentSocketListener(
        server: server,
        socketPath: RupaAgentSocketPath(socketURL.path)
    )

    try await listener.start()
    do {
        let result = try runRupaCLI([
            "rename-live",
            sessionID.uuidString,
            "--name",
            "Rejected",
            "--expected-generation",
            "9",
            "--socket",
            socketURL.path,
        ])

        #expect(result.terminationStatus == RupaCLIExitCode.data.rawValue)
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test func cliResponseEncodesStableJSONFields() async throws {
    let response = RupaCLIResponse(
        message: "Renamed",
        generation: 1,
        dirty: false,
        diagnostics: [
            RupaDiagnostic(
                severity: .info,
                message: "Document is valid."
            ),
        ]
    )

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(RupaCLIResponse.self, from: data)

    #expect(decoded.message == "Renamed")
    #expect(decoded.generation == 1)
    #expect(!decoded.dirty)
    #expect(!decoded.saved)
    #expect(decoded.diagnostics.first?.severity == .info)
}

@Test func cliServiceReportsAgentStatus() async throws {
    let server = RupaAgentServer(socketPath: "/tmp/rupa.sock")
    _ = server.register(session: EditorSession(document: .empty(named: "Open")))

    let response = try RupaCLIService().agentStatus(client: server)

    #expect(response.running)
    #expect(response.socketPath == "/tmp/rupa.sock")
    #expect(response.sessionCount == 1)
}

@Test func cliExitCodeMapsTypedRupaErrors() async throws {
    #expect(
        RupaCLIExitCode.value(
            for: RupaError(code: .commandInvalid, message: "Invalid")
        ) == .usage
    )
    #expect(
        RupaCLIExitCode.value(
            for: RupaError(code: .documentOpenInApp, message: "Open")
        ) == .data
    )
    #expect(
        RupaCLIExitCode.value(
            for: RupaError(code: .sessionNotFound, message: "Missing")
        ) == .data
    )
    #expect(
        RupaCLIExitCode.value(
            for: RupaError(code: .documentLoadFailed, message: "Load")
        ) == .inputOutput
    )
    #expect(
        RupaCLIExitCode.value(
            for: RupaError(code: .agentConnectionFailed, message: "Agent")
        ) == .unavailable
    )
    #expect(
        RupaCLIExitCode.value(
            for: RupaError(code: .evaluationFailed, message: "Evaluation")
        ) == .software
    )
    #expect(
        RupaCLIExitCode.value(
            for: ValidationError("Invalid argument")
        ) == .usage
    )
}

@Test func cliServiceListsAgentSessions() async throws {
    let server = RupaAgentServer()
    let id = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: id
    )

    let response = try RupaCLIService().sessions(client: server)

    #expect(response.sessions.count == 1)
    #expect(response.sessions[0].id == id)
    #expect(response.sessions[0].displayName == "Open")
}

@Test func cliServiceAttachResolvesFileBackedSession() async throws {
    let server = RupaAgentServer()
    let id = UUID()
    let url = URL(fileURLWithPath: "/tmp/open-attach.swcad")
    let session = EditorSession(document: .empty(named: "Attach File"))
    server.register(
        session: session,
        path: url,
        id: id
    )

    let response = try RupaCLIService().attach(
        target: RupaCLIDocumentTarget(fileURL: url),
        client: server
    )

    #expect(response.sessionID == id)
    #expect(response.path == url.path)
    #expect(response.displayName == "Attach File")
    #expect(response.generation == 0)
}

@Test func cliServiceAttachResolvesExplicitSessionID() async throws {
    let server = RupaAgentServer()
    let id = UUID()
    let session = EditorSession(document: .empty(named: "Attach Session"))
    server.register(session: session, id: id)

    let response = try RupaCLIService().attach(
        target: RupaCLIDocumentTarget(sessionID: id),
        client: server
    )

    #expect(response.sessionID == id)
    #expect(response.path == nil)
    #expect(response.displayName == "Attach Session")
}

@Test func cliServiceAttachRejectsMissingOpenSession() async throws {
    let server = RupaAgentServer()
    let url = URL(fileURLWithPath: "/tmp/missing-attach.swcad")

    var caught: RupaError?
    do {
        _ = try RupaCLIService().attach(
            target: RupaCLIDocumentTarget(fileURL: url),
            client: server
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .sessionNotFound)
}

@Test func cliServiceAttachRejectsAmbiguousTarget() async throws {
    let server = RupaAgentServer()
    let id = UUID()
    let url = URL(fileURLWithPath: "/tmp/ambiguous-attach.swcad")
    server.register(
        session: EditorSession(document: .empty(named: "Attach")),
        path: url,
        id: id
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().attach(
            target: RupaCLIDocumentTarget(
                fileURL: url,
                sessionID: id
            ),
            client: server
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func cliServiceRenamesLiveSessionThroughAgent() async throws {
    let server = RupaAgentServer()
    let id = UUID()
    let session = EditorSession()
    server.register(session: session, id: id)

    let response = try RupaCLIService().renameLiveSession(
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

@Test func cliServiceAutoRenameUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("open-auto.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().renameDocument(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "Auto Live",
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().renameDocument(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "Auto File",
        mode: .auto,
        client: RupaAgentServer()
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().renameDocument(
            target: RupaCLIDocumentTarget(fileURL: url),
            name: "Rejected",
            mode: .file,
            client: server
        )
    } catch let error as RupaError {
        caught = error
    }

    let loaded = try RupaDocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceLiveModeResolvesFilePathToOpenSession() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("live-path.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().renameDocument(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "Live Path",
        mode: .live,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    var caught: RupaError?
    do {
        _ = try RupaCLIService().renameDocument(
            target: RupaCLIDocumentTarget(fileURL: url),
            name: "No Client",
            mode: .live
        )
    } catch let error as RupaError {
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().renameFile(
            at: url,
            name: "Rejected",
            conflictClient: server
        )
    } catch let error as RupaError {
        caught = error
    }

    let loaded = try RupaDocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.metadata.name == "Before")
}

@Test func cliServiceDryRunDoesNotPersistFileRename() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("dry-run.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().renameFile(
        at: url,
        name: "Dry Run",
        dryRun: true
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().renameFile(
        at: url,
        name: "After"
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().setParameter(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "width",
        expression: .constant(.length(25.0, unit: .millimeter)),
        kind: .length,
        mode: .file
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().setParameter(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "liveWidth",
        expression: .constant(.length(12.0, unit: .millimeter)),
        kind: .length,
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    var document = RupaDocument.empty(named: "Before")
    document.upsertParameter(
        name: "width",
        expression: .constant(.length(25.0, unit: .millimeter)),
        kind: .length
    )
    try RupaDocumentFileService().save(document, to: url)

    let response = try RupaCLIService().deleteParameter(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "width",
        mode: .file
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().deleteParameter(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "liveWidth",
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().setParameter(
            target: RupaCLIDocumentTarget(fileURL: url),
            name: "rejected",
            expression: .constant(.length(1.0, unit: .meter)),
            kind: .length,
            mode: .file,
            client: server
        )
    } catch let error as RupaError {
        caught = error
    }

    let loaded = try RupaDocumentFileService().load(from: url)
    #expect(caught?.code == .documentOpenInApp)
    #expect(loaded.cadDocument.parameters.parameters.isEmpty)
}

@Test func cliServiceFileParameterExpressionPersistsClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let url = temporaryDirectory.appendingPathComponent("parameter-expression.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    _ = try RupaCLIService().setParameter(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length,
        mode: .file
    )

    let response = try RupaCLIService().setParameterExpression(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "height",
        expression: "width * 2 + 5mm",
        kind: .length,
        mode: .file
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    server.register(session: session, path: url)

    let response = try RupaCLIService().setParameterExpression(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "height",
        expression: "width * 2",
        kind: .length,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    _ = try RupaCLIService().setParameter(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length,
        mode: .file
    )
    _ = try RupaCLIService().setParameterExpression(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "height",
        expression: "width * 2",
        kind: .length,
        mode: .file
    )

    let response = try RupaCLIService().listParameters(
        target: RupaCLIDocumentTarget(fileURL: url),
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    _ = try session.execute(
        .upsertParameter(
            name: "liveWidth",
            expression: .constant(.length(5.0, unit: .millimeter)),
            kind: .length
        )
    )
    server.register(session: session, path: url)

    let response = try RupaCLIService().listParameters(
        target: RupaCLIDocumentTarget(fileURL: url),
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "CLI Box",
        plane: .xy,
        width: .length(40.0, .millimeter),
        height: .length(20.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().createExtrudedRectangleFromCorners(
        target: RupaCLIDocumentTarget(fileURL: url),
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

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().createExtrudedCircle(
        target: RupaCLIDocumentTarget(fileURL: url),
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

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    _ = try RupaCLIService().createRectangleSketch(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "CLI Profile",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        mode: .file
    )
    let loadedAfterSketch = try RupaDocumentFileService().load(from: url)
    let sketchFeatureID = try #require(loadedAfterSketch.cadDocument.designGraph.order.first)

    let response = try RupaCLIService().extrudeProfile(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "CLI Extrude",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: url),
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

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().createExtrudedRectangleFromCorners(
        target: RupaCLIDocumentTarget(fileURL: url),
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

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().extrudeProfile(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "Live Extrude",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(5.0, .millimeter),
        direction: .normal,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().createLineSketch(
        target: RupaCLIDocumentTarget(fileURL: url),
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

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)

    let response = try RupaCLIService().createRectangleSketch(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "CLI Rectangle",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        mode: .file
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().createCircleSketch(
        target: RupaCLIDocumentTarget(fileURL: url),
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

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    let session = EditorSession(document: .empty(named: "Open"))
    server.register(session: session, path: url)

    let response = try RupaCLIService().createRectangleSketch(
        target: RupaCLIDocumentTarget(fileURL: url),
        name: "Live Rectangle",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        mode: .auto,
        expectedGeneration: DocumentGeneration(0),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: url)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: url
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().createExtrudedRectangle(
            target: RupaCLIDocumentTarget(fileURL: url),
            name: "Rejected Box",
            plane: .xy,
            width: .length(1.0, .millimeter),
            height: .length(1.0, .millimeter),
            depth: .length(1.0, .millimeter),
            direction: .normal,
            mode: .file,
            client: server
        )
    } catch let error as RupaError {
        caught = error
    }

    let loaded = try RupaDocumentFileService().load(from: url)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        name: "Export Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try RupaCLIService().exportDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
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

    let preset = RupaExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        destinationPolicy: .overwrite
    )
    var metadata = RupaProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = RupaDocument.empty(named: "Preset Source")
    document.productMetadata = metadata

    let documentURL = temporaryDirectory.appendingPathComponent("preset-source.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("preset-export.stl")
    let versionedURL = temporaryDirectory.appendingPathComponent("preset-export-1.stl")
    try RupaDocumentFileService().save(document, to: documentURL)
    try Data("existing".utf8).write(to: outputURL)
    _ = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        name: "Preset Export Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try RupaCLIService().exportDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .file,
        options: RupaExportOptions(
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        name: "Dry Export Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try RupaCLIService().exportDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().exportDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
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

    let preset = RupaExportPreset(
        name: "Micro STL",
        format: .stl,
        outputUnit: .micrometer,
        destinationPolicy: .overwrite
    )
    var metadata = RupaProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = RupaDocument.empty(named: "Open Preset Source")
    document.productMetadata = metadata

    let documentURL = temporaryDirectory.appendingPathComponent("open-preset-export.swcad")
    let outputURL = temporaryDirectory.appendingPathComponent("open-preset-export.stl")
    try RupaDocumentFileService().save(document, to: documentURL)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().exportDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        outputURL: outputURL,
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        options: RupaExportOptions(presetName: "Micro STL"),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: documentURL
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().exportDocument(
            target: RupaCLIDocumentTarget(fileURL: documentURL),
            outputURL: outputURL,
            mode: .file,
            client: server
        )
    } catch let error as RupaError {
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        name: "Eval Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try RupaCLIService().evaluateDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().evaluateDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
    #expect(response.status == .valid)
    #expect(response.evaluatedGeneration == 1)
    #expect(response.bodyCount == 1)
    #expect(response.dirty)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceFileMeasureReturnsStructuredResultForClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("measure-source.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        name: "Measure Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try RupaCLIService().measureDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        mode: .file
    )

    #expect(response.generation == 0)
    #expect(!response.dirty)
    #expect(response.measurement.counts.sourceFeatures == 2)
    #expect(response.measurement.counts.solids == 1)
    #expect(abs(response.measurement.totals.profileAreaSquareMeters - 0.0002) < 0.000_000_000_001)
    #expect(abs(response.measurement.totals.solidVolumeCubicMeters - 0.000001) < 0.000_000_000_001)
    #expect(response.message.contains("Measurement summary"))
}

@MainActor
@Test func cliServiceAutoMeasureUsesLiveSessionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-measure.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().measureDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(response.measurement.counts.sourceFeatures == 2)
    #expect(response.measurement.counts.solids == 1)
    #expect(abs(response.measurement.totals.solidVolumeCubicMeters - 0.000000216) < 0.000_000_000_001)
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func cliServiceAutoMeasureUsesLiveSelectionForOpenFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("open-selected-measure.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().measureDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
    #expect(response.generation == 1)
    #expect(response.dirty)
    #expect(response.measurement.scope == .selection)
    #expect(response.measurement.counts.sourceFeatures == 2)
    #expect(response.measurement.counts.solids == 1)
    #expect(abs(response.measurement.totals.solidVolumeCubicMeters - 0.000000216) < 0.000_000_000_001)
    #expect(response.message.contains("Selection measurement"))
    #expect(loaded.cadDocument.designGraph.order.isEmpty)
}

@Test func cliServiceFileMeshSummaryReturnsStructuredResultForClosedDocument() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let documentURL = temporaryDirectory.appendingPathComponent("mesh-source.swcad")
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    _ = try RupaCLIService().createExtrudedRectangle(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        name: "Mesh Source",
        plane: .xy,
        width: .length(20.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(5.0, .millimeter),
        direction: .normal,
        mode: .file
    )

    let response = try RupaCLIService().meshSummary(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
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

    let response = try RupaCLIService().meshSummary(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)

    let response = try RupaCLIService().saveDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
    let session = EditorSession(document: try RupaDocumentFileService().load(from: documentURL))
    _ = try session.execute(
        .renameDocument(name: "Saved By Auto"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: documentURL)

    let response = try RupaCLIService().saveDocument(
        target: RupaCLIDocumentTarget(fileURL: documentURL),
        mode: .auto,
        expectedGeneration: DocumentGeneration(1),
        client: server
    )

    let loaded = try RupaDocumentFileService().load(from: documentURL)
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
    try RupaDocumentFileService().save(.empty(named: "Before"), to: documentURL)
    let server = RupaAgentServer()
    server.register(
        session: EditorSession(document: .empty(named: "Open")),
        path: documentURL
    )

    var caught: RupaError?
    do {
        _ = try RupaCLIService().saveDocument(
            target: RupaCLIDocumentTarget(fileURL: documentURL),
            mode: .file,
            client: server
        )
    } catch let error as RupaError {
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

private struct RupaCLIProcessResult {
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

private func runRupaCLI(_ arguments: [String]) throws -> RupaCLIProcessResult {
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

    return RupaCLIProcessResult(
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

    throw RupaError(
        code: .commandFailed,
        message: "Could not locate the rupa executable in test build products. Checked: \(candidates.map(\.path).joined(separator: ", "))"
    )
}
