import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func projectionDependencyIdentityScopesSemanticAndFeatureChangesPerEntity() throws {
    var document = DesignDocument.empty(named: "Projection Dependencies")
    let firstFeatureID = try projectionDependencyBox(named: "First", in: &document)
    let secondFeatureID = try projectionDependencyBox(named: "Second", in: &document)
    let unrelatedFeatureID = try projectionDependencyBox(named: "Unrelated", in: &document)
    let envelope = projectionDependencyEnvelope(
        firstFeatureID: firstFeatureID,
        secondFeatureID: secondFeatureID
    )
    let builder = ProjectionDependencyIdentityBuilder()
    let generation = DocumentGeneration(4)
    let first = try builder.identity(
        for: "first",
        in: envelope,
        document: document,
        generation: generation
    )
    let second = try builder.identity(
        for: "second",
        in: envelope,
        document: document,
        generation: generation
    )

    let laterFirst = try builder.identity(
        for: "first",
        in: envelope,
        document: document,
        generation: DocumentGeneration(9)
    )
    #expect(first.matchesDependencies(of: laterFirst))

    var unrelatedFeatureChange = document
    unrelatedFeatureChange.cadDocument.designGraph.nodes[unrelatedFeatureID]?.name = "Changed Unrelated"
    let afterUnrelatedFeatureChange = try builder.identity(
        for: "first",
        in: envelope,
        document: unrelatedFeatureChange,
        generation: DocumentGeneration(5)
    )
    #expect(first.matchesDependencies(of: afterUnrelatedFeatureChange))

    var firstFeatureChange = document
    firstFeatureChange.cadDocument.designGraph.nodes[firstFeatureID]?.name = "Changed First"
    let firstAfterDirectChange = try builder.identity(
        for: "first",
        in: envelope,
        document: firstFeatureChange,
        generation: DocumentGeneration(5)
    )
    let secondAfterFirstChange = try builder.identity(
        for: "second",
        in: envelope,
        document: firstFeatureChange,
        generation: DocumentGeneration(5)
    )
    #expect(!first.matchesDependencies(of: firstAfterDirectChange))
    #expect(second.matchesDependencies(of: secondAfterFirstChange))

    let firstInputID = try #require(
        document.cadDocument.designGraph.nodes[firstFeatureID]?.inputs.first?.featureID
    )
    var transitiveFeatureChange = document
    transitiveFeatureChange.cadDocument.designGraph.nodes[firstInputID]?.name = "Changed First Input"
    let firstAfterTransitiveChange = try builder.identity(
        for: "first",
        in: envelope,
        document: transitiveFeatureChange,
        generation: DocumentGeneration(5)
    )
    #expect(!first.matchesDependencies(of: firstAfterTransitiveChange))

    var firstPayloadChange = envelope
    firstPayloadChange.payload = .object([
        "first": .object(["value": .number(11.0)]),
        "second": .object(["value": .number(2.0)]),
        "unrelated": .object(["value": .number(3.0)]),
    ])
    let firstAfterPayloadChange = try builder.identity(
        for: "first",
        in: firstPayloadChange,
        document: document,
        generation: DocumentGeneration(5)
    )
    let secondAfterFirstPayloadChange = try builder.identity(
        for: "second",
        in: firstPayloadChange,
        document: document,
        generation: DocumentGeneration(5)
    )
    #expect(!first.matchesDependencies(of: firstAfterPayloadChange))
    #expect(second.matchesDependencies(of: secondAfterFirstPayloadChange))

    var unrelatedPayloadChange = envelope
    unrelatedPayloadChange.payload = .object([
        "first": .object(["value": .number(1.0)]),
        "second": .object(["value": .number(2.0)]),
        "unrelated": .object(["value": .number(30.0)]),
    ])
    let firstAfterUnrelatedPayloadChange = try builder.identity(
        for: "first",
        in: unrelatedPayloadChange,
        document: document,
        generation: DocumentGeneration(5)
    )
    #expect(first.matchesDependencies(of: firstAfterUnrelatedPayloadChange))

    var schemaChange = envelope
    schemaChange.schemaVersion = SemanticSchemaVersion(major: 0, minor: 2, patch: 0)
    let firstAfterSchemaChange = try builder.identity(
        for: "first",
        in: schemaChange,
        document: document,
        generation: DocumentGeneration(5)
    )
    #expect(!first.matchesDependencies(of: firstAfterSchemaChange))
}

@Test(.timeLimit(.minutes(1)))
func projectionDependencyIdentityTraversesNestedComponentsWithoutIncludingSiblings() throws {
    var document = DesignDocument.empty(named: "Nested Projection Dependencies")
    let sourceFeatureID = try projectionDependencyBox(named: "Nested Source", in: &document)
    let rootSceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)

    let leafSceneNode = SceneNode(
        name: "Nested Leaf",
        reference: .body(sourceFeatureID)
    )
    let innerDefinition = ComponentDefinition(
        name: "Inner Definition",
        rootSceneNodeIDs: [leafSceneNode.id]
    )
    let innerInstance = ComponentInstance(
        definitionID: innerDefinition.id,
        name: "Inner Instance"
    )
    let innerInstanceNode = SceneNode(
        name: "Inner Instance Node",
        reference: .componentInstance(innerInstance.id)
    )
    let outerDefinition = ComponentDefinition(
        name: "Outer Definition",
        rootSceneNodeIDs: [innerInstanceNode.id]
    )
    let outerInstance = ComponentInstance(
        definitionID: outerDefinition.id,
        name: "Outer Instance"
    )
    let outerInstanceNode = SceneNode(
        name: "Outer Instance Node",
        reference: .componentInstance(outerInstance.id)
    )
    let unrelatedSibling = SceneNode(name: "Unrelated Sibling")

    document.productMetadata.sceneNodes[leafSceneNode.id] = leafSceneNode
    document.productMetadata.sceneNodes[innerInstanceNode.id] = innerInstanceNode
    document.productMetadata.sceneNodes[outerInstanceNode.id] = outerInstanceNode
    document.productMetadata.sceneNodes[unrelatedSibling.id] = unrelatedSibling
    document.productMetadata.sceneNodes[rootSceneNodeID]?.childIDs.append(outerInstanceNode.id)
    document.productMetadata.sceneNodes[rootSceneNodeID]?.childIDs.append(unrelatedSibling.id)
    document.productMetadata.componentDefinitions[innerDefinition.id] = innerDefinition
    document.productMetadata.componentDefinitions[outerDefinition.id] = outerDefinition
    document.productMetadata.componentInstances[innerInstance.id] = innerInstance
    document.productMetadata.componentInstances[outerInstance.id] = outerInstance

    let entityID: SemanticEntityID = "nested"
    let envelope = SemanticExtensionEnvelope(
        namespace: "fixture.nested",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["nested": .bool(true)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: entityID,
                    ownership: .classified,
                    sourcePaths: [SemanticPayloadPath([.key("nested")])]
                ),
            ],
            sceneReferences: [
                ProjectionManifest.SceneReference(
                    semanticEntityID: entityID,
                    sceneNodeID: outerInstanceNode.id
                ),
            ]
        )
    )
    let builder = ProjectionDependencyIdentityBuilder()
    let baseline = try builder.identity(
        for: entityID,
        in: envelope,
        document: document,
        generation: DocumentGeneration(1)
    )

    var siblingChange = document
    siblingChange.productMetadata.sceneNodes[unrelatedSibling.id]?.name = "Changed Sibling"
    let afterSiblingChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: siblingChange,
        generation: DocumentGeneration(2)
    )
    #expect(baseline.matchesDependencies(of: afterSiblingChange))

    var nestedInstanceChange = document
    nestedInstanceChange.productMetadata.componentInstances[innerInstance.id]?.properties["revision"] = "2"
    let afterNestedInstanceChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: nestedInstanceChange,
        generation: DocumentGeneration(2)
    )
    #expect(!baseline.matchesDependencies(of: afterNestedInstanceChange))

    var nestedFeatureChange = document
    nestedFeatureChange.cadDocument.designGraph.nodes[sourceFeatureID]?.name = "Changed Nested Source"
    let afterNestedFeatureChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: nestedFeatureChange,
        generation: DocumentGeneration(2)
    )
    #expect(!baseline.matchesDependencies(of: afterNestedFeatureChange))
}

@Test(.timeLimit(.minutes(1)))
func projectionDependencyIdentityTracksOnlyReferencedSceneMaterialBindings() throws {
    var document = DesignDocument.empty(named: "Projection Materials")
    let sourceFeatureID = try projectionDependencyBox(named: "Source", in: &document)
    let unrelatedFeatureID = try projectionDependencyBox(named: "Unrelated", in: &document)
    let sourceSceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(sourceFeatureID)
    }?.key)
    let unrelatedSceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(unrelatedFeatureID)
    }?.key)
    let sourceMaterial = projectionDependencyMaterial(named: "Source Material")
    let unrelatedMaterial = projectionDependencyMaterial(named: "Unrelated Material")
    document.productMetadata.materialLibrary.materials = [
        sourceMaterial.id: sourceMaterial,
        unrelatedMaterial.id: unrelatedMaterial,
    ]
    let sourceBinding = TopologyMaterialBinding(
        target: SelectionTarget(
            sceneNodeID: sourceSceneNodeID,
            component: .face(.generatedTopology("feature:source/generated:front"))
        ),
        materialID: sourceMaterial.id,
        process: TopologyMaterialBinding.Process(
            namespace: "manufacturing",
            processID: "source-process"
        )
    )
    let unrelatedBinding = TopologyMaterialBinding(
        target: SelectionTarget(
            sceneNodeID: unrelatedSceneNodeID,
            component: .face(.generatedTopology("feature:unrelated/generated:front"))
        ),
        materialID: unrelatedMaterial.id,
        process: TopologyMaterialBinding.Process(
            namespace: "manufacturing",
            processID: "unrelated-process"
        )
    )
    document.productMetadata.topologyMaterialBindings = [
        sourceBinding.id: sourceBinding,
        unrelatedBinding.id: unrelatedBinding,
    ]

    let entityID: SemanticEntityID = "source"
    let envelope = SemanticExtensionEnvelope(
        namespace: "fixture.material",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["source": .bool(true)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: entityID,
                    ownership: .classified,
                    sourcePaths: [SemanticPayloadPath([.key("source")])]
                ),
            ],
            sceneReferences: [
                ProjectionManifest.SceneReference(
                    semanticEntityID: entityID,
                    sceneNodeID: sourceSceneNodeID
                ),
            ]
        )
    )
    let builder = ProjectionDependencyIdentityBuilder()
    let baseline = try builder.identity(
        for: entityID,
        in: envelope,
        document: document,
        generation: DocumentGeneration(1)
    )

    var unrelatedMaterialChange = document
    unrelatedMaterialChange.productMetadata.materialLibrary
        .materials[unrelatedMaterial.id]?.roughness = 0.9
    let afterUnrelatedMaterialChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: unrelatedMaterialChange,
        generation: DocumentGeneration(2)
    )
    #expect(baseline.matchesDependencies(of: afterUnrelatedMaterialChange))

    var sourceMaterialChange = document
    sourceMaterialChange.productMetadata.materialLibrary
        .materials[sourceMaterial.id]?.roughness = 0.9
    let afterSourceMaterialChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: sourceMaterialChange,
        generation: DocumentGeneration(2)
    )
    #expect(!baseline.matchesDependencies(of: afterSourceMaterialChange))

    var unrelatedBindingChange = document
    unrelatedBindingChange.productMetadata.topologyMaterialBindings[unrelatedBinding.id]?
        .process?.processID = "changed-unrelated-process"
    let afterUnrelatedBindingChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: unrelatedBindingChange,
        generation: DocumentGeneration(2)
    )
    #expect(baseline.matchesDependencies(of: afterUnrelatedBindingChange))

    var sourceBindingChange = document
    sourceBindingChange.productMetadata.topologyMaterialBindings[sourceBinding.id]?
        .process?.processID = "changed-source-process"
    let afterSourceBindingChange = try builder.identity(
        for: entityID,
        in: envelope,
        document: sourceBindingChange,
        generation: DocumentGeneration(2)
    )
    #expect(!baseline.matchesDependencies(of: afterSourceBindingChange))
}

@Test(.timeLimit(.minutes(1)))
func projectionDependencyIdentityTraversesSemanticEntityDependencyClosure() throws {
    var document = DesignDocument.empty(named: "Semantic Projection Closure")
    let childFeatureID = try projectionDependencyBox(named: "Child Source", in: &document)
    let unrelatedFeatureID = try projectionDependencyBox(named: "Unrelated Source", in: &document)
    let parentID: SemanticEntityID = "parent"
    let childID: SemanticEntityID = "child"
    let envelope = SemanticExtensionEnvelope(
        namespace: "fixture.semantic-closure",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([
            "parent": .object(["value": .number(1.0)]),
            "child": .object(["value": .number(2.0)]),
        ]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: parentID,
                    ownership: .domainOwned,
                    sourcePaths: [SemanticPayloadPath([.key("parent")])]
                ),
                ProjectionSemanticEntity(
                    id: childID,
                    ownership: .domainOwned,
                    sourcePaths: [SemanticPayloadPath([.key("child")])]
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: childID,
                    featureID: childFeatureID,
                    ownership: .domainOwned
                ),
            ],
            boundaryTags: [
                ProjectionManifest.BoundaryTag(
                    semanticEntityID: parentID,
                    kind: "contains",
                    target: .semanticEntity(childID)
                ),
                ProjectionManifest.BoundaryTag(
                    semanticEntityID: childID,
                    kind: "belongs-to",
                    target: .semanticEntity(parentID)
                ),
            ]
        )
    )
    let builder = ProjectionDependencyIdentityBuilder()
    let baseline = try builder.identity(
        for: parentID,
        in: envelope,
        document: document,
        generation: DocumentGeneration(1)
    )

    var childFeatureChange = document
    childFeatureChange.cadDocument.designGraph.nodes[childFeatureID]?.name = "Changed Child Source"
    let afterChildFeatureChange = try builder.identity(
        for: parentID,
        in: envelope,
        document: childFeatureChange,
        generation: DocumentGeneration(2)
    )
    #expect(!baseline.matchesDependencies(of: afterChildFeatureChange))

    var childPayloadChange = envelope
    childPayloadChange.payload = .object([
        "parent": .object(["value": .number(1.0)]),
        "child": .object(["value": .number(20.0)]),
    ])
    let afterChildPayloadChange = try builder.identity(
        for: parentID,
        in: childPayloadChange,
        document: document,
        generation: DocumentGeneration(2)
    )
    #expect(!baseline.matchesDependencies(of: afterChildPayloadChange))

    var unrelatedFeatureChange = document
    unrelatedFeatureChange.cadDocument.designGraph.nodes[unrelatedFeatureID]?.name = "Changed Unrelated Source"
    let afterUnrelatedFeatureChange = try builder.identity(
        for: parentID,
        in: envelope,
        document: unrelatedFeatureChange,
        generation: DocumentGeneration(2)
    )
    #expect(baseline.matchesDependencies(of: afterUnrelatedFeatureChange))
}

private func projectionDependencyEnvelope(
    firstFeatureID: FeatureID,
    secondFeatureID: FeatureID
) -> SemanticExtensionEnvelope {
    SemanticExtensionEnvelope(
        namespace: "fixture.projection",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([
            "first": .object(["value": .number(1.0)]),
            "second": .object(["value": .number(2.0)]),
            "unrelated": .object(["value": .number(3.0)]),
        ]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "first",
                    ownership: .domainOwned,
                    sourcePaths: [SemanticPayloadPath([.key("first")])]
                ),
                ProjectionSemanticEntity(
                    id: "second",
                    ownership: .domainOwned,
                    sourcePaths: [SemanticPayloadPath([.key("second")])]
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: "first",
                    featureID: firstFeatureID,
                    ownership: .domainOwned
                ),
                ProjectionManifest.SourceReference(
                    semanticEntityID: "second",
                    featureID: secondFeatureID,
                    ownership: .domainOwned
                ),
            ]
        )
    )
}

private func projectionDependencyBox(
    named name: String,
    in document: inout DesignDocument
) throws -> FeatureID {
    try document.createExtrudedRectangle(
        name: name,
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
}

private func projectionDependencyMaterial(named name: String) -> Material {
    Material(
        name: name,
        baseColor: ColorRGBA(r: 0.2, g: 0.4, b: 0.6, a: 1.0),
        metallic: 0.0,
        roughness: 0.4,
        opacity: 1.0
    )
}
