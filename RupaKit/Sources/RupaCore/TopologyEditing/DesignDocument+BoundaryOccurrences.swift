import SwiftCAD

extension DesignDocument {
    /// Refreshes all dependent coordinate maps as one source mutation.
    mutating func synchronizeBoundaryOccurrences() throws {
        let replacements = try resolvedBoundaryOccurrenceFeatures()
        var candidate = cadDocument
        for feature in replacements where candidate.designGraph.nodes[feature.id] != feature {
            try candidate.replaceFeature(feature, tolerance: modelingSettings.tolerance)
        }
        cadDocument = candidate
    }

    func validateBoundaryOccurrences() throws {
        for feature in try resolvedBoundaryOccurrenceFeatures() {
            guard cadDocument.designGraph.nodes[feature.id] == feature else {
                throw EditorError(code: .commandInvalid,
                    message: "Boundary coordinate maps do not match their retained scene occurrences.")
            }
        }
    }

    private func resolvedBoundaryOccurrenceFeatures() throws -> [FeatureNode] {
        let owners = productMetadata.sceneNodes.values.filter { $0.boundaryOccurrences != nil }
        guard !owners.isEmpty else { return [] }
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        var ownedFeatures: Set<FeatureID> = []
        return try owners.map { node in
            guard let binding = node.boundaryOccurrences,
                  let featureID = node.object?.sourceFeatureID,
                  var feature = cadDocument.designGraph.nodes[featureID],
                  case let .bridgeSurface(bridge) = feature.operation,
                  ownedFeatures.insert(featureID).inserted,
                  productMetadata.sceneNodes[binding.first]?.object?.sourceFeatureID == bridge.startBoundary.subshapeID.featureID,
                  productMetadata.sceneNodes[binding.second]?.object?.sourceFeatureID == bridge.endBoundary.subshapeID.featureID else {
                throw EditorError(code: .referenceUnresolved,
                    message: "Boundary occurrences must identify current sources and one output owner.")
            }
            let output = try hierarchy.worldTransform(of: node.id)
            feature.operation = .bridgeSurface(BridgeSurfaceFeature(
                startBoundary: bridge.startBoundary, endBoundary: bridge.endBoundary,
                endOrientation: bridge.endOrientation,
                startTransform: try Self.boundaryCoordinateMap(from: hierarchy.worldTransform(of: binding.first), to: output),
                endTransform: try Self.boundaryCoordinateMap(from: hierarchy.worldTransform(of: binding.second), to: output)))
            return feature
        }
    }

    static func boundaryCoordinateMap(from source: Transform3D, to output: Transform3D) throws -> AffineTransform3D? {
        for frame in [source, output] {
            try frame.validate()
            let values = frame.matrix.values
            guard values[12] == 0, values[13] == 0, values[14] == 0, values[15] == 1 else {
                throw EditorError(code: .commandInvalid, message: "Boundary placement requires affine source and output frames.")
            }
        }
        // Equal frames retain the native identity representation without inverse roundoff.
        let transform = try output.inverse().composed(with: source)
        let m = transform.matrix.values
        guard m[12] == 0, m[13] == 0, m[14] == 0, m[15] == 1 else {
            throw EditorError(code: .commandInvalid, message: "Boundary placement requires affine coordinate frames.")
        }
        _ = try source.inverse()
        if source == output { return nil }
        return try AffineTransform3D(
            basisX: Vector3D(x: m[0], y: m[4], z: m[8]),
            basisY: Vector3D(x: m[1], y: m[5], z: m[9]),
            basisZ: Vector3D(x: m[2], y: m[6], z: m[10]),
            translation: Vector3D(x: m[3], y: m[7], z: m[11]))
    }
}
