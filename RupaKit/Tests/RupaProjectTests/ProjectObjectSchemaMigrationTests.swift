import Foundation
import SwiftCAD
import Testing
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
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
func aRetiredValueIsReportedOnEveryStateOfTheOpenedDocument() async throws {
    var document = DesignDocument.empty(named: "Earlier schema")
    let nodeID = try appendMeshBody(named: "Plate", to: &document)
    // Write the value the way the earlier schema persisted it.
    document.productMetadata.sceneNodes[nodeID]?.object?.properties[retiredPropertyID] =
        .length(0.001)

    let controller = try ProjectController(
        package: try projectPackage(of: document),
        evaluatorPreparer: SchemaMigrationEvaluatorPreparer(),
        projector: FixtureProjector(),
        objectRegistry: try meshBodyObjectRegistry()
    )

    // A publication landing after the open must not lose the list.
    _ = try await controller.evaluateCurrent()
    let reported = try await controller.currentState().retiredObjectProperties

    #expect(reported.count == 1)
    let retired = try #require(reported.first)
    #expect(retired.sceneNodeID == nodeID)
    #expect(retired.sceneNodeName == "Plate")
    #expect(retired.typeID == meshBodyTypeID)
    #expect(retired.propertyID == retiredPropertyID)
    #expect(retired.value == .length(0.001))
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

/// An object type an authored mesh body can carry, so the fixture reaches the
/// controller's state without a CAD geometry evaluation provider.
private let meshBodyTypeID = ObjectTypeID("fixture.mesh.body")

private func meshBodyObjectRegistry() throws -> ObjectTypeRegistry {
    try ObjectTypeRegistry(
        definitions: [
            ObjectTypeDefinition(
                id: meshBodyTypeID,
                title: "Fixture Mesh Body",
                systemImage: "cube",
                representation: .threeDimensional,
                category: .body,
                geometryRole: .mesh
            ),
        ]
    )
}

private func appendMeshBody(
    named name: String,
    to document: inout DesignDocument
) throws -> SceneNodeID {
    var builder = MeshSourceBuilder(identity: "mesh.schema-migration")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    let asset = try AuthoredMeshAsset(source: try builder.build(), provenance: .created)
    document.authoredMeshAssets[asset.id] = asset
    let representationID: GeometryRepresentationID = "representation.schema-migration"
    return try document.productMetadata.appendSceneNodeToFirstRoot(
        name: name,
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            typeID: meshBodyTypeID,
            geometryRepresentations: GeometryRepresentationSet(
                representations: [
                    representationID: GeometryRepresentation(
                        id: representationID,
                        source: .authoredMesh(asset.id)
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: representationID,
                    presentation: representationID
                )
            )
        )
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
