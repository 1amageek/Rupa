import CoreGraphics
import Foundation
import RupaCore
import SwiftCAD
@testable import RupaRendering

/// A measuring surface that answers nothing usable, so a drag route's failure
/// contract can be stated without a camera.
///
/// The two outcomes are the two shapes a bad answer takes: the frame refuses
/// with a typed error, or the frame answers with a value that is not finite.
/// Both must reach the caller as a refusal rather than a silently substituted
/// quantity.
@MainActor
struct ViewportStubAffordanceMeasure: ViewportAffordanceMeasuring {
    enum Outcome {
        /// Every requirement throws this error.
        case refuses(MeshSourcePresentationRenderError)
        /// Every requirement answers, but with a non-finite value.
        case answersNonFinite
    }

    let outcome: Outcome

    /// The refusal a frame answers a transient condition with.
    static var frameNotReady: Self {
        Self(outcome: .refuses(MeshSourcePresentationRenderError(
            code: .frameNotReady,
            message: "No frame has judged this query yet."
        )))
    }

    /// The refusal a frame answers a geometric degeneracy with.
    static var refusesQuery: Self {
        Self(outcome: .refuses(MeshSourcePresentationRenderError(
            code: .failed,
            message: "The stub camera refuses this query."
        )))
    }

    static var answersNonFinite: Self {
        Self(outcome: .answersNonFinite)
    }

    func worldAxisDelta(
        from start: CGPoint,
        to end: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D
    ) throws -> Double {
        switch outcome {
        case let .refuses(error):
            throw error
        case .answersNonFinite:
            return .infinity
        }
    }

    func worldPlanePoint(
        at point: CGPoint,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) throws -> Point3D {
        try nonFinitePoint()
    }

    func viewPlanePoint(at point: CGPoint, through anchor: Point3D) throws -> Point3D {
        try nonFinitePoint()
    }

    private func nonFinitePoint() throws -> Point3D {
        switch outcome {
        case let .refuses(error):
            throw error
        case .answersNonFinite:
            return Point3D(x: .nan, y: .nan, z: .nan)
        }
    }
}
