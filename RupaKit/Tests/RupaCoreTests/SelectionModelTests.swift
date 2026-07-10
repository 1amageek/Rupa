import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func editorSessionSubobjectSelectionKeepsSceneNodeCompatibility() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation
    let wasDirty = session.isDirty
    let couldUndo = session.commandStack.canUndo
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    let faceTarget = SelectionTarget(
        sceneNodeID: bodyNodeID,
        component: .face(.bodyFaceTop)
    )

    let didSelect = session.selectTarget(faceTarget)

    #expect(didSelect)
    #expect(session.selectedTarget == faceTarget)
    #expect(session.selectedSceneNodeID == bodyNodeID)
    #expect(session.selection.selectedTargets == [faceTarget])
    #expect(session.selection.selectedSceneNodeIDs == [bodyNodeID])
    #expect(session.selection.selectedSceneNodeReferences(in: session.document) == [.body(bodyFeatureID)])
    #expect(session.generation == generation)
    #expect(session.isDirty == wasDirty)
    #expect(session.commandStack.canUndo == couldUndo)

    let didSelectObject = session.selectSceneNode(bodyNodeID)

    #expect(didSelectObject)
    #expect(session.selectedTarget == SelectionTarget(sceneNodeID: bodyNodeID))
    #expect(session.selection.selectedSceneNodeIDs == [bodyNodeID])
}

@MainActor
@Test func selectionModelKeepsMultipleTargetsOnOneSceneNode() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    let topFace = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceTop))
    let bottomFace = SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceBottom))
    var selection = SelectionModel()

    try selection.selectTargets([topFace, topFace, bottomFace], in: session.document)

    #expect(selection.selectedTargets == [topFace, bottomFace])
    #expect(selection.selectedSceneNodeIDs == [bodyNodeID])
    #expect(selection.primaryTarget == bottomFace)
    #expect(selection.primarySceneNodeID == bodyNodeID)

    let encodedSelection = try JSONEncoder().encode(selection)
    let decodedSelection = try JSONDecoder().decode(SelectionModel.self, from: encodedSelection)
    #expect(decodedSelection == selection)
}

@Test func selectionModelRejectsIncompatibleSubobjectTargets() throws {
    let document = DesignDocument.empty()
    let sceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    var selection = SelectionModel()

    do {
        try selection.selectTarget(
            SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop)),
            in: document
        )
        Issue.record("Face targets must require a body scene node.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }

    #expect(selection.selectedTargets.isEmpty)
    #expect(selection.selectedSceneNodeIDs.isEmpty)
}

@Test func selectionModelAcceptsSavedConstructionPlaneTargets() throws {
    var document = DesignDocument.empty()
    _ = try document.createConstructionPlane(
        name: "Selectable Plane",
        plane: .yz
    )
    let summary = ConstructionPlaneSummaryService().summarize(
        document: document,
        activePlaneID: nil
    )
    let entry = try #require(summary.planes.first)
    let target = try #require(entry.selectionTarget())
    var selection = SelectionModel()

    try selection.selectTarget(target, in: document)

    #expect(selection.selectedTargets == [target])
    #expect(selection.selectedSceneNodeIDs == [target.sceneNodeID])
    #expect(selection.selectedSceneNodeReferences(in: document) == [.constructionPlane(entry.id)])
}

@Test func selectionModelRejectsMismatchedConstructionPlaneTargets() throws {
    var document = DesignDocument.empty()
    _ = try document.createConstructionPlane(
        name: "First Plane",
        plane: .yz
    )
    let secondID = try document.createConstructionPlane(
        name: "Second Plane",
        plane: .zx
    )
    let summary = ConstructionPlaneSummaryService().summarize(
        document: document,
        activePlaneID: nil
    )
    let firstEntry = try #require(summary.planes.first { $0.name == "First Plane" })
    let firstSceneNodeID = try #require(firstEntry.sceneNodeID)
    let mismatchedTarget = SelectionTarget(
        sceneNodeID: firstSceneNodeID,
        component: .constructionPlane(secondID)
    )
    var selection = SelectionModel()

    do {
        try selection.selectTarget(mismatchedTarget, in: document)
        Issue.record("Construction plane targets must match their scene node source.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }

    #expect(selection.selectedTargets.isEmpty)
}

@Test func selectionModelAcceptsSketchPointHandleAndControlPointTargets() throws {
    var document = DesignDocument.empty()
    let lineFeatureID = try document.createLineSketch(
        name: "Selectable Line Handles",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
    )
    let splineFeatureID = try document.createSplineSketch(
        name: "Selectable Spline Controls",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            SketchPoint(x: .length(0.004, .meter), y: .length(0.006, .meter)),
            SketchPoint(x: .length(0.008, .meter), y: .length(-0.002, .meter)),
            SketchPoint(x: .length(0.012, .meter), y: .length(0.004, .meter)),
        ])
    )
    let lineSetup = try sketchTargetSetup(
        featureID: lineFeatureID,
        entityKind: "line",
        document: document
    )
    let splineSetup = try sketchTargetSetup(
        featureID: splineFeatureID,
        entityKind: "spline",
        document: document
    )
    let lineEndpointTarget = SelectionTarget(
        sceneNodeID: lineSetup.sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: lineFeatureID,
                entityID: lineSetup.entityID,
                handle: .lineEnd
            )
        )
    )
    let splineControlTarget = SelectionTarget(
        sceneNodeID: splineSetup.sceneNodeID,
        component: .sketchEntity(
            .sketchControlPoint(
                featureID: splineFeatureID,
                entityID: splineSetup.entityID,
                index: 2
            )
        )
    )
    var selection = SelectionModel()

    try selection.selectTargets([lineEndpointTarget, splineControlTarget], in: document)

    #expect(selection.selectedTargets == [lineEndpointTarget, splineControlTarget])
}

@Test func selectionModelRejectsMismatchedSketchPointHandleTargets() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Line Handle Mismatch",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
    )
    let setup = try sketchTargetSetup(
        featureID: featureID,
        entityKind: "line",
        document: document
    )
    let invalidTarget = SelectionTarget(
        sceneNodeID: setup.sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: setup.entityID,
                handle: .arcStart
            )
        )
    )
    var selection = SelectionModel()

    do {
        try selection.selectTarget(invalidTarget, in: document)
        Issue.record("Line entities must not accept arc endpoint handles.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }

    #expect(selection.selectedTargets.isEmpty)
}

@Test func selectionModelCodableUsesSelectionTargetsAsSourceState() throws {
    let sceneNodeID = SceneNodeID()
    let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let selection = SelectionModel(selectedTargets: [target], hoveredTarget: target)

    let data = try JSONEncoder().encode(selection)
    let json = try #require(String(data: data, encoding: .utf8))
    let decodedSelection = try JSONDecoder().decode(SelectionModel.self, from: data)

    #expect(json.contains("selectedTargets"))
    #expect(!json.contains("selectedSceneNodeIDs"))
    #expect(decodedSelection == selection)
    #expect(decodedSelection.selectedSceneNodeIDs == [sceneNodeID])
    #expect(decodedSelection.hoveredSceneNodeID == sceneNodeID)
}

@Test func selectionModelAcceptsSurfaceControlPointReferences() throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Selectable Surface CV",
        sourceMesh: selectionModelSurfaceQuadMesh(),
        options: PolySplineOptions()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let reference = controlPoint.selectionReference
    var selection = SelectionModel()

    try selection.selectReference(reference, in: document)
    try selection.hoverReference(reference, in: document)

    #expect(selection.selectedTargets.isEmpty)
    #expect(selection.selectedReferences == [reference])
    #expect(selection.primaryReference == reference)
    #expect(selection.hoveredReference == reference)

    let data = try JSONEncoder().encode(selection)
    let decodedSelection = try JSONDecoder().decode(SelectionModel.self, from: data)
    #expect(decodedSelection == selection)
}

@Test func selectionModelAcceptsSurfaceTrimReferences() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Selectable Surface Trim",
        surface: selectionModelDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let reference = try #require(
        summary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first
    )
    var selection = SelectionModel()

    try selection.selectReference(reference, in: document)
    try selection.hoverReference(reference, in: document)

    #expect(selection.selectedTargets.isEmpty)
    #expect(selection.selectedReferences == [reference])
    #expect(selection.primaryReference == reference)
    #expect(selection.hoveredReference == reference)

    let data = try JSONEncoder().encode(selection)
    let decodedSelection = try JSONDecoder().decode(SelectionModel.self, from: data)
    #expect(decodedSelection == selection)
}

@Test func selectionModelAcceptsDirectSurfaceBasisReferences() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Selectable Surface Basis",
        surface: selectionModelEditableDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let parameterReference = try #require(patch.parameterAddresses.first { $0.id == "center" }?.selectionReference)
    let knotReference = try #require(patch.basis.uKnotVector.first { $0.index == 3 }?.selectionReference)
    let spanReference = try #require(patch.basis.uSpans.first { $0.index == 0 }?.selectionReference)
    var selection = SelectionModel()

    try selection.selectReferences([parameterReference, knotReference, spanReference], in: document)
    try selection.hoverReference(spanReference, in: document)

    #expect(selection.selectedTargets.isEmpty)
    #expect(selection.selectedReferences == [parameterReference, knotReference, spanReference])
    #expect(selection.primaryReference == spanReference)
    #expect(selection.hoveredReference == spanReference)

    let data = try JSONEncoder().encode(selection)
    let decodedSelection = try JSONDecoder().decode(SelectionModel.self, from: data)
    #expect(decodedSelection == selection)
}

@Test func selectionModelPrunesMissingSubobjectTargets() throws {
    let missingID = SceneNodeID()
    var selection = SelectionModel(
        selectedTargets: [
            SelectionTarget(sceneNodeID: missingID, component: .face(.bodyFaceTop)),
        ],
        hoveredTarget: SelectionTarget(sceneNodeID: missingID, component: .face(.bodyFaceTop))
    )

    selection.pruneMissingReferences(in: .empty())

    #expect(selection.selectedTargets.isEmpty)
    #expect(selection.selectedSceneNodeIDs.isEmpty)
    #expect(selection.hoveredTarget == nil)
    #expect(selection.hoveredSceneNodeID == nil)
}

private func selectionModelSurfaceQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.0),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

private func selectionModelDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func selectionModelEditableDirectBSplineSurface() -> BSplineSurface3D {
    let baseSurface = selectionModelDirectBSplineSurface()
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: baseSurface.controlPoints
    )
}

private func sketchTargetSetup(
    featureID: FeatureID,
    entityKind: String,
    document: DesignDocument
) throws -> (
    sceneNodeID: SceneNodeID,
    entityID: SketchEntityID
) {
    let summary = try SketchEntitySnapshotService().snapshot(document: document)
    let entry = try #require(summary.entries.first { entry in
        entry.sourceFeatureID == featureID.description && entry.entityKind == entityKind
    })
    let target = try #require(entry.selectionTarget())
    let entityUUID = try #require(UUID(uuidString: entry.entityID))
    return (target.sceneNodeID, SketchEntityID(entityUUID))
}

@Test func selectionModelPrunesIncompatibleSubobjectTargets() throws {
    let document = DesignDocument.empty()
    let sceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    var selection = SelectionModel(
        selectedTargets: [
            SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop)),
        ],
        hoveredTarget: SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    )

    selection.pruneMissingReferences(in: document)

    #expect(selection.selectedTargets.isEmpty)
    #expect(selection.selectedSceneNodeIDs.isEmpty)
    #expect(selection.hoveredTarget == nil)
    #expect(selection.hoveredSceneNodeID == nil)
}
