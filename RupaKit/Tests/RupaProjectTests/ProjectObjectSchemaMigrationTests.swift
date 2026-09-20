import Foundation
import SwiftCAD
import Testing
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
@testable import RupaProjectPackage
@testable import RupaProject

/// A property an earlier object schema declared and the current one no longer does.
private let retiredPropertyID = PropertyID("stroke.width")

@Test(.timeLimit(.minutes(1)))
func aProjectSavedByAnEarlierObjectSchemaOpensWithoutTheValueItRetired() async throws {
    var document = DesignDocument.empty(named: "Earlier schema")
    _ = try document.createExtrudedRectangle(
        name: "Plate",
        plane: .xy,
        width: .length(0.1, .meter),
        height: .length(0.08, .meter),
        depth: .length(0.06, .meter),
        direction: .normal
    )
    let target = try #require(document.productMetadata.sceneNodes.values.first {
        ObjectTypeRegistry.builtIn.definition(for: $0.object?.typeID) != nil
    })
    #expect(
        ObjectTypeRegistry.builtIn
            .definition(for: target.object?.typeID)?
            .property(for: retiredPropertyID) == nil
    )
    // Write the value the way the earlier schema persisted it.
    document.productMetadata.sceneNodes[target.id]?.object?.properties[retiredPropertyID] =
        .length(0.001)

    let controller = try ProjectController(
        package: try projectPackage(of: document),
        evaluatorPreparer: SchemaMigrationEvaluatorPreparer(),
        projector: FixtureProjector()
    )

    let loaded = await controller.currentDocument()
    let object = try #require(loaded.productMetadata.sceneNodes[target.id]?.object)
    #expect(object.properties[retiredPropertyID] == nil)
    #expect(object.typeID == target.object?.typeID)
}

@Test(.timeLimit(.minutes(1)))
func aValueTheObjectSchemaDoesNotDeclareIsStillRefusedOnALiveDocument() async throws {
    var document = DesignDocument.empty(named: "Live")
    _ = try document.createExtrudedRectangle(
        name: "Plate",
        plane: .xy,
        width: .length(0.1, .meter),
        height: .length(0.08, .meter),
        depth: .length(0.06, .meter),
        direction: .normal
    )
    let target = try #require(document.productMetadata.sceneNodes.values.first {
        ObjectTypeRegistry.builtIn.definition(for: $0.object?.typeID) != nil
    })

    #expect(throws: (any Error).self) {
        try document.setSceneNodeObjectProperty(
            id: target.id,
            propertyID: retiredPropertyID,
            value: .length(0.001)
        )
    }
}

// MARK: - Helpers

private func projectPackage(of document: DesignDocument) throws -> ProjectPackageDocument {
    let source = try FixtureProjector().project(document)
    let cadSource = document.hasAuthoritativeCADSource
        ? try JSONProjectCADSourceCodec().encode(document.cadDocument)
        : nil
    return try ProjectPackageDocument(
        documentID: source.id,
        productSource: try JSONProjectProductSourceCodec().encode(document),
        cadSource: cadSource,
        authoredMeshAssets: document.authoredMeshAssets
    )
}

private struct SchemaMigrationEvaluatorPreparer: ProjectEvaluatorPreparing {
    func makeEvaluator(
        for _: DesignDocument,
        reusing _: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        ProjectEvaluationEngine()
    }
}
