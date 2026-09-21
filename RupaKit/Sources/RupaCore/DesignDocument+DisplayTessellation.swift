import Foundation
import RupaCoreTypes
import SwiftCAD

extension DesignDocument {
    /// An arc the graph holds, carrying its radius when the graph resolves a single one.
    ///
    /// The feature graph is the authority on whether the arc exists. A count naming an arc the
    /// graph does not hold claims nothing, because no resolution it could name would move a
    /// triangle.
    private struct DisplayTessellationArcGeometry {
        var radius: Double?
    }

    /// One subdivision count together with the arc it divides.
    private struct DisplayTessellationClaim {
        var span: Double
        var count: Int
        /// Present only when the graph resolves the arc's radius. An angular tolerance is radius
        /// independent, so a claim without one still names the resolution its count asks for.
        var radius: Double?

        var angularTolerance: Double {
            // The sampler takes `ceil(span / angularTolerance)`. The half step keeps a span that
            // lands a floating-point step above an exact multiple from producing `count + 1`.
            span / (Double(count) - 0.5)
        }

        var linearTolerance: Double? {
            radius.map { $0 * (1.0 - cos(span / (2.0 * Double(count)))) }
        }
    }

    /// Resolves the display resolution the evaluator uses for each body.
    ///
    /// This is the only place that turns declared subdivision counts into
    /// `TessellationOptions.featureOverrides`. The kernel resolves one override per body, so an
    /// override is keyed by the body object's source feature.
    package func displayTessellationOptions(
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> TessellationOptions {
        var options = modelingSettings.tessellationOptions
        let documentLinearTolerance = options.linearTolerance
        let documentMaxEdgeLength = options.maxEdgeLength
        for node in productMetadata.sceneNodes.values {
            guard let object = node.object,
                  object.category == .body,
                  let featureID = object.sourceFeatureID else {
                continue
            }
            let claims = try displayTessellationClaims(
                for: object,
                featureID: featureID,
                objectRegistry: objectRegistry
            )
            guard var angularTolerance = claims.map(\.angularTolerance).min() else { continue }
            var linearTolerance = claims.compactMap(\.linearTolerance).min() ?? documentLinearTolerance
            // Two body objects can name one source feature. The finest claim wins either way, so
            // the override does not depend on the order the scene nodes are visited in.
            if let resolved = options.featureOverrides[featureID] {
                angularTolerance = min(angularTolerance, resolved.angularTolerance)
                linearTolerance = min(linearTolerance, resolved.linearTolerance)
            }
            options.featureOverrides[featureID] = TessellationOptions(
                linearTolerance: linearTolerance,
                angularTolerance: angularTolerance,
                maxEdgeLength: documentMaxEdgeLength
            )
        }
        try options.validate()
        return options
    }

    private func displayTessellationClaims(
        for object: ObjectDescriptor,
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [DisplayTessellationClaim] {
        let counts = try declaredSubdivisionCounts(of: object, objectRegistry: objectRegistry)
        guard !counts.isEmpty else { return [] }
        let circularSection = counts.contains { $0.arc == .circularSection }
            ? try circularSectionArc(featureID)
            : nil
        let allEdgeRound = counts.contains { $0.arc == .allEdgeRound }
            ? try allEdgeRoundArc(featureID)
            : nil
        return counts.compactMap { arc, count in
            let geometry = switch arc {
            case DisplayTessellationArc.circularSection: circularSection
            case DisplayTessellationArc.allEdgeRound: allEdgeRound
            }
            guard let geometry else { return nil }
            return DisplayTessellationClaim(span: arc.span, count: count, radius: geometry.radius)
        }
    }

    /// The counts the object declares, paired with the arc each one divides.
    ///
    /// A body the source router rewrote into a schema-less solid kept the profile resolution it was
    /// drawn at, so that preserved value is read when no schema claims the object.
    private func declaredSubdivisionCounts(
        of object: ObjectDescriptor,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [(arc: DisplayTessellationArc, count: Int)] {
        guard let definition = objectRegistry.definition(for: object.typeID) else {
            guard let count = ProfileTessellationPolicy.arcSegmentCount(from: object) else { return [] }
            return [(.circularSection, count)]
        }
        var counts: [(arc: DisplayTessellationArc, count: Int)] = []
        for property in definition.properties where property.effect == .tessellation {
            guard case .integer(let count) = object.properties.value(
                for: property.id,
                default: property.defaultValue
            ), count > 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(property.title) must be a positive whole number."
                )
            }
            guard let arc = DisplayTessellationArc(dividedBy: property.renderBinding) else {
                throw EditorError(
                    code: .commandUnsupported,
                    message: "\(property.title) declares no arc display tessellation can divide."
                )
            }
            counts.append((arc, count))
        }
        return counts
    }

    /// The sphere's great circle or swept profile arc, resolved from the analytic source.
    private func circularSectionArc(_ featureID: FeatureID) throws -> DisplayTessellationArcGeometry? {
        if let feature = cadDocument.designGraph.nodes[featureID],
           case .primitive(let primitive) = feature.operation,
           case .sphere(let sphere) = primitive.definition {
            return DisplayTessellationArcGeometry(
                radius: try resolvedPositiveLengthValue(sphere.radius, owner: "Sphere display radius")
            )
        }
        guard let feature = cadDocument.designGraph.nodes[boxExtrusionFeatureID(featureID)],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            return nil
        }
        // The outer wall bounds the whole family: a tube's inner wall is a smaller arc, and a
        // sector's wall is a shorter one, both of which the resolution the outer radius asks for
        // already covers.
        if let profile = try recognizedCylinderProfile(in: sketch) {
            let radius = profile.outer.radius
            return radius > 0 ? DisplayTessellationArcGeometry(radius: radius) : nil
        }
        let holdsArc = sketch.entities.values.contains { entity in
            switch entity {
            case .circle, .arc:
                true
            case .point, .line, .spline:
                false
            }
        }
        return holdsArc ? DisplayTessellationArcGeometry(radius: nil) : nil
    }

    /// The all-edge round of the body, or `nil` when the body carries none.
    private func allEdgeRoundArc(_ featureID: FeatureID) throws -> DisplayTessellationArcGeometry? {
        let radius = try boxCornerRadius(featureID)
        return radius > 0 ? DisplayTessellationArcGeometry(radius: radius) : nil
    }
}
