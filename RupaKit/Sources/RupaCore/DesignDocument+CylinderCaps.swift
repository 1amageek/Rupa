import SwiftCAD
import Foundation
import RupaCoreTypes

extension DesignDocument {
    /// Whether this cylinder's two ends are closed, or `nil` when the body extrudes no profile
    /// family and so has no caps to read.
    ///
    /// A cylinder that has never had its caps cleared reads `true`, which is the solid it was
    /// built as.
    package func cylinderCaps(featureID: FeatureID) throws -> Bool? {
        guard try resolvedCylinderProfile(featureID: featureID) != nil else {
            return nil
        }
        guard case let .extrude(extrude) = cadDocument.designGraph
                .nodes[boxExtrusionFeatureID(featureID)]?.operation else {
            return nil
        }
        return extrude.resultKind == .solid
    }

    /// Opens or closes the two ends of this cylinder's extrusion.
    ///
    /// The profile is untouched: the wall an uncapped cylinder sweeps is the same circle, arc,
    /// annulus or annular sector a capped one sweeps, and only the extrusion's own result kind
    /// says whether the two ends are sewn on. Clearing the caps therefore turns the body from a
    /// solid into a sheet, which moves three values that have to agree — the feature's result
    /// kind, the single output role it declares, and the object's geometry role — so all three
    /// are written before anything is validated and the whole edit is rolled back if any of them
    /// is refused.
    package mutating func setCylinderCaps(
        featureID: FeatureID,
        includesCaps: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard try resolvedCylinderProfile(featureID: featureID) != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Caps require a cylinder built from an editable circle profile."
            )
        }

        // Caps and corner exclude each other for the reason hollow and corner do: an all-edge
        // fillet rounds a solid, and a sheet has no volume for it to round, so an uncapped
        // cylinder committed under a fillet would stop evaluating. The refusal comes before the
        // rewrite.
        if includesCaps == false {
            let cornerRadius = try boxCornerRadius(featureID)
            guard cornerRadius == 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A rounded cylinder cannot lose its caps. Clear the corner radius first."
                )
            }
        }

        let extrudeFeatureID = boxExtrusionFeatureID(featureID)
        guard var node = cadDocument.designGraph.nodes[extrudeFeatureID],
              case var .extrude(extrude) = node.operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Caps require an editable extruded cylinder."
            )
        }

        let resultKind: ExtrudeResultKind = includesCaps ? .solid : .sheet
        extrude.resultKind = resultKind
        node.operation = .extrude(extrude)
        node.outputs = [FeatureOutput(role: resultKind.featureOutputRole)]

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitCaps = false
        defer {
            if didCommitCaps == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        var updated = cadDocument
        try updated.replaceFeature(node, tolerance: modelingSettings.tolerance)
        cadDocument = updated
        try synchronizeCylinderCapsObjectProperty(
            featureID: featureID,
            resultKind: resultKind,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitCaps = true
    }
}

extension ExtrudeResultKind {
    var featureOutputRole: FeaturePort {
        switch self {
        case .solid:
            .body
        case .sheet:
            .sheet
        }
    }

    var objectGeometryRole: ObjectDescriptor.GeometryRole {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .surface
        }
    }
}
