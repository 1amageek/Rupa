import Foundation
import RupaCoreTypes

public struct MeshSummaryResult: Codable, Equatable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var bodyCount: Int
    public var vertexCount: Int
    public var normalCount: Int
    public var triangleCount: Int
    public var indexedElementCount: Int
    public var bounds: MeasurementResult.Bounds?
    public var bodies: [Body]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        bodyCount: Int = 0,
        vertexCount: Int = 0,
        normalCount: Int = 0,
        triangleCount: Int = 0,
        indexedElementCount: Int = 0,
        bounds: MeasurementResult.Bounds? = nil,
        bodies: [Body] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.bodyCount = bodyCount
        self.vertexCount = vertexCount
        self.normalCount = normalCount
        self.triangleCount = triangleCount
        self.indexedElementCount = indexedElementCount
        self.bounds = bounds
        self.bodies = bodies
        self.diagnostics = diagnostics
    }

    public var message: String {
        if let bounds {
            return "Mesh summary: \(bodyCount) bodies, \(vertexCount) vertices, \(triangleCount) triangles, \(bounds.formattedSize(in: displayUnit)) bounds."
        }
        return "Mesh summary: \(bodyCount) bodies, \(vertexCount) vertices, \(triangleCount) triangles."
    }
}

public extension MeshSummaryResult {
    struct Body: Codable, Equatable, Sendable {
        public var bodyID: String
        public var vertexCount: Int
        public var normalCount: Int
        public var triangleCount: Int
        public var indexedElementCount: Int
        public var materialID: String?
        public var bounds: MeasurementResult.Bounds

        public init(
            bodyID: String,
            vertexCount: Int,
            normalCount: Int,
            triangleCount: Int,
            indexedElementCount: Int,
            materialID: String?,
            bounds: MeasurementResult.Bounds
        ) {
            self.bodyID = bodyID
            self.vertexCount = vertexCount
            self.normalCount = normalCount
            self.triangleCount = triangleCount
            self.indexedElementCount = indexedElementCount
            self.materialID = materialID
            self.bounds = bounds
        }
    }
}
