import Foundation
import SwiftCAD

public struct ConstructionPlaneViewResolver: Sendable {
    public init() {}

    public func plane(
        origin: Point3D = .origin,
        viewNormal: Vector3D
    ) throws -> SketchPlane {
        let unitNormal: Vector3D
        do {
            unitNormal = try viewNormal.normalized(tolerance: 1.0e-12)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "View-aligned construction plane requires a valid view normal."
            )
        }

        let plane = Plane3D(
            origin: origin,
            normal: unitNormal
        )
        do {
            try plane.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "View-aligned construction plane resolved an invalid plane."
            )
        }
        return .plane(plane)
    }
}
