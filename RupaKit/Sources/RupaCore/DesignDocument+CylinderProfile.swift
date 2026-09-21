import SwiftCAD
import Foundation
import RupaCoreTypes

extension DesignDocument {
    /// The profile family a cylinder body extrudes, with the sketch feature carrying it.
    ///
    /// The body ID may name the all-edge fillet wrapper, so the extrusion is resolved the way every
    /// other cylinder edit resolves it.
    func resolvedCylinderProfile(
        featureID: FeatureID
    ) throws -> (profileFeature: FeatureNode, sketch: Sketch, profile: CylinderProfile)? {
        guard let feature = cadDocument.designGraph.nodes[boxExtrusionFeatureID(featureID)],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation,
              let profile = try recognizedCylinderProfile(in: sketch) else {
            return nil
        }
        return (profileFeature, sketch, profile)
    }

    /// Rewrites every entity of the family so the sketch holds the wall, hole, and turn described.
    ///
    /// The radial lines depend on all three at once, so no mutator can write its own value into
    /// the profile and leave the rest alone. Each of them resolves the profile, carries forward
    /// the two values it does not own, and rebuilds here.
    ///
    /// The family carries no constraint. `SketchProfileExtractor` nests a loop inside the loop
    /// that contains it by containment, so concentricity is the centre expression every entity
    /// shares rather than a solver constraint, and the two radial lines meet the arcs because this
    /// builder places both from the same radii and angles.
    func rebuiltCylinderSketch(
        _ sketch: Sketch,
        profile: CylinderProfile,
        outer: CylinderProfileBuilder.Wall,
        hollowMeters: Double,
        turn: CylinderProfileBuilder.Turn
    ) throws -> Sketch {
        let center = try resolvedSketchPoint(profile.center, owner: "Cylinder center")
        let rebuilt = CylinderProfileBuilder.build(
            center: profile.center,
            centerX: center.x,
            centerY: center.y,
            outer: outer,
            inner: hollowMeters > 0 ? CylinderProfileBuilder.Wall(meters: hollowMeters) : nil,
            turn: turn,
            reusing: CylinderProfileBuilder.EntityIDs(
                outer: profile.outer.id,
                inner: profile.inner?.id,
                radialStart: profile.radialEdges?.start,
                radialEnd: profile.radialEdges?.end
            )
        )
        var sketch = sketch
        sketch.entities = rebuilt.entities
        sketch.entityOrder = rebuilt.entityOrder
        sketch.constraints = []
        return sketch
    }

    /// The turn this profile already carries, which every mutator that does not own the sweep
    /// hands straight back to the builder.
    func currentCylinderTurn(_ profile: CylinderProfile) -> CylinderProfileBuilder.Turn {
        profile.isFullTurn
            ? .full
            : .sector(startAngle: profile.startAngle, sweep: profile.sweep)
    }

    /// The wall this profile already carries, expression and resolved length together.
    func currentCylinderWall(_ profile: CylinderProfile) -> CylinderProfileBuilder.Wall {
        CylinderProfileBuilder.Wall(
            radius: profile.outer.radiusExpression,
            meters: profile.outer.radius
        )
    }

    /// Rejects a turn whose ends the profile cannot tell apart.
    ///
    /// `SketchProfileExtractor` walks a profile by joining endpoints that coincide within the
    /// tolerance, so a sector is a shape only while the chord across its arc clears that distance:
    /// `2 * r * sin(sweep / 2) > tolerance.distance`, measured on the smallest arc the family
    /// holds. One expression covers both ends of the control, because the chord closes as the
    /// sweep approaches a full turn exactly as it does when the sweep approaches nothing.
    ///
    /// A full turn is the circle the cylinder starts as, has no chord, and is always accepted.
    func validateCylinderSweep(
        _ turn: CylinderProfileBuilder.Turn,
        outerRadius: Double,
        hollowMeters: Double
    ) throws {
        guard case let .sector(_, sweep) = turn else {
            return
        }
        let radius = hollowMeters > 0 ? hollowMeters : outerRadius
        let chord = 2.0 * radius * sin(sweep / 2.0)
        guard sweep.isFinite, chord > modelingSettings.tolerance.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "The angle leaves the two ends of the cylinder's wall closer together than the modeling tolerance."
            )
        }
    }
}
