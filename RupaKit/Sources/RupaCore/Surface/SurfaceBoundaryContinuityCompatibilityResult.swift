import SwiftCAD
import RupaCoreTypes

public struct SurfaceBoundaryContinuityCompatibilityResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case compatible
        case incompatible
    }

    public enum Severity: String, Codable, Equatable, Sendable {
        case info
        case warning
        case error
    }

    public struct Diagnostic: Codable, Equatable, Sendable {
        public var severity: Severity
        public var code: String
        public var message: String

        public init(
            severity: Severity,
            code: String,
            message: String
        ) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public struct Boundary: Codable, Equatable, Sendable {
        public var featureID: FeatureID
        public var selectionReference: SelectionReference
        public var role: String
        public var boundaryDirection: SurfaceParameterDirection
        public var inwardDirection: SurfaceParameterDirection
        public var boundaryDegree: Int
        public var inwardDegree: Int
        public var boundaryControlPointCount: Int
        public var inwardControlPointCount: Int
        public var isClamped: Bool
        public var supportedContinuityLevels: [SurfaceBoundaryContinuityLevel]

        public init(
            featureID: FeatureID,
            selectionReference: SelectionReference,
            role: String,
            boundaryDirection: SurfaceParameterDirection,
            inwardDirection: SurfaceParameterDirection,
            boundaryDegree: Int,
            inwardDegree: Int,
            boundaryControlPointCount: Int,
            inwardControlPointCount: Int,
            isClamped: Bool,
            supportedContinuityLevels: [SurfaceBoundaryContinuityLevel]
        ) {
            self.featureID = featureID
            self.selectionReference = selectionReference
            self.role = role
            self.boundaryDirection = boundaryDirection
            self.inwardDirection = inwardDirection
            self.boundaryDegree = boundaryDegree
            self.inwardDegree = inwardDegree
            self.boundaryControlPointCount = boundaryControlPointCount
            self.inwardControlPointCount = inwardControlPointCount
            self.isClamped = isClamped
            self.supportedContinuityLevels = supportedContinuityLevels
        }
    }

    public var status: Status
    public var target: Boundary
    public var reference: Boundary
    public var supportedContinuityLevels: [SurfaceBoundaryContinuityLevel]
    public var maximumSupportedContinuityLevel: SurfaceBoundaryContinuityLevel?
    public var recommendedReferenceDirection: SurfaceBoundaryReferenceDirection?
    public var recommendedMatchSide: SurfaceBoundaryMatchSide?
    public var diagnostics: [Diagnostic]

    public init(
        status: Status,
        target: Boundary,
        reference: Boundary,
        supportedContinuityLevels: [SurfaceBoundaryContinuityLevel],
        maximumSupportedContinuityLevel: SurfaceBoundaryContinuityLevel?,
        recommendedReferenceDirection: SurfaceBoundaryReferenceDirection?,
        recommendedMatchSide: SurfaceBoundaryMatchSide?,
        diagnostics: [Diagnostic]
    ) {
        self.status = status
        self.target = target
        self.reference = reference
        self.supportedContinuityLevels = supportedContinuityLevels
        self.maximumSupportedContinuityLevel = maximumSupportedContinuityLevel
        self.recommendedReferenceDirection = recommendedReferenceDirection
        self.recommendedMatchSide = recommendedMatchSide
        self.diagnostics = diagnostics
    }
}
