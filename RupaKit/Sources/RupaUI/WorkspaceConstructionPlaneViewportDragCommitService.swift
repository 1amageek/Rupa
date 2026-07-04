import RupaCore
import RupaRendering
import SwiftCAD

struct WorkspaceConstructionPlaneViewportDragCommitService: Sendable {
    struct Edit: Equatable, Sendable {
        var entry: ConstructionPlaneSummaryResult.Entry
        var plane: SketchPlane
        var successMessage: String
    }

    var editBuilder: WorkspaceConstructionPlaneEditBuilder

    init(
        editBuilder: WorkspaceConstructionPlaneEditBuilder = WorkspaceConstructionPlaneEditBuilder()
    ) {
        self.editBuilder = editBuilder
    }

    func edit(
        for target: ViewportConstructionPlaneDragTarget,
        entries: [ConstructionPlaneSummaryResult.Entry]
    ) throws -> Edit? {
        guard let entry = entries.first(where: { plane in
            plane.id == target.constructionPlaneID && plane.sceneNodeID == target.sceneNodeID
        }) else {
            return nil
        }

        switch target.handle {
        case .origin:
            return Edit(
                entry: entry,
                plane: try editBuilder.planeSettingOrigin(target.origin, on: entry.plane),
                successMessage: "Updated construction plane \(entry.name) origin."
            )
        case .normal:
            return Edit(
                entry: entry,
                plane: try editBuilder.planeSettingNormal(target.normal, on: entry.plane),
                successMessage: "Updated construction plane \(entry.name) normal."
            )
        }
    }
}
