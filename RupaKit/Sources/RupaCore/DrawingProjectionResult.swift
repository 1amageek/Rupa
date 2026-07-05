import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DrawingProjectionResult: Codable, Equatable, Sendable {
    public enum ProjectionMode: String, Codable, Equatable, Sendable {
        case orthographic
        case perspective
    }

    public enum StrokeKind: String, Codable, Equatable, Sendable {
        case boundary
        case crease
    }

    public enum Visibility: String, Codable, Equatable, Sendable {
        case unclassified
    }

    public struct ViewFrame: Codable, Equatable, Sendable {
        public var target: Point3D
        public var right: Vector3D
        public var up: Vector3D
        public var viewNormal: Vector3D
        public var visibleHeightMeters: Double
        public var scaleBarLengthMeters: Double

        public init(
            target: Point3D,
            right: Vector3D,
            up: Vector3D,
            viewNormal: Vector3D,
            visibleHeightMeters: Double,
            scaleBarLengthMeters: Double
        ) {
            self.target = target
            self.right = right
            self.up = up
            self.viewNormal = viewNormal
            self.visibleHeightMeters = visibleHeightMeters
            self.scaleBarLengthMeters = scaleBarLengthMeters
        }
    }

    public struct Bounds2D: Codable, Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(
            minX: Double,
            minY: Double,
            maxX: Double,
            maxY: Double
        ) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }
    }

    public struct Stroke: Codable, Equatable, Sendable {
        public var id: String
        public var bodyID: String
        public var kind: StrokeKind
        public var visibility: Visibility
        public var start: Point3D
        public var end: Point3D
        public var start2D: Point2D
        public var end2D: Point2D
        public var minimumDepthMeters: Double
        public var maximumDepthMeters: Double
        public var lengthMeters: Double

        public init(
            id: String,
            bodyID: String,
            kind: StrokeKind,
            visibility: Visibility,
            start: Point3D,
            end: Point3D,
            start2D: Point2D,
            end2D: Point2D,
            minimumDepthMeters: Double,
            maximumDepthMeters: Double,
            lengthMeters: Double
        ) {
            self.id = id
            self.bodyID = bodyID
            self.kind = kind
            self.visibility = visibility
            self.start = start
            self.end = end
            self.start2D = start2D
            self.end2D = end2D
            self.minimumDepthMeters = minimumDepthMeters
            self.maximumDepthMeters = maximumDepthMeters
            self.lengthMeters = lengthMeters
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var savedViewID: SavedViewID
    public var savedViewName: String
    public var projectionMode: ProjectionMode
    public var viewFrame: ViewFrame
    public var bodyCount: Int
    public var triangleCount: Int
    public var candidateEdgeCount: Int
    public var strokeCount: Int
    public var truncatedStrokes: Bool
    public var bounds: Bounds2D?
    public var strokes: [Stroke]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        savedViewID: SavedViewID,
        savedViewName: String,
        projectionMode: ProjectionMode,
        viewFrame: ViewFrame,
        bodyCount: Int,
        triangleCount: Int,
        candidateEdgeCount: Int,
        strokeCount: Int? = nil,
        truncatedStrokes: Bool,
        bounds: Bounds2D?,
        strokes: [Stroke],
        diagnostics: [EditorDiagnostic]
    ) {
        self.displayUnit = displayUnit
        self.savedViewID = savedViewID
        self.savedViewName = savedViewName
        self.projectionMode = projectionMode
        self.viewFrame = viewFrame
        self.bodyCount = bodyCount
        self.triangleCount = triangleCount
        self.candidateEdgeCount = candidateEdgeCount
        self.strokeCount = strokeCount ?? strokes.count
        self.truncatedStrokes = truncatedStrokes
        self.bounds = bounds
        self.strokes = strokes
        self.diagnostics = diagnostics
    }
}
