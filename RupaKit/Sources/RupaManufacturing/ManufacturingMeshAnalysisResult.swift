import RupaCore
import SwiftCAD

public struct ManufacturingMeshAnalysisResult: Equatable, Sendable {
    public var meshArtifact: MeshArtifactReference?
    public var bodyAnalyses: [BodyAnalysis]
    public var totalSurfaceAreaSquareMeters: Double
    public var totalOverhangAreaSquareMeters: Double
    public var totalSupportContactAreaSquareMeters: Double
    public var minimumWallThicknessMeters: Double?
    public var minimumBodyClearanceMeters: Double?
    public var minimumBodyClearanceRegion: ValidationRegionReference?

    public init(
        meshArtifact: MeshArtifactReference? = nil,
        bodyAnalyses: [BodyAnalysis],
        totalSurfaceAreaSquareMeters: Double,
        totalOverhangAreaSquareMeters: Double,
        totalSupportContactAreaSquareMeters: Double,
        minimumWallThicknessMeters: Double? = nil,
        minimumBodyClearanceMeters: Double? = nil,
        minimumBodyClearanceRegion: ValidationRegionReference? = nil
    ) {
        self.meshArtifact = meshArtifact
        self.bodyAnalyses = bodyAnalyses
        self.totalSurfaceAreaSquareMeters = totalSurfaceAreaSquareMeters
        self.totalOverhangAreaSquareMeters = totalOverhangAreaSquareMeters
        self.totalSupportContactAreaSquareMeters = totalSupportContactAreaSquareMeters
        self.minimumWallThicknessMeters = minimumWallThicknessMeters
        self.minimumBodyClearanceMeters = minimumBodyClearanceMeters
        self.minimumBodyClearanceRegion = minimumBodyClearanceRegion
    }

    public static let empty = ManufacturingMeshAnalysisResult(
        meshArtifact: nil,
        bodyAnalyses: [],
        totalSurfaceAreaSquareMeters: 0.0,
        totalOverhangAreaSquareMeters: 0.0,
        totalSupportContactAreaSquareMeters: 0.0,
        minimumWallThicknessMeters: nil,
        minimumBodyClearanceMeters: nil,
        minimumBodyClearanceRegion: nil
    )

    public var hasExportReadinessFailures: Bool {
        bodyAnalyses.contains { !$0.isExportReady }
    }

    public var hasSupportabilityWarnings: Bool {
        totalOverhangAreaSquareMeters > 0.0
    }

    public var exportReadyBodyCount: Int {
        bodyAnalyses.filter(\.isExportReady).count
    }

    public var validationRegions: [ValidationRegionReference] {
        bodyAnalyses.flatMap { analysis in
            [analysis.overhangRegion, analysis.minimumWallThicknessRegion].compactMap { $0 }
        } + [minimumBodyClearanceRegion].compactMap { $0 }
    }

    public struct BodyAnalysis: Equatable, Sendable {
        public var bodyID: BodyID
        public var bodyKind: String?
        public var triangleCount: Int
        public var surfaceAreaSquareMeters: Double
        public var overhangAreaSquareMeters: Double
        public var overhangTriangleCount: Int
        public var supportContactAreaSquareMeters: Double
        public var minimumWallThicknessMeters: Double?
        public var overhangRegion: ValidationRegionReference?
        public var minimumWallThicknessRegion: ValidationRegionReference?
        public var boundaryEdgeCount: Int
        public var nonManifoldEdgeCount: Int
        public var degenerateTriangleCount: Int
        public var invalidIndexCount: Int
        public var minimumEdgeLengthMeters: Double?
        public var validationErrorMessage: String?

        public init(
            bodyID: BodyID,
            bodyKind: String?,
            triangleCount: Int,
            surfaceAreaSquareMeters: Double,
            overhangAreaSquareMeters: Double,
            overhangTriangleCount: Int,
            supportContactAreaSquareMeters: Double,
            minimumWallThicknessMeters: Double?,
            overhangRegion: ValidationRegionReference? = nil,
            minimumWallThicknessRegion: ValidationRegionReference? = nil,
            boundaryEdgeCount: Int,
            nonManifoldEdgeCount: Int,
            degenerateTriangleCount: Int,
            invalidIndexCount: Int,
            minimumEdgeLengthMeters: Double?,
            validationErrorMessage: String?
        ) {
            self.bodyID = bodyID
            self.bodyKind = bodyKind
            self.triangleCount = triangleCount
            self.surfaceAreaSquareMeters = surfaceAreaSquareMeters
            self.overhangAreaSquareMeters = overhangAreaSquareMeters
            self.overhangTriangleCount = overhangTriangleCount
            self.supportContactAreaSquareMeters = supportContactAreaSquareMeters
            self.minimumWallThicknessMeters = minimumWallThicknessMeters
            self.overhangRegion = overhangRegion
            self.minimumWallThicknessRegion = minimumWallThicknessRegion
            self.boundaryEdgeCount = boundaryEdgeCount
            self.nonManifoldEdgeCount = nonManifoldEdgeCount
            self.degenerateTriangleCount = degenerateTriangleCount
            self.invalidIndexCount = invalidIndexCount
            self.minimumEdgeLengthMeters = minimumEdgeLengthMeters
            self.validationErrorMessage = validationErrorMessage
        }

        public var isExportReady: Bool {
            validationErrorMessage == nil
                && bodyKind == "solid"
                && boundaryEdgeCount == 0
                && nonManifoldEdgeCount == 0
                && degenerateTriangleCount == 0
                && invalidIndexCount == 0
        }
    }
}

extension ManufacturingMeshAnalysisResult {
    var payload: SemanticJSONValue {
        var object: [String: SemanticJSONValue] = [
            "bodyCount": .number(Double(bodyAnalyses.count)),
            "exportReadyBodyCount": .number(Double(exportReadyBodyCount)),
            "totalSurfaceAreaSquareMeters": .number(totalSurfaceAreaSquareMeters),
            "totalOverhangAreaSquareMeters": .number(totalOverhangAreaSquareMeters),
            "totalSupportContactAreaSquareMeters": .number(totalSupportContactAreaSquareMeters),
            "bodies": .array(bodyAnalyses.map(\.payload)),
        ]
        if let meshArtifact {
            object["meshArtifact"] = .object([
                "documentID": .string(meshArtifact.documentID.description),
                "computationFingerprint": .object([
                    "algorithm": .string(meshArtifact.artifact.computation.fingerprint.algorithm),
                    "value": .string(meshArtifact.artifact.computation.fingerprint.value),
                ]),
                "contentFingerprint": .object([
                    "algorithm": .string(meshArtifact.artifact.contentFingerprint.algorithm),
                    "value": .string(meshArtifact.artifact.contentFingerprint.value),
                ]),
                "artifactFingerprint": .object([
                    "algorithm": .string(meshArtifact.artifact.fingerprint.algorithm),
                    "value": .string(meshArtifact.artifact.fingerprint.value),
                ]),
            ])
        }
        if let minimumWallThicknessMeters {
            object["minimumWallThicknessMeters"] = .number(minimumWallThicknessMeters)
        }
        if let minimumBodyClearanceMeters {
            object["minimumBodyClearanceMeters"] = .number(minimumBodyClearanceMeters)
        }
        if let minimumBodyClearanceRegion {
            object["minimumBodyClearanceRegion"] = minimumBodyClearanceRegion.semanticJSONValue
        }
        return .object(object)
    }
}

private extension ManufacturingMeshAnalysisResult.BodyAnalysis {
    var payload: SemanticJSONValue {
        var object: [String: SemanticJSONValue] = [
            "bodyID": .string(bodyID.description),
            "triangleCount": .number(Double(triangleCount)),
            "surfaceAreaSquareMeters": .number(surfaceAreaSquareMeters),
            "overhangAreaSquareMeters": .number(overhangAreaSquareMeters),
            "overhangTriangleCount": .number(Double(overhangTriangleCount)),
            "supportContactAreaSquareMeters": .number(supportContactAreaSquareMeters),
            "boundaryEdgeCount": .number(Double(boundaryEdgeCount)),
            "nonManifoldEdgeCount": .number(Double(nonManifoldEdgeCount)),
            "degenerateTriangleCount": .number(Double(degenerateTriangleCount)),
            "invalidIndexCount": .number(Double(invalidIndexCount)),
            "isExportReady": .bool(isExportReady),
        ]
        if let bodyKind {
            object["bodyKind"] = .string(bodyKind)
        }
        if let minimumEdgeLengthMeters {
            object["minimumEdgeLengthMeters"] = .number(minimumEdgeLengthMeters)
        }
        if let minimumWallThicknessMeters {
            object["minimumWallThicknessMeters"] = .number(minimumWallThicknessMeters)
        }
        if let overhangRegion {
            object["overhangRegion"] = overhangRegion.semanticJSONValue
        }
        if let minimumWallThicknessRegion {
            object["minimumWallThicknessRegion"] = minimumWallThicknessRegion.semanticJSONValue
        }
        if let validationErrorMessage {
            object["validationErrorMessage"] = .string(validationErrorMessage)
        }
        return .object(object)
    }
}
