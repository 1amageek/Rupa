import RupaCore
import SwiftCAD

struct WorkspaceConstructionPlaneEditBuilder: Sendable {
    func planePreservingOrigin(
        from sourcePlane: SketchPlane,
        viewNormal: Vector3D
    ) throws -> SketchPlane {
        try ConstructionPlaneViewResolver().plane(
            origin: origin(from: sourcePlane),
            viewNormal: viewNormal
        )
    }

    func planeSettingOrigin(
        _ origin: Point3D,
        on sourcePlane: SketchPlane
    ) throws -> SketchPlane {
        try plane(origin: origin, normal: normal(from: sourcePlane))
    }

    func planeSettingNormal(
        _ normal: Vector3D,
        on sourcePlane: SketchPlane
    ) throws -> SketchPlane {
        try plane(origin: origin(from: sourcePlane), normal: normal)
    }

    func planeSettingOriginComponent(
        _ component: WorkspaceConstructionPlaneOriginComponent,
        value: Double,
        on sourcePlane: SketchPlane
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
        return try planeSettingOrigin(nextOrigin, on: sourcePlane)
    }

    func planeSettingNormalComponent(
        _ component: WorkspaceConstructionPlaneNormalComponent,
        value: Double,
        on sourcePlane: SketchPlane
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
        return try planeSettingNormal(nextNormal, on: sourcePlane)
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

    private func plane(origin: Point3D, normal: Vector3D) throws -> SketchPlane {
        let normalizedNormal = try normal.normalized(tolerance: 1.0e-12)
        let plane = Plane3D(origin: origin, normal: normalizedNormal)
        try plane.validate()
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
