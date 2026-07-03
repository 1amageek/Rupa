import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SectionAnalysisQuery: Codable, Equatable, Sendable {
    public enum Source: Codable, Equatable, Sendable {
        case sketchPlane(SketchPlane)
        case constructionPlane(ConstructionPlaneSourceID)
        case activeConstructionPlane
        case sceneNode(SceneNodeID)
    }

    public var source: Source
    public var offsetMeters: Double
    public var flipsNormal: Bool
    public var toleranceMeters: Double?
    public var includesIntersectionSegments: Bool
    public var maximumIntersectionSegments: Int

    public init(
        source: Source,
        offsetMeters: Double = 0.0,
        flipsNormal: Bool = false,
        toleranceMeters: Double? = nil,
        includesIntersectionSegments: Bool = true,
        maximumIntersectionSegments: Int = 10_000
    ) {
        self.source = source
        self.offsetMeters = offsetMeters
        self.flipsNormal = flipsNormal
        self.toleranceMeters = toleranceMeters
        self.includesIntersectionSegments = includesIntersectionSegments
        self.maximumIntersectionSegments = maximumIntersectionSegments
    }
}

public struct SectionAnalysisResult: Codable, Equatable, Sendable {
    public enum PlaneSourceKind: String, Codable, Equatable, Sendable {
        case sketchPlane
        case constructionPlane
        case activeConstructionPlane
        case sceneNode
    }

    public enum BodyClassification: String, Codable, Equatable, Sendable {
        case inFront
        case behind
        case coplanar
        case touching
        case intersects
        case spansPlane
    }

    public struct Plane: Codable, Equatable, Sendable {
        public var sourceKind: PlaneSourceKind
        public var sourceID: String?
        public var sourceName: String?
        public var origin: Point3D
        public var normal: Vector3D
        public var u: Vector3D
        public var v: Vector3D

        public init(
            sourceKind: PlaneSourceKind,
            sourceID: String?,
            sourceName: String?,
            origin: Point3D,
            normal: Vector3D,
            u: Vector3D,
            v: Vector3D
        ) {
            self.sourceKind = sourceKind
            self.sourceID = sourceID
            self.sourceName = sourceName
            self.origin = origin
            self.normal = normal
            self.u = u
            self.v = v
        }
    }

    public struct Body: Codable, Equatable, Sendable {
        public var bodyID: String
        public var sourceFeatureID: String?
        public var persistentName: String?
        public var name: String?
        public var kind: BodyKind?
        public var materialID: String?
        public var classification: BodyClassification
        public var vertexCount: Int
        public var triangleCount: Int
        public var frontVertexCount: Int
        public var behindVertexCount: Int
        public var coplanarVertexCount: Int
        public var frontTriangleCount: Int
        public var behindTriangleCount: Int
        public var coplanarTriangleCount: Int
        public var touchingTriangleCount: Int
        public var intersectingTriangleCount: Int
        public var intersectionSegmentCount: Int

        public init(
            bodyID: String,
            sourceFeatureID: String? = nil,
            persistentName: String? = nil,
            name: String?,
            kind: BodyKind?,
            materialID: String?,
            classification: BodyClassification,
            vertexCount: Int,
            triangleCount: Int,
            frontVertexCount: Int,
            behindVertexCount: Int,
            coplanarVertexCount: Int,
            frontTriangleCount: Int,
            behindTriangleCount: Int,
            coplanarTriangleCount: Int,
            touchingTriangleCount: Int,
            intersectingTriangleCount: Int,
            intersectionSegmentCount: Int
        ) {
            self.bodyID = bodyID
            self.sourceFeatureID = sourceFeatureID
            self.persistentName = persistentName
            self.name = name
            self.kind = kind
            self.materialID = materialID
            self.classification = classification
            self.vertexCount = vertexCount
            self.triangleCount = triangleCount
            self.frontVertexCount = frontVertexCount
            self.behindVertexCount = behindVertexCount
            self.coplanarVertexCount = coplanarVertexCount
            self.frontTriangleCount = frontTriangleCount
            self.behindTriangleCount = behindTriangleCount
            self.coplanarTriangleCount = coplanarTriangleCount
            self.touchingTriangleCount = touchingTriangleCount
            self.intersectingTriangleCount = intersectingTriangleCount
            self.intersectionSegmentCount = intersectionSegmentCount
        }
    }

    public struct IntersectionSegment: Codable, Equatable, Sendable {
        public var bodyID: String
        public var start: Point3D
        public var end: Point3D
        public var start2D: Point2D
        public var end2D: Point2D

        public init(
            bodyID: String,
            start: Point3D,
            end: Point3D,
            start2D: Point2D,
            end2D: Point2D
        ) {
            self.bodyID = bodyID
            self.start = start
            self.end = end
            self.start2D = start2D
            self.end2D = end2D
        }
    }

    public struct IntersectionContour: Codable, Equatable, Sendable {
        public var id: String
        public var bodyID: String
        public var points: [Point3D]
        public var points2D: [Point2D]
        public var isClosed: Bool
        public var signedAreaSquareMeters: Double
        public var lengthMeters: Double
        public var segmentCount: Int

        public init(
            id: String,
            bodyID: String,
            points: [Point3D],
            points2D: [Point2D],
            isClosed: Bool,
            signedAreaSquareMeters: Double,
            lengthMeters: Double,
            segmentCount: Int
        ) {
            self.id = id
            self.bodyID = bodyID
            self.points = points
            self.points2D = points2D
            self.isClosed = isClosed
            self.signedAreaSquareMeters = signedAreaSquareMeters
            self.lengthMeters = lengthMeters
            self.segmentCount = segmentCount
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var plane: Plane
    public var toleranceMeters: Double
    public var bodyCount: Int
    public var triangleCount: Int
    public var intersectingBodyCount: Int
    public var touchingBodyCount: Int
    public var frontBodyCount: Int
    public var behindBodyCount: Int
    public var coplanarBodyCount: Int
    public var spansPlaneBodyCount: Int
    public var intersectingTriangleCount: Int
    public var intersectionSegmentCount: Int
    public var closedIntersectionContourCount: Int
    public var openIntersectionContourCount: Int
    public var truncatedIntersectionSegments: Bool
    public var bodies: [Body]
    public var intersectionSegments: [IntersectionSegment]
    public var intersectionContours: [IntersectionContour]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        plane: Plane,
        toleranceMeters: Double,
        bodies: [Body],
        intersectionSegments: [IntersectionSegment],
        intersectionContours: [IntersectionContour] = [],
        truncatedIntersectionSegments: Bool,
        diagnostics: [EditorDiagnostic]
    ) {
        self.displayUnit = displayUnit
        self.plane = plane
        self.toleranceMeters = toleranceMeters
        self.bodyCount = bodies.count
        self.triangleCount = bodies.reduce(0) { $0 + $1.triangleCount }
        self.intersectingBodyCount = bodies.filter { $0.classification == .intersects }.count
        self.touchingBodyCount = bodies.filter { $0.classification == .touching }.count
        self.frontBodyCount = bodies.filter { $0.classification == .inFront }.count
        self.behindBodyCount = bodies.filter { $0.classification == .behind }.count
        self.coplanarBodyCount = bodies.filter { $0.classification == .coplanar }.count
        self.spansPlaneBodyCount = bodies.filter { $0.classification == .spansPlane }.count
        self.intersectingTriangleCount = bodies.reduce(0) { $0 + $1.intersectingTriangleCount }
        self.intersectionSegmentCount = bodies.reduce(0) { $0 + $1.intersectionSegmentCount }
        self.closedIntersectionContourCount = intersectionContours.filter(\.isClosed).count
        self.openIntersectionContourCount = intersectionContours.filter { !$0.isClosed }.count
        self.truncatedIntersectionSegments = truncatedIntersectionSegments
        self.bodies = bodies
        self.intersectionSegments = intersectionSegments
        self.intersectionContours = intersectionContours
        self.diagnostics = diagnostics
    }
}
