import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func anAppearanceEditOnANodeHoldingNoMaterialCreatesAndAssignsOne() throws {
    var document = try appearanceFixtureDocument(bodyCount: 1)
    let nodeID = try #require(appearanceBodySceneNodeIDs(in: document).first)
    #expect(document.productMetadata.sceneNodes[nodeID]?.materialID == nil)
    #expect(document.productMetadata.materialLibrary.materials.isEmpty)

    let materialID = try document.setSceneNodeAppearance(
        id: nodeID,
        edit: .baseColor(ColorRGBA(r: 0.2, g: 0.4, b: 0.6, a: 1.0))
    )

    #expect(document.productMetadata.sceneNodes[nodeID]?.materialID == materialID)
    let material = try #require(document.productMetadata.materialLibrary.materials[materialID])
    #expect(material.baseColor == ColorRGBA(r: 0.2, g: 0.4, b: 0.6, a: 1.0))
    // A material created for a node does not become the document default.
    #expect(document.productMetadata.materialLibrary.defaultMaterialID == nil)
}

@Test(.timeLimit(.minutes(1)))
func aCreatedMaterialKeepsTheNeutralValuesTheEditDoesNotName() throws {
    var document = try appearanceFixtureDocument(bodyCount: 1)
    let nodeID = try #require(appearanceBodySceneNodeIDs(in: document).first)

    let materialID = try document.setSceneNodeAppearance(id: nodeID, edit: .metallic(0.9))

    let material = try #require(document.productMetadata.materialLibrary.materials[materialID])
    #expect(material.metallic == 0.9)
    #expect(material.baseColor == Material.neutralBaseColor)
    #expect(material.roughness == Material.neutral(named: "probe").roughness)
    #expect(material.opacity == Material.neutral(named: "probe").opacity)
}

@Test(.timeLimit(.minutes(1)))
func aSecondNodeSharingANameDoesNotReuseTheFirstMaterialName() throws {
    var document = try appearanceFixtureDocument(bodyCount: 2)
    let nodeIDs = appearanceBodySceneNodeIDs(in: document)
    #expect(nodeIDs.count == 2)
    for nodeID in nodeIDs {
        document.productMetadata.sceneNodes[nodeID]?.name = "Shell"
    }

    let first = try document.setSceneNodeAppearance(id: nodeIDs[0], edit: .roughness(0.2))
    let second = try document.setSceneNodeAppearance(id: nodeIDs[1], edit: .roughness(0.3))

    #expect(first != second)
    #expect(document.productMetadata.materialLibrary.materials[first]?.name == "Shell")
    #expect(document.productMetadata.materialLibrary.materials[second]?.name == "Shell 2")
}

@Test(.timeLimit(.minutes(1)))
func aValueOutsideTheUnitIntervalIsRefusedWithTheDocumentUnchanged() throws {
    var document = try appearanceFixtureDocument(bodyCount: 1)
    let nodeID = try #require(appearanceBodySceneNodeIDs(in: document).first)

    do {
        _ = try document.setSceneNodeAppearance(id: nodeID, edit: .opacity(1.5))
        Issue.record("An appearance value outside the unit interval must be refused.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("0 to 1"))
    }

    #expect(document.productMetadata.materialLibrary.materials.isEmpty)
    #expect(document.productMetadata.sceneNodes[nodeID]?.materialID == nil)
}

@Test(.timeLimit(.minutes(1)))
func aNodeHoldingNoMaterialReadsTheNeutralAppearance() throws {
    let document = try appearanceFixtureDocument(bodyCount: 1)
    let nodeID = try #require(appearanceBodySceneNodeIDs(in: document).first)

    let appearance = try #require(document.authorableSceneNodeAppearance(id: nodeID))

    #expect(appearance.baseColor == Material.neutralBaseColor)
    #expect(appearance.metallic == Material.neutral(named: "probe").metallic)
    #expect(appearance.roughness == Material.neutral(named: "probe").roughness)
    #expect(appearance.opacity == Material.neutral(named: "probe").opacity)
}

@Test(.timeLimit(.minutes(1)))
func aNodeAppearanceResolvesThroughItsMaterialThenTheDocumentDefault() throws {
    var document = try appearanceFixtureDocument(bodyCount: 1)
    let nodeID = try #require(appearanceBodySceneNodeIDs(in: document).first)

    // Neither the node nor the document names a material.
    let neutral = try #require(document.sceneNodeAppearance(id: nodeID))
    #expect(neutral.baseColor == Material.neutralBaseColor)
    #expect(neutral.metallic == Material.neutralMetallic)
    #expect(neutral.roughness == Material.neutralRoughness)
    #expect(neutral.opacity == Material.neutralOpacity)

    let fallback = Material(
        name: "Document default",
        baseColor: ColorRGBA(r: 0.1, g: 0.2, b: 0.3, a: 1.0),
        metallic: 0.7,
        roughness: 0.15,
        opacity: 0.5
    )
    document.productMetadata.materialLibrary.materials[fallback.id] = fallback
    document.productMetadata.materialLibrary.defaultMaterialID = fallback.id
    let defaulted = try #require(document.sceneNodeAppearance(id: nodeID))
    #expect(defaulted == fallback)

    let assigned = Material(
        name: "Assigned",
        baseColor: ColorRGBA(r: 0.9, g: 0.8, b: 0.7, a: 1.0),
        metallic: 0.05,
        roughness: 0.9,
        opacity: 1.0
    )
    document.productMetadata.materialLibrary.materials[assigned.id] = assigned
    document.productMetadata.sceneNodes[nodeID]?.materialID = assigned.id
    let resolved = try #require(document.sceneNodeAppearance(id: nodeID))
    #expect(resolved == assigned)

    // A node the document does not hold is the one thing this read answers
    // nothing for.
    #expect(document.sceneNodeAppearance(id: SceneNodeID()) == nil)
}

@Test(.timeLimit(.minutes(1)))
func aCreatedMaterialSeedsFromTheDocumentDefaultWhenTheDocumentHoldsOne() throws {
    var document = try appearanceFixtureDocument(bodyCount: 1)
    let nodeID = try #require(appearanceBodySceneNodeIDs(in: document).first)
    let fallback = Material(
        name: "Document default",
        baseColor: ColorRGBA(r: 0.1, g: 0.2, b: 0.3, a: 1.0),
        metallic: 0.7,
        roughness: 0.15,
        opacity: 0.5
    )
    document.productMetadata.materialLibrary.materials[fallback.id] = fallback
    document.productMetadata.materialLibrary.defaultMaterialID = fallback.id

    let materialID = try document.setSceneNodeAppearance(id: nodeID, edit: .metallic(0.25))

    #expect(materialID != fallback.id)
    let material = try #require(document.productMetadata.materialLibrary.materials[materialID])
    #expect(material.metallic == 0.25)
    // The three components the edit does not name start where the canvas
    // already drew the body, which is the document default here.
    #expect(material.baseColor == fallback.baseColor)
    #expect(material.roughness == fallback.roughness)
    #expect(material.opacity == fallback.opacity)
    #expect(document.productMetadata.materialLibrary.defaultMaterialID == fallback.id)
    #expect(document.productMetadata.materialLibrary.materials[fallback.id] == fallback)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aGeneratedPatternArrayOutputHasNoAppearanceToAuthor() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        appearanceBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(name: "Appearance Source", rootSceneNodeIDs: [bodySceneNodeID])
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Appearance Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Appearance Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Appearance Array"
    })
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )

    #expect(session.document.authorableSceneNodeAppearance(id: outputSceneNodeID) == nil)
    // The canvas still has something to draw the generated output with.
    #expect(session.document.sceneNodeAppearance(id: outputSceneNodeID) != nil)
    do {
        _ = try session.execute(.setSceneNodeAppearance(id: outputSceneNodeID, edit: .metallic(0.5)))
        Issue.record("Pattern array output scene node appearance must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    #expect(session.document.productMetadata.materialLibrary.materials.isEmpty)
}

// MARK: - Fixtures

private func appearanceFixtureDocument(bodyCount: Int) throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Appearance")
    for index in 0..<bodyCount {
        _ = try document.createExtrudedRectangle(
            name: "Plate \(index)",
            plane: .xy,
            width: .length(0.1, .meter),
            height: .length(0.08, .meter),
            depth: .length(0.06, .meter),
            direction: .normal
        )
    }
    return document
}

private func appearanceBodySceneNodeIDs(in document: DesignDocument) -> [SceneNodeID] {
    document.productMetadata.sceneNodes
        .filter { $0.value.reference?.kind == .body }
        .map(\.key)
        .sorted()
}

private func appearanceBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
