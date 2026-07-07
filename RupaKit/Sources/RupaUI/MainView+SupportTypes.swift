import RupaCore

struct ViewAlignedConstructionPlaneRequest: Equatable {
    var viewNormal: Vector3D
}

struct SnappedModelInput {
    var point: Point2D
    var worldPoint: Point3D?

    init(point: Point2D, worldPoint: Point3D? = nil) {
        self.point = point
        self.worldPoint = worldPoint
    }
}
