import Foundation
import RupaCore
import SwiftCAD

enum WorkspaceLaunchSessionTestFixture {
    static let selectedCustomConstructionPlaneArgument =
        "--rupa-ui-fixture=selected-custom-cplane"
    static let customConstructionPlaneName = "Arbitrary CPlane"

    static func makeSelectedCustomConstructionPlaneSession() throws -> EditorSession {
        let session = EditorSession()
        let normal = try Vector3D(x: 0.35, y: 0.82, z: 0.45)
            .normalized(tolerance: 1.0e-12)
        let plane = SketchPlane.plane(
            Plane3D(
                origin: Point3D(x: 0.12, y: 0.08, z: -0.06),
                normal: normal
            )
        )
        guard let result = session.createConstructionPlane(
            name: customConstructionPlaneName,
            plane: plane
        ),
        let id = result.createdConstructionPlaneID,
        session.setActiveConstructionPlane(id: id) != nil else {
            throw WorkspaceLaunchSessionTestFixtureError.fixtureCommandRejected
        }
        let summary = ConstructionPlaneSummaryService().summarize(
            document: session.document,
            activePlaneID: session.workspaceState.activeConstructionPlaneID
        )
        guard let entry = summary.planes.first(where: {
            $0.name == customConstructionPlaneName
        }),
        let target = entry.selectionTarget(),
        session.selectTarget(target) else {
            throw WorkspaceLaunchSessionTestFixtureError.fixtureSelectionRejected
        }
        return session
    }
}

private enum WorkspaceLaunchSessionTestFixtureError: Error {
    case fixtureCommandRejected
    case fixtureSelectionRejected
}
