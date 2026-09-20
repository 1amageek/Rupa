import Foundation
import SwiftCAD
import Testing
import RupaCoreTypes
@testable import RupaCore

@Suite("Object property effects")
struct ObjectPropertyEffectTests {
    @Test(.timeLimit(.minutes(1)))
    func builtInCatalogSatisfiesTheEffectContract() throws {
        // `ObjectTypeRegistry.builtIn` skips validation, so the catalog is only proven by
        // registering the same definitions through the validating initializer.
        let registry = try ObjectTypeRegistry(definitions: ObjectTypeCatalog.builtInDefinitions)
        #expect(registry.definitions.count == ObjectTypeCatalog.builtInDefinitions.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func derivedPropertyMustNotOfferAnEditableControl() {
        let property = ObjectPropertyDefinition(
            id: "derived.editable",
            title: "Derived",
            group: "Shape",
            valueKind: .length,
            defaultValue: .length(1.0),
            inspectorControl: .textFieldAndSlider,
            effect: .derived,
            isEditable: true
        )
        #expect(throws: DocumentValidationError.self) {
            try property.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPropertyMustNotUseTheReadOnlyControl() {
        let property = ObjectPropertyDefinition(
            id: "source.readonly",
            title: "Source",
            group: "Shape",
            valueKind: .length,
            defaultValue: .length(1.0),
            inspectorControl: .readOnly,
            effect: .source
        )
        #expect(throws: DocumentValidationError.self) {
            try property.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourcePropertyWithoutRoutingFailsVisibly() throws {
        var document = DesignDocument.empty()
        let node = try rectangleSketchNode(in: &document)
        let before = document.productMetadata.sceneNodes[node.id]

        do {
            // `bevel` declares the `source` effect on every extruded profile and has no router
            // branch yet, so it is the property this contract is proven on.
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: PropertyID(rawValue: "bevel"),
                value: .length(0.01)
            )
            Issue.record("A source property the router cannot apply must fail.")
        } catch let error as EditorError {
            #expect(error.code == .commandUnsupported)
        }

        #expect(document.productMetadata.sceneNodes[node.id] == before)
    }

    @Test(.timeLimit(.minutes(1)))
    func tessellationPropertyEditIsAcceptedWithoutASourceMutation() throws {
        var document = DesignDocument.empty()
        let node = try rectangleSketchNode(in: &document)
        let sourceBefore = document.cadDocument.designGraph

        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: PropertyID(rawValue: "corner.sides"),
            value: .integer(8)
        )

        let stored = document.productMetadata.sceneNodes[node.id]?
            .object?.properties[PropertyID(rawValue: "corner.sides")]
        #expect(stored == .integer(8))
        #expect(document.cadDocument.designGraph == sourceBefore)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadingPrunesPropertyValuesTheSchemaNoLongerDeclares() throws {
        var document = DesignDocument.empty()
        let node = try rectangleSketchNode(in: &document)
        let retired = PropertyID(rawValue: "stroke.width")
        let declared = PropertyID(rawValue: "size.x")

        var staleNode = try #require(document.productMetadata.sceneNodes[node.id])
        staleNode.object?.properties[retired] = .length(0.002)
        staleNode.object?.properties[declared] = .length(0.5)
        document.productMetadata.sceneNodes[node.id] = staleNode

        #expect(throws: DocumentValidationError.self) {
            try document.productMetadata.validate(
                against: document.cadDocument,
                objectRegistry: .builtIn
            )
        }

        _ = document.productMetadata.pruneUndeclaredObjectProperties(objectRegistry: .builtIn)

        try document.productMetadata.validate(
            against: document.cadDocument,
            objectRegistry: .builtIn
        )
        let properties = document.productMetadata.sceneNodes[node.id]?.object?.properties
        #expect(properties?[retired] == nil)
        #expect(properties?[declared] == .length(0.5))
    }

    private func rectangleSketchNode(in document: inout DesignDocument) throws -> SceneNode {
        let featureID = try document.createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(1.0, .meter),
            height: .length(1.0, .meter)
        )
        return try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })
    }
}
