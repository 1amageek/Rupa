import SwiftCAD
import Testing
import RupaRendering
@testable import RupaUI

@Test(.timeLimit(.minutes(1))) func workspaceSidebarAndInspectorNavigationUseStablePresentationCases() {
    #expect(WorkspaceSidebarSection.allCases == [.scene, .history])
    #expect(WorkspaceSidebarSection.scene.title == "Scene")
    #expect(WorkspaceSidebarSection.history.title == "History")

    #expect(WorkspaceInspectorTab.allCases == [.properties, .definitions])
    #expect(WorkspaceInspectorTab.properties.title == "Properties")
    #expect(WorkspaceInspectorTab.definitions.title == "Definitions")
    #expect(ViewportDisplayMode.allCases.map(viewportDisplayModeTitle) == [
        "Solid", "Solid + Mesh Edges", "Wireframe", "Normals"
    ])
}

@Test(.timeLimit(.minutes(1))) func featureHistoryReorderCommandPreservesFullOrderWhenSearchFiltersNodes() throws {
    let primitive = FeatureOperation.primitive(
        PrimitiveFeature(
            definition: .box(
                BoxPrimitive(
                    width: .constant(.length(1.0, unit: .meter)),
                    depth: .constant(.length(1.0, unit: .meter)),
                    height: .constant(.length(1.0, unit: .meter))
                )
            )
        )
    )
    let first = FeatureNode(name: "First", operation: primitive)
    let second = FeatureNode(name: "Second", operation: primitive)
    let third = FeatureNode(name: "Third", operation: primitive)
    let orderedFeatures = [first, second, third]
    let visibleFeatureIDs: Set<FeatureID> = [first.id, third.id]

    let command = try #require(
        featureHistoryReorderCommand(
            orderedFeatures: orderedFeatures,
            visibleFeatureIDs: visibleFeatureIDs,
            movingFeatureID: first.id,
            offset: 1
        )
    )

    #expect(command == .reorderFeatureGraph(featureIDs: [second.id, first.id, third.id]))
    #expect(
        featureHistoryReorderCommand(
            orderedFeatures: orderedFeatures,
            visibleFeatureIDs: visibleFeatureIDs,
            movingFeatureID: second.id,
            offset: 1
        ) == nil
    )
}
