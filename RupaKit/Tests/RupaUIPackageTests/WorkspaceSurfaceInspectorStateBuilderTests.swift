import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceSurfaceInspectorStateBuilderResolvesSurfaceObjectAnalysisAndContinuity() throws {
    let fixture = try workspaceSurfaceInspectorFixture()
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: fixture.sceneNode.id)]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let analysis = try #require(try builder.analysisResult(for: [fixture.sceneNode]).get())
    let continuity = try #require(try builder.continuityResult(for: [fixture.sceneNode]).get())

    #expect(builder.showsContinuitySection(for: [fixture.sceneNode]))
    #expect(analysis.bSplineFaceCount == 2)
    #expect(analysis.sampleCount == 50)
    #expect(analysis.trimBoundaryEdgeCount == 8)
    #expect(continuity.bSplineFaceCount == 2)
    #expect(continuity.sharedEdgeCount == 1)
    #expect(continuity.adjacencies.count == 1)
}

@Test func workspaceSurfaceInspectorStateBuilderFiltersGeneratedFaceSelection() throws {
    let fixture = try workspaceSurfaceInspectorFixture()
    let objectBuilder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: fixture.sceneNode.id)]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )
    let fullAnalysis = try #require(try objectBuilder.analysisResult(for: [fixture.sceneNode]).get())
    let faceName = try #require(fullAnalysis.faces.first?.facePersistentNames.first)
    let topology = try TopologySnapshotService().snapshot(document: fixture.document)
    let faceEntry = try #require(
        topology.entries.first {
            $0.kind == .face && workspaceSurfaceStableTopologyKey($0.stableReference) == faceName
        }
    )
    let faceTarget = try #require(faceEntry.selectionTarget())
    let faceBuilder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [faceTarget]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let filteredAnalysis = try #require(try faceBuilder.analysisResult(for: [fixture.sceneNode]).get())

    #expect(faceBuilder.selectedStableTopologyKeys() == [faceName])
    #expect(faceBuilder.showsContinuitySection(for: [fixture.sceneNode]))
    #expect(filteredAnalysis.bSplineFaceCount == 1)
    #expect(filteredAnalysis.faces.first?.facePersistentNames.contains(faceName) == true)
}

@Test func workspaceSurfaceInspectorStateBuilderResolvesControlPointSelection() throws {
    let fixture = try workspaceSurfaceInspectorFixture()
    let summary = try SurfaceSourceSummaryService().summarize(document: fixture.document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedReferences: [controlPoint.selectionReference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let state = try #require(try builder.surfaceControlPointStateResult().get())

    #expect(builder.surfaceControlPointReferences == [controlPoint.selectionReference])
    #expect(state.selectedReferences == [controlPoint.selectionReference])
    #expect(state.canEditCoordinates)
    #expect(state.entries.first?.isEditable == true)
    #expect(state.entries.first?.isBoundary == false)
}

@Test func workspaceSurfaceInspectorStateBuilderExposesSurfaceBasisSelection() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Inspector Basis Surface",
        surface: workspaceSurfaceInspectorDirectBSplineSurface()
    )
    let sceneNode = try workspaceSurfaceInspectorSceneNode(
        featureID: featureID,
        in: document
    )
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: sceneNode.id)]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let state = try #require(try builder.surfaceBasisStateResult(for: [sceneNode]).get())

    #expect(state.sourceCount == 1)
    #expect(state.patchCount == 1)
    #expect(state.spanCount > 0)
    #expect(state.knotCount > 0)
    #expect(state.entries.allSatisfy { $0.sourceID == featureID.description })
    #expect(state.firstSelectableReference != nil)
    #expect(state.firstEditableSpanReference != nil)
}

@Test func workspaceSurfaceInspectorStateBuilderFiltersSurfaceBasisByGeneratedFaceSelection() throws {
    var document = DesignDocument.empty()
    let firstFeatureID = try document.createBSplineSurface(
        name: "First Inspector Basis Surface",
        surface: workspaceSurfaceInspectorDirectBSplineSurface()
    )
    let secondFeatureID = try document.createBSplineSurface(
        name: "Second Inspector Basis Surface",
        surface: workspaceSurfaceInspectorOffsetDirectBSplineSurface()
    )
    let firstSceneNode = try workspaceSurfaceInspectorSceneNode(
        featureID: firstFeatureID,
        in: document
    )
    let secondSceneNode = try workspaceSurfaceInspectorSceneNode(
        featureID: secondFeatureID,
        in: document
    )
    let nodes = [firstSceneNode, secondSceneNode]
    let objectBuilder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedTargets: nodes.map { SelectionTarget(sceneNodeID: $0.id) }),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )
    let objectState = try #require(try objectBuilder.surfaceBasisStateResult(for: nodes).get())
    let firstFeatureEntry = try #require(objectState.entries.first { entry in
        entry.sourceID == firstFeatureID.description
    })
    let faceName = try #require(firstFeatureEntry.facePersistentName)
    let topology = try TopologySnapshotService().snapshot(document: document)
    let faceEntry = try #require(
        topology.entries.first {
            $0.kind == .face && workspaceSurfaceStableTopologyKey($0.stableReference) == faceName
        }
    )
    let faceTarget = try #require(faceEntry.selectionTarget())
    let faceBuilder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedTargets: [faceTarget]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let faceState = try #require(try faceBuilder.surfaceBasisStateResult(for: nodes).get())

    #expect(faceState.sourceCount == 1)
    #expect(faceState.patchCount == 1)
    #expect(faceState.spanCount > 0)
    #expect(faceState.knotCount > 0)
    #expect(faceState.entries.allSatisfy { $0.facePersistentName == faceName })
    #expect(faceState.entries.allSatisfy { $0.sourceID == firstFeatureID.description })
    #expect(faceState.entries.count < objectState.entries.count)
}

@Test func workspaceSurfaceInspectorStateBuilderResolvesBoundaryContinuitySelection() throws {
    var document = DesignDocument.empty()
    let firstFeatureID = try document.createBSplineSurface(
        name: "First Direct Boundary Surface",
        surface: workspaceSurfaceInspectorDirectBSplineSurface()
    )
    let secondFeatureID = try document.createBSplineSurface(
        name: "Second Direct Boundary Surface",
        surface: workspaceSurfaceInspectorOffsetDirectBSplineSurface()
    )
    let firstReference = try workspaceSurfaceInspectorTrimReference(
        featureID: firstFeatureID,
        edgeIndex: 2,
        in: document
    )
    let secondReference = try workspaceSurfaceInspectorTrimReference(
        featureID: secondFeatureID,
        edgeIndex: 0,
        in: document
    )
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedReferences: [secondReference, firstReference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let state = try #require(try builder.surfaceBoundaryContinuityStateResult().get())

    #expect(builder.surfaceTrimReferences == [secondReference, firstReference])
    #expect(state.canMatch)
    #expect(state.targetReference == secondReference)
    #expect(state.referenceReference == firstReference)
    #expect(state.targetSupportedLevelSummary == "G0 / G1 / G2")
    #expect(state.referenceSupportedLevelSummary == "G0 / G1 / G2")
    #expect(state.pairSupportedLevelSummary == "G0 / G1 / G2")
    #expect(state.supports(.g2))
    #expect(state.recommendedReferenceDirectionSummary == "forward")
    #expect(state.recommendedMatchSideSummary == "opposite")
    #expect(state.diagnosticMessages.contains("Boundary pair supports G0/G1/G2 continuity matching."))
    #expect(state.statusTitle == "Compatible")

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let unavailableState = SurfaceBoundaryContinuityInspectorState(
        selectedReferences: [secondReference, firstReference],
        summaryResult: summary,
        compatibilityErrorMessage: "Boundary preflight failed."
    )
    #expect(!unavailableState.canMatch)
    #expect(unavailableState.statusTitle == "Unavailable")
    #expect(unavailableState.diagnosticMessages == ["Boundary preflight failed."])

    let g0OnlyCompatibility = SurfaceBoundaryContinuityCompatibilityResult(
        status: .compatible,
        target: SurfaceBoundaryContinuityCompatibilityResult.Boundary(
            featureID: secondFeatureID,
            selectionReference: secondReference,
            role: "vMin",
            boundaryDirection: .u,
            inwardDirection: .v,
            boundaryDegree: 3,
            inwardDegree: 1,
            boundaryControlPointCount: 4,
            inwardControlPointCount: 1,
            isClamped: true,
            supportedContinuityLevels: [.g0]
        ),
        reference: SurfaceBoundaryContinuityCompatibilityResult.Boundary(
            featureID: firstFeatureID,
            selectionReference: firstReference,
            role: "vMax",
            boundaryDirection: .u,
            inwardDirection: .v,
            boundaryDegree: 3,
            inwardDegree: 1,
            boundaryControlPointCount: 4,
            inwardControlPointCount: 1,
            isClamped: true,
            supportedContinuityLevels: [.g0]
        ),
        supportedContinuityLevels: [.g0],
        maximumSupportedContinuityLevel: .g0,
        recommendedReferenceDirection: .forward,
        recommendedMatchSide: nil,
        diagnostics: []
    )
    let g0OnlyState = SurfaceBoundaryContinuityInspectorState(
        selectedReferences: [secondReference, firstReference],
        summaryResult: summary,
        compatibilityResult: g0OnlyCompatibility
    )
    #expect(g0OnlyState.canMatch)
    #expect(g0OnlyState.pairSupportedLevelSummary == "G0")
    #expect(g0OnlyState.resolvedContinuityLevel(preferred: .g2) == .g0)
}

@Test func workspaceSurfaceInspectorStateBuilderExposesTrimDomainEditingSelection() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Trim Domain Surface",
        surface: workspaceSurfaceInspectorDirectBSplineSurface()
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    try document.setSurfaceTrimDomain(
        target: faceReference,
        uLowerBound: .scalar(0.25),
        uUpperBound: .scalar(0.75),
        vLowerBound: .scalar(0.2),
        vUpperBound: .scalar(0.8)
    )
    let trimReference = try workspaceSurfaceInspectorTrimReference(
        featureID: featureID,
        edgeIndex: 0,
        in: document
    )
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedReferences: [trimReference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let state = try #require(try builder.surfaceBoundaryContinuityStateResult().get())
    let trimDomain = try #require(state.trimDomain)

    #expect(state.selectedTrimCount == 1)
    #expect(!state.canMatch)
    #expect(trimDomain.targetReference == trimReference)
    #expect(trimDomain.uLowerBound == 0.25)
    #expect(trimDomain.uUpperBound == 0.75)
    #expect(trimDomain.vLowerBound == 0.2)
    #expect(trimDomain.vUpperBound == 0.8)
    #expect(trimDomain.fullULowerBound == 0.0)
    #expect(trimDomain.fullUUpperBound == 1.0)
    #expect(trimDomain.fullVLowerBound == 0.0)
    #expect(trimDomain.fullVUpperBound == 1.0)
    #expect(!trimDomain.isFullDomain)
}

@Test func workspaceSurfaceInspectorStateBuilderRejectsPolySplineBoundaryContinuitySelection() throws {
    let fixture = try workspaceSurfaceInspectorFixture()
    let summary = try SurfaceSourceSummaryService().summarize(document: fixture.document, displayUnit: .millimeter)
    let firstReference = try #require(summary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first)
    let secondReference = try #require(summary.sources.first?.patches.last?.trimLoops.first?.selectionReferences.first)
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedReferences: [firstReference, secondReference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let state = try #require(try builder.surfaceBoundaryContinuityStateResult().get())

    #expect(!state.canMatch)
    #expect(state.selectedTrimCount == 2)
    #expect(state.targetSupportedLevelSummary == nil)
    #expect(state.referenceSupportedLevelSummary == nil)
    #expect(state.statusTitle == "Supported direct B-spline trim edges required")
}

private struct WorkspaceSurfaceInspectorFixture {
    var document: DesignDocument
    var featureID: FeatureID
    var sceneNode: SceneNode
}

private func workspaceSurfaceInspectorFixture() throws -> WorkspaceSurfaceInspectorFixture {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Inspector Surface",
        sourceMesh: workspaceSurfaceInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first { node in
        node.reference?.featureID == featureID && node.object?.geometryRole == .surface
    })
    return WorkspaceSurfaceInspectorFixture(
        document: document,
        featureID: featureID,
        sceneNode: sceneNode
    )
}

private func workspaceSurfaceInspectorDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func workspaceSurfaceInspectorOffsetDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.04, z: 0.002),
        bottomRight: Point3D(x: 0.02, y: 0.04, z: -0.002),
        topRight: Point3D(x: 0.02, y: 0.06, z: 0.001),
        topLeft: Point3D(x: 0.0, y: 0.06, z: 0.003)
    )
}

private func workspaceSurfaceInspectorSceneNode(
    featureID: FeatureID,
    in document: DesignDocument
) throws -> SceneNode {
    try #require(document.productMetadata.sceneNodes.values.first { node in
        node.reference?.featureID == featureID && node.object?.geometryRole == .surface
    })
}

private func workspaceSurfaceInspectorTrimReference(
    featureID: FeatureID,
    edgeIndex: Int,
    in document: DesignDocument
) throws -> SelectionReference {
    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let source = try #require(summary.sources.first { $0.featureID == featureID.description })
    let trimLoop = try #require(source.patches.first?.trimLoops.first)
    guard trimLoop.selectionReferences.indices.contains(edgeIndex) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Workspace surface trim reference is missing."
        )
    }
    return trimLoop.selectionReferences[edgeIndex]
}

private func workspaceSurfaceStableTopologyKey(
    _ reference: StableSubshapeReference
) -> String {
    let id = reference.subshapeID
    return "feature:\(id.featureID.description)/role:\(id.role)/ordinal:\(id.ordinal)"
}

private func workspaceSurfaceInspectorPatchNetworkMesh(centerZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}
