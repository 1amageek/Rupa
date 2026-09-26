import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SectionAnalysisQuery: Codable, Equatable, Sendable {
    public enum Source: Codable, Equatable, Sendable {
        case sketchPlane(SketchPlane)
        case constructionPlane(ConstructionPlaneSourceID)
        case activeConstructionPlane
        case sceneNode(SceneNodeID)
        /// A selected planar face; the plane faces out of the body.
        case face(SelectionTarget)
    }

    public var source: Source
    public var offsetMeters: Double
    public var flipsNormal: Bool
    public var toleranceMeters: Double?
    public var includesIntersectionSegments: Bool
    public var maximumIntersectionSegments: Int
    public var clipping: SectionAnalysisClippingRequest?

    public init(
        source: Source,
        offsetMeters: Double = 0.0,
        flipsNormal: Bool = false,
        toleranceMeters: Double? = nil,
        includesIntersectionSegments: Bool = true,
        maximumIntersectionSegments: Int = 10_000,
        clipping: SectionAnalysisClippingRequest? = nil
    ) {
        self.source = source
        self.offsetMeters = offsetMeters
        self.flipsNormal = flipsNormal
        self.toleranceMeters = toleranceMeters
        self.includesIntersectionSegments = includesIntersectionSegments
        self.maximumIntersectionSegments = maximumIntersectionSegments
        self.clipping = clipping
    }
}

public struct SectionAnalysisResult: Codable, Equatable, Sendable {
    public enum PlaneSourceKind: String, Codable, Equatable, Sendable {
        case sketchPlane
        case constructionPlane
        case activeConstructionPlane
        case sceneNode
        case face
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
        public var sceneNodeID: SceneNodeID?
        public var occurrenceID: SceneOccurrenceID?
        public var sourceFeatureID: String?
        public var subshapeID: String?
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
            sceneNodeID: SceneNodeID? = nil,
            occurrenceID: SceneOccurrenceID? = nil,
            sourceFeatureID: String? = nil,
            subshapeID: String? = nil,
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
            self.sceneNodeID = sceneNodeID
            self.occurrenceID = occurrenceID
            self.sourceFeatureID = sourceFeatureID
            self.subshapeID = subshapeID
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
        public var sceneNodeID: SceneNodeID?
        public var occurrenceID: SceneOccurrenceID?
        public var start: Point3D
        public var end: Point3D
        public var start2D: Point2D
        public var end2D: Point2D

        public init(
            bodyID: String,
            sceneNodeID: SceneNodeID? = nil,
            occurrenceID: SceneOccurrenceID? = nil,
            start: Point3D,
            end: Point3D,
            start2D: Point2D,
            end2D: Point2D
        ) {
            self.bodyID = bodyID
            self.sceneNodeID = sceneNodeID
            self.occurrenceID = occurrenceID
            self.start = start
            self.end = end
            self.start2D = start2D
            self.end2D = end2D
        }
    }

    public struct IntersectionContour: Codable, Equatable, Sendable {
        public var id: String
        public var bodyID: String
        public var sceneNodeID: SceneNodeID?
        public var occurrenceID: SceneOccurrenceID?
        public var points: [Point3D]
        public var points2D: [Point2D]
        public var isClosed: Bool
        public var signedAreaSquareMeters: Double
        public var lengthMeters: Double
        public var segmentCount: Int

        public init(
            id: String,
            bodyID: String,
            sceneNodeID: SceneNodeID? = nil,
            occurrenceID: SceneOccurrenceID? = nil,
            points: [Point3D],
            points2D: [Point2D],
            isClosed: Bool,
            signedAreaSquareMeters: Double,
            lengthMeters: Double,
            segmentCount: Int
        ) {
            self.id = id
            self.bodyID = bodyID
            self.sceneNodeID = sceneNodeID
            self.occurrenceID = occurrenceID
            self.points = points
            self.points2D = points2D
            self.isClosed = isClosed
            self.signedAreaSquareMeters = signedAreaSquareMeters
            self.lengthMeters = lengthMeters
            self.segmentCount = segmentCount
        }
    }

    /// Two bodies whose sections overlap: solids that occupy the same space.
    public struct Interference: Codable, Equatable, Sendable {
        public var firstBodyID: String
        public var firstSceneNodeID: SceneNodeID?
        public var firstOccurrenceID: SceneOccurrenceID?
        public var secondBodyID: String
        public var secondSceneNodeID: SceneNodeID?
        public var secondOccurrenceID: SceneOccurrenceID?
        /// The closed contours of both sections.
        public var contourIDs: [String]

        public init(
            firstBodyID: String,
            firstSceneNodeID: SceneNodeID? = nil,
            firstOccurrenceID: SceneOccurrenceID? = nil,
            secondBodyID: String,
            secondSceneNodeID: SceneNodeID? = nil,
            secondOccurrenceID: SceneOccurrenceID? = nil,
            contourIDs: [String]
        ) {
            self.firstBodyID = firstBodyID
            self.firstSceneNodeID = firstSceneNodeID
            self.firstOccurrenceID = firstOccurrenceID
            self.secondBodyID = secondBodyID
            self.secondSceneNodeID = secondSceneNodeID
            self.secondOccurrenceID = secondOccurrenceID
            self.contourIDs = contourIDs
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
    public var interferences: [Interference]
    public var diagnostics: [EditorDiagnostic]

    /// Every contour of a section some other section overlaps.
    public var interferingContourIDs: Set<String> {
        Set(interferences.flatMap(\.contourIDs))
    }

    public init(
        displayUnit: LengthDisplayUnit,
        plane: Plane,
        toleranceMeters: Double,
        bodies: [Body],
        intersectionSegments: [IntersectionSegment],
        intersectionContours: [IntersectionContour] = [],
        interferences: [Interference] = [],
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
        self.interferences = interferences
        self.diagnostics = diagnostics
    }
}

extension SectionAnalysisResult {
    /// Results saved before interference was reported decode with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayUnit = try container.decode(LengthDisplayUnit.self, forKey: .displayUnit)
        plane = try container.decode(Plane.self, forKey: .plane)
        toleranceMeters = try container.decode(Double.self, forKey: .toleranceMeters)
        bodyCount = try container.decode(Int.self, forKey: .bodyCount)
        triangleCount = try container.decode(Int.self, forKey: .triangleCount)
        intersectingBodyCount = try container.decode(Int.self, forKey: .intersectingBodyCount)
        touchingBodyCount = try container.decode(Int.self, forKey: .touchingBodyCount)
        frontBodyCount = try container.decode(Int.self, forKey: .frontBodyCount)
        behindBodyCount = try container.decode(Int.self, forKey: .behindBodyCount)
        coplanarBodyCount = try container.decode(Int.self, forKey: .coplanarBodyCount)
        spansPlaneBodyCount = try container.decode(Int.self, forKey: .spansPlaneBodyCount)
        intersectingTriangleCount = try container.decode(Int.self, forKey: .intersectingTriangleCount)
        intersectionSegmentCount = try container.decode(Int.self, forKey: .intersectionSegmentCount)
        closedIntersectionContourCount = try container.decode(Int.self, forKey: .closedIntersectionContourCount)
        openIntersectionContourCount = try container.decode(Int.self, forKey: .openIntersectionContourCount)
        truncatedIntersectionSegments = try container.decode(Bool.self, forKey: .truncatedIntersectionSegments)
        bodies = try container.decode([Body].self, forKey: .bodies)
        intersectionSegments = try container.decode([IntersectionSegment].self, forKey: .intersectionSegments)
        intersectionContours = try container.decode([IntersectionContour].self, forKey: .intersectionContours)
        interferences = try container.decodeIfPresent([Interference].self, forKey: .interferences) ?? []
        diagnostics = try container.decode([EditorDiagnostic].self, forKey: .diagnostics)
    }
}
