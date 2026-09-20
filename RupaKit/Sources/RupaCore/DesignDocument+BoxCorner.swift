import SwiftCAD
import Foundation
import RupaCoreTypes

extension DesignDocument {
    /// Resolves only the all-edge primitive wrapper, never an arbitrary fillet.
    package func boxExtrusionFeatureID(_ featureID: FeatureID) -> FeatureID {
        if case .fillet(let fillet) = cadDocument.designGraph.nodes[featureID]?.operation,
           fillet.allEdges {
            return fillet.target.featureID
        }
        return featureID
    }

    /// Resolves the wrapper from the extrusion it hides, the inverse of `boxExtrusionFeatureID`.
    ///
    /// The wrapper keeps the visible feature ID, so a path that walked the design graph to the
    /// extrusion must map back before it names a body for a scene node or hands the ID to a
    /// caller that expects the whole box.
    package func visibleBoxFeatureID(_ featureID: FeatureID) -> FeatureID {
        for candidate in cadDocument.designGraph.order {
            guard case .fillet(let fillet) = cadDocument.designGraph.nodes[candidate]?.operation,
                  fillet.allEdges, fillet.target.featureID == featureID else { continue }
            return candidate
        }
        return featureID
    }

    /// The visible bodies extruded from one profile feature, in design graph order.
    ///
    /// Matching on the graph rather than on a generated name finds the body whatever created it,
    /// so a cube authored from the toolbar and one grown from a sketch's `extrusion` property are
    /// the same case to every caller.
    package func extrudedBodyFeatureIDs(forProfile featureID: FeatureID) -> [FeatureID] {
        cadDocument.designGraph.order.compactMap { candidate in
            guard case let .extrude(extrude) = cadDocument.designGraph.nodes[candidate]?.operation,
                  extrude.profile.featureID == featureID else { return nil }
            return visibleBoxFeatureID(candidate)
        }
    }

    package func boxCornerRadius(_ featureID: FeatureID) throws -> Double {
        guard case .fillet(let fillet) = cadDocument.designGraph.nodes[featureID]?.operation,
              fillet.allEdges else { return 0 }
        return try resolvedLengthValue(fillet.radius, owner: "Box corner")
    }

    func validateBoxCorner(_ radius: Double, sizes: [Double]) throws {
        let tolerance = modelingSettings.tolerance.distance
        guard radius.isFinite, radius == 0 ||
                (radius > tolerance && sizes.allSatisfy({ $0 - 2 * radius > tolerance })) else {
            throw EditorError(code: .commandInvalid,
                message: "Corner must be zero or a positive radius below half the shortest box side.")
        }
    }

    /// Rejects a positive radius the kernel's all-edge fillet cannot build.
    ///
    /// `RoundedBoxFilletBuilder` accepts only an orthogonal box, and `CADDocument.replaceFeature`
    /// does not evaluate, so a corner accepted on any other prism would commit a document that no
    /// longer evaluates and surface as a failure at the next render instead of at this edit.
    /// Zero is always accepted: unwrapping is how such a document is repaired.
    func validateBoxCornerTarget(_ featureID: FeatureID) throws {
        guard case let .extrude(extrude) = cadDocument.designGraph.nodes[featureID]?.operation,
              case let .sketch(sketch) = cadDocument.designGraph.nodes[extrude.profile.featureID]?.operation,
              let profile = try recognizedRectangleProfile(in: sketch) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Rounding every edge requires a box extruded from a rectangle profile."
            )
        }
        guard profile.cornerRadius == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "The profile is already rounded, so its box has no edges left to round."
            )
        }
    }

    mutating func setBoxCorner(
        featureID: FeatureID,
        radius: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let sizes = try resolvedExtrudedBodyDimensions(featureID: featureID)
        try validateBoxCorner(radius, sizes: [sizes.sizeX, sizes.sizeY, sizes.sizeZ])
        guard var visible = cadDocument.designGraph.nodes[featureID],
              var base = cadDocument.designGraph.nodes[boxExtrusionFeatureID(featureID)],
              case .extrude = base.operation else {
            throw EditorError(code: .commandInvalid, message: "Corner requires an editable extruded box.")
        }
        if radius != 0 {
            try validateBoxCornerTarget(base.id)
        }
        var updated = cadDocument
        if radius == 0 {
            guard base.id != featureID else {
                try synchronizeBoxCornerObjectProperties(
                    featureID: featureID,
                    objectRegistry: objectRegistry
                )
                return
            }
            guard !updated.designGraph.dependencies.contains(where: {
                $0.source == base.id && $0.target != featureID
            }) else {
                throw EditorError(code: .commandInvalid, message: "The corner input is shared by another feature.")
            }
            visible.operation = base.operation
            visible.inputs = base.inputs
            updated.designGraph.nodes.removeValue(forKey: base.id)
            updated.designGraph.order.removeAll { $0 == base.id }
            updated.designGraph.dependencies.removeAll { $0.source == base.id || $0.target == base.id }
        } else {
            if base.id == featureID {
                base.id = FeatureID()
                base.name = "Box source"
                guard let index = updated.designGraph.order.firstIndex(of: featureID) else {
                    throw EditorError(code: .referenceUnresolved, message: "Missing box feature order.")
                }
                updated.designGraph.nodes[base.id] = base
                updated.designGraph.order.insert(base.id, at: index)
                updated.designGraph.dependencies.append(contentsOf: base.inputs.map {
                    DependencyEdge(source: $0.featureID, target: base.id)
                })
            }
            visible.operation = .fillet(.init(target: .init(featureID: base.id), edges: [],
                radius: .constant(.length(radius, unit: .meter)), allEdges: true))
            visible.inputs = [.init(featureID: base.id, role: .target)]
        }
        try updated.replaceFeature(visible, tolerance: modelingSettings.tolerance)
        cadDocument = updated
        try synchronizeBoxCornerObjectProperties(featureID: featureID, objectRegistry: objectRegistry)
    }
}

extension DesignDocument {
    /// Routes a rectangle profile's `bevel` to the all-edge fillet on the box it extrudes.
    ///
    /// `bevel` and the body's `corner.radius` name one fillet feature, so the edit lands on the
    /// body rather than on the profile's entities. A profile nothing has extruded yet keeps the
    /// value as latent state; the extrusion that creates its body applies it.
    mutating func setRectangleProfileBevel(
        featureID: FeatureID,
        bevelMeters: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let bodies = extrudedBodyFeatureIDs(forProfile: featureID)
        guard bodies.count <= 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "The profile builds more than one body, so a bevel names no single box."
            )
        }
        guard let bodyFeatureID = bodies.first else {
            try validateLatentRectangleBevel(featureID: featureID, bevelMeters: bevelMeters)
            return
        }
        try setBoxCorner(
            featureID: bodyFeatureID,
            radius: bevelMeters,
            objectRegistry: objectRegistry
        )
    }

    /// Validates a bevel the profile carries while nothing has extruded it.
    ///
    /// The stored value is the whole state until a body exists, so the profile's own sides are the
    /// only bound available. Checking here keeps a value the extrusion would later refuse from
    /// being stored as though it had been applied.
    func validateLatentRectangleBevel(featureID: FeatureID, bevelMeters: Double) throws {
        let profile = try sketchProfileFeature(featureID: featureID, owner: "Rectangle bevel")
        guard let recognized = try recognizedRectangleProfile(in: profile.sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "A bevel requires an axis-aligned rectangle profile."
            )
        }
        guard bevelMeters == 0 || recognized.cornerRadius == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "The profile is already rounded, so its box has no edges left to round."
            )
        }
        try validateBoxCorner(bevelMeters, sizes: [recognized.sizeX, recognized.sizeY])
    }
}
