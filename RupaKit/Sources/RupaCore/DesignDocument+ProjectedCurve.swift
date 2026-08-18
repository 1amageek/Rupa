import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createProjectedCurve(
        name: String,
        source: CurveOutputReference,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        direction: Vector3D? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedName = try normalizedMetadataName(name, owner: "Projected curve")
        let operation = FeatureOperation.projectCurve(ProjectCurveFeature(
            source: source,
            planeOrigin: planeOrigin,
            planeNormal: planeNormal,
            direction: direction
        ))
        let feature = try FeatureNodeFactory.make(
            operation: operation,
            name: resolvedName,
            in: cadDocument,
            tolerance: modelingSettings.tolerance
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: resolvedName,
            reference: .feature(feature.id)
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return feature.id
    }
}
