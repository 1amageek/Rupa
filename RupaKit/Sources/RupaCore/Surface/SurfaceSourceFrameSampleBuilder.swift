import SwiftCAD
import RupaCoreTypes

struct SurfaceSourceFrameSampleBuilder: Sendable {
    struct Result: Sendable {
        var samples: [SurfaceSourceSummaryResult.FrameSample]
        var diagnostics: [SurfaceSourceSummaryResult.Diagnostic]

        init(
            samples: [SurfaceSourceSummaryResult.FrameSample] = [],
            diagnostics: [SurfaceSourceSummaryResult.Diagnostic] = []
        ) {
            self.samples = samples
            self.diagnostics = diagnostics
        }
    }

    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    func buildSamples(
        featureID: FeatureID,
        patchID: Int,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference,
        uSpans: [SurfaceSourceSummaryResult.Basis.Span],
        vSpans: [SurfaceSourceSummaryResult.Basis.Span],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) -> Result {
        var samples: [SurfaceSourceSummaryResult.FrameSample] = []
        var diagnostics: [SurfaceSourceSummaryResult.Diagnostic] = []
        samples.reserveCapacity(max(uSpans.count * vSpans.count, 1))

        for vSpan in vSpans {
            for uSpan in uSpans {
                let u = midpoint(uSpan.lowerBound, uSpan.upperBound)
                let v = midpoint(vSpan.lowerBound, vSpan.upperBound)
                do {
                    samples.append(try sample(
                        featureID: featureID,
                        patchID: patchID,
                        surface: surface,
                        surfaceReference: surfaceReference,
                        uSpan: uSpan,
                        vSpan: vSpan,
                        u: u,
                        v: v,
                        surfaceFrameDisplays: surfaceFrameDisplays
                    ))
                } catch {
                    diagnostics.append(SurfaceSourceSummaryResult.Diagnostic(
                        severity: "warning",
                        code: "surfaceFrameSampleUnavailable",
                        message: "Surface frame sample \(uSpan.id)/\(vSpan.id) could not be evaluated for patch \(patchID): \(String(describing: error))."
                    ))
                }
            }
        }

        return Result(
            samples: samples,
            diagnostics: diagnostics
        )
    }

    private func sample(
        featureID: FeatureID,
        patchID: Int,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference,
        uSpan: SurfaceSourceSummaryResult.Basis.Span,
        vSpan: SurfaceSourceSummaryResult.Basis.Span,
        u: Double,
        v: Double,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) throws -> SurfaceSourceSummaryResult.FrameSample {
        let geometry = try surface.differentialGeometry(atU: u, v: v, tolerance: tolerance)
        let uAxis = try geometry.tangentU.normalized(tolerance: tolerance.distance)
        let normal = geometry.normal
        let vAxis = try normal.cross(uAxis).normalized(tolerance: tolerance.distance)
        let handedness = uAxis.cross(vAxis).dot(normal)
        let selectionReference = SelectionReference.surface(.parameter(SurfaceParameterReference(
            surface: surfaceReference,
            u: u,
            v: v
        )))
        let frameDisplayID = try SurfaceFrameDisplayID(query: SurfaceFrameQuery(
            selectionReference: selectionReference
        ))

        return SurfaceSourceSummaryResult.FrameSample(
            id: "feature:\(featureID.description)/patch:\(patchID)/frame:uSpan\(uSpan.index):vSpan\(vSpan.index)",
            uSpanID: uSpan.id,
            vSpanID: vSpan.id,
            u: u,
            v: v,
            position: point(geometry.position),
            uAxis: vector(uAxis),
            vAxis: vector(vAxis),
            normal: vector(normal),
            handedness: handedness,
            normalCurvatureU: geometry.normalCurvatureU,
            normalCurvatureV: geometry.normalCurvatureV,
            meanCurvature: geometry.meanCurvature,
            gaussianCurvature: geometry.gaussianCurvature,
            minimumPrincipalCurvature: geometry.minimumPrincipalCurvature,
            maximumPrincipalCurvature: geometry.maximumPrincipalCurvature,
            minimumPrincipalDirection: vector(geometry.minimumPrincipalDirection),
            maximumPrincipalDirection: vector(geometry.maximumPrincipalDirection),
            selectionReference: selectionReference,
            isFrameDisplayVisible: surfaceFrameDisplays[frameDisplayID]?.isVisible == true
        )
    }

    private func midpoint(_ lowerBound: Double, _ upperBound: Double) -> Double {
        lowerBound + (upperBound - lowerBound) * 0.5
    }

    private func point(_ point: Point3D) -> SurfaceSourceSummaryResult.Point {
        SurfaceSourceSummaryResult.Point(
            x: point.x,
            y: point.y,
            z: point.z
        )
    }

    private func vector(_ vector: Vector3D) -> SurfaceSourceSummaryResult.Vector {
        SurfaceSourceSummaryResult.Vector(
            x: vector.x,
            y: vector.y,
            z: vector.z
        )
    }
}
