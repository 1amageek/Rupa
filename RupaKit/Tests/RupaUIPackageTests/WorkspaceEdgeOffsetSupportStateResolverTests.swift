import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceEdgeOffsetSupportStateResolverRequiresOneSelectedEdgeTarget() throws {
    let sceneNodeID = SceneNodeID()
    let firstTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceTestEdgeComponent(role: "edge.first"))
    )
    let secondTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceTestEdgeComponent(role: "edge.second"))
    )
    let resolver = WorkspaceEdgeOffsetSupportStateResolver(
        document: .empty(),
        selection: SelectionModel(selectedTargets: [firstTarget, secondTarget]),
        objectRegistry: .builtIn
    )

    let resolution = resolver.resolution(for: [firstTarget, secondTarget])

    #expect(resolution.status == .unavailable)
    #expect(resolution.diagnosticMessage == "Offset Edge currently supports one selected edge.")
    #expect(resolver.supportTitle(for: resolution) == "Missing")
}

@Test func workspaceEdgeOffsetSupportStateResolverReportsUnsupportedForNonEdgeTarget() {
    let target = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let resolver = WorkspaceEdgeOffsetSupportStateResolver(
        document: .empty(),
        selection: SelectionModel(selectedTargets: [target]),
        objectRegistry: .builtIn
    )

    let resolution = resolver.resolution(for: [target])

    #expect(resolution.status == .notApplicable)
    #expect(resolution.diagnosticMessage == "Offset Edge support face inference requires an edge target.")
    #expect(resolver.supportTitle(for: resolution) == "Unsupported")
}

@Test func workspaceEdgeOffsetSupportStateResolverMapsSupportTitles() throws {
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .face(try workspaceTestFaceComponent(role: "face.support"))
    )
    let resolver = WorkspaceEdgeOffsetSupportStateResolver(
        document: .empty(),
        selection: .empty,
        objectRegistry: .builtIn
    )

    #expect(resolver.supportTitle(for: .supported(target, source: .selectedFace)) == "Selected Face")
    #expect(resolver.supportTitle(for: .supported(target, source: .inferredCapFace)) == "Cap Face")
    #expect(
        resolver.supportTitle(
            for: EdgeOffsetSupportFaceResolution(status: .supported, supportTarget: target)
        ) == "Ready"
    )
    #expect(resolver.supportTitle(for: .ambiguous("ambiguous")) == "Ambiguous")
    #expect(resolver.supportTitle(for: .unavailable("missing")) == "Missing")
    #expect(resolver.supportTitle(for: .notApplicable("unsupported")) == "Unsupported")
}
