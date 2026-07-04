import Foundation
import RupaCore
import SwiftCAD

public enum WorkspaceLaunchSessionFactory {
    public static let activeCustomConstructionPlaneFixtureArgument =
        "--rupa-ui-fixture=active-custom-cplane"
    public static let activeCustomConstructionPlaneFixtureName = "Arbitrary CPlane"

    public static func makeSession(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> EditorSession {
        let session = EditorSession()
        guard arguments.contains(activeCustomConstructionPlaneFixtureArgument) else {
            return session
        }

        do {
            try installActiveCustomConstructionPlane(in: session)
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
        guard session.createConstructionPlane(
            name: activeCustomConstructionPlaneFixtureName,
            plane: plane,
            activates: true
        ) != nil else {
            throw WorkspaceLaunchSessionFactoryError.fixtureCommandRejected
        }
    }
}

private enum WorkspaceLaunchSessionFactoryError: Error {
    case fixtureCommandRejected
}
