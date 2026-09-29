import SwiftCAD

extension DesignDocument {
    /// The unit vector, in its surface source's own frame, along which sliding the surface control
    /// point `reference` in `direction` moves it: exactly what `slideSurfaceControlPoints` applies,
    /// so the viewport's slide handles point where a slide goes. Control points of B-spline surface
    /// sources and PolySpline patches' interiors slide along the control hull
    /// (`SurfaceControlHullSlideFrame`); a PolySpline patch's boundary vertex along its patch's
    /// edges.
    public func surfaceControlPointSlideDirection(
        for reference: SelectionReference,
        direction: PolySplineSurfaceVertexSlideDirection
    ) throws -> Vector3D {
        let tolerance = modelingSettings.tolerance
        switch try SurfaceControlPointSelectionTargetResolver().editTarget(for: reference, in: self) {
        case .boundaryVertex(let target):
            let resolved = try PolySplineSurfaceVertexTarget.resolve(target, in: self)
            return try PolySplineSurfaceVertexEditingService(tolerance: tolerance).slideUnitVector(
                for: resolved, in: try polySplineSource(resolved.featureID), direction: direction
            )
        case .interiorControlPoint(let target):
            return try PolySplineSurfaceControlPointEditingService(tolerance: tolerance).slideUnitVector(
                for: target, in: try polySplineSource(target.featureID), direction: direction
            )
        case .bSplineSurfaceControlPoint(let target):
            guard case let .bSplineSurface(feature) = cadDocument.designGraph.nodes[target.featureID]?.operation else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Surface control point slide requires an existing direct B-spline surface source feature."
                )
            }
            return try BSplineSurfaceControlPointEditingService(tolerance: tolerance).slideUnitVector(
                for: target, in: feature, direction: direction
            )
        }
    }

    private func polySplineSource(_ featureID: FeatureID) throws -> PolySplineFeature {
        guard case let .polySpline(polySpline) = cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point slide requires an existing PolySpline source feature."
            )
        }
        return polySpline
    }
}
