import Foundation
import SwiftCAD

extension DesignDocument {
    /// A sketch spline's exact planar geometry on its own degree and knots, its control points
    /// resolved through the document's parameters. Every reader that evaluates a spline other
    /// than through its control points goes through this or `sketchSplineGeometry2D`.
    func resolvedSketchSplineCurve(_ spline: SketchSpline, owner: String) throws -> SketchSplineCurve {
        let points = try spline.controlPoints.map { point -> Point2D in
            let resolved = try resolvedSketchPoint(point, owner: "\(owner) control point")
            return Point2D(x: resolved.x, y: resolved.y)
        }
        do {
            return try SketchSplineCurve(spline: spline, controlPoints: points, tolerance: .standard)
        } catch let error as SketchError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error)")
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        } catch let error as GeometryError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error)")
        }
    }

    /// A spline as the kernel's planar curve geometry: a cubic chain keeps the chain case (and so
    /// its earlier results exactly), any other degree or knots the general spline case. Both take
    /// the parameter normalized over the knot domain as `splitSketchCurve`'s fraction.
    func sketchSplineGeometry2D(_ spline: SketchSpline, owner: String) throws -> SketchCurveGeometry2D {
        if spline.isCubicBezierChain {
            let points = try spline.controlPoints.map { point -> Point2D in
                let resolved = try resolvedSketchPoint(point, owner: "\(owner) control point")
                return Point2D(x: resolved.x, y: resolved.y)
            }
            guard spline.spanCount != nil else {
                throw EditorError(code: .commandInvalid, message: "\(owner) requires a spline of 3n + 1 control points.")
            }
            return .cubicBezierChain(controlPoints: points)
        }
        return .sketchSpline(try resolvedSketchSplineCurve(spline, owner: owner))
    }

    /// The sketch spline of a kernel B-spline: its control points as literal lengths, its degree,
    /// and its knots, left implicit when they are exactly the chain form's.
    func sketchSpline(from curve: BSplineCurve2D, isClosed: Bool = false) -> SketchSpline {
        let points = curve.controlPoints.map { sketchPoint(x: $0.x, y: $0.y) }
        let chain = SketchSpline(controlPoints: points, isClosed: isClosed, degree: curve.degree)
        return chain.knotVector == curve.knots
            ? chain
            : SketchSpline(controlPoints: points, isClosed: isClosed, degree: curve.degree, knots: curve.knots)
    }

    /// An open spline of any degree or knots split at `fraction` of its knot domain: both parts
    /// keep its degree and carry the B-spline's knots over their own intervals, so a fraction on
    /// either part is linear in the original's. Other commands read the parts through their knots.
    func splitGeneralSpline(
        _ spline: SketchSpline,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchSpline, new: SketchSpline) {
        guard spline.isClosed == false else {
            throw EditorError(code: .commandInvalid, message: "\(owner) requires an open spline; open a closed one first.")
        }
        let curve = try resolvedSketchSplineCurve(spline, owner: owner)
        let (lower, upper) = curve.domain
        let parameter = curve.parameter(ofFraction: fraction)
        let tolerance = 1.0e-9 * max(upper - lower, 1)
        guard parameter > lower + tolerance, parameter < upper - tolerance else {
            throw EditorError(code: .commandInvalid, message: "\(owner) fraction must fall inside the spline.")
        }
        do {
            let retained = try curve.bSpline.trimmed(from: lower, to: parameter, tolerance: .standard)
            let next = try curve.bSpline.trimmed(from: parameter, to: upper, tolerance: .standard)
            return (sketchSpline(from: retained), sketchSpline(from: next))
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        } catch let error as GeometryError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error)")
        }
    }
}

extension SketchSplineCurve {
    /// The knot domain's first and last value.
    var domain: (lower: Double, upper: Double) {
        let knots = bSpline.knots
        return (knots[degree], knots[knots.count - degree - 1])
    }

    /// The fraction in [0, 1] over the knot domain of the B-spline parameter `parameter`.
    func fraction(ofParameter parameter: Double) -> Double {
        let (lower, upper) = domain
        return (parameter - lower) / (upper - lower)
    }

    /// The B-spline parameter of the fraction `fraction` over the knot domain.
    func parameter(ofFraction fraction: Double) -> Double {
        let (lower, upper) = domain
        return lower + fraction * (upper - lower)
    }
}
