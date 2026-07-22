import RupaCore
import SwiftCAD

struct WorkspaceConstructionPlaneEditBuilder: Sendable {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    func planePreservingOrigin(
        from sourcePlane: SketchPlane,
        viewNormal: Vector3D
    ) throws -> SketchPlane {
        try ConstructionPlaneViewResolver().plane(
            origin: Self.origin(from: sourcePlane),
            viewNormal: viewNormal,
            tolerance: tolerance
        )
    }

    func planeSettingOrigin(
        _ origin: Point3D,
        on sourcePlane: SketchPlane
    ) throws -> SketchPlane {
        try plane(origin: origin, normal: Self.normal(from: sourcePlane))
    }

    func planeSettingNormal(
        _ normal: Vector3D,
        on sourcePlane: SketchPlane
    ) throws -> SketchPlane {
        try plane(origin: Self.origin(from: sourcePlane), normal: normal)
    }

    func planeSettingOriginComponent(
        _ component: WorkspaceConstructionPlaneOriginComponent,
        value: Double,
        on sourcePlane: SketchPlane
    ) throws -> SketchPlane {
        var nextOrigin = Self.origin(from: sourcePlane)
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
        var nextNormal = Self.normal(from: sourcePlane)
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

    static func origin(from plane: SketchPlane) -> Point3D {
        switch plane {
        case .xy, .yz, .zx:
            .origin
        case .plane(let plane):
            plane.origin
        }
    }

    static func normal(from plane: SketchPlane) -> Vector3D {
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
