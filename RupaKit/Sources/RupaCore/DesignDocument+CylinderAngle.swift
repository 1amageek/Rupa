import SwiftCAD
import Foundation
import RupaCoreTypes

extension DesignDocument {
    /// The turn this cylinder's wall currently sweeps, in degrees, or `nil` when the body extrudes
    /// no profile family and so has no turn to read.
    ///
    /// A cylinder that has never been swept reads `360`, which is the circle it was built as.
    package func cylinderAngle(featureID: FeatureID) throws -> Double? {
        guard let resolved = try resolvedCylinderProfile(featureID: featureID) else {
            return nil
        }
        return resolved.profile.sweep * 180.0 / .pi
    }

    /// Rejects a turn outside the sweep the family is defined over.
    ///
    /// The sweep is `(0°, 360°]`: a full turn is the circle the cylinder starts as, and nothing at
    /// all is no body. The schema publishes `[0°, 360°]`, so the lower endpoint is the one value in
    /// the declared range this refuses, and it refuses it rather than snapping to the nearest
    /// shape.
    func validateCylinderAngle(_ degrees: Double) throws {
        guard degrees.isFinite, degrees > 0, degrees <= 360.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Angle must be greater than zero and at most a full turn of 360 degrees."
            )
        }
    }

    /// Rewrites the profile family so the cylinder's wall sweeps this turn.
    ///
    /// A full turn writes the circle the cylinder started as back over the same entity ID and
    /// drops the two radial lines; anything less writes an arc over it and mints or rewrites the
    /// lines. The wall and the hole are carried forward, but they are rewritten all the same,
    /// because the radial lines run between them and so depend on both.
    ///
    /// The turn keeps the start angle the profile already carries, so repeated edits open and
    /// close the sector from the same edge rather than walking it around the axis. A sector opened
    /// out of a full turn starts at zero.
    package mutating func setCylinderAngle(
        featureID: FeatureID,
        degrees: Double,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let resolved = try resolvedCylinderProfile(featureID: featureID) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Angle requires a cylinder built from an editable circle profile."
            )
        }
        try validateCylinderAngle(degrees)

        // Angle and corner exclude each other for the reason hollow and corner do: a sector is
        // none of the four prisms the kernel's all-edge fillet accepts, so a sweep committed under
        // a fillet would stop evaluating. The refusal comes before the rebuild.
        if degrees < 360.0 {
            let cornerRadius = try boxCornerRadius(featureID)
            guard cornerRadius == 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A rounded cylinder cannot be swept. Clear the corner radius first."
                )
            }
        }

        let hollow = resolved.profile.hollowRadius
        let turn: CylinderProfileBuilder.Turn = degrees == 360.0
            ? .full
            : .sector(
                startAngle: resolved.profile.isFullTurn ? 0 : resolved.profile.startAngle,
                sweep: degrees * .pi / 180.0
            )
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
        try commitSketchProfile(resolved.profileFeature, sketch: sketch, owner: "Cylinder angle")
        try synchronizeCylinderAngleObjectProperty(
            featureID: featureID,
            degrees: degrees,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
