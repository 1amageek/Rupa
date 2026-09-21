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
        // The contract is that a `source` property the router cannot apply fails rather than
        // being stored as an edit nothing performed. It is proven on a schema this test owns,
        // because proving it on whichever built-in property happened to be unrouted retires the
        // test the moment that property gets a mutator, which is what happened to `bevel`.
        let registry = try registryDeclaringAnUnroutedSourceProperty()
        var document = DesignDocument.empty()
        let node = try polygonSketchNode(in: &document)
        let before = document.productMetadata.sceneNodes[node.id]

        do {
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: unroutedPropertyID,
                value: .length(0.01),
                objectRegistry: registry
            )
            Issue.record("A source property the router cannot apply must fail.")
        } catch let error as EditorError {
            #expect(error.code == .commandUnsupported)
        }

        #expect(document.productMetadata.sceneNodes[node.id] == before)
    }

    private var unroutedPropertyID: PropertyID { PropertyID(rawValue: "unrouted.length") }

    /// The built-in catalog with one extra `source` property on the polygon profile, bound to a
    /// binding no mutation names.
    private func registryDeclaringAnUnroutedSourceProperty() throws -> ObjectTypeRegistry {
        let unrouted = ObjectPropertyDefinition(
            id: unroutedPropertyID,
            title: "Unrouted",
            group: "Shape",
            valueKind: .length,
            defaultValue: .length(0.0),
            inspectorControl: .textField,
            effect: .source,
            renderBinding: ObjectPropertyDefinition.RenderBinding(rawValue: "unrouted.length")
        )
        let definitions = ObjectTypeCatalog.builtInDefinitions.map { definition -> ObjectTypeDefinition in
            guard definition.id == .polygon else {
                return definition
            }
            var extended = definition
            extended.properties.append(unrouted)
            return extended
        }
        return try ObjectTypeRegistry(definitions: definitions)
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

    private func polygonSketchNode(in document: inout DesignDocument) throws -> SceneNode {
        let featureID = try document.createPolygonSketch(
            name: "Profile",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(0.5, .meter),
            sides: 6
        )
        return try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        })
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
