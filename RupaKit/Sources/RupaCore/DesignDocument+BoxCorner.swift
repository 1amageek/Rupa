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

    func validateAllEdgeCorner(_ radius: Double, on target: AllEdgeFilletTarget) throws {
        let tolerance = modelingSettings.tolerance.distance
        guard radius.isFinite, radius == 0 ||
                (radius > tolerance && target.admits(radius, tolerance: tolerance)) else {
            throw EditorError(code: .commandInvalid,
                message: "Corner must be zero or a positive radius the body's own dimensions leave room for.")
        }
    }

    /// The prism the kernel would round for this body, or `nil` when the body is not one it
    /// rounds and so publishes no corner bound at all.
    ///
    /// `height` proposes a depth the document does not carry yet, so an extrusion can check the
    /// corner its own new depth has to admit before it commits to it.
    func allEdgeFilletTarget(
        featureID: FeatureID,
        height: Double? = nil
    ) throws -> AllEdgeFilletTarget? {
        guard case let .extrude(extrude) = cadDocument.designGraph
                .nodes[boxExtrusionFeatureID(featureID)]?.operation,
              case let .sketch(sketch) = cadDocument.designGraph
                .nodes[extrude.profile.featureID]?.operation else {
            return nil
        }
        guard let profile = try recognizedAllEdgeFilletProfile(in: sketch) else {
            return nil
        }
        // The body's resolved dimensions carry the depth every prism is bounded along, and for the
        // two the kernel measures from their outer extent they are the cross-section as well: a
        // cylinder's span across the axis is its diameter. The other two profiles measure a side
        // and a cap arc, neither of which the extent names.
        let sizes = try resolvedExtrudedBodyDimensions(featureID: featureID)
        let depth = height ?? sizes.sizeY
        switch profile {
        case .circle:
            return .cylinder(radius: sizes.sizeX / 2.0, height: depth)
        case .rectangle:
            return .box(sizes: [sizes.sizeX, depth, sizes.sizeZ])
        case let .regularPolygon(sideLength, sideCount):
            return .regularPolygon(sideLength: sideLength, sideCount: sideCount, height: depth)
        case let .stadium(capRadius):
            return .stadium(capRadius: capRadius, height: depth)
        }
    }

    /// The largest corner radius this body accepts, or `nil` when it accepts none.
    ///
    /// The kernel refuses its own bound, so the value sits one tolerance inside it and the end of
    /// a control bound by it is always an edit that applies. The Inspector reads the bound from
    /// here rather than deriving one from the dimensions it displays.
    package func maximumAllEdgeCornerRadius(featureID: FeatureID) throws -> Double? {
        guard let target = try allEdgeFilletTarget(featureID: featureID) else { return nil }
        let tolerance = modelingSettings.tolerance.distance
        return max(0, target.radiusBound(tolerance: tolerance) - tolerance)
    }

    /// Rejects a positive radius the kernel's all-edge fillet cannot build.
    ///
    /// `AllEdgeFilletBuilder` accepts the four profiles `AllEdgeFilletProfile` names, and
    /// `CADDocument.replaceFeature` does not evaluate, so a corner accepted on any other prism
    /// would commit a document that no longer evaluates and surface as a failure at the next
    /// render instead of at this edit. Zero is always accepted: unwrapping is how such a document
    /// is repaired.
    func validateBoxCornerTarget(_ featureID: FeatureID) throws {
        guard case let .extrude(extrude) = cadDocument.designGraph.nodes[featureID]?.operation,
              case let .sketch(sketch) = cadDocument.designGraph.nodes[extrude.profile.featureID]?.operation,
              let profile = try recognizedAllEdgeFilletProfile(in: sketch) else {
            throw unroundableAllEdgeTarget()
        }
        // Only the rectangle can already carry rounding of its own; the other three profiles have
        // no corner property to have spent, so the dimensions are their whole precondition.
        if case let .rectangle(_, _, cornerRadius) = profile, cornerRadius != 0 {
            throw EditorError(
                code: .commandInvalid,
                message: "The profile is already rounded, so its box has no edges left to round."
            )
        }
    }

    func unroundableAllEdgeTarget() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Rounding every edge requires a box, a cylinder, a regular polygon prism, or a slot along one straight segment."
        )
    }

    mutating func setBoxCorner(
        featureID: FeatureID,
        radius: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard radius.isFinite else {
            throw EditorError(code: .commandInvalid,
                message: "Corner must be zero or a positive radius the body's own dimensions leave room for.")
        }
        if radius != 0 {
            guard let target = try allEdgeFilletTarget(featureID: featureID) else {
                throw unroundableAllEdgeTarget()
            }
            try validateAllEdgeCorner(radius, on: target)
        }
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
                base.name = "Corner source"
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
    /// Routes a profile's `bevel` to the all-edge fillet on the body it extrudes.
    ///
    /// `bevel` and the body's `corner.radius` name one fillet feature, so the edit lands on the
    /// body rather than on the profile's entities. A profile nothing has extruded yet keeps the
    /// value as latent state; the extrusion that creates its body applies it.
    mutating func setProfileBevel(
        featureID: FeatureID,
        bevelMeters: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let bodies = extrudedBodyFeatureIDs(forProfile: featureID)
        guard bodies.count <= 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "The profile builds more than one body, so a bevel names no single one."
            )
        }
        guard let bodyFeatureID = bodies.first else {
            try validateLatentProfileBevel(featureID: featureID, bevelMeters: bevelMeters)
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
    /// The stored value is the whole state until a body exists, so the profile's own extent is the
    /// only bound available. Checking here keeps a value the extrusion would later refuse from
    /// being stored as though it had been applied.
    func validateLatentProfileBevel(featureID: FeatureID, bevelMeters: Double) throws {
        let profile = try sketchProfileFeature(featureID: featureID, owner: "Profile bevel")
        // Zero is what a profile outside every family is allowed to hold, and clearing the value is
        // how one that was edited out of its family is repaired, so it is accepted before the
        // family is resolved rather than after.
        guard bevelMeters != 0 else { return }
        guard let recognized = try recognizedAllEdgeFilletProfile(in: profile.sketch) else {
            throw unroundableAllEdgeTarget()
        }
        // Nothing has extruded this profile, so the prism it will become has no height to bound the
        // bevel and only its cross-section does.
        switch recognized {
        case let .circle(radius):
            try validateAllEdgeCorner(bevelMeters, on: .cylinder(radius: radius, height: nil))
        case let .rectangle(sizeX, sizeY, cornerRadius):
            guard cornerRadius == 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The profile is already rounded, so its box has no edges left to round."
                )
            }
            try validateAllEdgeCorner(bevelMeters, on: .box(sizes: [sizeX, sizeY]))
        case let .regularPolygon(sideLength, sideCount):
            try validateAllEdgeCorner(
                bevelMeters,
                on: .regularPolygon(sideLength: sideLength, sideCount: sideCount, height: nil)
            )
        case let .stadium(capRadius):
            try validateAllEdgeCorner(bevelMeters, on: .stadium(capRadius: capRadius, height: nil))
        }
    }
}
