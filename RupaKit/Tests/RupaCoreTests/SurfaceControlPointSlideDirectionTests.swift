import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// The direction Core reports for sliding a surface control point is the one its slide applies:
/// along the control hull at the point, which the viewport's handles read.
@Suite struct SurfaceControlPointSlideDirectionTests {
    /// A cubic patch whose interior control point's hull runs askew of the patch's edges.
    private func skewedSurface() -> BSplineSurface3D {
        var base = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 0.03, y: 0.0, z: 0.0),
            topRight: Point3D(x: 0.03, y: 0.03, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 0.03, z: 0.0)
        )
        base.controlPoints[1][2] = Point3D(x: 0.02, y: 0.01, z: 0.008)
        base.controlPoints[2][1] = Point3D(x: 0.01, y: 0.02, z: -0.004)
        return base
    }

    @Test func theReportedDirectionIsTheOneTheSlideMovesAlong() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createBSplineSurface(name: "Surface", surface: skewedSurface())
        let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
        let controlPoint = try #require(summary.sources.first?.patches.first?.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
        let reference = try #require(controlPoint.selectionReference)
        for direction in PolySplineSurfaceVertexSlideDirection.allCases {
            var slid = document
            let reported = try slid.surfaceControlPointSlideDirection(for: reference, direction: direction)
            #expect(abs(reported.length - 1) < 1e-12)
            try slid.slideSurfaceControlPoints(targets: [reference], direction: direction, distance: .length(1.0, .millimeter))
            guard case let .bSplineSurface(feature) = slid.cadDocument.designGraph.nodes[featureID]?.operation else {
                Issue.record("Expected the direct B-spline surface.")
                return
            }
            let moved = feature.surface.controlPoints[1][1] - skewedSurface().controlPoints[1][1]
            #expect((moved - reported * 0.001).length < 1e-12, "\(direction)")
        }
        // The hull runs askew of the patch's edges here, so a rule of the patch's corners would
        // point elsewhere.
        let positiveU = try document.surfaceControlPointSlideDirection(for: reference, direction: .positiveU)
        #expect(abs(positiveU.z) > 0.1)
    }
}
