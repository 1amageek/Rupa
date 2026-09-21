import SwiftCAD
import Foundation
import RupaCoreTypes

extension DesignDocument {
    /// The hollow this cylinder currently carries, or `nil` when the body extrudes no profile
    /// family and so has no hollow to read.
    package func cylinderHollow(featureID: FeatureID) throws -> Double? {
        try resolvedCylinderProfile(featureID: featureID)?.profile.hollowRadius
    }

    /// The largest hollow this cylinder accepts, or `nil` when it accepts none.
    ///
    /// Hollow and corner exclude each other, so a cylinder already carrying an all-edge fillet
    /// publishes zero rather than a bound every drag would refuse. The value otherwise sits one
    /// tolerance inside the wall the profile has to keep, the same way `maximumAllEdgeCornerRadius`
    /// sits inside the kernel's own bound, so the end of a control bound by it always applies.
    ///
    /// A swept cylinder keeps the full bound: the hole is the same hole, and the chord the sweep
    /// needs is checked against the hollow the caller actually sends.
    package func maximumCylinderHollow(featureID: FeatureID) throws -> Double? {
        guard let resolved = try resolvedCylinderProfile(featureID: featureID) else {
            return nil
        }
        let cornerRadius = try boxCornerRadius(featureID)
        guard cornerRadius == 0 else {
            return 0
        }
        let tolerance = modelingSettings.tolerance.distance
        return max(0, resolved.profile.outer.radius - 2.0 * tolerance)
    }

    /// Rejects a hollow the profile family cannot hold.
    ///
    /// Zero is the solid cylinder and is always accepted; clearing a hole is how a tube is
    /// repaired. A positive hollow has to leave a wall on both sides of itself, so the radius
    /// carries the same bound from the other side and shrinking a cylinder onto the hole it
    /// already has is refused the way shrinking one onto its own fillet already is.
    func validateCylinderHollow(_ hollow: Double, outerRadius: Double) throws {
        let tolerance = modelingSettings.tolerance.distance
        guard hollow.isFinite,
              hollow == 0 || (hollow > tolerance && outerRadius - hollow > tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Hollow must be zero or a positive radius strictly inside the cylinder's own radius."
            )
        }
    }

    /// Rewrites the profile family so the cylinder carries this hollow.
    ///
    /// The wall and the turn are carried forward untouched, but they are rewritten all the same:
    /// a hole changes where the radial lines of a partial sweep begin, so the whole family is
    /// authored at once by `CylinderProfileBuilder`. The inner entity is minted when the hollow
    /// goes from zero to positive, rewritten while it stays positive, and dropped when it returns
    /// to zero.
    package mutating func setCylinderHollow(
        featureID: FeatureID,
        hollow: Double,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let resolved = try resolvedCylinderProfile(featureID: featureID) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Hollow requires a cylinder built from an editable circle profile."
            )
        }
        // Hollow and corner exclude each other, and the refusal comes before the rebuild so the
        // document is left as it was. A tube is none of the four prisms the kernel's all-edge
        // fillet accepts, so a hollow committed under a fillet would stop evaluating.
        if hollow > 0 {
            let cornerRadius = try boxCornerRadius(featureID)
            guard cornerRadius == 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A rounded cylinder cannot be hollowed. Clear the corner radius first."
                )
            }
        }
        try validateCylinderHollow(hollow, outerRadius: resolved.profile.outer.radius)
        // The hole becomes the smallest arc the family holds, so a sweep the outer wall carried
        // comfortably can stop being a shape once a hollow is added inside it.
        let turn = currentCylinderTurn(resolved.profile)
        try validateCylinderSweep(
            turn,
            outerRadius: resolved.profile.outer.radius,
            hollowMeters: hollow
        )

        let sketch = try rebuiltCylinderSketch(
            resolved.sketch,
            profile: resolved.profile,
            outer: currentCylinderWall(resolved.profile),
            hollowMeters: hollow,
            turn: turn
        )
        try commitSketchProfile(resolved.profileFeature, sketch: sketch, owner: "Cylinder hollow")
        try synchronizeCylinderHollowObjectProperty(
            featureID: featureID,
            hollow: hollow,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
