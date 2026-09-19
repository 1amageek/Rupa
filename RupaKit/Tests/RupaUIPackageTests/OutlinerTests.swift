import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test(.timeLimit(.minutes(1)))
func outlinerSymbolsFollowSourceKindsNotNames() throws {
    let cases: [(SceneNodeReference?, String)] = [
        (nil, "folder"), (.body(FeatureID()), "cube"),
        (.authoredMesh(GeometrySourceID()), "cube.transparent"),
        (.sketch(FeatureID()), "pencil.and.outline"), (.construction, "ruler"),
        (.feature(FeatureID()), "gearshape"),
        (.componentInstance(ComponentInstanceID()), "square.stack.3d.up")
    ]
    for (reference, symbol) in cases {
        let node = SceneNode(
            name: "Triangle", reference: reference, isVisible: false, isLocked: true
        )
        let metadata = ProductMetadata(
            sceneNodes: [node.id: node], rootSceneNodeIDs: [node.id]
        )
        let projection = OutlinerProjection.make(
            metadata: metadata, expandedIDs: [], searchText: "", filter: .all
        )
        let row = try #require(projection.row(for: node.id))
        #expect(row.systemImage == symbol)
        #expect(row.id == node.id && row.name == node.name)
        #expect(!row.isVisible && row.isLocked)
    }
}

@Test(.timeLimit(.minutes(1)))
func outlinerProjectionPreservesOrderAndSearchAncestors() {
    let bolt = SceneNode(name: "Bolt", isVisible: true)
    let hidden = SceneNode(name: "Hidden", isVisible: false)
    let assembly = SceneNode(
        name: "Assembly",
        childIDs: [bolt.id, hidden.id]
    )
    let root = SceneNode(name: "Scene", childIDs: [assembly.id])
    let metadata = ProductMetadata(
        sceneNodes: [root.id: root, assembly.id: assembly, bolt.id: bolt, hidden.id: hidden],
        rootSceneNodeIDs: [root.id]
    )

    let all = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [root.id, assembly.id],
        searchText: "",
        filter: .all
    )
    #expect(all.rows.map(\.id) == [root.id, assembly.id, bolt.id, hidden.id])
    #expect(all.rows.map(\.depth) == [0, 1, 2, 2])

    let search = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [],
        searchText: "bolt",
        filter: .all
    )
    #expect(search.rows.map(\.id) == [root.id, assembly.id, bolt.id])
    #expect(search.rows.map(\.depth) == [0, 1, 2])
    #expect(search.rows[1].isExpanded)
}

@Test(.timeLimit(.minutes(1)))
func outlinerProjectionNeverRendersGrandchildrenBelowCollapsedAncestors() {
    let leaf = SceneNode(name: "Leaf")
    let middle = SceneNode(name: "Middle", childIDs: [leaf.id])
    let root = SceneNode(name: "Root", childIDs: [middle.id])
    let metadata = ProductMetadata(
        sceneNodes: [root.id: root, middle.id: middle, leaf.id: leaf],
        rootSceneNodeIDs: [root.id]
    )

    let projection = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [middle.id],
        searchText: "",
        filter: .all
    )
    #expect(projection.rows.map(\.id) == [root.id])
    #expect(projection.row(for: root.id)?.isExpanded == false)
    #expect(projection.row(for: middle.id)?.isExpanded == true)
}

@Test(.timeLimit(.minutes(1)))
func outlinerProjectionAppliesSourceStateFiltersWithoutDeletingRows() {
    let visible = SceneNode(name: "Visible", isVisible: true, isLocked: false)
    let hiddenLocked = SceneNode(name: "Hidden", isVisible: false, isLocked: true)
    let root = SceneNode(name: "Scene", childIDs: [visible.id, hiddenLocked.id])
    let metadata = ProductMetadata(
        sceneNodes: [root.id: root, visible.id: visible, hiddenLocked.id: hiddenLocked],
        rootSceneNodeIDs: [root.id]
    )

    let hidden = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [root.id],
        searchText: "",
        filter: .hidden
    )
    #expect(hidden.rows.map(\.id) == [root.id, hiddenLocked.id])

    let unlocked = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [root.id],
        searchText: "",
        filter: .unlocked
    )
    #expect(unlocked.rows.map(\.id) == [root.id, visible.id])
    #expect(unlocked.allRows.count == 3)
}

@Test(.timeLimit(.minutes(1)))
func outlinerGeneratedOutputProjectionDisablesRowMutations() {
    let root = SceneNode(name: "Scene")
    let child = SceneNode(name: "Generated", childIDs: [])
    var source = PatternArraySource(
        name: "Array",
        definitionID: ComponentDefinitionID(),
        distribution: .rectangular(
            RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: Vector3D(x: 1, y: 0, z: 0),
                    distance: .scalar(1.0),
                    copyCount: 1
                )
            )
        ),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [child.id],
        outputFeatureIDs: [FeatureID()],
        rootSceneNodeID: root.id
    )
    source.outputSceneNodeIDs = [child.id]
    var rootWithChild = root
    rootWithChild.childIDs = [child.id]
    let metadata = ProductMetadata(
        sceneNodes: [root.id: rootWithChild, child.id: child],
        rootSceneNodeIDs: [root.id],
        patternArrays: [source.id: source]
    )

    let projection = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [root.id],
        searchText: "",
        filter: .all
    )
    let generated = projection.row(for: child.id)
    #expect(projection.row(for: root.id)?.systemImage == "square.grid.3x3")
    #expect(generated?.isGeneratedOutput == true)
    #expect(generated?.canRename == false)
    #expect(generated?.canMutateState == false)
    #expect(projection.row(for: child.id)?.isGeneratedOutput == true)
    #expect(projection.canMutate(ids: [root.id]))
    #expect(!projection.canMutate(ids: [root.id, child.id]))
}

@Test(.timeLimit(.minutes(1)))
func outlinerContextSelectionAndRenameDraftHaveExplicitBoundaries() {
    let first = SceneNodeID()
    let second = SceneNodeID()
    let third = SceneNodeID()
    let ordered = [first, second, third]

    #expect(
        OutlinerProjection.contextSelection(
            rowID: second,
            selectedIDs: [first, third],
            orderedIDs: ordered
        ) == [second]
    )
    #expect(
        OutlinerProjection.contextSelection(
            rowID: third,
            selectedIDs: [third, first],
            orderedIDs: ordered
        ) == [first, third]
    )
    #expect(OutlinerProjection.normalizedRename("  New Name  ") == "New Name")
    #expect(OutlinerProjection.normalizedRename(" \n\t ") == nil)
}

@Test(.timeLimit(.minutes(1)))
func outlinerPlannerRejectsMixedMissingStateSelectionBeforePlanning() {
    let valid = SceneNode(name: "Valid")
    let metadata = ProductMetadata(
        sceneNodes: [valid.id: valid],
        rootSceneNodeIDs: [valid.id]
    )
    var didRejectMissingReference = false

    do {
        _ = try OutlinerSourceCommandPlanner.stateChange(
            ids: [valid.id, SceneNodeID()],
            isVisible: false,
            in: metadata
        )
    } catch let error as EditorError {
        didRejectMissingReference = error.code == .referenceUnresolved
    } catch {
        didRejectMissingReference = false
    }

    #expect(didRejectMissingReference)
}

@Test(.timeLimit(.minutes(1)))
func outlinerPlannerIsolateKeepsSelectedSubtreeAndHidesOtherBranches() throws {
    let selectedLeaf = SceneNode(name: "Selected Leaf", isVisible: false)
    let selectedGroup = SceneNode(
        name: "Selected Group",
        childIDs: [selectedLeaf.id],
        isVisible: false
    )
    let otherLeaf = SceneNode(name: "Other Leaf")
    let otherGroup = SceneNode(
        name: "Other Group",
        childIDs: [otherLeaf.id]
    )
    let root = SceneNode(
        name: "Scene",
        childIDs: [selectedGroup.id, otherGroup.id]
    )
    let metadata = ProductMetadata(
        sceneNodes: [
            root.id: root,
            selectedGroup.id: selectedGroup,
            selectedLeaf.id: selectedLeaf,
            otherGroup.id: otherGroup,
            otherLeaf.id: otherLeaf
        ],
        rootSceneNodeIDs: [root.id]
    )

    let commands = try OutlinerSourceCommandPlanner.isolate(
        ids: [selectedGroup.id],
        in: metadata
    )

    #expect(commands == [
        .setSceneNodeVisibility(id: selectedGroup.id, isVisible: true),
        .setSceneNodeVisibility(id: selectedLeaf.id, isVisible: true),
        .setSceneNodeVisibility(id: otherGroup.id, isVisible: false),
        .setSceneNodeVisibility(id: otherLeaf.id, isVisible: false)
    ])
}

@Test(.timeLimit(.minutes(1)))
func outlinerPlannerRoutesRenameToEachOwningCommand() throws {
    let constructionPlaneID = ConstructionPlaneSourceID()
    let componentInstanceID = ComponentInstanceID()
    let construction = SceneNode(
        name: "Plane",
        reference: .constructionPlane(constructionPlaneID)
    )
    let descriptorOnlyInstance = SceneNode(
        name: "Instance",
        object: .componentInstance(componentInstanceID)
    )
    let ordinary = SceneNode(name: "Ordinary")
    let metadata = ProductMetadata(
        sceneNodes: [
            construction.id: construction,
            descriptorOnlyInstance.id: descriptorOnlyInstance,
            ordinary.id: ordinary
        ],
        rootSceneNodeIDs: [construction.id, descriptorOnlyInstance.id, ordinary.id]
    )

    #expect(
        try OutlinerSourceCommandPlanner.rename(
            id: construction.id,
            name: "Plane Renamed",
            in: metadata
        ) == [.renameConstructionPlane(id: constructionPlaneID, name: "Plane Renamed")]
    )
    #expect(
        try OutlinerSourceCommandPlanner.rename(
            id: descriptorOnlyInstance.id,
            name: "Instance Renamed",
            in: metadata
        ) == [.renameComponentInstance(id: componentInstanceID, name: "Instance Renamed")]
    )
    #expect(
        try OutlinerSourceCommandPlanner.rename(
            id: ordinary.id,
            name: "Ordinary Renamed",
            in: metadata
        ) == [.renameSceneNode(id: ordinary.id, name: "Ordinary Renamed")]
    )
}

@Test(.timeLimit(.minutes(1)))
func outlinerFrameEligibilityKeepsBodySelectionWithConsumedHiddenSketch() {
    let consumedSketch = SceneNode(
        name: "Consumed Sketch",
        reference: .sketch(FeatureID()),
        isVisible: false
    )
    let body = SceneNode(
        name: "Body",
        reference: .body(FeatureID()),
        childIDs: [consumedSketch.id]
    )
    let metadata = ProductMetadata(
        sceneNodes: [body.id: body, consumedSketch.id: consumedSketch],
        rootSceneNodeIDs: [body.id]
    )
    let projection = OutlinerProjection.make(
        metadata: metadata,
        expandedIDs: [body.id],
        searchText: "",
        filter: .all
    )
    let selectedIDs: Set<SceneNodeID> = [body.id, consumedSketch.id]

    #expect(projection.rows.map(\.id) == [body.id])
    #expect(
        OutlinerProjection.frameSelectionIsEnabled(
            rowID: body.id,
            selectedIDs: selectedIDs,
            canFrameSelection: true
        )
    )
    #expect(
        OutlinerIntent.frameCurrentSelection == .frameCurrentSelection
    )
}

@Test(.timeLimit(.minutes(1)))
func outlinerDropDestinationUsesSourceSiblingAnchors() {
    let first = SceneNode(name: "First")
    let second = SceneNode(name: "Second")
    let third = SceneNode(name: "Third")
    let root = SceneNode(
        name: "Scene",
        childIDs: [first.id, second.id, third.id]
    )
    let metadata = ProductMetadata(
        sceneNodes: [
            root.id: root,
            first.id: first,
            second.id: second,
            third.id: third
        ],
        rootSceneNodeIDs: [root.id]
    )

    #expect(
        OutlinerProjection.dropDestination(
            rowID: second.id,
            locationY: 1,
            metadata: metadata
        ) == OutlinerDropDestination(parentID: root.id, beforeSiblingID: second.id)
    )
    #expect(
        OutlinerProjection.dropDestination(
            rowID: second.id,
            locationY: 21,
            metadata: metadata
        ) == OutlinerDropDestination(parentID: root.id, beforeSiblingID: third.id)
    )
    #expect(
        OutlinerProjection.dropDestination(
            rowID: second.id,
            locationY: 11,
            metadata: metadata
        ) == OutlinerDropDestination(parentID: second.id, beforeSiblingID: nil)
    )
    #expect(
        OutlinerProjection.rootDropDestination()
            == OutlinerDropDestination(parentID: nil, beforeSiblingID: nil)
    )
}

@Test(.timeLimit(.minutes(1)))
func outlinerDragPayloadRejectsForeignAndStaleSessions() {
    let nonce = UUID()
    let session = OutlinerMoveDragSession(
        nonce: nonce,
        ids: [SceneNodeID()],
        expectedGeneration: DocumentGeneration(4)
    )

    #expect(OutlinerMoveDragSession.nonce(
        from: OutlinerMoveDragSession.payload(for: nonce)
    ) == nonce)
    #expect(OutlinerMoveDragSession.nonce(from: Data("foreign".utf8)) == nil)
    #expect(session.matches(nonce: nonce, generation: DocumentGeneration(4)))
    #expect(!session.matches(nonce: UUID(), generation: DocumentGeneration(4)))
    #expect(!session.matches(nonce: nonce, generation: DocumentGeneration(5)))
    #expect(!session.matches(nonce: nil, generation: DocumentGeneration(4)))
}

@Test(.timeLimit(.minutes(1)))
func outlinerProjectionRejectsUnsafeParentDropTargets() {
    func row(
        isLocked: Bool = false,
        isGeneratedOutput: Bool = false,
        isPatternRoot: Bool = false
    ) -> OutlinerRow {
        OutlinerRow(
            id: SceneNodeID(),
            parentID: nil,
            depth: 0,
            name: "Node",
            kindTitle: "Body",
            isVisible: true,
            isEffectivelyVisible: true,
            isLocked: isLocked,
            hasChildren: true,
            isExpanded: true,
            isGeneratedOutput: isGeneratedOutput,
            isPatternRoot: isPatternRoot,
            isComponentInstance: false,
            canRename: true,
            canMutateState: true,
            disabledReason: nil
        )
    }

    let pattern = row(isPatternRoot: true)
    let projection = OutlinerProjection(rows: [pattern], allRows: [pattern])

    #expect(OutlinerProjection.canReceiveChildren(row()))
    #expect(!OutlinerProjection.canReceiveChildren(row(isLocked: true)))
    #expect(!OutlinerProjection.canReceiveChildren(row(isGeneratedOutput: true)))
    #expect(!OutlinerProjection.canReceiveChildren(pattern))
    #expect(!projection.canMove(ids: [pattern.id]))
}

/// Group collects rows into a new parent, which is the same re-parenting a drag performs, so a row
/// a drag would refuse cannot be swept into a group by the menu instead.
@Test(.timeLimit(.minutes(1)))
func outlinerLifecycleGroupCollectsOnlyRowsADragCouldMove() {
    let scene = OutlinerLifecycleScene()

    let pair = scene.lifecycle([scene.bracketID, scene.assemblyID])
    #expect(pair.canGroup)
    #expect(pair.groupableIDs == [scene.bracketID, scene.assemblyID])
    #expect(pair.groupActionTitle == "Group 2 Objects")
    #expect(scene.lifecycle([scene.bracketID]).groupActionTitle == "Group Object")

    let refusals: [[SceneNodeID]] = [
        [scene.bracketID, scene.sealedGroupID],
        [scene.bracketID, scene.generatedID],
        [scene.bracketID, scene.patternRootID],
        [scene.bracketID, scene.rootID],
        [scene.rootID],
        []
    ]
    for ids in refusals {
        let lifecycle = scene.lifecycle(ids)
        #expect(!lifecycle.canGroup)
        #expect(lifecycle.groupableIDs.isEmpty)
        #expect(lifecycle.groupActionTitle == "Group")
    }
}

/// Ungroup dissolves a node that holds nothing but its children, so a row that carries geometry is
/// left where it is rather than refusing the groups selected next to it.
@Test(.timeLimit(.minutes(1)))
func outlinerLifecycleUngroupDissolvesOnlyUnlockedGroupingNodes() {
    let scene = OutlinerLifecycleScene()

    let one = scene.lifecycle([scene.assemblyID])
    #expect(one.canUngroup)
    #expect(one.dissolvableIDs == [scene.assemblyID])
    #expect(one.ungroupActionTitle == "Ungroup")

    let two = scene.lifecycle([scene.assemblyID, scene.fittingID])
    #expect(two.dissolvableIDs == [scene.assemblyID, scene.fittingID])
    #expect(two.ungroupActionTitle == "Ungroup 2 Groups")

    #expect(scene.lifecycle([scene.assemblyID, scene.bracketID]).dissolvableIDs == [scene.assemblyID])

    let refusals: [[SceneNodeID]] = [
        [scene.bracketID],
        [scene.rootID],
        [scene.patternRootID],
        [scene.sealedGroupID],
        [scene.assemblyID, scene.sealedGroupID],
        []
    ]
    for ids in refusals {
        let lifecycle = scene.lifecycle(ids)
        #expect(!lifecycle.canUngroup)
        #expect(lifecycle.dissolvableIDs.isEmpty)
        #expect(lifecycle.ungroupActionTitle == "Ungroup")
    }
}

/// Core refuses a delete that reaches a root, a locked node, or generated pattern output rather than
/// trimming it, so a partly deletable selection has to offer no delete at all. A delete that quietly
/// skipped part of a selection would leave the user believing an object is gone.
@Test(.timeLimit(.minutes(1)))
func outlinerLifecycleDeleteRefusesASelectionItWouldOnlyPartlyRemove() {
    let scene = OutlinerLifecycleScene()

    let pair = scene.lifecycle([scene.bracketID, scene.assemblyID])
    #expect(pair.canDelete)
    #expect(pair.deletableIDs == [scene.bracketID, scene.assemblyID])
    // The pattern root owns its output, so deleting the root is how that output goes away.
    #expect(scene.lifecycle([scene.patternRootID]).deletableIDs == [scene.patternRootID])

    let refusals: [[SceneNodeID]] = [
        [scene.bracketID, scene.rootID],
        [scene.bracketID, scene.sealedGroupID],
        [scene.bracketID, scene.generatedID],
        [scene.rootID],
        [SceneNodeID()],
        []
    ]
    for ids in refusals {
        let lifecycle = scene.lifecycle(ids)
        #expect(!lifecycle.canDelete)
        #expect(lifecycle.deletableIDs.isEmpty)
    }
}

/// A scene holding one row of every kind the lifecycle actions have to answer differently.
private struct OutlinerLifecycleScene {
    let metadata: ProductMetadata
    let projection: OutlinerProjection
    let rootID: SceneNodeID
    let bracketID: SceneNodeID
    let assemblyID: SceneNodeID
    let fittingID: SceneNodeID
    let sealedGroupID: SceneNodeID
    let patternRootID: SceneNodeID
    let generatedID: SceneNodeID

    init() {
        let bracket = SceneNode(name: "Bracket", reference: .body(FeatureID()))
        let pin = SceneNode(name: "Pin", reference: .body(FeatureID()))
        let assembly = SceneNode(name: "Assembly", childIDs: [pin.id])
        let washer = SceneNode(name: "Washer", reference: .body(FeatureID()))
        let fitting = SceneNode(name: "Fitting", childIDs: [washer.id])
        let shim = SceneNode(name: "Shim", reference: .body(FeatureID()))
        let sealedGroup = SceneNode(name: "Sealed", childIDs: [shim.id], isLocked: true)
        let generated = SceneNode(name: "Copy", reference: .body(FeatureID()))
        let patternRoot = SceneNode(name: "Array", childIDs: [generated.id])
        let root = SceneNode(
            name: "Scene",
            childIDs: [bracket.id, assembly.id, fitting.id, sealedGroup.id, patternRoot.id]
        )
        let source = PatternArraySource(
            name: "Array",
            definitionID: ComponentDefinitionID(),
            distribution: .rectangular(
                RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: Vector3D(x: 1, y: 0, z: 0),
                        distance: .scalar(1.0),
                        copyCount: 1
                    )
                )
            ),
            outputMode: .independentCopy,
            outputSceneNodeIDs: [generated.id],
            outputFeatureIDs: [FeatureID()],
            rootSceneNodeID: patternRoot.id
        )
        metadata = ProductMetadata(
            sceneNodes: [
                root.id: root,
                bracket.id: bracket,
                assembly.id: assembly,
                pin.id: pin,
                fitting.id: fitting,
                washer.id: washer,
                sealedGroup.id: sealedGroup,
                shim.id: shim,
                patternRoot.id: patternRoot,
                generated.id: generated
            ],
            rootSceneNodeIDs: [root.id],
            patternArrays: [source.id: source]
        )
        projection = OutlinerProjection.make(
            metadata: metadata,
            expandedIDs: [root.id],
            searchText: "",
            filter: .all
        )
        rootID = root.id
        bracketID = bracket.id
        assemblyID = assembly.id
        fittingID = fitting.id
        sealedGroupID = sealedGroup.id
        patternRootID = patternRoot.id
        generatedID = generated.id
    }

    func lifecycle(_ ids: [SceneNodeID]) -> OutlinerLifecycleAvailability {
        OutlinerLifecycleAvailability(ids: ids, metadata: metadata, projection: projection)
    }
}
