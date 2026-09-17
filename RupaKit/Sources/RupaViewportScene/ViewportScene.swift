import CoreGraphics
import RupaCore
import SwiftCAD

public enum ViewportSelectableKind: String, Equatable, Sendable {
    case sketch
    case body
    case curve
}

public enum ViewportBodyFace: String, CaseIterable, Hashable, Sendable {
    case front
    case back
    case top
    case bottom
    case left
    case right
    case side
}

public enum ViewportBodyEdge: String, CaseIterable, Hashable, Sendable {
    case leftBottom
    case rightBottom
    case rightTop
    case leftTop
}

public enum ViewportBodyVertex: String, CaseIterable, Hashable, Sendable {
    case frontBottomLeft
    case frontBottomRight
    case frontTopRight
    case frontTopLeft
    case backBottomLeft
    case backBottomRight
    case backTopRight
    case backTopLeft
}

public extension ViewportBodyEdge {
    static var verticalCases: [ViewportBodyEdge] {
        [.leftBottom, .rightBottom, .rightTop, .leftTop]
    }
}

public extension ViewportBodyVertex {
    var usesMinX: Bool {
        switch self {
        case .frontBottomLeft, .frontTopLeft, .backBottomLeft, .backTopLeft:
            true
        case .frontBottomRight, .frontTopRight, .backBottomRight, .backTopRight:
            false
        }
    }

    var usesMinY: Bool {
        switch self {
        case .frontBottomLeft, .frontBottomRight, .frontTopRight, .frontTopLeft:
            true
        case .backBottomLeft, .backBottomRight, .backTopRight, .backTopLeft:
            false
        }
    }

    var usesMinZ: Bool {
        switch self {
        case .frontBottomLeft, .frontBottomRight, .backBottomLeft, .backBottomRight:
            true
        case .frontTopRight, .frontTopLeft, .backTopRight, .backTopLeft:
            false
        }
    }
}

public enum ViewportSketchPrimitive: Equatable, Sendable {
    case point(entityID: SketchEntityID, point: CGPoint)
    case line(entityID: SketchEntityID, start: CGPoint, end: CGPoint)
    case circle(entityID: SketchEntityID, center: CGPoint, radiusMeters: Double)
    case arc(
        entityID: SketchEntityID,
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    )
    case spline(
        entityID: SketchEntityID,
        points: [CGPoint],
        controlPoints: [CGPoint],
        sketchPlane: SketchPlane
    )

    public var entityID: SketchEntityID {
        switch self {
        case .point(let entityID, _),
             .line(let entityID, _, _),
             .circle(let entityID, _, _),
             .arc(let entityID, _, _, _, _),
             .spline(let entityID, _, _, _):
            entityID
        }
    }
}

public struct ViewportSketchRegion: Equatable, Sendable {
    public var componentID: SelectionComponentID
    public var points: [CGPoint]

    public init(
        componentID: SelectionComponentID,
        points: [CGPoint]
    ) {
        self.componentID = componentID
        self.points = points
    }
}

public enum ViewportSceneItemKind: Equatable, Sendable {
    case sketch(primitives: [ViewportSketchPrimitive])
    case body(component: ViewportBodyComponent)
    case curve(component: ViewportCurveComponent)

    public var selectableKind: ViewportSelectableKind {
        switch self {
        case .sketch:
            return .sketch
        case .body:
            return .body
        case .curve:
            return .curve
        }
    }
}

/// One evaluated curve output and its stable document-level identity.
///
/// `curve.points` is the display tessellation. `curve.exactCurve` and
/// `curve.exactParameterDomain` remain the canonical geometry when available.
public struct ViewportCurveSegment: Equatable, Sendable {
    public var reference: CurveOutputReference
    public var curve: EvaluatedCurve

    public init(reference: CurveOutputReference, curve: EvaluatedCurve) {
        self.reference = reference
        self.curve = curve
    }

    public var points: [Point3D] {
        curve.points
    }

    public var selectionReference: SelectionReference {
        .curve(.whole(reference))
    }
}

public struct ViewportCurveComponent: Equatable, Sendable {
    public var segments: [ViewportCurveSegment]
    public var yMinMeters: Double
    public var yMaxMeters: Double

    public init(
        segments: [ViewportCurveSegment],
        yMinMeters: Double,
        yMaxMeters: Double
    ) {
        self.segments = segments
        self.yMinMeters = yMinMeters
        self.yMaxMeters = yMaxMeters
    }

}

public struct ViewportBodyComponent: Equatable, Sendable {
    public var bodyID: String?
    public var subshapeID: String?
    public var typeID: ObjectTypeID?
    public var properties: ObjectPropertySet
    public var sizeXMeters: Double
    public var sizeYMeters: Double
    public var sizeZMeters: Double
    public var yMinMeters: Double
    public var yMaxMeters: Double
    public var cylinder: ViewportCylinderComponent?
    public var mesh: ViewportBodyMesh?
    public var topology: ViewportBodyTopology?
    public var surfaceControlPointDisplays: [ViewportSurfaceControlPointDisplay]
    public var surfaceTrimEndpointDisplays: [ViewportSurfaceTrimEndpointDisplay]
    public var surfaceTrimControlPointDisplays: [ViewportSurfaceTrimControlPointDisplay]
    public var surfaceKnotDisplays: [ViewportSurfaceKnotDisplay]
    public var surfaceSpanDisplays: [ViewportSurfaceSpanDisplay]
    public var surfaceTrimKnotDisplays: [ViewportSurfaceTrimKnotDisplay]
    public var surfaceTrimSpanDisplays: [ViewportSurfaceTrimSpanDisplay]
    public var surfaceFrameDisplays: [ViewportSurfaceFrameDisplay]

    public init(
        bodyID: String? = nil,
        subshapeID: String? = nil,
        typeID: ObjectTypeID? = nil,
        properties: ObjectPropertySet = ObjectPropertySet(),
        sizeXMeters: Double,
        sizeYMeters: Double,
        sizeZMeters: Double,
        yMinMeters: Double,
        yMaxMeters: Double,
        cylinder: ViewportCylinderComponent? = nil,
        mesh: ViewportBodyMesh? = nil,
        topology: ViewportBodyTopology? = nil,
        surfaceControlPointDisplays: [ViewportSurfaceControlPointDisplay] = [],
        surfaceTrimEndpointDisplays: [ViewportSurfaceTrimEndpointDisplay] = [],
        surfaceTrimControlPointDisplays: [ViewportSurfaceTrimControlPointDisplay] = [],
        surfaceKnotDisplays: [ViewportSurfaceKnotDisplay] = [],
        surfaceSpanDisplays: [ViewportSurfaceSpanDisplay] = [],
        surfaceTrimKnotDisplays: [ViewportSurfaceTrimKnotDisplay] = [],
        surfaceTrimSpanDisplays: [ViewportSurfaceTrimSpanDisplay] = [],
        surfaceFrameDisplays: [ViewportSurfaceFrameDisplay] = []
    ) {
        self.bodyID = bodyID
        self.subshapeID = subshapeID
        self.typeID = typeID
        self.properties = properties
        self.sizeXMeters = sizeXMeters
        self.sizeYMeters = sizeYMeters
        self.sizeZMeters = sizeZMeters
        self.yMinMeters = yMinMeters
        self.yMaxMeters = yMaxMeters
        self.cylinder = cylinder
        self.mesh = mesh
        self.topology = topology
        self.surfaceControlPointDisplays = surfaceControlPointDisplays
        self.surfaceTrimEndpointDisplays = surfaceTrimEndpointDisplays
        self.surfaceTrimControlPointDisplays = surfaceTrimControlPointDisplays
        self.surfaceKnotDisplays = surfaceKnotDisplays
        self.surfaceSpanDisplays = surfaceSpanDisplays
        self.surfaceTrimKnotDisplays = surfaceTrimKnotDisplays
        self.surfaceTrimSpanDisplays = surfaceTrimSpanDisplays
        self.surfaceFrameDisplays = surfaceFrameDisplays
    }
}

public typealias ViewportBodyMesh = BodyDisplaySnapshot.Mesh

public struct ViewportSurfaceControlPointDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var point: Point3D
    public var uIndex: Int
    public var vIndex: Int
    public var isBoundary: Bool

    public init(
        selectionReference: SelectionReference,
        point: Point3D,
        uIndex: Int,
        vIndex: Int,
        isBoundary: Bool
    ) {
        self.selectionReference = selectionReference
        self.point = point
        self.uIndex = uIndex
        self.vIndex = vIndex
        self.isBoundary = isBoundary
    }
}

public struct ViewportSurfaceTrimEndpointDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var endpoint: SurfaceTrimEndpoint
    public var point: Point3D
    public var u: Double
    public var v: Double
    public var tangentU: Vector3D
    public var tangentV: Vector3D

    public init(
        selectionReference: SelectionReference,
        endpoint: SurfaceTrimEndpoint,
        point: Point3D,
        u: Double,
        v: Double,
        tangentU: Vector3D,
        tangentV: Vector3D
    ) {
        self.selectionReference = selectionReference
        self.endpoint = endpoint
        self.point = point
        self.u = u
        self.v = v
        self.tangentU = tangentU
        self.tangentV = tangentV
    }
}

public struct ViewportSurfaceTrimControlPointDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var controlPointIndex: Int
    public var point: Point3D
    public var u: Double
    public var v: Double
    public var tangentU: Vector3D
    public var tangentV: Vector3D

    public init(
        selectionReference: SelectionReference,
        controlPointIndex: Int,
        point: Point3D,
        u: Double,
        v: Double,
        tangentU: Vector3D,
        tangentV: Vector3D
    ) {
        self.selectionReference = selectionReference
        self.controlPointIndex = controlPointIndex
        self.point = point
        self.u = u
        self.v = v
        self.tangentU = tangentU
        self.tangentV = tangentV
    }
}

public struct ViewportSurfaceTrimKnotDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var knotIndex: Int
    public var value: Double
    public var point: Point3D
    public var u: Double
    public var v: Double

    public init(
        selectionReference: SelectionReference,
        knotIndex: Int,
        value: Double,
        point: Point3D,
        u: Double,
        v: Double
    ) {
        self.selectionReference = selectionReference
        self.knotIndex = knotIndex
        self.value = value
        self.point = point
        self.u = u
        self.v = v
    }
}

public struct ViewportSurfaceTrimSpanDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var spanIndex: Int
    public var lowerBound: Double
    public var upperBound: Double
    public var point: Point3D
    public var u: Double
    public var v: Double

    public init(
        selectionReference: SelectionReference,
        spanIndex: Int,
        lowerBound: Double,
        upperBound: Double,
        point: Point3D,
        u: Double,
        v: Double
    ) {
        self.selectionReference = selectionReference
        self.spanIndex = spanIndex
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.point = point
        self.u = u
        self.v = v
    }
}

public struct ViewportSurfaceKnotDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var direction: SurfaceParameterDirection
    public var knotIndex: Int
    public var value: Double
    public var point: Point3D
    public var u: Double
    public var v: Double

    public init(
        selectionReference: SelectionReference,
        direction: SurfaceParameterDirection,
        knotIndex: Int,
        value: Double,
        point: Point3D,
        u: Double,
        v: Double
    ) {
        self.selectionReference = selectionReference
        self.direction = direction
        self.knotIndex = knotIndex
        self.value = value
        self.point = point
        self.u = u
        self.v = v
    }
}

public struct ViewportSurfaceSpanDisplay: Equatable, Sendable {
    public var selectionReference: SelectionReference
    public var direction: SurfaceParameterDirection
    public var spanIndex: Int
    public var lowerBound: Double
    public var upperBound: Double
    public var point: Point3D
    public var u: Double
    public var v: Double

    public init(
        selectionReference: SelectionReference,
        direction: SurfaceParameterDirection,
        spanIndex: Int,
        lowerBound: Double,
        upperBound: Double,
        point: Point3D,
        u: Double,
        v: Double
    ) {
        self.selectionReference = selectionReference
        self.direction = direction
        self.spanIndex = spanIndex
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.point = point
        self.u = u
        self.v = v
    }
}

public struct ViewportSurfaceFrameDisplay: Equatable, Sendable {
    public var id: SurfaceFrameDisplayID
    public var query: SurfaceFrameQuery
    public var position: Point3D
    public var uAxis: Vector3D
    public var vAxis: Vector3D
    public var normal: Vector3D
    public var u: Double
    public var v: Double
    public var faceSubshapeIDs: [String]

    public init(
        id: SurfaceFrameDisplayID,
        query: SurfaceFrameQuery,
        position: Point3D,
        uAxis: Vector3D,
        vAxis: Vector3D,
        normal: Vector3D,
        u: Double,
        v: Double,
        faceSubshapeIDs: [String]
    ) {
        self.id = id
        self.query = query
        self.position = position
        self.uAxis = uAxis
        self.vAxis = vAxis
        self.normal = normal
        self.u = u
        self.v = v
        self.faceSubshapeIDs = faceSubshapeIDs
    }
}

public struct ViewportBodyTopology: Equatable, Sendable {
    public var faces: [Face]
    public var edges: [Edge]
    public var vertices: [Vertex]
    public var meshFaceRuns: [MeshFaceRun]

    public init(
        faces: [Face] = [],
        edges: [Edge] = [],
        vertices: [Vertex] = [],
        meshFaceRuns: [MeshFaceRun] = []
    ) {
        self.faces = faces
        self.edges = edges
        self.vertices = vertices
        self.meshFaceRuns = meshFaceRuns
    }

    /// The prepared CAD sub-shape of the triangle the native frame hit.
    ///
    /// The universal mesh source names the triangles of a CAD body in the order
    /// the kernel emitted them, so the raw value of a hit triangle's
    /// `MeshFaceID` is that triangle's index and the run containing it names the
    /// generating face. The scan is linear because a run list carries no
    /// ordering guarantee across the value boundary; assuming one and searching
    /// it as sorted would answer a malformed list with the wrong face instead of
    /// no face.
    ///
    /// A `nil` result is a truthful miss: the triangle belongs to a face that
    /// evaluation gave no stable sub-shape identity, so there is no CAD name to
    /// select. It is never a substituted neighbouring face.
    public func componentID(forTriangle index: Int) -> SelectionComponentID? {
        for run in meshFaceRuns where run.triangleRange.contains(index) {
            return run.componentID
        }
        return nil
    }

    public struct Face: Equatable, Sendable {
        public var componentID: SelectionComponentID
        public var points: [Point3D]

        public init(componentID: SelectionComponentID, points: [Point3D]) {
            self.componentID = componentID
            self.points = points
        }
    }

    public struct Edge: Equatable, Sendable {
        public var componentID: SelectionComponentID
        public var start: Point3D
        public var end: Point3D

        public init(componentID: SelectionComponentID, start: Point3D, end: Point3D) {
            self.componentID = componentID
            self.start = start
            self.end = end
        }
    }

    public struct Vertex: Equatable, Sendable {
        public var componentID: SelectionComponentID
        public var point: Point3D

        public init(componentID: SelectionComponentID, point: Point3D) {
            self.componentID = componentID
            self.point = point
        }
    }

    /// The contiguous drawn triangles one CAD face generated.
    ///
    /// This list is independent of `faces`: a `Face` carries the projected
    /// outer loop a CPU polygon test needs and is absent for a face that has
    /// none, while a run needs no polygon and describes exactly the triangles
    /// the native frame draws.
    public struct MeshFaceRun: Equatable, Sendable {
        public var componentID: SelectionComponentID
        public var triangleRange: Range<Int>

        public init(componentID: SelectionComponentID, triangleRange: Range<Int>) {
            self.componentID = componentID
            self.triangleRange = triangleRange
        }
    }
}

extension ViewportBodyTopology {
    init(_ topology: BodyDisplaySnapshot.Topology) {
        self.init(
            faces: topology.faces.map { face in
                ViewportBodyTopology.Face(
                    componentID: face.componentID,
                    points: face.points
                )
            },
            edges: topology.edges.map { edge in
                ViewportBodyTopology.Edge(
                    componentID: edge.componentID,
                    start: edge.start,
                    end: edge.end
                )
            },
            vertices: topology.vertices.map { vertex in
                ViewportBodyTopology.Vertex(
                    componentID: vertex.componentID,
                    point: vertex.point
                )
            },
            meshFaceRuns: topology.meshFaceRuns.map { run in
                ViewportBodyTopology.MeshFaceRun(
                    componentID: run.componentID,
                    triangleRange: run.triangleRange
                )
            }
        )
    }
}

public struct ViewportCylinderComponent: Equatable, Sendable {
    public var topRadiusMeters: Double
    public var bottomRadiusMeters: Double
    public var sideSegments: Int
    public var verticalSegments: Int
    public var angleDegrees: Double
    public var hasCaps: Bool
    public var hollowMeters: Double
    public var cornerRadiusMeters: Double
    public var cornerSideSegments: Int

    public init(
        topRadiusMeters: Double,
        bottomRadiusMeters: Double,
        sideSegments: Int = 64,
        verticalSegments: Int = 1,
        angleDegrees: Double = 360.0,
        hasCaps: Bool = true,
        hollowMeters: Double = 0.0,
        cornerRadiusMeters: Double = 0.0,
        cornerSideSegments: Int = 8
    ) {
        self.topRadiusMeters = topRadiusMeters
        self.bottomRadiusMeters = bottomRadiusMeters
        self.sideSegments = sideSegments
        self.verticalSegments = verticalSegments
        self.angleDegrees = angleDegrees
        self.hasCaps = hasCaps
        self.hollowMeters = hollowMeters
        self.cornerRadiusMeters = cornerRadiusMeters
        self.cornerSideSegments = cornerSideSegments
    }
}

public struct ViewportSceneItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var featureID: FeatureID
    public var sceneNodeID: SceneNodeID?
    public var componentInstanceID: ComponentInstanceID?
    public var sourceFeatureID: FeatureID?
    public var modelTransform: Transform3D
    public var modelBounds: CGRect
    public var kind: ViewportSceneItemKind
    public var sketchRegions: [ViewportSketchRegion]

    public init(
        id: String,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID? = nil,
        componentInstanceID: ComponentInstanceID? = nil,
        sourceFeatureID: FeatureID? = nil,
        modelTransform: Transform3D = .identity,
        modelBounds: CGRect,
        kind: ViewportSceneItemKind,
        sketchRegions: [ViewportSketchRegion] = []
    ) {
        self.id = id
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.componentInstanceID = componentInstanceID
        self.sourceFeatureID = sourceFeatureID
        self.modelTransform = modelTransform
        self.modelBounds = modelBounds
        self.kind = kind
        self.sketchRegions = sketchRegions
    }
}

public struct ViewportScene: Equatable, Sendable {
    public var items: [ViewportSceneItem]

    public init(items: [ViewportSceneItem]) {
        self.items = items
    }

    public var modelBounds: CGRect? {
        guard let firstItem = items.first else {
            return nil
        }
        var bounds = firstItem.modelBounds
        for item in items.dropFirst() {
            bounds = bounds.union(item.modelBounds)
        }
        return bounds
    }

    public var verticalBounds: ClosedRange<Double>? {
        var bounds: ClosedRange<Double>?
        for item in items {
            let itemBounds: ClosedRange<Double>
            switch item.kind {
            case .body(let component):
                itemBounds = min(component.yMinMeters, component.yMaxMeters)
                    ... max(component.yMinMeters, component.yMaxMeters)
            case .curve(let component):
                itemBounds = min(component.yMinMeters, component.yMaxMeters)
                    ... max(component.yMinMeters, component.yMaxMeters)
            case .sketch:
                continue
            }
            if let currentBounds = bounds {
                bounds = min(currentBounds.lowerBound, itemBounds.lowerBound)
                    ... max(currentBounds.upperBound, itemBounds.upperBound)
            } else {
                bounds = itemBounds
            }
        }
        if let bounds {
            return bounds
        }
        return items.isEmpty ? nil : 0.0 ... 0.0
    }
}

public struct ViewportModelDrag: Equatable, Sendable {
    public var start: Point2D
    public var end: Point2D
    public var sketchPlane: SketchPlane
    public var modifierFlags: ViewportInputModifierFlags
    public var startWorldPoint: Point3D?
    public var endWorldPoint: Point3D?
    public var startViewRayAnchorWorldPoint: Point3D?
    public var endViewRayAnchorWorldPoint: Point3D?

    public init(
        start: Point2D,
        end: Point2D,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags(),
        startWorldPoint: Point3D? = nil,
        endWorldPoint: Point3D? = nil,
        startViewRayAnchorWorldPoint: Point3D? = nil,
        endViewRayAnchorWorldPoint: Point3D? = nil
    ) {
        self.start = start
        self.end = end
        self.sketchPlane = sketchPlane
        self.modifierFlags = modifierFlags
        self.startWorldPoint = startWorldPoint
        self.endWorldPoint = endWorldPoint
        self.startViewRayAnchorWorldPoint = startViewRayAnchorWorldPoint
        self.endViewRayAnchorWorldPoint = endViewRayAnchorWorldPoint
    }

    public func constrained(by axisConstraint: SketchAxisConstraint?) -> ViewportModelDrag {
        guard let axisConstraint else {
            return self
        }
        return ViewportModelDrag(
            start: start,
            end: axisConstraint.constrainedCanvasPoint(end, from: start, on: sketchPlane),
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startWorldPoint,
            startViewRayAnchorWorldPoint: startViewRayAnchorWorldPoint
        )
    }
}

public struct ViewportFaceSurfacePointResolver: Sendable {
    public init() {}

    public func worldPoint(
        for viewportPoint: CGPoint,
        face: ViewportBodyTopology.Face,
        layout: ViewportLayout,
        tolerance: CGFloat = 1.0e-6
    ) -> Point3D? {
        guard face.points.count >= 3,
              viewportPoint.x.isFinite,
              viewportPoint.y.isFinite,
              let ray = layout.viewportRay(for: viewportPoint) else {
            return nil
        }
        let origin = face.points[0]
        for index in 1 ..< face.points.count - 1 {
            guard let edges = normalizedTriangleEdges(
                a: origin,
                b: face.points[index],
                c: face.points[index + 1]
            ) else {
                continue
            }
            let first = edges.first
            let second = edges.second
            let rawNormal = first.cross(second)
            guard rawNormal.isFinite, rawNormal.length > 1.0e-12 else {
                continue
            }
            let normal: Vector3D
            do {
                normal = try rawNormal.normalized(tolerance: 1.0e-12)
            } catch {
                continue
            }
            let denominator = ray.direction.dot(normal)
            guard denominator.isFinite, abs(denominator) > 1.0e-12 else {
                continue
            }
            let distance = (origin - ray.origin).dot(normal) / denominator
            guard distance.isFinite else {
                continue
            }
            let candidate = ray.origin + ray.direction * distance
            guard candidate.isFinite else {
                continue
            }
            if case .perspective = layout.projection,
               (distance < 0.0 || layout.projectedPoint(candidate) == nil) {
                continue
            }
            guard let weights = barycentricWeights(
                point: candidate,
                a: origin,
                b: face.points[index],
                c: face.points[index + 1],
                tolerance: tolerance
            ) else {
                continue
            }
            return weightedPoint(
                origin,
                face.points[index],
                face.points[index + 1],
                weights: weights
            )
        }
        return nil
    }

    private func normalizedTriangleEdges(
        a: Point3D,
        b: Point3D,
        c: Point3D
    ) -> (first: Vector3D, second: Vector3D, scale: Double)? {
        let first = vector(from: a, to: b)
        let second = vector(from: a, to: c)
        let third = vector(from: b, to: c)
        let scale = max(first.length, second.length, third.length)
        guard first.isFinite,
              second.isFinite,
              third.isFinite,
              scale.isFinite,
              scale > 0.0 else {
            return nil
        }
        let inverseScale = 1.0 / scale
        guard inverseScale.isFinite else {
            return nil
        }
        let normalizedFirst = scaled(first, by: inverseScale)
        let normalizedSecond = scaled(second, by: inverseScale)
        guard normalizedFirst.isFinite, normalizedSecond.isFinite else {
            return nil
        }
        return (
            first: normalizedFirst,
            second: normalizedSecond,
            scale: scale
        )
    }

    private func barycentricWeights(
        point: Point3D,
        a: Point3D,
        b: Point3D,
        c: Point3D,
        tolerance: CGFloat
    ) -> (a: Double, b: Double, c: Double)? {
        guard let edges = normalizedTriangleEdges(a: a, b: b, c: c) else {
            return nil
        }
        let first = edges.first
        let second = edges.second
        let relative = scaled(
            vector(from: a, to: point),
            by: 1.0 / edges.scale
        )
        let normal = first.cross(second)
        let denominator = normal.dot(normal)
        let toleranceValue = max(Double(tolerance), 1.0e-9)
        guard first.isFinite, second.isFinite, relative.isFinite,
              normal.isFinite, denominator.isFinite,
              normal.length > 1.0e-12,
              denominator > 0.0 else {
            return nil
        }
        let planeDistance = abs(relative.dot(normal))
        let planeScale = max(normal.length * max(relative.length, 1.0), 1.0e-12)
        guard planeDistance.isFinite,
              planeDistance <= toleranceValue * planeScale else {
            return nil
        }
        let bWeight = (
            second.dot(second) * relative.dot(first)
                - first.dot(second) * relative.dot(second)
        ) / denominator
        let cWeight = (
            first.dot(first) * relative.dot(second)
                - first.dot(second) * relative.dot(first)
        ) / denominator
        let aWeight = 1.0 - bWeight - cWeight
        guard aWeight.isFinite, bWeight.isFinite, cWeight.isFinite,
              aWeight >= -toleranceValue,
              bWeight >= -toleranceValue,
              cWeight >= -toleranceValue,
              aWeight <= 1.0 + toleranceValue,
              bWeight <= 1.0 + toleranceValue,
              cWeight <= 1.0 + toleranceValue else {
            return nil
        }
        return (
            a: aWeight,
            b: bWeight,
            c: cWeight
        )
    }

    private func scaled(_ vector: Vector3D, by factor: Double) -> Vector3D {
        Vector3D(
            x: vector.x * factor,
            y: vector.y * factor,
            z: vector.z * factor
        )
    }

    private func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(
            x: end.x - start.x,
            y: end.y - start.y,
            z: end.z - start.z
        )
    }

    private func weightedPoint(
        _ a: Point3D,
        _ b: Point3D,
        _ c: Point3D,
        weights: (a: Double, b: Double, c: Double)
    ) -> Point3D {
        Point3D(
            x: a.x * weights.a + b.x * weights.b + c.x * weights.c,
            y: a.y * weights.a + b.y * weights.b + c.y * weights.c,
            z: a.z * weights.a + b.z * weights.b + c.z * weights.c
        )
    }
}

public struct ViewportCanvasDragPlaceholder: Equatable {
    public var modelBounds: CGRect
    public var footprint: ViewportProjectedRect

    public init?(
        drag: ViewportModelDrag,
        layout: ViewportLayout,
        widthMeters widthOverrideMeters: Double? = nil,
        heightMeters heightOverrideMeters: Double? = nil
    ) {
        self.init(
            start: drag.start,
            end: drag.end,
            layout: layout,
            sketchPlane: drag.sketchPlane,
            widthMeters: widthOverrideMeters,
            heightMeters: heightOverrideMeters
        )
    }

    public init?(
        start: Point2D,
        end: Point2D,
        layout: ViewportLayout,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        widthMeters widthOverrideMeters: Double? = nil,
        heightMeters heightOverrideMeters: Double? = nil
    ) {
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite else {
            return nil
        }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let width = widthOverrideMeters ?? abs(deltaX)
        let height = heightOverrideMeters ?? abs(deltaY)
        guard width.isFinite,
              height.isFinite,
              width > 0.0,
              height > 0.0 else {
            return nil
        }
        guard let projection = ViewportSketchPlaneProjection(sketchPlane: sketchPlane) else {
            return nil
        }
        let localStart = projection.localPoint(fromCanvas: start)
        let localEnd = projection.localPoint(fromCanvas: end)
        let localDeltaX = localEnd.x - localStart.x
        let localDeltaY = localEnd.y - localStart.y
        let endX = localStart.x + Self.signedDimension(width, following: localDeltaX)
        let endY = localStart.y + Self.signedDimension(height, following: localDeltaY)
        let minX = min(localStart.x, endX)
        let minY = min(localStart.y, endY)
        let maxX = max(localStart.x, endX)
        let maxY = max(localStart.y, endY)
        guard minX < maxX, minY < maxY else {
            return nil
        }

        let modelBounds = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxY - minY)
        )
        guard let bottomLeft = projection.project(localPoint: Point2D(x: minX, y: minY), layout: layout),
              let bottomRight = projection.project(localPoint: Point2D(x: maxX, y: minY), layout: layout),
              let topRight = projection.project(localPoint: Point2D(x: maxX, y: maxY), layout: layout),
              let topLeft = projection.project(localPoint: Point2D(x: minX, y: maxY), layout: layout) else {
            return nil
        }
        self.modelBounds = modelBounds
        self.footprint = ViewportProjectedRect(
            bottomLeft: bottomLeft,
            bottomRight: bottomRight,
            topRight: topRight,
            topLeft: topLeft
        )
    }

    private static func signedDimension(_ dimension: Double, following delta: Double) -> Double {
        delta < 0.0 ? -dimension : dimension
    }
}

public enum ViewportCanvasDragPreviewKind: Equatable, Sendable {
    case rectangle(widthMeters: Double?, heightMeters: Double?)
    case polygon(PolygonToolState, radiusMeters: Double?, rotationAngleRadians: Double?)
    case arc(radiusMeters: Double?, spanAngleRadians: Double?)
    case spline
    case circle(radiusMeters: Double?)
}

public enum ViewportCanvasDragPreview: Equatable {
    case rectangle(ViewportCanvasDragPlaceholder)
    case polygon(ViewportCanvasPolygonDragPreview)
    case arc(ViewportCanvasArcDragPreview)
    case spline(ViewportCanvasSplineDragPreview)
    case circle(ViewportCanvasCircleDragPreview)

    public init?(
        kind: ViewportCanvasDragPreviewKind,
        drag: ViewportModelDrag,
        layout: ViewportLayout
    ) {
        switch kind {
        case .rectangle(let widthMeters, let heightMeters):
            guard let placeholder = ViewportCanvasDragPlaceholder(
                drag: drag,
                layout: layout,
                widthMeters: widthMeters,
                heightMeters: heightMeters
            ) else {
                return nil
            }
            self = .rectangle(placeholder)
        case .polygon(let state, let radiusMeters, let rotationAngleRadians):
            guard let preview = ViewportCanvasPolygonDragPreview(
                drag: drag,
                layout: layout,
                sideCount: state.sideCount,
                sizingMode: state.sizingMode,
                inclinationMode: state.inclinationMode,
                radiusMeters: radiusMeters,
                rotationAngleRadians: rotationAngleRadians
            ) else {
                return nil
            }
            self = .polygon(preview)
        case .arc(let radiusMeters, let spanAngleRadians):
            guard let preview = ViewportCanvasArcDragPreview(
                drag: drag,
                layout: layout,
                radiusMeters: radiusMeters,
                spanAngleRadians: spanAngleRadians
            ) else {
                return nil
            }
            self = .arc(preview)
        case .spline:
            guard let preview = ViewportCanvasSplineDragPreview(
                drag: drag,
                layout: layout
            ) else {
                return nil
            }
            self = .spline(preview)
        case .circle(let radiusMeters):
            guard let preview = ViewportCanvasCircleDragPreview(
                drag: drag,
                layout: layout,
                radiusMeters: radiusMeters
            ) else {
                return nil
            }
            self = .circle(preview)
        }
    }
}

public struct ViewportCanvasPolygonDragPreview: Equatable {
    public var modelCenter: CGPoint
    public var modelRadiusMeters: Double
    public var sizingRadiusMeters: Double
    public var sizingMode: PolygonSizingMode
    public var inclinationMode: PolygonInclinationMode
    public var sides: Int
    public var rotationAngleRadians: Double
    public var modelVertices: [Point2D]
    public var projectedCenter: CGPoint
    public var projectedVertices: [CGPoint]
    public var projectedRadiusEnd: CGPoint
    public var modelBounds: CGRect

    public init?(
        drag: ViewportModelDrag,
        layout: ViewportLayout,
        sideCount: Int = CanvasSketchCurveDrafts.defaultPolygonSides,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        radiusMeters radiusOverrideMeters: Double? = nil,
        rotationAngleRadians rotationAngleOverrideRadians: Double? = nil
    ) {
        guard let projection = ViewportSketchPlaneProjection(sketchPlane: drag.sketchPlane) else {
            return nil
        }
        let center = projection.localPoint(fromCanvas: drag.start)
        let radiusPoint = projection.localPoint(fromCanvas: drag.end)
        let draft: CanvasSketchCurveDrafts.Polygon
        do {
            draft = try CanvasSketchCurveDrafts.polygon(
                fromCenter: center,
                toRadiusPoint: radiusPoint,
                sides: sideCount,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                radiusMeters: radiusOverrideMeters,
                rotationAngleRadians: rotationAngleOverrideRadians
            )
        } catch {
            return nil
        }
        guard let projectedCenter = projection.project(localPoint: draft.center, layout: layout),
              let projectedRadiusEnd = projection.project(
                  localPoint: Point2D(
                      x: draft.center.x + cos(draft.rotationAngleRadians) * draft.circumradiusMeters,
                      y: draft.center.y + sin(draft.rotationAngleRadians) * draft.circumradiusMeters
                  ),
                  layout: layout
              ) else {
            return nil
        }
        let projectedVertices = draft.vertices.compactMap {
            projection.project(localPoint: $0, layout: layout)
        }
        guard projectedVertices.count == draft.vertices.count else {
            return nil
        }

        self.modelCenter = CGPoint(x: draft.center.x, y: draft.center.y)
        self.modelRadiusMeters = draft.circumradiusMeters
        self.sizingRadiusMeters = draft.radiusMeters
        self.sizingMode = draft.sizingMode
        self.inclinationMode = draft.inclinationMode
        self.sides = draft.sides
        self.rotationAngleRadians = draft.rotationAngleRadians
        self.modelVertices = draft.vertices
        self.projectedCenter = projectedCenter
        self.projectedVertices = projectedVertices
        self.projectedRadiusEnd = projectedRadiusEnd
        self.modelBounds = bounds(
            for: draft.vertices.map {
                CGPoint(x: $0.x, y: $0.y)
            }
        )
    }
}

public struct ViewportCanvasArcDragPreview: Equatable {
    public var modelCenter: CGPoint
    public var modelRadiusMeters: Double
    public var startAngleRadians: Double
    public var endAngleRadians: Double
    public var projectedCenter: CGPoint
    public var projectedPoints: [CGPoint]
    public var projectedRadiusEnd: CGPoint
    public var modelBounds: CGRect

    public init?(
        drag: ViewportModelDrag,
        layout: ViewportLayout,
        radiusMeters radiusOverrideMeters: Double? = nil,
        spanAngleRadians spanAngleOverrideRadians: Double? = nil
    ) {
        guard let projection = ViewportSketchPlaneProjection(sketchPlane: drag.sketchPlane) else {
            return nil
        }
        let centerPoint = projection.localPoint(fromCanvas: drag.start)
        let radiusPoint = projection.localPoint(fromCanvas: drag.end)
        let draft: CanvasSketchCurveDrafts.Arc
        do {
            draft = try CanvasSketchCurveDrafts.arc(
                fromCenter: centerPoint,
                toRadiusPoint: radiusPoint,
                radiusMeters: radiusOverrideMeters,
                spanAngleRadians: spanAngleOverrideRadians
            )
        } catch {
            return nil
        }

        let center = CGPoint(x: draft.center.x, y: draft.center.y)
        let boundsPoints = viewportSceneArcBoundsPoints(
            center: center,
            radiusMeters: draft.radiusMeters,
            startAngleRadians: draft.startAngleRadians,
            endAngleRadians: draft.endAngleRadians
        )
        let arcSamplePoints = viewportSceneArcSamplePoints(
            center: center,
            radiusMeters: draft.radiusMeters,
            startAngleRadians: draft.startAngleRadians,
            endAngleRadians: draft.endAngleRadians,
            segmentCount: 24
        )
        guard let projectedCenter = projection.project(localPoint: draft.center, layout: layout),
              let projectedRadiusEnd = projection.project(
                  localPoint: Point2D(
                      x: draft.center.x + cos(draft.endAngleRadians) * draft.radiusMeters,
                      y: draft.center.y + sin(draft.endAngleRadians) * draft.radiusMeters
                  ),
                  layout: layout
              ) else {
            return nil
        }
        let projectedPoints = arcSamplePoints.compactMap {
            projection.project(
                localPoint: Point2D(x: Double($0.x), y: Double($0.y)),
                layout: layout
            )
        }
        guard projectedPoints.count == arcSamplePoints.count else {
            return nil
        }
        self.modelCenter = center
        self.modelRadiusMeters = draft.radiusMeters
        self.startAngleRadians = draft.startAngleRadians
        self.endAngleRadians = draft.endAngleRadians
        self.projectedCenter = projectedCenter
        self.projectedPoints = projectedPoints
        self.projectedRadiusEnd = projectedRadiusEnd
        self.modelBounds = bounds(for: boundsPoints)
    }
}

public struct ViewportCanvasSplineDragPreview: Equatable {
    public var modelControlPoints: [Point2D]
    public var modelCurvePoints: [CGPoint]
    public var projectedControlPoints: [CGPoint]
    public var projectedCurvePoints: [CGPoint]
    public var modelBounds: CGRect

    public init?(
        drag: ViewportModelDrag,
        layout: ViewportLayout
    ) {
        guard let projection = ViewportSketchPlaneProjection(sketchPlane: drag.sketchPlane) else {
            return nil
        }
        let start = projection.localPoint(fromCanvas: drag.start)
        let end = projection.localPoint(fromCanvas: drag.end)
        let draft: CanvasSketchCurveDrafts.Spline
        do {
            draft = try CanvasSketchCurveDrafts.spline(
                from: start,
                to: end
            )
        } catch {
            return nil
        }

        let curvePoints = viewportSceneCubicBezierSamplePoints(
            controlPoints: draft.controlPoints,
            segmentCount: 32
        )
        let projectedControlPoints = draft.controlPoints.compactMap {
            projection.project(localPoint: $0, layout: layout)
        }
        let projectedCurvePoints = curvePoints.compactMap {
            projection.project(
                localPoint: Point2D(x: Double($0.x), y: Double($0.y)),
                layout: layout
            )
        }
        guard projectedControlPoints.count == draft.controlPoints.count,
              projectedCurvePoints.count == curvePoints.count else {
            return nil
        }
        self.modelControlPoints = draft.controlPoints
        self.modelCurvePoints = curvePoints
        self.projectedControlPoints = projectedControlPoints
        self.projectedCurvePoints = projectedCurvePoints
        self.modelBounds = bounds(for: curvePoints)
    }
}

public struct ViewportCanvasCircleDragPreview: Equatable {
    public var modelCenter: CGPoint
    public var modelRadiusMeters: Double
    public var projectedCenter: CGPoint
    public var projectedPoints: [CGPoint]
    public var projectedRadiusEnd: CGPoint
    public var modelBounds: CGRect

    public init?(
        drag: ViewportModelDrag,
        layout: ViewportLayout,
        radiusMeters radiusOverrideMeters: Double? = nil
    ) {
        guard let projection = ViewportSketchPlaneProjection(sketchPlane: drag.sketchPlane) else {
            return nil
        }
        let center = projection.localPoint(fromCanvas: drag.start)
        let edge = projection.localPoint(fromCanvas: drag.end)
        let deltaX = edge.x - center.x
        let deltaY = edge.y - center.y
        let fallbackRadius = sqrt(deltaX * deltaX + deltaY * deltaY)
        let radius = radiusOverrideMeters ?? fallbackRadius
        guard radius.isFinite, radius > 1.0e-12,
              let projectedCenter = projection.project(localPoint: center, layout: layout),
              let projectedRadiusEnd = projection.project(
                  localPoint: Point2D(x: center.x + radius, y: center.y),
                  layout: layout
              ) else {
            return nil
        }
        let localPoints = (0 ... 48).map { index in
            let angle = Double(index) / 48.0 * Double.pi * 2.0
            return Point2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        let projectedPoints = localPoints.compactMap {
            projection.project(localPoint: $0, layout: layout)
        }
        guard projectedPoints.count == localPoints.count else {
            return nil
        }
        self.modelCenter = CGPoint(x: center.x, y: center.y)
        self.modelRadiusMeters = radius
        self.projectedCenter = projectedCenter
        self.projectedPoints = projectedPoints
        self.projectedRadiusEnd = projectedRadiusEnd
        self.modelBounds = bounds(
            for: localPoints.map { CGPoint(x: $0.x, y: $0.y) }
        )
    }
}

public struct ViewportProjectedRect: Equatable {
    public var bottomLeft: CGPoint
    public var bottomRight: CGPoint
    public var topRight: CGPoint
    public var topLeft: CGPoint

    public init(
        bottomLeft: CGPoint,
        bottomRight: CGPoint,
        topRight: CGPoint,
        topLeft: CGPoint
    ) {
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.topRight = topRight
        self.topLeft = topLeft
    }

    public init(rect: CGRect) {
        self.init(
            bottomLeft: CGPoint(x: rect.minX, y: rect.maxY),
            bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
            topRight: CGPoint(x: rect.maxX, y: rect.minY),
            topLeft: CGPoint(x: rect.minX, y: rect.minY)
        )
    }

    public var corners: [CGPoint] {
        [bottomLeft, bottomRight, topRight, topLeft]
    }

    public var center: CGPoint {
        CGPoint(
            x: (bottomLeft.x + bottomRight.x + topRight.x + topLeft.x) / 4.0,
            y: (bottomLeft.y + bottomRight.y + topRight.y + topLeft.y) / 4.0
        )
    }

    public var bounds: CGRect {
        let minX = corners.map(\.x).min() ?? 0.0
        let minY = corners.map(\.y).min() ?? 0.0
        let maxX = corners.map(\.x).max() ?? 0.0
        let maxY = corners.map(\.y).max() ?? 0.0
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    public var handlePoints: [CGPoint] {
        corners + [
            midpoint(bottomLeft, bottomRight),
            midpoint(bottomRight, topRight),
            midpoint(topRight, topLeft),
            midpoint(topLeft, bottomLeft),
        ]
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> ViewportProjectedRect {
        ViewportProjectedRect(
            bottomLeft: CGPoint(x: bottomLeft.x + dx, y: bottomLeft.y + dy),
            bottomRight: CGPoint(x: bottomRight.x + dx, y: bottomRight.y + dy),
            topRight: CGPoint(x: topRight.x + dx, y: topRight.y + dy),
            topLeft: CGPoint(x: topLeft.x + dx, y: topLeft.y + dy)
        )
    }

    public func contains(_ point: CGPoint, tolerance: CGFloat = 0.0) -> Bool {
        if tolerance > 0.0, bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) == false {
            return false
        }

        var isInside = false
        let polygon = corners
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[(index + polygon.count - 1) % polygon.count]
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            guard crossesY else {
                continue
            }

            let crossingX = (previous.x - current.x) * (point.y - current.y)
                / (previous.y - current.y)
                + current.x
            if point.x < crossingX {
                isInside.toggle()
            }
        }

        if isInside {
            return true
        }

        guard tolerance > 0.0 else {
            return false
        }
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if point.distanceToSegment(start: start, end: end) <= tolerance {
                return true
            }
        }
        return false
    }

    private func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2.0, y: (lhs.y + rhs.y) / 2.0)
    }
}

public struct ViewportBodyProjection: Equatable {
    public var frontFootprint: ViewportProjectedRect
    public var backFootprint: ViewportProjectedRect
    public var offset: CGSize

    public var frontRect: CGRect {
        frontFootprint.bounds
    }

    public var backRect: CGRect {
        backFootprint.bounds
    }

    public init(frontRect: CGRect, backRect: CGRect, offset: CGSize) {
        self.frontFootprint = ViewportProjectedRect(rect: frontRect)
        self.backFootprint = ViewportProjectedRect(rect: backRect)
        self.offset = offset
    }

    public init(
        frontFootprint: ViewportProjectedRect,
        backFootprint: ViewportProjectedRect,
        offset: CGSize
    ) {
        self.frontFootprint = frontFootprint
        self.backFootprint = backFootprint
        self.offset = offset
    }

    public var hitBounds: CGRect {
        frontRect
            .union(backRect)
    }

    public var center: CGPoint {
        CGPoint(
            x: (frontFootprint.center.x + backFootprint.center.x) / 2.0,
            y: (frontFootprint.center.y + backFootprint.center.y) / 2.0
        )
    }

    public func footprint(for face: ViewportBodyFace) -> ViewportProjectedRect {
        switch face {
        case .front:
            frontFootprint
        case .back:
            backFootprint
        case .top:
            ViewportProjectedRect(
                bottomLeft: frontFootprint.topLeft,
                bottomRight: frontFootprint.topRight,
                topRight: backFootprint.topRight,
                topLeft: backFootprint.topLeft
            )
        case .bottom:
            ViewportProjectedRect(
                bottomLeft: frontFootprint.bottomLeft,
                bottomRight: frontFootprint.bottomRight,
                topRight: backFootprint.bottomRight,
                topLeft: backFootprint.bottomLeft
            )
        case .left:
            ViewportProjectedRect(
                bottomLeft: frontFootprint.bottomLeft,
                bottomRight: backFootprint.bottomLeft,
                topRight: backFootprint.topLeft,
                topLeft: frontFootprint.topLeft
            )
        case .right, .side:
            ViewportProjectedRect(
                bottomLeft: frontFootprint.bottomRight,
                bottomRight: backFootprint.bottomRight,
                topRight: backFootprint.topRight,
                topLeft: frontFootprint.topRight
            )
        }
    }

    public func segment(for edge: ViewportBodyEdge) -> (start: CGPoint, end: CGPoint) {
        switch edge {
        case .leftBottom:
            (frontFootprint.bottomLeft, backFootprint.bottomLeft)
        case .rightBottom:
            (frontFootprint.bottomRight, backFootprint.bottomRight)
        case .rightTop:
            (frontFootprint.topRight, backFootprint.topRight)
        case .leftTop:
            (frontFootprint.topLeft, backFootprint.topLeft)
        }
    }

    public func point(for vertex: ViewportBodyVertex) -> CGPoint {
        switch vertex {
        case .frontBottomLeft:
            frontFootprint.bottomLeft
        case .frontBottomRight:
            frontFootprint.bottomRight
        case .frontTopRight:
            frontFootprint.topRight
        case .frontTopLeft:
            frontFootprint.topLeft
        case .backBottomLeft:
            backFootprint.bottomLeft
        case .backBottomRight:
            backFootprint.bottomRight
        case .backTopRight:
            backFootprint.topRight
        case .backTopLeft:
            backFootprint.topLeft
        }
    }
}

public struct ViewportLayout: Equatable {
    public struct FittingInsets: Equatable, Sendable {
        public var top: CGFloat
        public var leading: CGFloat
        public var bottom: CGFloat
        public var trailing: CGFloat

        public init(
            top: CGFloat = 0.0,
            leading: CGFloat = 0.0,
            bottom: CGFloat = 0.0,
            trailing: CGFloat = 0.0
        ) {
            self.top = Self.normalized(top)
            self.leading = Self.normalized(leading)
            self.bottom = Self.normalized(bottom)
            self.trailing = Self.normalized(trailing)
        }

        public static let zero = FittingInsets()

        /// Returns the drawable rectangle after applying bounded chrome insets.
        /// Camera fit and rendering use this same rectangle so control-plane
        /// fit commands do not maintain a second inset normalization policy.
        public func fittingRect(in size: CGSize) -> CGRect {
            let resolvedLeading = min(leading, max(size.width - 1.0, 0.0))
            let resolvedTrailing = min(trailing, max(size.width - resolvedLeading - 1.0, 0.0))
            let resolvedTop = min(top, max(size.height - 1.0, 0.0))
            let resolvedBottom = min(bottom, max(size.height - resolvedTop - 1.0, 0.0))
            return CGRect(
                x: resolvedLeading,
                y: resolvedTop,
                width: max(size.width - resolvedLeading - resolvedTrailing, 1.0),
                height: max(size.height - resolvedTop - resolvedBottom, 1.0)
            )
        }

        private static func normalized(_ value: CGFloat) -> CGFloat {
            guard value.isFinite,
                  value > 0.0 else {
                return 0.0
            }
            return value
        }
    }

    public var viewportSize: CGSize
    public var modelBounds: CGRect
    public var renderOrigin: Point3D
    /// World-space navigation target; `renderOrigin` remains precision-only.
    public var focus: Point3D
    public var scale: CGFloat
    public var fittingCenter: CGPoint
    public var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }
    public var center: CGPoint
    public var basis: ViewportProjectionBasis
    public var projection: ViewportCameraProjection
    public var maximumZoom: CGFloat
    public var fittingInsets: FittingInsets
    public var verticalBounds: ClosedRange<Double>?

    public init?(
        scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        maximumZoom: CGFloat = ViewportCamera.maximumZoom,
        fittingInsets: FittingInsets = .zero
    ) {
        guard let modelBounds = scene.modelBounds else {
            return nil
        }
        self.init(
            modelBounds: modelBounds,
            size: size,
            camera: camera,
            basis: basis,
            maximumZoom: maximumZoom,
            verticalBounds: scene.verticalBounds,
            fittingInsets: fittingInsets
        )
    }

    public init(
        modelBounds: CGRect,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        maximumZoom: CGFloat = ViewportCamera.maximumZoom,
        verticalBounds: ClosedRange<Double>? = nil,
        fittingInsets: FittingInsets = .zero
    ) {
        let modelWidth = max(modelBounds.width, 1.0e-9)
        let modelHeight = max(modelBounds.height, 1.0e-9)
        let clampedCamera = camera.clamped(maximumZoom: maximumZoom)
        let renderOrigin = Self.renderOrigin(modelBounds: modelBounds, verticalBounds: verticalBounds)
        let resolvedFocus = clampedCamera.focus ?? renderOrigin
        let projectedBounds = Self.projectedBounds(
            width: modelWidth,
            height: modelHeight,
            verticalHeight: Self.verticalHeight(verticalBounds),
            basis: basis
        )
        let fittingRect = fittingInsets.fittingRect(in: size)

        self.viewportSize = size
        self.modelBounds = modelBounds
        self.renderOrigin = renderOrigin
        self.focus = resolvedFocus
        self.scale = (clampedCamera.referenceScale ?? min(
            fittingRect.width / max(projectedBounds.width, 1.0e-9),
            fittingRect.height / max(projectedBounds.height, 1.0e-9)
        )) * clampedCamera.zoom
        self.fittingCenter = CGPoint(x: fittingRect.midX, y: fittingRect.midY)
        self.center = CGPoint(
            x: size.width / 2 + clampedCamera.pan.width,
            y: size.height / 2 + clampedCamera.pan.height
        )
        self.basis = basis
        self.projection = clampedCamera.projection
        self.maximumZoom = max(maximumZoom, ViewportCamera.minimumZoom)
        self.fittingInsets = fittingInsets
        self.verticalBounds = verticalBounds
    }

    public func project(_ point: CGPoint) -> CGPoint {
        // This planar convenience uses the retained reference elevation.
        project(Point3D(x: Double(point.x), y: renderOrigin.y, z: Double(point.y)))
    }

    public func projectedPoint(_ point: CGPoint) -> ViewportProjectedPoint? {
        projectedPoint(Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)))
    }

    /// Projects a point known to be inside the visible half-space.
    ///
    /// Fallible callers must use `projectedPoint(_:)`; this total convenience
    /// intentionally fails at the ownership boundary instead of manufacturing
    /// a mirrored, clamped, or non-finite screen point.
    public func project(_ point: Point3D) -> CGPoint {
        guard let projected = projectedPoint(point) else {
            preconditionFailure("Viewport point is outside the visible projection half-space.")
        }
        return projected.point
    }

    /// Projects a world point after homogeneous near-plane admission.
    ///
    /// A point behind a perspective camera is intentionally rejected instead
    /// of being mirrored or clamped into the viewport.
    public func projectedPoint(_ point: Point3D) -> ViewportProjectedPoint? {
        guard point.isFinite,
              let rows = projectionRows(relativeTo: renderOrigin),
              rows.isFinite else {
            return nil
        }
        let homogeneous = rows.evaluate(Point3D(
            x: point.x - renderOrigin.x,
            y: point.y - renderOrigin.y,
            z: point.z - renderOrigin.z
        ))
        return projectedPoint(homogeneous)
    }

    private func projectedPoint(_ homogeneous: ViewportHomogeneousPoint) -> ViewportProjectedPoint? {
        guard homogeneous.isFinite,
              homogeneous.w >= Self.minimumPerspectiveW else {
            return nil
        }
        let inverseW = 1.0 / homogeneous.w
        let ndcX = homogeneous.x * inverseW
        let ndcY = homogeneous.y * inverseW
        let depth = homogeneous.depth * inverseW
        guard ndcX.isFinite, ndcY.isFinite, depth.isFinite else {
            return nil
        }
        let x = (ndcX + 1.0) * Double(viewportSize.width) * 0.5
        let y = (1.0 - ndcY) * Double(viewportSize.height) * 0.5
        guard x.isFinite, y.isFinite else {
            return nil
        }
        return ViewportProjectedPoint(
            point: CGPoint(x: x, y: y),
            depth: depth,
            w: homogeneous.w
        )
    }

    public func projectedPolygon(_ points: [Point3D]) -> [ViewportProjectedPoint] {
        guard points.count > 1,
              let rows = projectionRows(relativeTo: renderOrigin), rows.isFinite else { return [] }
        var result: [ViewportProjectedPoint] = []
        result.reserveCapacity(points.count + 1)
        for index in points.indices {
            let first = points[index] - renderOrigin
            let second = points[(index + 1) % points.count] - renderOrigin
            let start = rows.evaluate(Point3D(x: first.x, y: first.y, z: first.z))
            let end = rows.evaluate(Point3D(x: second.x, y: second.y, z: second.z))
            guard start.isFinite, end.isFinite else { return [] }
            let startInside = start.w >= Self.minimumPerspectiveW
            let endInside = end.w >= Self.minimumPerspectiveW
            if startInside != endInside {
                let fraction = (Self.minimumPerspectiveW - start.w) / (end.w - start.w)
                // Clip in homogeneous space: reprojecting a world-space
                // intersection can round its w back outside the near plane.
                let intersection = ViewportHomogeneousPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction,
                    depth: start.depth + (end.depth - start.depth) * fraction,
                    w: Self.minimumPerspectiveW
                )
                guard let projected = projectedPoint(intersection) else { return [] }
                result.append(projected)
            }
            if endInside {
                guard let projected = projectedPoint(end) else { return [] }
                result.append(projected)
            }
        }
        return result
    }

    /// Returns the projection rows for mesh positions relative to `origin`.
    /// The returned rows may be copied directly into a GPU uniform buffer.
    public func projectionRows(relativeTo origin: Point3D = .origin) -> ViewportProjectionRows? {
        guard basis.isRigidOrientation,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0.0, viewportSize.height > 0.0,
              scale.isFinite, scale > 0.0,
              let viewNormal = basis.viewNormal,
              viewNormal.isFinite,
              origin.isFinite,
              renderOrigin.isFinite,
              focus.isFinite,
              projection.isValid else {
            return nil
        }
        let width = Double(viewportSize.width)
        let height = Double(viewportSize.height)
        let clipX = 2.0 * Double(center.x) / width - 1.0
        let clipY = 1.0 - 2.0 * Double(center.y) / height
        let horizontal = Vector3D(
            x: Double(basis.xDirection.dx),
            y: Double(basis.yDirection.dx),
            z: Double(basis.zDirection.dx)
        )
        let verticalDown = Vector3D(
            x: Double(basis.xDirection.dy),
            y: Double(basis.yDirection.dy),
            z: Double(basis.zDirection.dy)
        )
        guard horizontal.isFinite, verticalDown.isFinite,
              clipX.isFinite, clipY.isFinite else {
            return nil
        }

        let worldOffset = origin - renderOrigin
        let focusOffset = focus - renderOrigin
        switch projection {
        case .parallel:
            let xScale = 2.0 * Double(scale) / width
            let yScale = -2.0 * Double(scale) / height
            let depthExtent = maxDepthExtent(using: viewNormal)
            let rows = ViewportProjectionRows(
                x: Self.row(
                    coefficient: horizontal * xScale,
                    constant: clipX,
                    centeredAt: focusOffset,
                    translatedBy: worldOffset
                ),
                y: Self.row(
                    coefficient: verticalDown * yScale,
                    constant: clipY,
                    centeredAt: focusOffset,
                    translatedBy: worldOffset
                ),
                depth: Self.row(
                    coefficient: viewNormal / (2.0 * depthExtent),
                    constant: 0.5,
                    centeredAt: focusOffset,
                    translatedBy: worldOffset
                ),
                w: ViewportProjectionRow(x: 0.0, y: 0.0, z: 0.0, constant: 1.0)
            )
            return rows.isFinite ? rows : nil
        case .perspective(let fieldOfViewRadians):
            let tangent = tan(fieldOfViewRadians * 0.5)
            let fittingHeight = Double(viewportSize.height)
            let cameraDistance = fittingHeight / (2.0 * Double(scale) * tangent)
            // The depth row is the homogeneous near-plane plane. Keeping its
            // value equal to the CPU admission threshold makes Metal's
            // built-in z <= w clip reject exactly the same points as picking.
            let nearClip = Self.minimumPerspectiveW
            let xFocal = 2.0 * Double(scale) * cameraDistance / width
            let yFocal = 2.0 * Double(scale) * cameraDistance / height
            guard tangent.isFinite, tangent > 0.0,
                  fittingHeight.isFinite, fittingHeight > 0.0,
                  cameraDistance.isFinite, cameraDistance > nearClip,
                  nearClip.isFinite, xFocal.isFinite, yFocal.isFinite else {
                return nil
            }
            let worldW = ViewportProjectionRow(
                x: -viewNormal.x,
                y: -viewNormal.y,
                z: -viewNormal.z,
                constant: cameraDistance
            )
            // Translate the camera in its focus plane. Multiplying the screen
            // offset by worldW would instead create an off-axis lens and erase
            // the depth-dependent parallax of a native pinhole camera.
            let xCoefficient = horizontal * xFocal
            let yCoefficient = verticalDown * (-yFocal)
            let xConstant = clipX * worldW.constant
            let yConstant = clipY * worldW.constant
            let rows = ViewportProjectionRows(
                x: Self.row(
                    coefficient: xCoefficient,
                    constant: xConstant,
                    centeredAt: focusOffset,
                    translatedBy: worldOffset
                ),
                y: Self.row(
                    coefficient: yCoefficient,
                    constant: yConstant,
                    centeredAt: focusOffset,
                    translatedBy: worldOffset
                ),
                depth: ViewportProjectionRow(x: 0.0, y: 0.0, z: 0.0, constant: nearClip),
                w: Self.row(
                    coefficient: Vector3D(x: worldW.x, y: worldW.y, z: worldW.z),
                    constant: worldW.constant,
                    centeredAt: focusOffset,
                    translatedBy: worldOffset
                )
            )
            return rows.isFinite ? rows : nil
        }
    }

    public func project(_ point: CGPoint, in item: ViewportSceneItem) -> CGPoint {
        let transformedPoint = transformedPoint(
            Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)),
            in: item
        )
        return project(transformedPoint)
    }

    public func projectedPoint(
        _ point: CGPoint,
        in item: ViewportSceneItem
    ) -> ViewportProjectedPoint? {
        projectedPoint(
            Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)),
            in: item
        )
    }

    public func project(_ point: Point3D, in item: ViewportSceneItem) -> CGPoint {
        project(transformedPoint(point, in: item))
    }

    public func projectedPoint(
        _ point: Point3D,
        in item: ViewportSceneItem
    ) -> ViewportProjectedPoint? {
        projectedPoint(transformedPoint(point, in: item))
    }

    public func transformedPoint(_ point: Point3D, in item: ViewportSceneItem) -> Point3D {
        Self.transformedPoint(point, by: item.modelTransform)
    }

    public func projectedDepth(_ point: Point3D, in item: ViewportSceneItem) -> Double? {
        projectedDepth(transformedPoint(point, in: item))
    }

    public func projectedDepth(_ point: Point3D) -> Double? {
        switch projection {
        case .parallel:
            guard let viewNormal = basis.viewNormal else { return nil }
            return (point.x - focus.x) * viewNormal.x
                + (point.y - focus.y) * viewNormal.y
                + (point.z - focus.z) * viewNormal.z
        case .perspective:
            return projectedPoint(point)?.depth
        }
    }

    public func unproject(_ point: CGPoint) -> CGPoint {
        if projection == .parallel {
            // Solve the reference plane locally before adding the world focus.
            let elevation = CGFloat(focus.y - renderOrigin.y)
            let x = (point.x - center.x) / scale + basis.yDirection.dx * elevation
            let y = (point.y - center.y) / scale + basis.yDirection.dy * elevation
            let determinant = basis.xDirection.dx * basis.zDirection.dy
                - basis.zDirection.dx * basis.xDirection.dy
            precondition(abs(determinant) > 1.0e-12, "Reference canvas plane is edge-on.")
            return CGPoint(
                x: focus.x + Double((x * basis.zDirection.dy - basis.zDirection.dx * y) / determinant),
                y: focus.z + Double((basis.xDirection.dx * y - x * basis.xDirection.dy) / determinant)
            )
        }
        guard let world = unproject(
            point, planeOrigin: renderOrigin, normal: Vector3D(x: 0, y: 1, z: 0)
        ) else {
            preconditionFailure("Viewport point cannot be unprojected onto the reference canvas plane.")
        }
        return CGPoint(x: world.x, y: world.z)
    }

    /// Unprojects a screen point through the active camera onto the displayed
    /// canvas plane. Perspective callers must use this fallible contract;
    /// parallel affine math is never used as a failure fallback.
    public func canvasCoordinates(for point: CGPoint) -> CGPoint? {
        let plane = ViewportCanvasPlane.displayed(for: basis)
        guard let worldPoint = unproject(point, onto: plane) else {
            return nil
        }
        let coordinates = plane.coordinates(of: worldPoint)
        guard coordinates.x.isFinite, coordinates.y.isFinite else {
            return nil
        }
        return coordinates
    }

    public func unproject(
        _ point: CGPoint,
        onto canvasPlane: ViewportCanvasPlane
    ) -> Point3D? {
        guard let normal = canvasPlane.normal else { return nil }
        return unproject(point, planeOrigin: canvasPlane.worldPoint(first: 0, second: 0), normal: normal)
    }

    private func unproject(_ point: CGPoint, planeOrigin: Point3D, normal: Vector3D) -> Point3D? {
        guard let ray = viewportRay(for: point) else { return nil }
        let denominator = ray.direction.dot(normal)
        guard denominator.isFinite, abs(denominator) > 1.0e-12 else {
            return nil
        }
        let distance = (planeOrigin - ray.origin).dot(normal) / denominator
        guard distance.isFinite, projection == .parallel || distance >= 0.0 else {
            return nil
        }
        let worldPoint = ray.origin + ray.direction * distance
        guard worldPoint.isFinite else {
            return nil
        }
        return worldPoint
    }

    /// Resolves navigation on the view plane through the camera focus, not a
    /// construction plane whose intersection may jump or disappear while orbiting.
    public func worldPointOnFocusPlane(for point: CGPoint) -> Point3D? {
        guard let normal = basis.viewNormal else { return nil }
        return unproject(point, planeOrigin: focus, normal: normal)
    }

    public func viewportRay(for point: CGPoint) -> ViewportWorldRay? {
        guard point.x.isFinite, point.y.isFinite,
              let viewNormal = basis.viewNormal,
              let horizontal = screenHorizontal,
              let verticalDown = screenVerticalDown,
              projectionRows(relativeTo: renderOrigin)?.isFinite == true,
              viewNormal.isFinite else {
            return nil
        }
        let dualHorizontal = verticalDown.cross(viewNormal)
        let dualVertical = viewNormal.cross(horizontal)
        let dualNormal = horizontal.cross(verticalDown)
        let determinant = horizontal.dot(dualHorizontal)
        guard determinant.isFinite, abs(determinant) > 1.0e-12 else { return nil }
        switch projection {
        case .parallel:
            let viewportX = Double((point.x - center.x) / scale)
            let viewportY = Double((point.y - center.y) / scale)
            let anchor = focus + (dualHorizontal * viewportX + dualVertical * viewportY) / determinant
            return ViewportWorldRay(origin: anchor, direction: viewNormal)
        case .perspective:
            guard let cameraDistance = perspectiveCameraDistance else {
                return nil
            }
            let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
            let ndcX = 2.0 * Double(point.x - viewportCenter.x) / Double(viewportSize.width)
            let ndcY = -2.0 * Double(point.y - viewportCenter.y) / Double(viewportSize.height)
            let xFocal = 2.0 * Double(scale) * cameraDistance / Double(viewportSize.width)
            let yFocal = 2.0 * Double(scale) * cameraDistance / Double(viewportSize.height)
            guard xFocal.isFinite, yFocal.isFinite,
                  abs(xFocal) > 1.0e-12, abs(yFocal) > 1.0e-12,
                  ndcX.isFinite, ndcY.isFinite else {
                return nil
            }
            // Use the same symmetric lens and translated camera origin as
            // projectionRows; the fitting center is not a lens principal point.
            let direction = (
                dualHorizontal * (ndcX / xFocal)
                + dualVertical * (-ndcY / yFocal)
                - dualNormal
            ) / determinant
            let normalizedDirection: Vector3D
            do {
                normalizedDirection = try direction.normalized(tolerance: 1.0e-12)
            } catch {
                return nil
            }
            let cameraOrigin = focus + viewNormal * cameraDistance
                + horizontal * Double((viewportCenter.x - center.x) / scale)
                + verticalDown * Double((viewportCenter.y - center.y) / scale)
            return ViewportWorldRay(origin: cameraOrigin, direction: normalizedDirection)
        }
    }

    public var visibleHeightMeters: Double {
        let height = Double(viewportSize.height)
        guard height.isFinite, height > 0.0,
              scale.isFinite, scale > 0.0 else {
            preconditionFailure("Viewport layout has no finite visible height.")
        }
        return height / Double(scale)
    }


    public func displayedCanvasWorldPoint(for viewportPoint: CGPoint) -> Point3D? {
        unproject(
            viewportPoint,
            onto: ViewportCanvasPlane.displayed(for: basis)
        )
    }

    public func projectedFootprint(_ itemBounds: CGRect) -> ViewportProjectedRect {
        guard let footprint = projectedFootprintIfVisible(itemBounds) else {
            preconditionFailure("Viewport footprint is outside the visible projection half-space.")
        }
        return footprint
    }

    /// Projects all four corners of a model-space rectangle, retaining the
    /// rectangle only when every corner is visible to the active camera.
    /// Perspective consumers use this fallible path instead of manufacturing
    /// a screen-space footprint for a near-clipped body.
    public func projectedFootprintIfVisible(_ itemBounds: CGRect) -> ViewportProjectedRect? {
        let points = [
            Point3D(x: Double(itemBounds.minX), y: 0.0, z: Double(itemBounds.minY)),
            Point3D(x: Double(itemBounds.maxX), y: 0.0, z: Double(itemBounds.minY)),
            Point3D(x: Double(itemBounds.maxX), y: 0.0, z: Double(itemBounds.maxY)),
            Point3D(x: Double(itemBounds.minX), y: 0.0, z: Double(itemBounds.maxY)),
        ]
        let projected = points.compactMap(projectedPoint)
        guard projected.count == points.count else {
            return nil
        }
        return ViewportProjectedRect(
            bottomLeft: projected[0].point,
            bottomRight: projected[1].point,
            topRight: projected[2].point,
            topLeft: projected[3].point
        )
    }

    public func projectedRect(_ itemBounds: CGRect) -> CGRect {
        projectedFootprint(itemBounds).bounds
    }

    public func projectedRectIfVisible(_ itemBounds: CGRect) -> CGRect? {
        projectedFootprintIfVisible(itemBounds)?.bounds
    }

    public static func transformedPoint(
        _ point: Point3D,
        by transform: Transform3D
    ) -> Point3D {
        transform.viewportTransformedPoint(point)
    }

    public func bodyProjection(for item: ViewportSceneItem) -> ViewportBodyProjection? {
        guard case .body(let component) = item.kind else {
            return nil
        }

        guard let footprint = projectedFootprintIfVisible(item.modelBounds) else {
            return nil
        }
        let depthOffset = max(12.0, min(54.0, CGFloat(component.sizeYMeters) * scale * 0.85))
        let offset = CGSize(
            width: basis.yDirection.dx * depthOffset,
            height: basis.yDirection.dy * depthOffset
        )
        return ViewportBodyProjection(
            frontFootprint: footprint,
            backFootprint: footprint.offsetBy(dx: offset.width, dy: offset.height),
            offset: offset
        )
    }

    public static let minimumPerspectiveW = 1.0e-6

    private var screenHorizontal: Vector3D? {
        let vector = Vector3D(
            x: Double(basis.xDirection.dx),
            y: Double(basis.yDirection.dx),
            z: Double(basis.zDirection.dx)
        )
        return vector.isFinite ? vector : nil
    }

    private var screenVerticalDown: Vector3D? {
        let vector = Vector3D(
            x: Double(basis.xDirection.dy),
            y: Double(basis.yDirection.dy),
            z: Double(basis.zDirection.dy)
        )
        return vector.isFinite ? vector : nil
    }

    private var perspectiveCameraDistance: Double? {
        guard case .perspective(let fieldOfViewRadians) = projection,
              fieldOfViewRadians.isFinite,
              fieldOfViewRadians > 0.0,
              fieldOfViewRadians < .pi,
              scale.isFinite, scale > 0.0 else {
            return nil
        }
        let height = Double(viewportSize.height)
        let tangent = tan(fieldOfViewRadians * 0.5)
        let distance = height / (2.0 * Double(scale) * tangent)
        guard distance.isFinite, distance > Self.minimumPerspectiveW else {
            return nil
        }
        return distance
    }

    private func maxDepthExtent(using viewNormal: Vector3D) -> Double {
        var maximum = 0.0
        let xValues = [modelBounds.minX, modelBounds.maxX]
        let zValues = [modelBounds.minY, modelBounds.maxY]
        let yValues = verticalBoundsForDepth
        for x in xValues {
            for y in yValues {
                for z in zValues {
                    let delta = Point3D(x: Double(x), y: y, z: Double(z)) - focus
                    maximum = max(maximum, abs(delta.dot(viewNormal)))
                }
            }
        }
        if maximum.isFinite, maximum > 1.0e-9 {
            return maximum
        }
        let verticalHeight = verticalBounds.map { $0.upperBound - $0.lowerBound } ?? 0.0
        return max(verticalHeight.isFinite ? verticalHeight : 0.0, 1.0e-9)
    }

    private var verticalBoundsForDepth: [Double] {
        guard let vertical = verticalBounds,
              vertical.lowerBound.isFinite,
              vertical.upperBound.isFinite,
              vertical.lowerBound <= vertical.upperBound else {
            return [renderOrigin.y]
        }
        return [vertical.lowerBound, vertical.upperBound]
    }

    private static func row(
        coefficient: Vector3D,
        constant: Double,
        centeredAt centerOffset: Vector3D,
        translatedBy worldOffset: Vector3D
    ) -> ViewportProjectionRow {
        ViewportProjectionRow(
            x: coefficient.x,
            y: coefficient.y,
            z: coefficient.z,
            constant: constant + coefficient.dot(worldOffset - centerOffset)
        )
    }

    private static func interpolate(_ start: Point3D, _ end: Point3D, _ fraction: Double) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: start.z + (end.z - start.z) * fraction
        )
    }

    private static func projectedBounds(
        width: CGFloat,
        height: CGFloat,
        verticalHeight: CGFloat,
        basis: ViewportProjectionBasis
    ) -> CGRect {
        var points: [CGPoint] = []
        points.reserveCapacity(8)
        for x in [CGFloat(0.0), width] {
            for y in [CGFloat(0.0), verticalHeight] {
                for z in [CGFloat(0.0), height] {
                    points.append(CGPoint(
                        x: basis.xDirection.dx * x
                            + basis.yDirection.dx * y
                            + basis.zDirection.dx * z,
                        y: basis.xDirection.dy * x
                            + basis.yDirection.dy * y
                            + basis.zDirection.dy * z
                    ))
                }
            }
        }
        let minX = points.map(\.x).min() ?? 0.0
        let minY = points.map(\.y).min() ?? 0.0
        let maxX = points.map(\.x).max() ?? 0.0
        let maxY = points.map(\.y).max() ?? 0.0
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func verticalHeight(_ verticalBounds: ClosedRange<Double>?) -> CGFloat {
        guard let verticalBounds else {
            return 0.0
        }
        let height = verticalBounds.upperBound - verticalBounds.lowerBound
        guard height.isFinite,
              height > 0.0 else {
            return 0.0
        }
        return CGFloat(height)
    }

    private static func renderOrigin(
        modelBounds: CGRect,
        verticalBounds: ClosedRange<Double>?
    ) -> Point3D {
        let y = verticalBounds.map { ($0.lowerBound + $0.upperBound) * 0.5 } ?? 0.0
        return Point3D(
            x: Double(modelBounds.midX),
            y: y.isFinite ? y : 0.0,
            z: Double(modelBounds.midY)
        )
    }
}

public struct ViewportModelCoordinateMapper {
    public var layout: ViewportLayout

    public init(
        document: DesignDocument,
        ruler: RulerConfiguration,
        size: CGSize,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        documentGeneration: DocumentGeneration? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        fittingInsets: ViewportLayout.FittingInsets = .zero
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: document,
            ruler: ruler,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache
        )
        self.init(
            ruler: ruler,
            scene: scene,
            size: size,
            camera: camera,
            basis: basis,
            fittingInsets: fittingInsets
        )
    }

    public init(
        ruler: RulerConfiguration,
        scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        geometryBoundsSource: ViewportGeometryBoundsSource = .scene,
        fittingInsets: ViewportLayout.FittingInsets = .zero
    ) {
        let modelBounds = Self.modelBounds(
            for: scene,
            ruler: ruler,
            geometryBoundsSource: geometryBoundsSource
        )
        let verticalBounds = Self.verticalBounds(
            for: scene,
            geometryBoundsSource: geometryBoundsSource
        )
        let identityLayout = ViewportLayout(
            modelBounds: modelBounds,
            size: size,
            camera: .identity,
            basis: basis,
            verticalBounds: verticalBounds,
            fittingInsets: fittingInsets
        )
        let maximumZoom = ViewportCameraZoomPolicy.maximumZoom(
            ruler: ruler,
            identityScale: camera.referenceScale ?? identityLayout.scale
        )
        self.layout = ViewportLayout(
            modelBounds: modelBounds,
            size: size,
            camera: camera,
            basis: basis,
            maximumZoom: maximumZoom,
            verticalBounds: verticalBounds,
            fittingInsets: fittingInsets
        )
    }

    public func modelPoint(for viewportPoint: CGPoint) -> Point2D? {
        guard let point = layout.canvasCoordinates(for: viewportPoint) else {
            return nil
        }
        return Point2D(
            x: Double(point.x),
            y: Double(point.y)
        )
    }

    public func displayedCanvasWorldPoint(for viewportPoint: CGPoint) -> Point3D? {
        layout.displayedCanvasWorldPoint(for: viewportPoint)
    }

    public func modelDrag(
        from start: CGPoint,
        to end: CGPoint,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags(),
        startWorldPoint: Point3D? = nil,
        endWorldPoint: Point3D? = nil,
        startViewRayAnchorWorldPoint: Point3D? = nil,
        endViewRayAnchorWorldPoint: Point3D? = nil
    ) -> ViewportModelDrag? {
        guard let startPoint = modelPoint(for: start),
              let endPoint = modelPoint(for: end) else {
            return nil
        }
        return ViewportModelDrag(
            start: startPoint,
            end: endPoint,
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startWorldPoint,
            endWorldPoint: endWorldPoint,
            startViewRayAnchorWorldPoint: startViewRayAnchorWorldPoint,
            endViewRayAnchorWorldPoint: endViewRayAnchorWorldPoint
        )
    }

    private static func emptyModelBounds(ruler: RulerConfiguration) -> CGRect {
        let ruler = ruler.normalizedForWorkspaceScale()
        let span = max(
            ruler.visibleSpanMeters,
            ruler.majorTickMeters * 20.0,
            ruler.minorTickMeters * 40.0
        )
        let size = CGFloat(span)
        return CGRect(
            x: -size / 2.0,
            y: -size / 2.0,
            width: size,
            height: size
        )
    }

    private static func framedSceneBounds(
        _ sceneBounds: CGRect,
        ruler: RulerConfiguration
    ) -> CGRect {
        let normalizedRuler = ruler.normalizedForWorkspaceScale()
        let minimumSpan = max(
            normalizedRuler.majorTickMeters * 4.0,
            normalizedRuler.minorTickMeters * 20.0,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        let sceneSpan = max(Double(sceneBounds.width), Double(sceneBounds.height))
        let padding = max(
            sceneSpan * 0.12,
            normalizedRuler.majorTickMeters,
            normalizedRuler.minorTickMeters * 4.0
        )
        let width = max(Double(sceneBounds.width) + padding * 2.0, minimumSpan)
        let height = max(Double(sceneBounds.height) + padding * 2.0, minimumSpan)
        return CGRect(
            x: sceneBounds.midX - CGFloat(width) / 2.0,
            y: sceneBounds.midY - CGFloat(height) / 2.0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }

    private static func modelBounds(
        for scene: ViewportScene,
        ruler: RulerConfiguration,
        geometryBoundsSource: ViewportGeometryBoundsSource
    ) -> CGRect {
        let baseBounds = emptyModelBounds(ruler: ruler)
        let rawBounds: CGRect?
        switch geometryBoundsSource {
        case .scene:
            rawBounds = scene.modelBounds
        case .geometry(let bounds):
            rawBounds = bounds.map {
                CGRect(
                    x: $0.minimum.x,
                    y: $0.minimum.z,
                    width: $0.maximum.x - $0.minimum.x,
                    height: $0.maximum.z - $0.minimum.z
                )
            }
        }
        guard let rawBounds else {
            return baseBounds
        }
        let framedBounds = framedSceneBounds(rawBounds, ruler: ruler)
        if baseBounds.intersects(rawBounds) {
            return baseBounds.union(framedBounds)
        }
        return framedBounds
    }

    private static func verticalBounds(
        for scene: ViewportScene,
        geometryBoundsSource: ViewportGeometryBoundsSource
    ) -> ClosedRange<Double>? {
        switch geometryBoundsSource {
        case .scene:
            return scene.verticalBounds
        case .geometry(let bounds):
            return bounds.map { $0.minimum.y ... $0.maximum.y }
        }
    }
}

public struct ViewportSceneContext {
    public var scene: ViewportScene
    public var mapper: ViewportModelCoordinateMapper

    public var layout: ViewportLayout {
        mapper.layout
    }

    public init(
        ruler: RulerConfiguration,
        scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        geometryBoundsSource: ViewportGeometryBoundsSource = .scene,
        fittingInsets: ViewportLayout.FittingInsets = .zero
    ) {
        self.scene = scene
        self.mapper = ViewportModelCoordinateMapper(
            ruler: ruler,
            scene: scene,
            size: size,
            camera: camera,
            basis: basis,
            geometryBoundsSource: geometryBoundsSource,
            fittingInsets: fittingInsets
        )
    }

    public init(
        document: DesignDocument,
        ruler: RulerConfiguration,
        documentGeneration: DocumentGeneration? = nil,
        size: CGSize,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        fittingInsets: ViewportLayout.FittingInsets = .zero
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: document,
            ruler: ruler,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache
        )
        self.scene = scene
        self.mapper = ViewportModelCoordinateMapper(
            ruler: ruler,
            scene: scene,
            size: size,
            camera: camera,
            basis: basis,
            fittingInsets: fittingInsets
        )
    }
}

public struct ViewportHit: Equatable, Sendable {
    public var featureID: FeatureID
    public var sceneNodeID: SceneNodeID?
    public var kind: ViewportSelectableKind
    public var sketchEntityID: SketchEntityID?
    public var sketchPointHandle: SketchEntityPointHandle?
    public var sketchControlPointIndex: Int?
    public var bodyFace: ViewportBodyFace?
    public var bodyEdge: ViewportBodyEdge?
    public var selectionComponent: SelectionComponent?
    public var selectionReference: SelectionReference?

    public init(
        featureID: FeatureID,
        sceneNodeID: SceneNodeID? = nil,
        kind: ViewportSelectableKind,
        sketchEntityID: SketchEntityID? = nil,
        sketchPointHandle: SketchEntityPointHandle? = nil,
        sketchControlPointIndex: Int? = nil,
        bodyFace: ViewportBodyFace? = nil,
        bodyEdge: ViewportBodyEdge? = nil,
        selectionComponent: SelectionComponent? = nil,
        selectionReference: SelectionReference? = nil
    ) {
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.kind = kind
        self.sketchEntityID = sketchEntityID
        self.sketchPointHandle = sketchPointHandle
        self.sketchControlPointIndex = sketchControlPointIndex
        self.bodyFace = bodyFace
        self.bodyEdge = bodyEdge
        self.selectionComponent = selectionComponent
        self.selectionReference = selectionReference
    }
}

public enum ViewportSelectionIntent: Equatable, Sendable {
    case replace
    case toggle
}

public struct ViewportCanvasTarget: Equatable, Sendable {
    public var hit: ViewportHit?
    public var modelPoint: Point2D
    public var modelWorldPoint: Point3D?
    public var viewRayAnchorWorldPoint: Point3D?
    public var sketchPlane: SketchPlane
    public var selectionIntent: ViewportSelectionIntent
    public var modifierFlags: ViewportInputModifierFlags

    public init(
        hit: ViewportHit?,
        modelPoint: Point2D,
        modelWorldPoint: Point3D? = nil,
        viewRayAnchorWorldPoint: Point3D? = nil,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        selectionIntent: ViewportSelectionIntent = .replace,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) {
        self.hit = hit
        self.modelPoint = modelPoint
        self.modelWorldPoint = modelWorldPoint
        self.viewRayAnchorWorldPoint = viewRayAnchorWorldPoint
        self.sketchPlane = sketchPlane
        self.selectionIntent = selectionIntent
        self.modifierFlags = modifierFlags
    }
}

public struct ViewportSelectionDragTarget: Equatable, Sendable {
    public var hits: [ViewportHit]
    public var presentationOccurrenceIDs: [SceneOccurrenceID]
    public var selectionIntent: ViewportSelectionIntent

    public init(
        hits: [ViewportHit],
        presentationOccurrenceIDs: [SceneOccurrenceID] = [],
        selectionIntent: ViewportSelectionIntent = .replace
    ) {
        self.hits = hits
        self.presentationOccurrenceIDs = presentationOccurrenceIDs
        self.selectionIntent = selectionIntent
    }
}

public struct ViewportVertexDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var deltaX: Double
    public var deltaY: Double

    public init(
        target: SelectionTarget,
        deltaX: Double,
        deltaY: Double
    ) {
        self.target = target
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public struct ViewportPolySplineSurfaceVertexDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var deltaX: Double
    public var deltaY: Double
    public var deltaZ: Double

    public init(
        target: SelectionTarget,
        deltaX: Double,
        deltaY: Double,
        deltaZ: Double
    ) {
        self.target = target
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.deltaZ = deltaZ
    }
}

public struct ViewportSurfaceControlPointDragTarget: Equatable, Sendable {
    public var target: SelectionReference
    public var deltaX: Double
    public var deltaY: Double
    public var deltaZ: Double

    public init(
        target: SelectionReference,
        deltaX: Double,
        deltaY: Double,
        deltaZ: Double
    ) {
        self.target = target
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.deltaZ = deltaZ
    }
}

public struct ViewportSurfaceTrimEndpointDragTarget: Equatable, Sendable {
    public var target: SelectionReference
    public var endpoint: SurfaceTrimEndpoint
    public var u: Double
    public var v: Double

    public init(
        target: SelectionReference,
        endpoint: SurfaceTrimEndpoint,
        u: Double,
        v: Double
    ) {
        self.target = target
        self.endpoint = endpoint
        self.u = u
        self.v = v
    }
}

public struct ViewportSurfaceTrimControlPointDragTarget: Equatable, Sendable {
    public var target: SelectionReference
    public var controlPointIndex: Int
    public var u: Double
    public var v: Double

    public init(
        target: SelectionReference,
        controlPointIndex: Int,
        u: Double,
        v: Double
    ) {
        self.target = target
        self.controlPointIndex = controlPointIndex
        self.u = u
        self.v = v
    }
}

public struct ViewportSurfaceControlPointSlideDragTarget: Equatable, Sendable {
    public var targets: [SelectionReference]
    public var direction: PolySplineSurfaceVertexSlideDirection
    public var distance: Double

    public init(
        targets: [SelectionReference],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: Double
    ) {
        self.targets = targets
        self.direction = direction
        self.distance = distance
    }
}

public enum ViewportSurfaceFrameAxis: String, CaseIterable, Equatable, Sendable {
    case u
    case v
    case normal
}

public struct ViewportSurfaceFrameDragTarget: Equatable, Sendable {
    public var targets: [SelectionReference]
    public var query: SurfaceFrameQuery
    public var axis: ViewportSurfaceFrameAxis
    public var distance: Double

    public init(
        targets: [SelectionReference],
        query: SurfaceFrameQuery,
        axis: ViewportSurfaceFrameAxis,
        distance: Double
    ) {
        self.targets = targets
        self.query = query
        self.axis = axis
        self.distance = distance
    }
}

public struct ViewportPolySplineSurfaceVertexSlideDragTarget: Equatable, Sendable {
    public var targets: [SelectionTarget]
    public var direction: PolySplineSurfaceVertexSlideDirection
    public var distance: Double

    public init(
        targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: Double
    ) {
        self.targets = targets
        self.direction = direction
        self.distance = distance
    }
}

public struct ViewportFaceDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var distance: Double

    public init(
        target: SelectionTarget,
        distance: Double
    ) {
        self.target = target
        self.distance = distance
    }
}

public struct ViewportRegionOffsetDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var distance: Double

    public init(
        target: SelectionTarget,
        distance: Double
    ) {
        self.target = target
        self.distance = distance
    }
}

public struct ViewportEdgeOffsetDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var distance: Double

    public init(
        target: SelectionTarget,
        distance: Double
    ) {
        self.target = target
        self.distance = distance
    }
}

public struct ViewportSlotWidthDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var width: Double

    public init(
        target: SelectionTarget,
        width: Double
    ) {
        self.target = target
        self.width = width
    }
}

public struct ViewportSketchVertexOffsetDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var handle: SketchEntityPointHandle
    public var distance: Double

    public init(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        distance: Double
    ) {
        self.target = target
        self.handle = handle
        self.distance = distance
    }
}

public struct ViewportEdgeChamferDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var distance: Double

    public init(
        target: SelectionTarget,
        distance: Double
    ) {
        self.target = target
        self.distance = distance
    }
}

public struct ViewportEdgeFilletDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var radius: Double

    public init(
        target: SelectionTarget,
        radius: Double
    ) {
        self.target = target
        self.radius = radius
    }
}

public struct ViewportSplineControlPointDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var controlPointIndex: Int
    public var deltaX: Double
    public var deltaY: Double

    public init(
        target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: Double,
        deltaY: Double
    ) {
        self.target = target
        self.controlPointIndex = controlPointIndex
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public struct ViewportSplineControlPointSlideDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var controlPointIndexes: [Int]
    public var direction: SplineControlPointSlideDirection
    public var distance: Double

    public init(
        target: SelectionTarget,
        controlPointIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distance: Double
    ) {
        self.target = target
        self.controlPointIndexes = controlPointIndexes
        self.direction = direction
        self.distance = distance
    }
}

public struct ViewportSketchPointHandleDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var handle: SketchEntityPointHandle
    public var deltaX: Double
    public var deltaY: Double

    public init(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: Double,
        deltaY: Double
    ) {
        self.target = target
        self.handle = handle
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public enum ViewportSketchCurveHandleKind: String, Equatable, Sendable {
    case circleRadius
    case arcRadius
    case arcStartAngle
    case arcEndAngle
}

public struct ViewportSketchCurveHandleDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var handle: ViewportSketchCurveHandleKind
    public var radiusMeters: Double?
    public var startAngleRadians: Double?
    public var endAngleRadians: Double?

    public init(
        target: SelectionTarget,
        handle: ViewportSketchCurveHandleKind,
        radiusMeters: Double? = nil,
        startAngleRadians: Double? = nil,
        endAngleRadians: Double? = nil
    ) {
        self.target = target
        self.handle = handle
        self.radiusMeters = radiusMeters
        self.startAngleRadians = startAngleRadians
        self.endAngleRadians = endAngleRadians
    }
}

public struct ViewportSketchDimensionDragTarget: Equatable, Sendable {
    public var target: SelectionTarget
    public var kind: SketchEntityDimensionKind
    public var value: CADExpression

    public init(
        target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    ) {
        self.target = target
        self.kind = kind
        self.value = value
    }
}

private func bounds(for points: [CGPoint]) -> CGRect {
    let minX = points.map(\.x).min() ?? 0.0
    let minY = points.map(\.y).min() ?? 0.0
    let maxX = points.map(\.x).max() ?? 0.0
    let maxY = points.map(\.y).max() ?? 0.0
    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY
    )
}

private struct ViewportSketchPlaneProjection {
    private var coordinateSystem: SketchPlaneCoordinateSystem
    private var canvasMapper: SketchPlaneCanvasMapper

    init?(sketchPlane: SketchPlane) {
        do {
            self.coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
            self.canvasMapper = SketchPlaneCanvasMapper(sketchPlane: sketchPlane)
        } catch {
            return nil
        }
    }

    func localPoint(fromCanvas point: Point2D) -> Point2D {
        canvasMapper.localPoint(fromCanvas: point)
    }

    func project(
        localPoint: Point2D,
        layout: ViewportLayout
    ) -> CGPoint? {
        guard localPoint.x.isFinite, localPoint.y.isFinite else {
            return nil
        }
        return layout.projectedPoint(coordinateSystem.point(from: localPoint))?.point
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0 else {
            return distance(to: start)
        }
        let t = max(0.0, min(1.0, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
        return distance(
            to: CGPoint(
                x: start.x + t * dx,
                y: start.y + t * dy
            )
        )
    }
}
