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
    #expect(state.featureEditTitle == "Source Controlled")
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

@Test func patternArrayInspectorStateReportsEditableRectangularAxes() throws {
    let fixture = PatternArrayInspectorFixture()
    let rootNode = SceneNode(id: fixture.rootSceneNodeID, name: "Array Root")
    let source = PatternArraySource(
        id: fixture.sourceID,
        name: "Array",
        definitionID: fixture.definitionID,
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(12.0, .millimeter),
                copyCount: 3,
                distanceMode: .extent
            ),
            secondAxis: PatternArrayLinearAxis(
                direction: .unitY,
                distance: .length(6.0, .millimeter),
                copyCount: 2,
                distanceMode: .spacing
            )
        )),
        outputMode: .componentInstance,
        outputInstanceIDs: [
            fixture.firstComponentInstanceID,
            fixture.secondComponentInstanceID,
        ],
        rootSceneNodeID: fixture.rootSceneNodeID
    )
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [rootNode],
        sceneNodes: [rootNode.id: rootNode],
        patternArrays: [source.id: source],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: false,
            patternArrays: [fixture.componentInstanceSummary]
        )
    ))
    let rectangular = try #require(state.rectangularFirstAxis)
    let secondAxis = try #require(state.rectangularSecondAxis)

    #expect(rectangular.copyCount == 3)
    #expect(rectangular.distanceMeters == 0.012)
    #expect(rectangular.distanceMode == .extent)
    #expect(rectangular.distanceModeTitle == "Extent")
    #expect(rectangular.distanceIsEditable)
    #expect(secondAxis.copyCount == 2)
    #expect(secondAxis.distanceMeters == 0.006)
    #expect(secondAxis.distanceMode == .spacing)
    #expect(secondAxis.distanceModeTitle == "Spacing")
    #expect(secondAxis.distanceIsEditable)
}

@Test func patternArrayInspectorStateReportsEditableRadialDistribution() throws {
    let fixture = PatternArrayInspectorFixture()
    let rootNode = SceneNode(id: fixture.rootSceneNodeID, name: "Array Root")
    let source = PatternArraySource(
        id: fixture.sourceID,
        name: "Array",
        definitionID: fixture.definitionID,
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: Point3D(x: 0.001, y: 0.002, z: 0.003),
                axis: .unitZ,
                angle: .angle(180.0, .degree),
                copyCount: 5,
                angleMode: .extent
            ),
            radialAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(4.0, .millimeter),
                copyCount: 2,
                distanceMode: .spacing
            )
        )),
        outputMode: .componentInstance,
        outputInstanceIDs: [
            fixture.firstComponentInstanceID,
            fixture.secondComponentInstanceID,
        ],
        rootSceneNodeID: fixture.rootSceneNodeID
    )
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [rootNode],
        sceneNodes: [rootNode.id: rootNode],
        patternArrays: [source.id: source],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: false,
            patternArrays: [fixture.componentInstanceSummary(distributionKind: .radial)]
        )
    ))
    let angularAxis = try #require(state.radialAngularAxis)
    let radialAxis = try #require(state.radialAxis)

    #expect(angularAxis.center == Point3D(x: 0.001, y: 0.002, z: 0.003))
    #expect(angularAxis.axis == .unitZ)
    #expect(angularAxis.copyCount == 5)
    #expect(abs((angularAxis.angleRadians ?? 0.0) - Double.pi) < 1.0e-12)
    #expect(angularAxis.angleMode == .extent)
    #expect(angularAxis.angleModeTitle == "Extent")
    #expect(angularAxis.angleIsEditable)
    #expect(radialAxis.copyCount == 2)
    #expect(radialAxis.distanceMeters == 0.004)
    #expect(radialAxis.distanceMode == .spacing)
}

@Test func patternArrayInspectorStateReportsEditableCurveDistribution() throws {
    let fixture = PatternArrayInspectorFixture()
    let rootNode = SceneNode(id: fixture.rootSceneNodeID, name: "Array Root")
    let source = PatternArraySource(
        id: fixture.sourceID,
        name: "Array",
        definitionID: fixture.definitionID,
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.01, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 4,
            twist: .angle(45.0, .degree),
            endScale: .scalar(1.5),
            alignment: .parallel,
            extent: .scalar(0.75),
            extentMode: .ratio
        )),
        outputMode: .componentInstance,
        outputInstanceIDs: [
            fixture.firstComponentInstanceID,
            fixture.secondComponentInstanceID,
        ],
        rootSceneNodeID: fixture.rootSceneNodeID
    )
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [rootNode],
        sceneNodes: [rootNode.id: rootNode],
        patternArrays: [source.id: source],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: false,
            patternArrays: [fixture.componentInstanceSummary(distributionKind: .curve)]
        )
    ))
    let curve = try #require(state.curve)

    #expect(curve.path == .polyline(points: [.origin, Point3D(x: 0.01, y: 0.0, z: 0.0)], normal: .unitZ))
    #expect(curve.pathTitle == "2 Point Polyline")
    #expect(curve.copyCount == 4)
    #expect(abs((curve.twistRadians ?? 0.0) - Double.pi / 4.0) < 1.0e-12)
    #expect(curve.endScale == 1.5)
    #expect(curve.alignment == .parallel)
    #expect(curve.extentRatio == 0.75)
    #expect(curve.extentMode == .ratio)
    #expect(curve.extentModeTitle == "Ratio")
    #expect(curve.twistIsEditable)
    #expect(curve.endScaleIsEditable)
    #expect(curve.extentIsEditable)
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
    #expect(state.featureEditTitle == "Allowed")
    #expect(state.independentCopyOutputStateTitle == "#1 Diverged")
    #expect(state.independentCopyRegenerationTitle == "Reuse Until Definition Changes")
}

@Test func patternArrayInspectorStateSummarizesIndependentCopySourceState() throws {
    let fixture = PatternArrayInspectorFixture()
    let rootNode = SceneNode(id: fixture.rootSceneNodeID, name: "Array Root")
    let state = try #require(PatternArrayInspectorState(
        selectedNodes: [rootNode],
        sceneNodes: [rootNode.id: rootNode],
        summaryResult: PatternArraySummaryResult(
            generation: DocumentGeneration(7),
            dirty: true,
            patternArrays: [fixture.independentCopySummary]
        )
    ))

    #expect(state.selectedRole == .sourceRoot)
    #expect(state.selectedOutputIndices.isEmpty)
    #expect(state.independentCopyOutputStateTitle == "1 Source Match, 1 Diverged")
    #expect(state.independentCopyRegenerationTitle == "Reuse Until Definition Changes")
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
    var firstOutputFeatureID = FeatureID()
    var secondOutputFeatureID = FeatureID()
    var name: String

    init(name: String = "Array") {
        self.name = name
    }

    var componentInstanceSummary: PatternArraySummary {
        componentInstanceSummary(distributionKind: .rectangular)
    }

    func componentInstanceSummary(
        distributionKind: PatternArraySummary.DistributionKind
    ) -> PatternArraySummary {
        PatternArraySummary(
            sourceID: sourceID,
            name: name,
            definitionID: definitionID,
            definitionName: "Definition",
            rootSceneNodeID: rootSceneNodeID,
            rootSceneNodeName: "Array Root",
            distributionKind: distributionKind,
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
            outputFeatureIDs: [
                firstOutputFeatureID,
                secondOutputFeatureID,
            ],
            editableFields: [.name, .definitionID, .distribution, .outputMode],
            lifecycleActions: [.updatePatternArray, .explodePatternArray],
            outputOwnership: PatternArraySummary.OutputOwnership(
                kind: .sourceOwnedIndependentCopies,
                directOutputEditingAllowed: false,
                directFeatureEditingAllowed: true,
                sourceEditAction: .updatePatternArray,
                detachAction: .explodePatternArray,
                editableAfterDetach: true
            ),
            independentCopyOutputs: [
                PatternArraySummary.IndependentCopyOutputStatus(
                    outputIndex: 0,
                    sceneNodeID: firstOutputSceneNodeID,
                    featureIDs: [firstOutputFeatureID],
                    state: .divergedFromSourceDefinition,
                    regenerationPolicy: .reuseUntilDefinitionIdentityChanges
                ),
                PatternArraySummary.IndependentCopyOutputStatus(
                    outputIndex: 1,
                    sceneNodeID: secondOutputSceneNodeID,
                    featureIDs: [secondOutputFeatureID],
                    state: .matchesSourceDefinition,
                    regenerationPolicy: .reuseUntilDefinitionIdentityChanges
                ),
            ],
            diagnostics: []
        )
    }
}
