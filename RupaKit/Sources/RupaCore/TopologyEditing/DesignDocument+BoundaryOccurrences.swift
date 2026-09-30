import SwiftCAD

extension DesignDocument {
    /// Refreshes all dependent coordinate maps as one source mutation; true when a map changed,
    /// so a validation of the document before the refresh no longer describes it.
    @discardableResult
    mutating func synchronizeBoundaryOccurrences() throws -> Bool {
        let replacements = try resolvedBoundaryOccurrenceFeatures()
        var candidate = cadDocument
        var changed = false
        for feature in replacements where candidate.designGraph.nodes[feature.id] != feature {
            try candidate.replaceFeature(feature, tolerance: modelingSettings.tolerance)
            changed = true
        }
        cadDocument = candidate
        return changed
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
        try source.coordinateMap(to: output)
    }
}
