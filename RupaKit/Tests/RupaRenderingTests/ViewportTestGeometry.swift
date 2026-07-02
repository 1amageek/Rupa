import CoreGraphics

func isParallel(_ lhs: CGVector, _ rhs: CGVector) -> Bool {
    let crossProduct = lhs.dx * rhs.dy - lhs.dy * rhs.dx
    let scale = max(hypot(lhs.dx, lhs.dy) * hypot(rhs.dx, rhs.dy), 1.0)
    return abs(crossProduct / scale) < 1.0e-9
}
