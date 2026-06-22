import Testing
import RupaCore
import SwiftCAD
@testable import RupaRendering

@Test func viewportProjectionBasisReportsPositiveAxisFrontViewNormals() throws {
    try assertViewNormal(
        ViewportProjectionBasis.axisFront(.x),
        equals: Vector3D(x: 1.0, y: 0.0, z: 0.0)
    )
    try assertViewNormal(
        ViewportProjectionBasis.axisFront(.y),
        equals: Vector3D(x: 0.0, y: 1.0, z: 0.0)
    )
    try assertViewNormal(
        ViewportProjectionBasis.axisFront(.z),
        equals: Vector3D(x: 0.0, y: 0.0, z: 1.0)
    )
}

@Test func viewportProjectionBasisViewNormalProjectsToScreenZero() throws {
    let basis = ViewportProjectionBasis.isometric
    let normal = try #require(basis.viewNormal)

    let projectedX = Double(basis.xDirection.dx) * normal.x
        + Double(basis.yDirection.dx) * normal.y
        + Double(basis.zDirection.dx) * normal.z
    let projectedY = Double(basis.xDirection.dy) * normal.x
        + Double(basis.yDirection.dy) * normal.y
        + Double(basis.zDirection.dy) * normal.z
    let length = (normal.x * normal.x + normal.y * normal.y + normal.z * normal.z).squareRoot()

    #expect(abs(projectedX) <= 1.0e-9)
    #expect(abs(projectedY) <= 1.0e-9)
    #expect(abs(length - 1.0) <= 1.0e-9)
}

@Test func viewportProjectionBasisAlignsToCanonicalConstructionPlanes() throws {
    try assertViewNormal(
        try ViewportProjectionBasis.aligned(to: .xy),
        equals: Vector3D(x: 0.0, y: 0.0, z: 1.0),
        tolerance: 1.0e-9
    )
    try assertViewNormal(
        try ViewportProjectionBasis.aligned(to: .yz),
        equals: Vector3D(x: 1.0, y: 0.0, z: 0.0),
        tolerance: 1.0e-9
    )
    try assertViewNormal(
        try ViewportProjectionBasis.aligned(to: .zx),
        equals: Vector3D(x: 0.0, y: 1.0, z: 0.0),
        tolerance: 1.0e-9
    )
}

@Test func viewportProjectionBasisAlignsToCustomConstructionPlaneNormal() throws {
    let normal = try Vector3D(x: 1.0, y: 2.0, z: 3.0).normalized(tolerance: 1.0e-12)
    let basis = try ViewportProjectionBasis.aligned(
        to: .plane(Plane3D(origin: .origin, normal: normal))
    )

    try assertViewNormal(basis, equals: normal, tolerance: 1.0e-9)
}

@Test func viewportProjectionBasisAlignsToSketchPlaneCoordinateAxes() throws {
    let planes: [SketchPlane] = [
        .xy,
        .yz,
        .zx,
        .plane(Plane3D(
            origin: Point3D(x: 0.2, y: -0.1, z: 0.3),
            normal: try Vector3D(x: 1.0, y: 2.0, z: 3.0).normalized(tolerance: 1.0e-12)
        )),
    ]

    for plane in planes {
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
        let basis = try ViewportProjectionBasis.aligned(to: plane)

        try assertProjectedVector(coordinateSystem.u, in: basis, equalsX: 1.0, equalsY: 0.0)
        try assertProjectedVector(coordinateSystem.v, in: basis, equalsX: 0.0, equalsY: -1.0)
    }
}

private func assertViewNormal(
    _ basis: ViewportProjectionBasis,
    equals expected: Vector3D,
    tolerance: Double = 0.2
) throws {
    let normal = try #require(basis.viewNormal)

    #expect(abs(normal.x - expected.x) <= tolerance)
    #expect(abs(normal.y - expected.y) <= tolerance)
    #expect(abs(normal.z - expected.z) <= tolerance)
}

private func assertProjectedVector(
    _ vector: Vector3D,
    in basis: ViewportProjectionBasis,
    equalsX expectedX: Double,
    equalsY expectedY: Double,
    tolerance: Double = 1.0e-9
) throws {
    let projectedX = Double(basis.xDirection.dx) * vector.x
        + Double(basis.yDirection.dx) * vector.y
        + Double(basis.zDirection.dx) * vector.z
    let projectedY = Double(basis.xDirection.dy) * vector.x
        + Double(basis.yDirection.dy) * vector.y
        + Double(basis.zDirection.dy) * vector.z

    #expect(abs(projectedX - expectedX) <= tolerance)
    #expect(abs(projectedY - expectedY) <= tolerance)
}
