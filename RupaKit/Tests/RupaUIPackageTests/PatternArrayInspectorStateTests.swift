import RupaCore
import Testing
@testable import RupaUI

@Test func patternArrayInspectorStateReportsSourceRootSelection() throws {
    let fixture = PatternArrayInspectorFixture()
    let summary = fixture.componentInstanceSummary
    let rootNode = SceneNode(id: fixture.rootSceneNodeID, name: "Array Root")
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [rootNode],
        sceneNodes: [rootNode.id: rootNode],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: false,
            patternArrays: [summary]
        )
    ))

    #expect(state.sourceID == fixture.sourceID)
    #expect(state.name == "Array")
    #expect(state.selectedRole == .sourceRoot)
    #expect(state.selectedOutputIndices.isEmpty)
    #expect(state.selectionRoleTitle == "Source Root")
    #expect(state.selectedOutputTitle == "None")
    #expect(state.ownershipTitle == "Source-owned Component Instances")
    #expect(state.directEditTitle == "Source Controlled")
    #expect(state.sourceEditTitle == "Update Pattern Array")
    #expect(state.detachTitle == "Explode Pattern Array")
    #expect(state.diagnosticsTitle == "None")
}

@Test func patternArrayInspectorStateReportsComponentInstanceOutputSelection() throws {
    let fixture = PatternArrayInspectorFixture()
    let outputNode = SceneNode(
        id: SceneNodeID(),
        name: "Array 2",
        reference: .componentInstance(fixture.secondComponentInstanceID)
    )
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [outputNode],
        sceneNodes: [outputNode.id: outputNode],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: false,
            patternArrays: [fixture.componentInstanceSummary]
        )
    ))

    #expect(state.selectedRole == .output)
    #expect(state.selectedOutputIndices == [1])
    #expect(state.selectionRoleTitle == "Output")
    #expect(state.selectedOutputTitle == "#2")
    #expect(state.outputModeTitle == "Component Instance")
}

@Test func patternArrayInspectorStateReportsIndependentCopyDescendantSelection() throws {
    let fixture = PatternArrayInspectorFixture()
    let outputRoot = SceneNode(
        id: fixture.firstOutputSceneNodeID,
        name: "Array Copy 1",
        childIDs: [fixture.outputBodySceneNodeID]
    )
    let outputBody = SceneNode(
        id: fixture.outputBodySceneNodeID,
        name: "Array Copy 1 Body",
        reference: .body(FeatureID())
    )
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [outputBody],
        sceneNodes: [
            outputRoot.id: outputRoot,
            outputBody.id: outputBody,
        ],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: true,
            patternArrays: [fixture.independentCopySummary]
        )
    ))

    #expect(state.selectedRole == .outputDescendant)
    #expect(state.selectedOutputIndices == [0])
    #expect(state.selectionRoleTitle == "Output Descendant")
    #expect(state.selectedOutputTitle == "#1")
    #expect(state.outputModeTitle == "Independent Copy")
    #expect(state.ownershipTitle == "Source-owned Independent Copies")
}

@Test func patternArrayInspectorStateRejectsUnrelatedAndMixedPatternSelections() {
    let firstFixture = PatternArrayInspectorFixture()
    let secondFixture = PatternArrayInspectorFixture(name: "Second Array")
    let unrelatedNode = SceneNode(id: SceneNodeID(), name: "Unrelated")
    let firstNode = SceneNode(
        id: SceneNodeID(),
        name: "First Array 1",
        reference: .componentInstance(firstFixture.firstComponentInstanceID)
    )
    let secondNode = SceneNode(
        id: SceneNodeID(),
        name: "Second Array 1",
        reference: .componentInstance(secondFixture.firstComponentInstanceID)
    )
    let result = PatternArraySummaryResult(
        generation: DocumentGeneration(7),
        dirty: false,
        patternArrays: [
            firstFixture.componentInstanceSummary,
            secondFixture.componentInstanceSummary,
        ]
    )

    #expect(PatternArrayInspectorState(
        selectedNodes: [unrelatedNode],
        sceneNodes: [unrelatedNode.id: unrelatedNode],
        summaryResult: result
    ) == nil)
    #expect(PatternArrayInspectorState(
        selectedNodes: [firstNode, secondNode],
        sceneNodes: [
            firstNode.id: firstNode,
            secondNode.id: secondNode,
        ],
        summaryResult: result
    ) == nil)
}

private struct PatternArrayInspectorFixture {
    var sourceID = PatternArraySourceID()
    var definitionID = ComponentDefinitionID()
    var rootSceneNodeID = SceneNodeID()
    var firstComponentInstanceID = ComponentInstanceID()
    var secondComponentInstanceID = ComponentInstanceID()
    var firstOutputSceneNodeID = SceneNodeID()
    var secondOutputSceneNodeID = SceneNodeID()
    var outputBodySceneNodeID = SceneNodeID()
    var name: String

    init(name: String = "Array") {
        self.name = name
    }

    var componentInstanceSummary: PatternArraySummary {
        PatternArraySummary(
            sourceID: sourceID,
            name: name,
            definitionID: definitionID,
            definitionName: "Definition",
            rootSceneNodeID: rootSceneNodeID,
            rootSceneNodeName: "Array Root",
            distributionKind: .rectangular,
            outputMode: .componentInstance,
            outputCount: 2,
            componentInstanceOutputIDs: [
                firstComponentInstanceID,
                secondComponentInstanceID,
            ],
            outputSceneNodeIDs: [],
            outputFeatureIDs: [],
            editableFields: [.name, .definitionID, .distribution, .outputMode],
            lifecycleActions: [.updatePatternArray, .explodePatternArray],
            outputOwnership: PatternArraySummary.OutputOwnership(
                kind: .sourceOwnedComponentInstances,
                directOutputEditingAllowed: false,
                sourceEditAction: .updatePatternArray,
                detachAction: .explodePatternArray,
                editableAfterDetach: true
            ),
            diagnostics: []
        )
    }

    var independentCopySummary: PatternArraySummary {
        PatternArraySummary(
            sourceID: sourceID,
            name: name,
            definitionID: definitionID,
            definitionName: "Definition",
            rootSceneNodeID: rootSceneNodeID,
            rootSceneNodeName: "Array Root",
            distributionKind: .curve,
            outputMode: .independentCopy,
            outputCount: 2,
            componentInstanceOutputIDs: [],
            outputSceneNodeIDs: [
                firstOutputSceneNodeID,
                secondOutputSceneNodeID,
            ],
            outputFeatureIDs: [FeatureID()],
            editableFields: [.name, .definitionID, .distribution, .outputMode],
            lifecycleActions: [.updatePatternArray, .explodePatternArray],
            outputOwnership: PatternArraySummary.OutputOwnership(
                kind: .sourceOwnedIndependentCopies,
                directOutputEditingAllowed: false,
                sourceEditAction: .updatePatternArray,
                detachAction: .explodePatternArray,
                editableAfterDetach: true
            ),
            diagnostics: []
        )
    }
}
