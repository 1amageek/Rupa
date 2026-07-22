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
        public var materialCoverage: MeshMaterialCoverage?
        public var generatedFaceCount: Int?
        public var unassignedFaceMaterialCount: Int?
        public var faceMaterialBindings: [FaceMaterialBinding]?
        public var bounds: MeasurementResult.Bounds

        public init(
            bodyID: String,
            vertexCount: Int,
            normalCount: Int,
            triangleCount: Int,
            indexedElementCount: Int,
            materialID: String?,
            materialCoverage: MeshMaterialCoverage? = nil,
            generatedFaceCount: Int? = nil,
            unassignedFaceMaterialCount: Int? = nil,
            faceMaterialBindings: [FaceMaterialBinding]? = nil,
            bounds: MeasurementResult.Bounds
        ) {
            self.bodyID = bodyID
            self.vertexCount = vertexCount
            self.normalCount = normalCount
            self.triangleCount = triangleCount
            self.indexedElementCount = indexedElementCount
            self.materialID = materialID
            self.materialCoverage = materialCoverage
            self.generatedFaceCount = generatedFaceCount
            self.unassignedFaceMaterialCount = unassignedFaceMaterialCount
            self.faceMaterialBindings = faceMaterialBindings
            self.bounds = bounds
        }
    }

    struct FaceMaterialBinding: Codable, Equatable, Sendable {
        public var stableReference: StableSubshapeReference
        public var faceID: String
        public var materialID: String?
        public var processNamespace: String?
        public var processID: String?

        public init(
            stableReference: StableSubshapeReference,
            faceID: String,
            materialID: String?,
            processNamespace: String? = nil,
            processID: String? = nil
        ) {
            self.stableReference = stableReference
            self.faceID = faceID
            self.materialID = materialID
            self.processNamespace = processNamespace
            self.processID = processID
        }
    }
}
