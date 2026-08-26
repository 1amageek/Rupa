import SwiftCAD

struct ViewportTrianglePolygon: Equatable, Sendable {
    let first: Point3D
    let second: Point3D
    let third: Point3D
    let fourth: Point3D?

    init(
        first: Point3D,
        second: Point3D,
        third: Point3D,
        fourth: Point3D? = nil
    ) {
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
    }

    var count: Int {
        fourth == nil ? 3 : 4
    }

    var points: [Point3D] {
        if let fourth {
            return [first, second, third, fourth]
        }
        return [first, second, third]
    }
}
