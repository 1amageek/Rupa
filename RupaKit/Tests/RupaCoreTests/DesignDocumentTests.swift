import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func defaultDocumentUsesMetersInternally() async throws {
    let document = DesignDocument.empty()
    #expect(document.cadDocument.units.length.rawValue == "meter")
    #expect(document.cadDocument.units.angle.rawValue == "radian")
}

@Test func lengthDisplayUnitsCoverMicrometerThroughMeter() async throws {
    #expect(LengthDisplayUnit.micrometer.metersPerUnit == 0.000_001)
    #expect(LengthDisplayUnit.meter.metersPerUnit == 1.0)
}

@Test func rulerTracksSelectedDisplayUnit() async throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.micrometer)

    #expect(document.displayUnit == .micrometer)
    #expect(abs(document.ruler.minorTickMeters - 0.000_001) < 0.000_000_000_001)
    #expect(abs(document.ruler.majorTickMeters - 0.000_01) < 0.000_000_000_001)
}

@Test func rectangleGeneratedRepresentationFollowsExtrusionProperty() async throws {
    let definition = try #require(ObjectTypeCatalog.definition(for: .rectangle))
    #expect(definition.sourceRepresentation == .twoDimensional)
    #expect(definition.generatedRepresentation(for: definition.defaultProperties) == .twoDimensional)

    var properties = definition.defaultProperties
    properties["extrusion"] = .length(0.25)

    #expect(definition.generatedRepresentation(for: properties) == .threeDimensional)
}

@Test func builtInObjectCatalogContainsOnlyImplementedSourceTypes() async throws {
    #expect(ObjectTypeCatalog.definition(for: .line) != nil)
    #expect(ObjectTypeCatalog.definition(for: .rectangle) != nil)
    #expect(ObjectTypeCatalog.definition(for: .circle) != nil)
    #expect(ObjectTypeCatalog.definition(for: .cube) != nil)
    #expect(ObjectTypeCatalog.definition(for: .cylinder) != nil)
    #expect(ObjectTypeCatalog.definition(for: .path) == nil)
    #expect(ObjectTypeCatalog.definition(for: .sphere) == nil)
    #expect(ObjectTypeCatalog.definition(for: .torus) == nil)
}

@Test func sketchObjectsReceiveTypedProperties() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createRectangleSketch(
        name: "Profile",
        plane: .xy,
        width: .length(2.0, .meter),
        height: .length(3.0, .meter)
    )

    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(node.object?.typeID == .rectangle)
    #expect(node.object?.properties["size.x"] == .length(2.0))
    #expect(node.object?.properties["size.y"] == .length(3.0))
}

@Test func objectPropertyMutationUsesObjectTypeSchema() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createRectangleSketch(
        name: "Editable Profile",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter)
    )

    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    try document.setSceneNodeObjectProperty(
        id: node.id,
        propertyID: "extrusion",
        value: .length(0.5)
    )
    let editedNode = try #require(document.productMetadata.sceneNodes[node.id])
    #expect(editedNode.object?.properties["extrusion"] == .length(0.5))

    do {
        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: "unknown",
            value: .length(1.0)
        )
        Issue.record("Undefined object properties must be rejected.")
    } catch {
        #expect(error is DocumentValidationError)
    }
}

@Test func customObjectRegistrySurvivesNonPropertyMutations() async throws {
    let customTypeID: ObjectTypeID = "custom.panel"
    let registry = try ObjectTypeRegistry(
        definitions: ObjectTypeCatalog.builtInDefinitions + [
            ObjectTypeDefinition(
                id: customTypeID,
                title: "Panel",
                systemImage: "rectangle",
                representation: .twoDimensional,
                category: .sketch,
                geometryRole: .sketchProfile,
                properties: [
                    ObjectPropertyDefinition(
                        id: "panel.thickness",
                        title: "Thickness",
                        group: "Shape",
                        valueKind: .length,
                        defaultValue: .length(0.02),
                        inspectorControl: .textFieldAndSlider,
                        renderBinding: "panel.thickness",
                        numericRange: ObjectPropertyDefinition.NumericRange(
                            lowerBound: 0.0,
                            upperBound: 1.0
                        )
                    ),
                ]
            ),
        ]
    )
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Custom Panel Source",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        objectRegistry: registry
    )
    var node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    node.object = .sketch(
        featureID: featureID,
        typeID: customTypeID,
        properties: ObjectPropertySet(values: ["panel.thickness": .length(0.04)]),
        objectRegistry: registry
    )
    document.productMetadata.sceneNodes[node.id] = node

    try document.validate(objectRegistry: registry)
    try document.setSceneNodeVisibility(
        id: node.id,
        isVisible: false,
        objectRegistry: registry
    )

    #expect(document.productMetadata.sceneNodes[node.id]?.isVisible == false)
    #expect(document.productMetadata.sceneNodes[node.id]?.object?.typeID == customTypeID)
}

@Test func customObjectRegistryParticipatesInEvaluationValidation() async throws {
    let customTypeID: ObjectTypeID = "custom.panel"
    let registry = try ObjectTypeRegistry(
        definitions: ObjectTypeCatalog.builtInDefinitions + [
            ObjectTypeDefinition(
                id: customTypeID,
                title: "Panel",
                systemImage: "rectangle",
                representation: .twoDimensional,
                category: .sketch,
                geometryRole: .sketchProfile,
                properties: [
                    ObjectPropertyDefinition(
                        id: "panel.thickness",
                        title: "Thickness",
                        group: "Shape",
                        valueKind: .length,
                        defaultValue: .length(0.02),
                        inspectorControl: .textFieldAndSlider,
                        renderBinding: "panel.thickness"
                    ),
                ]
            ),
        ]
    )
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Custom Panel Source",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        objectRegistry: registry
    )
    var node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    node.object = .sketch(
        featureID: featureID,
        typeID: customTypeID,
        properties: ObjectPropertySet(values: ["panel.thickness": .length(0.04)]),
        objectRegistry: registry
    )
    document.productMetadata.sceneNodes[node.id] = node
    let store = CADDocumentStore(document: document, objectRegistry: registry)

    store.evaluateCurrentDocument()

    #expect(store.evaluationStatus == .valid)
}

@Test func objectTypeValidationRejectsMismatchedCategory() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Profile",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter)
    )
    var node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    node.object = ObjectDescriptor(
        category: .sketch,
        geometryRole: .solid,
        typeID: .cube,
        sourceFeatureID: featureID
    )
    document.productMetadata.sceneNodes[node.id] = node

    do {
        try document.validate(objectRegistry: .builtIn)
        Issue.record("Validation should reject object type category mismatch.")
    } catch {
        #expect(error is DocumentValidationError)
    }
}

@Test func objectSizePropertyMutationUpdatesCubeSourceGeometry() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Block",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    try document.setSceneNodeObjectProperty(
        id: bodyNode.id,
        propertyID: "size.x",
        value: .length(2.0)
    )

    let editedBodyNode = try #require(document.productMetadata.sceneNodes[bodyNode.id])
    #expect(editedBodyNode.object?.properties["size.x"] == .length(2.0))
    let bodyFeatureID = try #require(editedBodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected an extrude feature.")
        return
    }
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case let .sketch(sketch) = profileFeature.operation else {
        Issue.record("Expected a sketch profile.")
        return
    }
    let bounds = try sketchBounds(sketch, parameters: document.cadDocument.parameters)

    #expect(abs(bounds.width - 2.0) < 0.000_000_000_001)
    #expect(abs(bounds.height - 1.0) < 0.000_000_000_001)
}

@Test func sketchExtrusionPropertyCreatesAndRemovesGeneratedBody() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Panel",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(2.0, .meter)
    )
    let sketchNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })

    try document.setSceneNodeObjectProperty(
        id: sketchNode.id,
        propertyID: "extrusion",
        value: .length(0.25)
    )

    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.sourceProfileFeatureID == featureID
    })
    #expect(document.cadDocument.designGraph.order.count == 2)
    #expect(bodyNode.name == "Panel Extrusion")
    #expect(bodyNode.object?.typeID == .cube)
    let bodyFeatureID = try #require(bodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected generated extrusion body.")
        return
    }
    let distance = try resolvedLength(extrude.distance, parameters: document.cadDocument.parameters)
    #expect(abs(distance - 0.25) < 0.000_000_000_001)

    try document.setSceneNodeObjectProperty(
        id: sketchNode.id,
        propertyID: "extrusion",
        value: .length(0.0)
    )

    #expect(document.cadDocument.designGraph.order == [featureID])
    #expect(!document.productMetadata.sceneNodes.values.contains {
        $0.reference?.kind == .body && $0.object?.sourceProfileFeatureID == featureID
    })
}

@Test func circleProfileExtractorUsesFeatureSpecificSegmentCount() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: "Segmented Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(1.0, .meter)
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Expected a sketch feature.")
        return
    }

    let parameters = try ParameterResolver().resolve(document.cadDocument.parameters)
    let profiles = try CircleAwareSketchProfileExtractor(
        circleSegmentCountsByFeatureID: [featureID: 12]
    ).extractProfiles(
        from: sketch,
        sourceFeatureID: featureID,
        parameters: parameters
    )

    #expect(profiles.first?.vertices.count == 12)
}

@Test func cylinderSideSegmentsParticipateInEvaluationProfileExtraction() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedCircle(
        name: "Segmented Cylinder",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(0.5, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.typeID == .cylinder
    })
    let sourceProfileFeatureID = try #require(bodyNode.object?.sourceProfileFeatureID)

    try document.setSceneNodeObjectProperty(
        id: bodyNode.id,
        propertyID: "sides.x",
        value: .integer(12)
    )

    #expect(document.circleProfileSegmentCounts()[sourceProfileFeatureID] == 12)
}

@Test func productMetadataRoundTripsThroughProductPackage() async throws {
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
    let validationRule = ValidationRule(
        name: "Generic geometry readiness",
        category: .geometry,
        severity: .warning
    )
    let exportPreset = ExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        validationRuleIDs: [validationRule.id]
    )
    var metadata = ProductMetadata.empty()
    metadata.materialLibrary = MaterialLibrary(
        materials: [material.id: material],
        defaultMaterialID: material.id
    )
    metadata.validationRules = [validationRule.id: validationRule]
    metadata.exportPresets = [exportPreset.id: exportPreset]
    metadata.templateDefaults = TemplateDefaults(
        displayUnit: .centimeter,
        ruler: .standard(for: .centimeter),
        validationRuleIDs: [validationRule.id],
        exportPresetIDs: [exportPreset.id],
        defaultMaterialID: material.id
    )

    var document = DesignDocument.empty(named: "Product Metadata")
    document.setDisplayUnit(.centimeter)
    document.productMetadata = metadata

    let url = temporaryDirectory.appendingPathComponent("product-metadata.swcad")
    let service = DocumentFileService()
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
    let sourceDocument = DesignDocument.empty(named: "Legacy")
    try CADPipeline().save(sourceDocument.cadDocument, to: url)

    let loaded = try DocumentFileService().load(from: url)

    #expect(loaded.cadDocument.metadata.name == "Legacy")
    #expect(loaded.displayUnit == .millimeter)
    #expect(loaded.ruler == .standard(for: .millimeter))
    #expect(!loaded.productMetadata.rootSceneNodeIDs.isEmpty)
}

@Test func productMetadataRejectsInvalidSceneReference() async throws {
    var document = DesignDocument.empty()
    var metadata = ProductMetadata.empty()
    let rootID = try #require(metadata.rootSceneNodeIDs.first)
    metadata.sceneNodes[rootID]?.reference = .feature(FeatureID())
    document.productMetadata = metadata

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
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
    let result = try DocumentExportService().export(
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

    let preset = ExportPreset(
        name: "Micro STL",
        format: .stl,
        outputUnit: .micrometer,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Preset Export")
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
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: ExportOptions(presetName: "Micro STL")
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
    var caught: EditorError?
    do {
        _ = try DocumentExportService().export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: ExportOptions(destinationPolicy: .prompt)
        )
    } catch let error as EditorError {
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
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: ExportOptions(destinationPolicy: .versioned)
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

    let preset = ExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Mismatched Export")
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
    var caught: EditorError?
    do {
        _ = try DocumentExportService().export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: ExportOptions(presetName: "Print STL")
        )
    } catch let error as EditorError {
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
    var caught: EditorError?
    do {
        _ = try DocumentExportService().export(
            document: .empty(named: "Empty"),
            generation: DocumentGeneration(0),
            to: outputURL
        )
    } catch let error as EditorError {
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
    let result = try DocumentExportService().export(
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

private func sketchBounds(
    _ sketch: Sketch,
    parameters: ParameterTable
) throws -> (width: Double, height: Double) {
    var points: [(x: Double, y: Double)] = []
    for entity in sketch.entities.values {
        switch entity {
        case .point(let point):
            points.append(try resolvedPoint(point, parameters: parameters))
        case .line(let line):
            points.append(try resolvedPoint(line.start, parameters: parameters))
            points.append(try resolvedPoint(line.end, parameters: parameters))
        case .circle(let circle):
            let center = try resolvedPoint(circle.center, parameters: parameters)
            let radius = try resolvedLength(circle.radius, parameters: parameters)
            points.append((x: center.x - radius, y: center.y - radius))
            points.append((x: center.x + radius, y: center.y + radius))
        }
    }
    let first = try #require(points.first)
    let minX = points.dropFirst().reduce(first.x) { min($0, $1.x) }
    let maxX = points.dropFirst().reduce(first.x) { max($0, $1.x) }
    let minY = points.dropFirst().reduce(first.y) { min($0, $1.y) }
    let maxY = points.dropFirst().reduce(first.y) { max($0, $1.y) }
    return (width: maxX - minX, height: maxY - minY)
}

private func resolvedPoint(
    _ point: SketchPoint,
    parameters: ParameterTable
) throws -> (x: Double, y: Double) {
    (
        x: try resolvedLength(point.x, parameters: parameters),
        y: try resolvedLength(point.y, parameters: parameters)
    )
}

private func resolvedLength(
    _ expression: CADExpression,
    parameters: ParameterTable
) throws -> Double {
    let quantity = try parameters.resolvedValue(for: expression)
    return quantity.value
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
