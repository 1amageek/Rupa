import Darwin
import RupaCore
import SwiftCAD
@testable import RupaAgent

func agentPolySplineQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.004),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

func agentPolySplinePatchNetworkMesh(centerZ: Double = 0.001) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}

func agentDirectBSplineSurface() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
    var weights = base.weights
    weights[1][1] = 2.0
    return BSplineSurface3D(
        uDegree: base.uDegree,
        vDegree: base.vDegree,
        uKnots: base.uKnots,
        vKnots: base.vKnots,
        controlPoints: base.controlPoints,
        weights: weights
    )
}

func agentOffsetDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.04, z: 0.002),
        bottomRight: Point3D(x: 0.02, y: 0.04, z: -0.002),
        topRight: Point3D(x: 0.02, y: 0.06, z: 0.001),
        topLeft: Point3D(x: 0.0, y: 0.06, z: 0.003)
    )
}

func agentDirectBSplineSurfaceWithInteriorKnots() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: base.controlPoints,
        weights: base.weights
    )
}

func agentAuthoredBSplineSurfaceTrimLoop() -> BSplineSurfaceTrimLoop {
    BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
}

func surfaceVectorLength(_ vector: SurfaceAnalysisResult.Vector) -> Double {
    hypot(hypot(vector.x, vector.y), vector.z)
}

func surfaceVectorDot(
    _ lhs: SurfaceAnalysisResult.Vector,
    _ rhs: SurfaceAnalysisResult.Vector
) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

func surfaceVectorCross(
    _ lhs: SurfaceAnalysisResult.Vector,
    _ rhs: SurfaceAnalysisResult.Vector
) -> SurfaceAnalysisResult.Vector {
    SurfaceAnalysisResult.Vector(
        x: lhs.y * rhs.z - lhs.z * rhs.y,
        y: lhs.z * rhs.x - lhs.x * rhs.z,
        z: lhs.x * rhs.y - lhs.y * rhs.x
    )
}
