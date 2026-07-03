import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceSectionAnalysisStateBuilderResolvesSelectedSectionPlane() throws {
    var document = try workspaceSectionAnalysisDocument()
    let sectionNodeID = try document.createSectionPlane(name: "Mid Height Section")
    try document.setSceneNodeTransform(
        id: sectionNodeID,
        localTransform: Transform3D(
            matrix: try Matrix4x4(values: [
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 1.0, 1.0,
            ])
        )
    )
    let node = try #require(document.productMetadata.sceneNodes[sectionNodeID])
    let builder = WorkspaceSectionAnalysisStateBuilder(
        document: document,
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn
    )

    let analysis = try #require(try builder.analysisSummaryResult(for: [node]).get())

    #expect(analysis.plane.sourceKind == .sceneNode)
    #expect(analysis.plane.sourceID == sectionNodeID.description)
    #expect(analysis.intersectingBodyCount == 1)
    #expect(analysis.intersectionSegments.isEmpty == false)
}

@Test func workspaceSectionAnalysisStateBuilderIgnoresBodySelection() throws {
    let document = try workspaceSectionAnalysisDocument()
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first { node in
        node.reference?.kind == .body
    })
    let builder = WorkspaceSectionAnalysisStateBuilder(
        document: document,
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn
    )

    let analysis = try builder.analysisSummaryResult(for: [bodyNode]).get()

    #expect(analysis == nil)
}

private func workspaceSectionAnalysisDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Workspace Section Analysis Fixture")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Section Fixture Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-1.0, .meter),
            y: .length(-1.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0, .meter),
            y: .length(1.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Section Fixture Body",
        profile: ProfileReference(featureID: profileID),
        distance: .length(2.0, .meter),
        direction: .normal
    )
    return document
}
