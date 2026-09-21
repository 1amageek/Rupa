import SwiftCAD
import Foundation
import RupaCoreTypes

extension DesignDocument {
    /// The circle profile family a cylinder body extrudes, with the sketch feature carrying it.
    ///
    /// The body ID may name the all-edge fillet wrapper, so the extrusion is resolved the way every
    /// other cylinder edit resolves it.
    func resolvedCylinderCircleProfile(
        featureID: FeatureID
    ) throws -> (profileFeature: FeatureNode, sketch: Sketch, profile: CylinderCircleProfile)? {
        guard let feature = cadDocument.designGraph.nodes[boxExtrusionFeatureID(featureID)],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation,
              let profile = try recognizedCylinderCircleProfile(in: sketch) else {
            return nil
        }
        return (profileFeature, sketch, profile)
    }

    /// The hollow this cylinder currently carries, or `nil` when the body extrudes no circle
    /// profile family and so has no hollow to read.
    package func cylinderHollow(featureID: FeatureID) throws -> Double? {
        try resolvedCylinderCircleProfile(featureID: featureID)?.profile.hollowRadius
    }

    /// The largest hollow this cylinder accepts, or `nil` when it accepts none.
    ///
    /// Hollow and corner exclude each other, so a cylinder already carrying an all-edge fillet
    /// publishes zero rather than a bound every drag would refuse. The value otherwise sits one
    /// tolerance inside the wall the profile has to keep, the same way `maximumAllEdgeCornerRadius`
    /// sits inside the kernel's own bound, so the end of a control bound by it always applies.
    package func maximumCylinderHollow(featureID: FeatureID) throws -> Double? {
        guard let resolved = try resolvedCylinderCircleProfile(featureID: featureID) else {
            return nil
        }
        let cornerRadius = try boxCornerRadius(featureID)
        guard cornerRadius == 0 else {
            return 0
        }
        let tolerance = modelingSettings.tolerance.distance
        return max(0, resolved.profile.outer.radius - 2.0 * tolerance)
    }

    /// Rejects a hollow the circle profile family cannot hold.
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

    /// Rewrites the circle profile family so the cylinder carries this hollow.
    ///
    /// The outer circle is untouched. The inner one is minted when the hollow goes from zero to
    /// positive, rewritten while it stays positive, and dropped when it returns to zero. It carries
    /// no constraint: `SketchProfileExtractor` nests a loop inside the loop that contains it by
    /// containment, so concentricity is the centre expression the two circles share, not a solver
    /// constraint, and this mutator is the only author of that entity.
    package mutating func setCylinderHollow(
        featureID: FeatureID,
        hollow: Double,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let resolved = try resolvedCylinderCircleProfile(featureID: featureID) else {
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

        var sketch = resolved.sketch
        if hollow == 0 {
            if let inner = resolved.profile.inner {
                sketch.entities[inner.id] = nil
                sketch.entityOrder.removeAll { $0 == inner.id }
            }
        } else {
            let innerID = resolved.profile.inner?.id ?? SketchEntityID()
            sketch.entities[innerID] = .circle(
                SketchCircle(
                    center: resolved.profile.center,
                    radius: .length(hollow, .meter)
                )
            )
            if sketch.entityOrder.isEmpty == false, sketch.entityOrder.contains(innerID) == false {
                sketch.entityOrder.append(innerID)
            }
        }
        try commitSketchProfile(resolved.profileFeature, sketch: sketch, owner: "Cylinder hollow")
        try synchronizeCylinderHollowObjectProperty(
            featureID: featureID,
            hollow: hollow,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
