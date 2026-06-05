import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func defaultDocumentUsesMetersInternally() async throws {
    let document = RupaDocument.empty()
    #expect(document.cadDocument.units.length.rawValue == "meter")
    #expect(document.cadDocument.units.angle.rawValue == "radian")
}

@Test func lengthDisplayUnitsCoverMicrometerThroughMeter() async throws {
    #expect(LengthDisplayUnit.micrometer.metersPerUnit == 0.000_001)
    #expect(LengthDisplayUnit.meter.metersPerUnit == 1.0)
}

@Test func rulerTracksSelectedDisplayUnit() async throws {
    var document = RupaDocument.empty()
    document.setDisplayUnit(.micrometer)

    #expect(document.displayUnit == .micrometer)
    #expect(abs(document.ruler.minorTickMeters - 0.000_001) < 0.000_000_000_001)
    #expect(abs(document.ruler.majorTickMeters - 0.000_01) < 0.000_000_000_001)
}

@Test func productMetadataRoundTripsThroughRupaPackage() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }

    let material = Material(
        name: "Default",
        baseColor: ColorRGBA(r: 0.2, g: 0.4, b: 0.8, a: 1.0),
        metallic: 0.0,
        roughness: 0.45,
        opacity: 1.0
    )
    let validationRule = RupaValidationRule(
        name: "Generic geometry readiness",
        category: .geometry,
        severity: .warning
    )
    let exportPreset = RupaExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        validationRuleIDs: [validationRule.id]
    )
    var metadata = RupaProductMetadata.empty()
    metadata.materialLibrary = RupaMaterialLibrary(
        materials: [material.id: material],
        defaultMaterialID: material.id
    )
    metadata.validationRules = [validationRule.id: validationRule]
    metadata.exportPresets = [exportPreset.id: exportPreset]
    metadata.templateDefaults = RupaTemplateDefaults(
        displayUnit: .centimeter,
        ruler: .standard(for: .centimeter),
        validationRuleIDs: [validationRule.id],
        exportPresetIDs: [exportPreset.id],
        defaultMaterialID: material.id
    )

    var document = RupaDocument.empty(named: "Product Metadata")
    document.setDisplayUnit(.centimeter)
    document.productMetadata = metadata

    let url = temporaryDirectory.appendingPathComponent("product-metadata.swcad")
    let service = RupaDocumentFileService()
    try service.save(document, to: url)
    let loaded = try service.load(from: url)

    #expect(loaded.displayUnit == .centimeter)
    #expect(loaded.ruler == .standard(for: .centimeter))
    #expect(loaded.productMetadata == metadata)
}

@Test func legacySwiftCADPackageLoadsWithDefaultProductMetadata() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }

    let url = temporaryDirectory.appendingPathComponent("legacy.swcad")
    let sourceDocument = RupaDocument.empty(named: "Legacy")
    try CADPipeline().save(sourceDocument.cadDocument, to: url)

    let loaded = try RupaDocumentFileService().load(from: url)

    #expect(loaded.cadDocument.metadata.name == "Legacy")
    #expect(loaded.displayUnit == .millimeter)
    #expect(loaded.ruler == .standard(for: .millimeter))
    #expect(!loaded.productMetadata.rootSceneNodeIDs.isEmpty)
}

@Test func productMetadataRejectsInvalidSceneReference() async throws {
    var document = RupaDocument.empty()
    var metadata = RupaProductMetadata.empty()
    let rootID = try #require(metadata.rootSceneNodeIDs.first)
    metadata.sceneNodes[rootID]?.reference = .feature(FeatureID())
    document.productMetadata = metadata

    var caught: RupaDocumentValidationError?
    do {
        try document.validate()
    } catch let error as RupaDocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("existing CAD feature"))
}

@MainActor
@Test func documentExportServiceWritesEvaluatedModelArtifact() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Export Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("box.stl")
    let result = try RupaDocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL
    )

    #expect(result.format == .stl)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.outputPath == outputURL.path)
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@MainActor
@Test func documentExportServiceUsesPresetUnitAndReportsPolicy() async throws {
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
    var document = RupaDocument.empty(named: "Preset Export")
    document.productMetadata = metadata
    let session = EditorSession(document: document)
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Micro Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("micro-box.stl")
    let result = try RupaDocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: RupaExportOptions(presetName: "Micro STL")
    )

    let header = String(decoding: try Data(contentsOf: outputURL).prefix(80), as: UTF8.self)
    #expect(result.presetName == "Micro STL")
    #expect(result.outputUnit == .micrometer)
    #expect(result.destinationPolicy == .overwrite)
    #expect(header.contains("unit=micrometer"))
}

@MainActor
@Test func documentExportServicePromptPolicyRejectsExistingOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Prompt Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("prompt-box.stl")
    try Data("existing".utf8).write(to: outputURL)
    var caught: RupaError?
    do {
        _ = try RupaDocumentExportService().export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: RupaExportOptions(destinationPolicy: .prompt)
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .exportFailed)
    #expect(String(decoding: try Data(contentsOf: outputURL), as: UTF8.self) == "existing")
}

@MainActor
@Test func documentExportServiceVersionedPolicyWritesNextAvailableOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Versioned Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("versioned-box.stl")
    let versionedURL = temporaryDirectory.appendingPathComponent("versioned-box-1.stl")
    try Data("existing".utf8).write(to: outputURL)
    let result = try RupaDocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: RupaExportOptions(destinationPolicy: .versioned)
    )

    #expect(result.outputPath == versionedURL.path)
    #expect(result.destinationPolicy == .versioned)
    #expect(String(decoding: try Data(contentsOf: outputURL), as: UTF8.self) == "existing")
    #expect(FileManager.default.fileExists(atPath: versionedURL.path))
}

@MainActor
@Test func documentExportServiceRejectsPresetFormatMismatch() async throws {
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
    var document = RupaDocument.empty(named: "Mismatched Export")
    document.productMetadata = metadata
    let session = EditorSession(document: document)
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Mismatch Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("mismatch.obj")
    var caught: RupaError?
    do {
        _ = try RupaDocumentExportService().export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: RupaExportOptions(presetName: "Print STL")
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func documentExportServiceRejectsNonEvaluatingDocumentWithoutCreatingOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let outputURL = temporaryDirectory.appendingPathComponent("empty.stl")
    var caught: RupaError?
    do {
        _ = try RupaDocumentExportService().export(
            document: .empty(named: "Empty"),
            generation: DocumentGeneration(0),
            to: outputURL
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@MainActor
@Test func documentExportServiceDryRunEvaluatesWithoutWritingOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Dry Export Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("dry-box.stl")
    let result = try RupaDocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        dryRun: true
    )

    #expect(result.dryRun)
    #expect(result.byteCount == 0)
    #expect(result.format == .stl)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
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
