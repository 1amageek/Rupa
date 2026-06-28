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
