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
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
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
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
    )
    let fullAnalysis = try #require(try objectBuilder.analysisResult(for: [fixture.sceneNode]).get())
    let faceName = try #require(fullAnalysis.faces.first?.facePersistentNames.first)
    let faceTarget = SelectionTarget(
        sceneNodeID: fixture.sceneNode.id,
        component: .face(.generatedTopology(faceName))
    )
    let faceBuilder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [faceTarget]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
    )

    let filteredAnalysis = try #require(try faceBuilder.analysisResult(for: [fixture.sceneNode]).get())

    #expect(faceBuilder.generatedTopologyPersistentNames() == [faceName])
    #expect(faceBuilder.showsContinuitySection(for: [fixture.sceneNode]))
    #expect(filteredAnalysis.bSplineFaceCount == 1)
    #expect(filteredAnalysis.faces.first?.facePersistentNames.contains(faceName) == true)
}

@Test func workspaceSurfaceInspectorStateBuilderResolvesControlPointSelection() throws {
    let fixture = try workspaceSurfaceInspectorFixture()
    let summary = try SurfaceSourceSummaryService().summarize(document: fixture.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedReferences: [controlPoint.selectionReference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
    )

    let state = try #require(try builder.surfaceControlPointStateResult().get())

    #expect(builder.surfaceControlPointReferences == [controlPoint.selectionReference])
    #expect(state.selectedReferences == [controlPoint.selectionReference])
    #expect(state.canEditCoordinates)
    #expect(state.entries.first?.isEditable == true)
    #expect(state.entries.first?.isBoundary == false)
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
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
    )

    let state = try #require(try builder.surfaceBoundaryContinuityStateResult().get())

    #expect(builder.surfaceTrimReferences == [secondReference, firstReference])
    #expect(state.canMatch)
    #expect(state.targetReference == secondReference)
    #expect(state.referenceReference == firstReference)
    #expect(state.targetSupportedLevelSummary == "G0 / G1 / G2")
    #expect(state.referenceSupportedLevelSummary == "G0 / G1 / G2")
    #expect(state.statusTitle == "Ready")
}

@Test func workspaceSurfaceInspectorStateBuilderRejectsPolySplineBoundaryContinuitySelection() throws {
    let fixture = try workspaceSurfaceInspectorFixture()
    let summary = try SurfaceSourceSummaryService().summarize(document: fixture.document)
    let firstReference = try #require(summary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first)
    let secondReference = try #require(summary.sources.first?.patches.last?.trimLoops.first?.selectionReferences.first)
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedReferences: [firstReference, secondReference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
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

private func workspaceSurfaceInspectorTrimReference(
    featureID: FeatureID,
    edgeIndex: Int,
    in document: DesignDocument
) throws -> SelectionReference {
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
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
