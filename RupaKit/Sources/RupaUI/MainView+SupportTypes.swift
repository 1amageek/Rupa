import RupaCore

struct ViewAlignedConstructionPlaneRequest: Equatable {
    var viewNormal: Vector3D
}

struct SnappedModelInput {
    var point: Point2D
    var topologyWorldPoint: Point3D?

    init(point: Point2D, topologyWorldPoint: Point3D? = nil) {
        self.point = point
        self.topologyWorldPoint = topologyWorldPoint
    }
}
