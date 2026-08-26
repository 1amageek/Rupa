import Foundation
import RupaCore
import RupaKit
import RupaProject
import SwiftCAD

public enum WorkspaceLaunchProjectFixture {
    public static let activeCustomConstructionPlaneArgument =
        "--rupa-ui-fixture=active-custom-cplane"
    public static let selectedCustomConstructionPlaneArgument =
        "--rupa-ui-fixture=selected-custom-cplane"
    public static let customConstructionPlaneName = "Arbitrary CPlane"

    @discardableResult
    @MainActor
    public static func applyIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        to workspace: ProjectWorkspace
    ) async throws -> ProjectViewSnapshot {
        guard let initial = workspace.view else {
            throw WorkspaceLaunchProjectFixtureError.projectViewUnavailable
        }
        let installsCustomPlane = arguments.contains(activeCustomConstructionPlaneArgument)
            || arguments.contains(selectedCustomConstructionPlaneArgument)
        guard installsCustomPlane else {
            return initial
        }

        let normal = try Vector3D(x: 0.35, y: 0.82, z: 0.45)
            .normalized(tolerance: 1.0e-12)
        let plane = SketchPlane.plane(
            Plane3D(
                origin: Point3D(x: 0.12, y: 0.08, z: -0.06),
                normal: normal
            )
        )
        let created = try await workspace.commit(
            ProjectSourceTransaction(
                name: "launchFixture.createConstructionPlane",
                commands: [
                    .createConstructionPlane(
                        name: customConstructionPlaneName,
                        plane: plane
                    ),
                ],
                expectedProjectID: initial.projectID,
                expectedTransactionRevision: initial.transactionRevision,
                expectedPublicationSequence: initial.publicationSequence
            )
        )
        let summary = ConstructionPlaneSummaryService().summarize(
            document: created.document.document,
            activePlaneID: created.workspaceState.activeConstructionPlaneID
        )
        guard let entry = summary.planes.first(where: {
            $0.name == customConstructionPlaneName
        }) else {
            throw WorkspaceLaunchProjectFixtureError.fixturePlaneMissing
        }
        let active = try await workspace.applyWorkspace(
            .setActiveConstructionPlane(entry.id)
        )
        guard arguments.contains(selectedCustomConstructionPlaneArgument) else {
            return active
        }
        guard let target = entry.selectionTarget() else {
            throw WorkspaceLaunchProjectFixtureError.fixtureSelectionTargetMissing
        }
        return try await workspace.applySelection(.replace(SelectionModel(selectedTargets: [target])))
    }
}

public enum WorkspaceLaunchProjectFixtureError: Error, LocalizedError, Sendable {
    case projectViewUnavailable
    case fixturePlaneMissing
    case fixtureSelectionTargetMissing

    public var errorDescription: String? {
        switch self {
        case .projectViewUnavailable:
            "The project must publish its initial view before applying a launch fixture."
        case .fixturePlaneMissing:
            "The construction-plane launch fixture was not present after creation."
        case .fixtureSelectionTargetMissing:
            "The construction-plane launch fixture did not produce a selectable scene target."
        }
    }
}
