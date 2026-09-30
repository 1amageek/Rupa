import Foundation
import SwiftCAD
import RupaCoreTypes

/// A curvature comb along one curve, placed in the world: at each sample the curve's point, the
/// unit normal toward its centre of curvature and the curvature there. A straight curve has no
/// comb.
public struct CurvatureComb: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var point: Point3D
        public var normal: Vector3D
        public var curvature: Double

        public init(point: Point3D, normal: Vector3D, curvature: Double) {
            self.point = point
            self.normal = normal
            self.curvature = curvature
        }
    }

    public var samples: [Sample]

    public init(samples: [Sample]) {
        self.samples = samples
    }
}

/// The combs a curvature measurement shows (Toggle Curvature): each anchored generated edge or
/// sketch curve is evaluated exactly by Swift-CAD at samples across its span, under the placement
/// its object has in the scene, so the combs follow the curve wherever it is shown.
public struct CurvatureCombService: Sendable {
    private let anchorResolver: MeasurementAnchorWorldPointResolver

    public init(anchorResolver: MeasurementAnchorWorldPointResolver = MeasurementAnchorWorldPointResolver()) {
        self.anchorResolver = anchorResolver
    }

    /// One comb per anchored curve that bends, in anchor order.
    public func combs(
        for annotation: MeasurementAnnotation,
        in document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> [CurvatureComb] {
        guard annotation.kind == .curvature else {
            throw EditorError(code: .commandInvalid, message: "Only a curvature measurement has combs.")
        }
        // A document of sketches alone has no topology snapshot to carry its evaluated curves.
        let evaluated = try topology.evaluatedDocument ?? DocumentEvaluationContextResolver().evaluatedDocument(
            document: document, failurePrefix: "Curvature combs require the evaluated curves"
        )
        let tolerance = document.modelingSettings.tolerance
        return try annotation.anchors.compactMap { anchor in
            let (curve, span) = try placedCurve(for: anchor, in: document, topology: topology, evaluated: evaluated)
            return try comb(of: curve, over: span, tolerance: tolerance)
        }
    }

    /// The anchor's curve in the world and the parameter span it covers.
    private func placedCurve(
        for anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot,
        evaluated: EvaluatedDocument
    ) throws -> (curve: Curve3D, span: ClosedRange<Double>) {
        let tolerance = document.modelingSettings.tolerance
        let curve: Curve3D
        let span: ClosedRange<Double>
        let transform: Transform3D
        if anchor.referencesTopologyEdge {
            guard let placed = try anchorResolver.placedTopologyEntry(for: anchor, in: document, topology: topology),
                  placed.entry.kind == .edge, let reference = placed.entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "A curvature measurement's edge is no longer in the model.")
            }
            let resolved = try EdgeQueryEvaluator(tolerance: tolerance).resolve(EdgeReference(subshape: reference), in: evaluated)
            curve = resolved.curve
            span = min(resolved.startParameter, resolved.endParameter)...max(resolved.startParameter, resolved.endParameter)
            transform = placed.transform
        } else if let sketch = anchor.sketchReference, case .entity(let entityID) = sketch.reference {
            guard let evaluatedCurve = evaluated.curves[sketch.featureID]?.first(where: { $0.source == .sketchEntity(entityID) }),
                  let exact = evaluatedCurve.exactCurve else {
                throw EditorError(code: .referenceUnresolved, message: "A curvature measurement's sketch curve is no longer in the model.")
            }
            curve = exact
            switch evaluatedCurve.parameterDomain {
            case let .closed(lower, upper):
                span = min(lower, upper)...max(lower, upper)
            case let .periodic(period):
                span = 0...period
            case .unbounded:
                throw EditorError(code: .commandInvalid, message: "A curvature measurement needs a bounded curve.")
            }
            transform = try anchorResolver.placementTransform(for: anchor, in: document)
        } else {
            throw EditorError(code: .commandInvalid, message: "A curvature measurement follows generated edges and sketch curves.")
        }
        guard let affine = try transform.coordinateMap(to: .identity) else {
            return (curve, span)
        }
        return (try Curve3D.affineImage(AffineImageCurve3D(source: curve, transform: affine, tolerance: tolerance)), span)
    }

    /// Samples across the span, several per knot span of a spline so the comb follows each span's
    /// bend; nil when the curve does not bend anywhere. A flat stretch has teeth of no length on
    /// the side of the bend before it (or after it, at the start).
    private func comb(of curve: Curve3D, over span: ClosedRange<Double>, tolerance: ModelingTolerance) throws -> CurvatureComb? {
        guard span.upperBound > span.lowerBound else {
            throw EditorError(code: .commandInvalid, message: "A curvature measurement's curve has no length to comb.")
        }
        let count = sampleCount(of: curve)
        var samples: [(point: Point3D, normal: Vector3D?, curvature: Double)] = []
        samples.reserveCapacity(count)
        for index in 0..<count {
            let parameter = span.lowerBound + (span.upperBound - span.lowerBound) * Double(index) / Double(count - 1)
            let geometry = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
            guard geometry.curvature.isFinite, geometry.position.isFinite else {
                throw EditorError(code: .commandFailed, message: "A curvature measurement's curve has no finite curvature.")
            }
            let bent = geometry.curvature > Self.flatCurvature
            samples.append((
                geometry.position,
                bent ? geometry.curvatureVector * (1 / geometry.curvature) : nil,
                bent ? geometry.curvature : 0
            ))
        }
        guard var normal = samples.first(where: { $0.normal != nil })?.normal else {
            return nil
        }
        return CurvatureComb(samples: samples.map { bend in
            if let bent = bend.normal { normal = bent }
            return CurvatureComb.Sample(point: bend.point, normal: normal, curvature: bend.curvature)
        })
    }

    private func sampleCount(of curve: Curve3D) -> Int {
        guard case let .bSpline(spline) = curve else { return 64 }
        let knots = spline.knots
        let spans = zip(knots, knots.dropFirst()).filter { $0.1 > $0.0 }.count
        return min(max(spans * 16, 32), 1024)
    }

    /// Below this a curve is straight: 1/κ is a radius past a kilometre.
    private static let flatCurvature = 1.0e-3
}

private extension MeasurementAnchor {
    var referencesTopologyEdge: Bool {
        kind == .topologyReference && topologyReference?.kind == .edge
    }
}
