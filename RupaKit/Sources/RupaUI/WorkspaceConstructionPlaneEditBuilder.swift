import RupaCore

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

    private func origin(from plane: SketchPlane) -> Point3D {
        switch plane {
        case .xy, .yz, .zx:
            .origin
        case .plane(let plane):
            plane.origin
        }
    }
}
