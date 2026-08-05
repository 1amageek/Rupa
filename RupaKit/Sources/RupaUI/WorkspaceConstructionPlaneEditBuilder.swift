import RupaCore
import SwiftCAD

struct WorkspaceConstructionPlaneEditBuilder: Sendable {
    func planePreservingOrigin(
        from sourcePlane: SketchPlane,
        viewNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> SketchPlane {
        try ConstructionPlaneViewResolver().plane(
            origin: origin(from: sourcePlane),
            viewNormal: viewNormal,
            tolerance: tolerance
        )
    }

    func planeSettingOrigin(
        _ origin: Point3D,
        on sourcePlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> SketchPlane {
        try plane(
            origin: origin,
            normal: normal(from: sourcePlane),
            tolerance: tolerance
        )
    }

    func planeSettingNormal(
        _ normal: Vector3D,
        on sourcePlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> SketchPlane {
        try plane(
            origin: origin(from: sourcePlane),
            normal: normal,
            tolerance: tolerance
        )
    }

    func planeSettingOriginComponent(
        _ component: WorkspaceConstructionPlaneOriginComponent,
        value: Double,
        on sourcePlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> SketchPlane {
        var nextOrigin = origin(from: sourcePlane)
        switch component {
        case .x:
            nextOrigin.x = value
        case .y:
            nextOrigin.y = value
        case .z:
            nextOrigin.z = value
        }
        return try planeSettingOrigin(nextOrigin, on: sourcePlane, tolerance: tolerance)
    }

    func planeSettingNormalComponent(
        _ component: WorkspaceConstructionPlaneNormalComponent,
        value: Double,
        on sourcePlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> SketchPlane {
        var nextNormal = normal(from: sourcePlane)
        switch component {
        case .x:
            nextNormal.x = value
        case .y:
            nextNormal.y = value
        case .z:
            nextNormal.z = value
        }
        return try planeSettingNormal(nextNormal, on: sourcePlane, tolerance: tolerance)
    }

    func origin(from plane: SketchPlane) -> Point3D {
        switch plane {
        case .xy, .yz, .zx:
            .origin
        case .plane(let plane):
            plane.origin
        }
    }

    func normal(from plane: SketchPlane) -> Vector3D {
        switch plane {
        case .xy:
            .unitZ
        case .yz:
            .unitX
        case .zx:
            .unitY
        case .plane(let plane):
            plane.normal
        }
    }

    private func plane(
        origin: Point3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> SketchPlane {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        let plane = Plane3D(origin: origin, normal: normalizedNormal)
        try plane.validate(tolerance: tolerance)
        return .plane(plane)
    }
}

enum WorkspaceConstructionPlaneOriginComponent: String, CaseIterable, Sendable {
    case x
    case y
    case z
}

enum WorkspaceConstructionPlaneNormalComponent: String, CaseIterable, Sendable {
    case x
    case y
    case z
}
