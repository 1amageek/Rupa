import RupaGeometry

/// One original provider output; meshes and provenance remain immutable.
public struct GeometryEvaluationPart: Equatable, Sendable {
    public let mesh: MeshSource
    public let localBounds: GeometryBounds3D
    public let copyTelemetry: GeometryCopyTelemetry
    public let sourceBodyID: String?
    public let sourceFeatureID: String?
    public let outputRole: String?

    public init(mesh: MeshSource, localBounds: GeometryBounds3D,
                copyTelemetry: GeometryCopyTelemetry = GeometryCopyTelemetry(),
                sourceBodyID: String? = nil, sourceFeatureID: String? = nil, outputRole: String? = nil) {
        self.mesh = mesh
        self.localBounds = localBounds
        self.copyTelemetry = copyTelemetry
        self.sourceBodyID = sourceBodyID
        self.sourceFeatureID = sourceFeatureID
        self.outputRole = outputRole
    }
    public static func metadataByteCount(sourceBodyID: String?, sourceFeatureID: String?, outputRole: String?) throws -> Int {
        var total = MemoryLayout<Self>.stride
        for value in [sourceBodyID, sourceFeatureID, outputRole] {
            guard let value else { continue }
            let sum = total.addingReportingOverflow(value.utf8.count)
            guard sum.overflow == false else {
                throw EvaluationError(code: .resourceExhausted, message: "Original output-part metadata exceeds the representable budget.")
            }
            total = sum.partialValue
        }
        return total
    }

    public func metadataByteCount() throws -> Int {
        try Self.metadataByteCount(sourceBodyID: sourceBodyID, sourceFeatureID: sourceFeatureID, outputRole: outputRole)
    }

}
