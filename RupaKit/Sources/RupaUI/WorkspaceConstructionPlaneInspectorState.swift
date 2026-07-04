import RupaCore
import SwiftCAD

struct WorkspaceConstructionPlaneInspectorState: Equatable, Sendable {
    var id: ConstructionPlaneSourceID
    var name: String
    var sceneNodeID: SceneNodeID?
    var isActive: Bool
    var planeKindTitle: String
    var origin: Point3D
    var normal: Vector3D

    init(
        entry: ConstructionPlaneSummaryResult.Entry,
        editBuilder: WorkspaceConstructionPlaneEditBuilder = WorkspaceConstructionPlaneEditBuilder()
    ) {
        self.id = entry.id
        self.name = entry.name
        self.sceneNodeID = entry.sceneNodeID
        self.isActive = entry.isActive
        self.planeKindTitle = Self.planeKindTitle(entry.plane)
        self.origin = editBuilder.origin(from: entry.plane)
        self.normal = editBuilder.normal(from: entry.plane)
    }

    private static func planeKindTitle(_ plane: SketchPlane) -> String {
        switch plane {
        case .xy:
            "XY"
        case .yz:
            "YZ"
        case .zx:
            "ZX"
        case .plane:
            "Custom"
        }
    }
}
