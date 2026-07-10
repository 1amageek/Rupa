import Foundation
import RupaCore
import SwiftCAD

public enum WorkspaceLaunchSessionFactory {
    public static let activeCustomConstructionPlaneFixtureArgument =
        "--rupa-ui-fixture=active-custom-cplane"
    public static let selectedCustomConstructionPlaneFixtureArgument =
        "--rupa-ui-fixture=selected-custom-cplane"
    public static let activeCustomConstructionPlaneFixtureName = "Arbitrary CPlane"

    public static func makeSession(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> EditorSession {
        let session = EditorSession()
        let installsCustomPlane = arguments.contains(activeCustomConstructionPlaneFixtureArgument)
            || arguments.contains(selectedCustomConstructionPlaneFixtureArgument)
        guard installsCustomPlane else {
            return session
        }

        do {
            try installActiveCustomConstructionPlane(in: session)
            if arguments.contains(selectedCustomConstructionPlaneFixtureArgument) {
                try selectActiveCustomConstructionPlane(in: session)
            }
        } catch {
            session.reportToolStatus(
                "Failed to install launch construction-plane fixture: \(error)",
                severity: .warning
            )
        }
        return session
    }

    private static func installActiveCustomConstructionPlane(
        in session: EditorSession
    ) throws {
        let normal = try Vector3D(x: 0.35, y: 0.82, z: 0.45)
            .normalized(tolerance: 1.0e-12)
        let plane = SketchPlane.plane(
            Plane3D(
                origin: Point3D(x: 0.12, y: 0.08, z: -0.06),
                normal: normal
            )
        )
        guard let result = session.createConstructionPlane(
            name: activeCustomConstructionPlaneFixtureName,
            plane: plane
        ),
        let id = result.createdConstructionPlaneID,
        session.setActiveConstructionPlane(id: id) != nil else {
            throw WorkspaceLaunchSessionFactoryError.fixtureCommandRejected
        }
    }

    private static func selectActiveCustomConstructionPlane(
        in session: EditorSession
    ) throws {
        let summary = ConstructionPlaneSummaryService().summarize(
            document: session.document,
            activePlaneID: session.workspaceState.activeConstructionPlaneID
        )
        guard let entry = summary.planes.first(where: {
            $0.name == activeCustomConstructionPlaneFixtureName
        }) else {
            throw WorkspaceLaunchSessionFactoryError.fixturePlaneMissing
        }
        guard let target = entry.selectionTarget() else {
            throw WorkspaceLaunchSessionFactoryError.fixtureSelectionTargetMissing
        }
        guard session.selectTarget(target) else {
            throw WorkspaceLaunchSessionFactoryError.fixtureSelectionRejected
        }
    }
}

private enum WorkspaceLaunchSessionFactoryError: LocalizedError {
    case fixtureCommandRejected
    case fixturePlaneMissing
    case fixtureSelectionTargetMissing
    case fixtureSelectionRejected

    var errorDescription: String? {
        switch self {
        case .fixtureCommandRejected:
            return "The construction-plane fixture command was rejected."
        case .fixturePlaneMissing:
            return "The construction-plane fixture was not present after creation."
        case .fixtureSelectionTargetMissing:
            return "The construction-plane fixture did not produce a selectable scene target."
        case .fixtureSelectionRejected:
            return "The construction-plane fixture selection was rejected."
        }
    }
}
