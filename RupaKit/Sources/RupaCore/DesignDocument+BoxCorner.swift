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

    mutating func setBoxCorner(featureID: FeatureID, radius: Double) throws {
        let sizes = try resolvedExtrudedBodyDimensions(featureID: featureID)
        try validateBoxCorner(radius, sizes: [sizes.sizeX, sizes.sizeY, sizes.sizeZ])
        guard var visible = cadDocument.designGraph.nodes[featureID],
              var base = cadDocument.designGraph.nodes[boxExtrusionFeatureID(featureID)],
              case .extrude = base.operation else {
            throw EditorError(code: .commandInvalid, message: "Corner requires an editable extruded box.")
        }
        var updated = cadDocument
        if radius == 0 {
            guard base.id != featureID else { return }
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
    }
}
