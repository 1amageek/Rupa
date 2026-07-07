import CoreGraphics
import RupaCore
import SwiftCAD

public enum ViewportSelectableKind: String, Equatable, Sendable {
    case sketch
    case body
}

public enum ViewportBodyFace: String, CaseIterable, Equatable, Sendable {
    case front
    case back
    case top
    case bottom
    case left
    case right
    case side
}

public enum ViewportBodyEdge: String, CaseIterable, Equatable, Sendable {
    case leftBottom
    case rightBottom
    case rightTop
    case leftTop
}

public enum ViewportBodyVertex: String, CaseIterable, Equatable, Sendable {
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

public enum ViewportSketchPrimitive: Equatable {
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

public enum ViewportSceneItemKind: Equatable {
    case sketch(primitives: [ViewportSketchPrimitive])
    case body(component: ViewportBodyComponent)

    public var selectableKind: ViewportSelectableKind {
        switch self {
        case .sketch:
            return .sketch
        case .body:
            return .body
        }
    }
}

public struct ViewportBodyComponent: Equatable {
    public var bodyID: String?
    public var persistentName: String?
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
        persistentName: String? = nil,
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
        self.persistentName = persistentName
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
    public var facePersistentNames: [String]

    public init(
        id: SurfaceFrameDisplayID,
        query: SurfaceFrameQuery,
        position: Point3D,
        uAxis: Vector3D,
        vAxis: Vector3D,
        normal: Vector3D,
        u: Double,
        v: Double,
        facePersistentNames: [String]
    ) {
        self.id = id
        self.query = query
        self.position = position
        self.uAxis = uAxis
        self.vAxis = vAxis
        self.normal = normal
        self.u = u
        self.v = v
        self.facePersistentNames = facePersistentNames
    }
}

public struct ViewportBodyTopology: Equatable {
    public var faces: [Face]
    public var edges: [Edge]
    public var vertices: [Vertex]

    public init(
        faces: [Face] = [],
        edges: [Edge] = [],
        vertices: [Vertex] = []
    ) {
        self.faces = faces
        self.edges = edges
        self.vertices = vertices
    }

    public struct Face: Equatable {
        public var componentID: SelectionComponentID
        public var points: [Point3D]

        public init(componentID: SelectionComponentID, points: [Point3D]) {
            self.componentID = componentID
            self.points = points
        }
    }

    public struct Edge: Equatable {
        public var componentID: SelectionComponentID
        public var start: Point3D
        public var end: Point3D

        public init(componentID: SelectionComponentID, start: Point3D, end: Point3D) {
            self.componentID = componentID
            self.start = start
            self.end = end
        }
    }

    public struct Vertex: Equatable {
        public var componentID: SelectionComponentID
        public var point: Point3D

        public init(componentID: SelectionComponentID, point: Point3D) {
            self.componentID = componentID
            self.point = point
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
            }
        )
    }
}

public struct ViewportBodyTopologyHit: Equatable, Sendable {
    public var component: SelectionComponent
    public var score: CGFloat
    public var depth: Double?

    public init(
        component: SelectionComponent,
        score: CGFloat,
        depth: Double? = nil
    ) {
        self.component = component
        self.score = score
        self.depth = depth
    }
}

public struct ViewportCylinderComponent: Equatable {
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

public struct ViewportSceneItem: Equatable, Identifiable {
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

public struct ViewportScene: Equatable {
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
            guard case .body(let component) = item.kind else {
                continue
            }
            let itemBounds = min(component.yMinMeters, component.yMaxMeters)
                ... max(component.yMinMeters, component.yMaxMeters)
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

    public init(
        start: Point2D,
        end: Point2D,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags(),
        startWorldPoint: Point3D? = nil,
        endWorldPoint: Point3D? = nil
    ) {
        self.start = start
        self.end = end
        self.sketchPlane = sketchPlane
        self.modifierFlags = modifierFlags
        self.startWorldPoint = startWorldPoint
        self.endWorldPoint = endWorldPoint
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
            startWorldPoint: startWorldPoint
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
        guard face.points.count >= 3 else {
            return nil
        }
        let projectedPoints = face.points.map { layout.project($0) }
        let origin2D = projectedPoints[0]
        let origin3D = face.points[0]
        for index in 1 ..< projectedPoints.count - 1 {
            guard let weights = barycentricWeights(
                point: viewportPoint,
                a: origin2D,
                b: projectedPoints[index],
                c: projectedPoints[index + 1],
                tolerance: tolerance
            ) else {
                continue
            }
            return weightedPoint(
                origin3D,
                face.points[index],
                face.points[index + 1],
                weights: weights
            )
        }
        return nil
    }

    private func barycentricWeights(
        point: CGPoint,
        a: CGPoint,
        b: CGPoint,
        c: CGPoint,
        tolerance: CGFloat
    ) -> (a: Double, b: Double, c: Double)? {
        let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        guard abs(denominator) > tolerance else {
            return nil
        }
        let aWeight = ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
        let bWeight = ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
        let cWeight = 1.0 - aWeight - bWeight
        guard aWeight >= -tolerance,
              bWeight >= -tolerance,
              cWeight >= -tolerance,
              aWeight <= 1.0 + tolerance,
              bWeight <= 1.0 + tolerance,
              cWeight <= 1.0 + tolerance else {
            return nil
        }
        return (
            a: Double(aWeight),
            b: Double(bWeight),
            c: Double(cWeight)
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
            widthMeters: widthOverrideMeters,
            heightMeters: heightOverrideMeters
        )
    }

    public init?(
        start: Point2D,
        end: Point2D,
        layout: ViewportLayout,
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
        let endX = start.x + Self.signedDimension(width, following: deltaX)
        let endY = start.y + Self.signedDimension(height, following: deltaY)
        let minX = min(start.x, endX)
        let minY = min(start.y, endY)
        let maxX = max(start.x, endX)
        let maxY = max(start.y, endY)
        guard minX < maxX, minY < maxY else {
            return nil
        }

        let modelBounds = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxY - minY)
        )
        self.modelBounds = modelBounds
        self.footprint = layout.projectedFootprint(modelBounds)
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
}

public enum ViewportCanvasDragPreview: Equatable {
    case rectangle(ViewportCanvasDragPlaceholder)
    case polygon(ViewportCanvasPolygonDragPreview)
    case arc(ViewportCanvasArcDragPreview)
    case spline(ViewportCanvasSplineDragPreview)

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
        let draft: CanvasSketchCurveDrafts.Polygon
        do {
            draft = try CanvasSketchCurveDrafts.polygon(
                fromCenter: drag.start,
                toRadiusPoint: drag.end,
                sides: sideCount,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                radiusMeters: radiusOverrideMeters,
                rotationAngleRadians: rotationAngleOverrideRadians
            )
        } catch {
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
        self.projectedCenter = layout.project(modelCenter)
        self.projectedVertices = draft.vertices.map {
            layout.project(CGPoint(x: $0.x, y: $0.y))
        }
        self.projectedRadiusEnd = layout.project(
            CGPoint(
                x: draft.center.x + cos(draft.rotationAngleRadians) * draft.circumradiusMeters,
                y: draft.center.y + sin(draft.rotationAngleRadians) * draft.circumradiusMeters
            )
        )
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
        let draft: CanvasSketchCurveDrafts.Arc
        do {
            draft = try CanvasSketchCurveDrafts.arc(
                fromCenter: drag.start,
                toRadiusPoint: drag.end,
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
        self.modelCenter = center
        self.modelRadiusMeters = draft.radiusMeters
        self.startAngleRadians = draft.startAngleRadians
        self.endAngleRadians = draft.endAngleRadians
        self.projectedCenter = layout.project(center)
        self.projectedPoints = viewportSceneProjectedArcPoints(
            center: center,
            radiusMeters: draft.radiusMeters,
            startAngleRadians: draft.startAngleRadians,
            endAngleRadians: draft.endAngleRadians,
            layout: layout,
            segmentCount: 24
        )
        self.projectedRadiusEnd = layout.project(
            CGPoint(
                x: draft.center.x + cos(draft.endAngleRadians) * draft.radiusMeters,
                y: draft.center.y + sin(draft.endAngleRadians) * draft.radiusMeters
            )
        )
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
        let draft: CanvasSketchCurveDrafts.Spline
        do {
            draft = try CanvasSketchCurveDrafts.spline(
                from: drag.start,
                to: drag.end
            )
        } catch {
            return nil
        }

        let curvePoints = viewportSceneCubicBezierSamplePoints(
            controlPoints: draft.controlPoints,
            segmentCount: 32
        )
        self.modelControlPoints = draft.controlPoints
        self.modelCurvePoints = curvePoints
        self.projectedControlPoints = draft.controlPoints.map {
            layout.project(CGPoint(x: $0.x, y: $0.y))
        }
        self.projectedCurvePoints = curvePoints.map(layout.project)
        self.modelBounds = bounds(for: curvePoints)
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
    public var viewportSize: CGSize
    public var modelBounds: CGRect
    public var renderOrigin: Point3D
    public var scale: CGFloat
    public var center: CGPoint
    public var basis: ViewportProjectionBasis
    public var maximumZoom: CGFloat

    public init?(
        scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        maximumZoom: CGFloat = ViewportCamera.maximumZoom
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
            verticalBounds: scene.verticalBounds
        )
    }

    public init(
        modelBounds: CGRect,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        maximumZoom: CGFloat = ViewportCamera.maximumZoom,
        verticalBounds: ClosedRange<Double>? = nil
    ) {
        let modelWidth = max(modelBounds.width, 1.0e-9)
        let modelHeight = max(modelBounds.height, 1.0e-9)
        let clampedCamera = camera.clamped(maximumZoom: maximumZoom)
        let projectedBounds = Self.projectedBounds(
            width: modelWidth,
            height: modelHeight,
            verticalHeight: Self.verticalHeight(verticalBounds),
            basis: basis
        )
        let usableWidth = max(size.width - 180.0, 1.0)
        let usableHeight = max(size.height - 140.0, 1.0)

        self.viewportSize = size
        self.modelBounds = modelBounds
        self.renderOrigin = Self.renderOrigin(modelBounds: modelBounds, verticalBounds: verticalBounds)
        self.scale = min(
            usableWidth / max(projectedBounds.width, 1.0e-9),
            usableHeight / max(projectedBounds.height, 1.0e-9)
        ) * clampedCamera.zoom
        self.center = CGPoint(
            x: size.width / 2.0 + clampedCamera.pan.width,
            y: size.height / 2.0 + clampedCamera.pan.height
        )
        self.basis = basis
        self.maximumZoom = max(maximumZoom, ViewportCamera.minimumZoom)
    }

    public func project(_ point: CGPoint) -> CGPoint {
        let x = CGFloat(Double(point.x) - renderOrigin.x) - modelCenterOffsetX
        let y = CGFloat(Double(point.y) - renderOrigin.z) - modelCenterOffsetZ
        return CGPoint(
            x: center.x + (basis.xDirection.dx * x + basis.zDirection.dx * y) * scale,
            y: center.y + (basis.xDirection.dy * x + basis.zDirection.dy * y) * scale
        )
    }

    public func project(_ point: Point3D) -> CGPoint {
        let x = CGFloat(point.x - renderOrigin.x) - modelCenterOffsetX
        let y = CGFloat(point.y - renderOrigin.y)
        let z = CGFloat(point.z - renderOrigin.z) - modelCenterOffsetZ
        return CGPoint(
            x: center.x
                + (basis.xDirection.dx * x + basis.yDirection.dx * y + basis.zDirection.dx * z) * scale,
            y: center.y
                + (basis.xDirection.dy * x + basis.yDirection.dy * y + basis.zDirection.dy * z) * scale
        )
    }

    public func project(_ point: CGPoint, in item: ViewportSceneItem) -> CGPoint {
        let transformedPoint = transformedPoint(
            Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)),
            in: item
        )
        return project(transformedPoint)
    }

    public func project(_ point: Point3D, in item: ViewportSceneItem) -> CGPoint {
        project(transformedPoint(point, in: item))
    }

    public func transformedPoint(_ point: Point3D, in item: ViewportSceneItem) -> Point3D {
        Self.transformedPoint(point, by: item.modelTransform)
    }

    public func projectedDepth(_ point: Point3D, in item: ViewportSceneItem) -> Double? {
        projectedDepth(transformedPoint(point, in: item))
    }

    public func projectedDepth(_ point: Point3D) -> Double? {
        guard let viewNormal = basis.viewNormal else {
            return nil
        }
        return (point.x - renderOrigin.x) * viewNormal.x
            + (point.y - renderOrigin.y) * viewNormal.y
            + (point.z - renderOrigin.z) * viewNormal.z
    }

    public func unproject(_ point: CGPoint) -> CGPoint {
        let viewportX = (point.x - center.x) / scale
        let viewportY = (point.y - center.y) / scale
        let determinant = basis.xDirection.dx * basis.zDirection.dy - basis.zDirection.dx * basis.xDirection.dy
        let modelX = (viewportX * basis.zDirection.dy - basis.zDirection.dx * viewportY) / determinant
        let modelY = (basis.xDirection.dx * viewportY - viewportX * basis.xDirection.dy) / determinant
        return CGPoint(
            x: CGFloat(renderOrigin.x) + modelCenterOffsetX + modelX,
            y: CGFloat(renderOrigin.z) + modelCenterOffsetZ + modelY
        )
    }

    public func projectedFootprint(_ itemBounds: CGRect) -> ViewportProjectedRect {
        ViewportProjectedRect(
            bottomLeft: project(CGPoint(x: itemBounds.minX, y: itemBounds.minY)),
            bottomRight: project(CGPoint(x: itemBounds.maxX, y: itemBounds.minY)),
            topRight: project(CGPoint(x: itemBounds.maxX, y: itemBounds.maxY)),
            topLeft: project(CGPoint(x: itemBounds.minX, y: itemBounds.maxY))
        )
    }

    public func projectedRect(_ itemBounds: CGRect) -> CGRect {
        projectedFootprint(itemBounds).bounds
    }

    public static func transformedPoint(
        _ point: Point3D,
        by transform: Transform3D
    ) -> Point3D {
        let values = transform.matrix.values
        guard values.count == 16 else {
            return point
        }
        let w = values[3] * point.x
            + values[7] * point.y
            + values[11] * point.z
            + values[15]
        let scale = abs(w) > 1.0e-12 ? 1.0 / w : 1.0
        return Point3D(
            x: (values[0] * point.x + values[4] * point.y + values[8] * point.z + values[12]) * scale,
            y: (values[1] * point.x + values[5] * point.y + values[9] * point.z + values[13]) * scale,
            z: (values[2] * point.x + values[6] * point.y + values[10] * point.z + values[14]) * scale
        )
    }

    public func bodyProjection(for item: ViewportSceneItem) -> ViewportBodyProjection? {
        guard case .body(let component) = item.kind else {
            return nil
        }

        let footprint = projectedFootprint(item.modelBounds)
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

    private var modelCenterOffsetX: CGFloat {
        CGFloat(Double(modelBounds.midX) - renderOrigin.x)
    }

    private var modelCenterOffsetZ: CGFloat {
        CGFloat(Double(modelBounds.midY) - renderOrigin.z)
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
        size: CGSize,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        documentGeneration: DocumentGeneration? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: document,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache
        )
        self.init(
            document: document,
            scene: scene,
            size: size,
            camera: camera,
            basis: basis
        )
    }

    public init(
        document: DesignDocument,
        scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        let modelBounds = Self.modelBounds(for: document, scene: scene)
        let identityLayout = ViewportLayout(
            modelBounds: modelBounds,
            size: size,
            camera: .identity,
            basis: basis,
            verticalBounds: scene.verticalBounds
        )
        let maximumZoom = ViewportCameraZoomPolicy.maximumZoom(
            for: document,
            identityScale: identityLayout.scale
        )
        self.layout = ViewportLayout(
            modelBounds: modelBounds,
            size: size,
            camera: camera,
            basis: basis,
            maximumZoom: maximumZoom,
            verticalBounds: scene.verticalBounds
        )
    }

    public func modelPoint(for viewportPoint: CGPoint) -> Point2D {
        let point = layout.unproject(viewportPoint)
        return Point2D(
            x: Double(point.x),
            y: Double(point.y)
        )
    }

    public func modelDrag(
        from start: CGPoint,
        to end: CGPoint,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags(),
        startWorldPoint: Point3D? = nil,
        endWorldPoint: Point3D? = nil
    ) -> ViewportModelDrag {
        ViewportModelDrag(
            start: modelPoint(for: start),
            end: modelPoint(for: end),
            sketchPlane: sketchPlane,
            modifierFlags: modifierFlags,
            startWorldPoint: startWorldPoint,
            endWorldPoint: endWorldPoint
        )
    }

    private static func emptyModelBounds(for document: DesignDocument) -> CGRect {
        let ruler = document.ruler.normalizedForWorkspaceScale()
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
        for document: DesignDocument,
        scene: ViewportScene
    ) -> CGRect {
        let baseBounds = emptyModelBounds(for: document)
        guard let sceneBounds = scene.modelBounds else {
            return baseBounds
        }
        let framedBounds = framedSceneBounds(sceneBounds, ruler: document.ruler)
        if baseBounds.intersects(sceneBounds) {
            return baseBounds.union(framedBounds)
        }
        return framedBounds
    }
}

public struct ViewportSceneContext {
    public var scene: ViewportScene
    public var mapper: ViewportModelCoordinateMapper

    public var layout: ViewportLayout {
        mapper.layout
    }

    public init(
        document: DesignDocument,
        documentGeneration: DocumentGeneration? = nil,
        size: CGSize,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: document,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache
        )
        self.scene = scene
        self.mapper = ViewportModelCoordinateMapper(
            document: document,
            scene: scene,
            size: size,
            camera: camera,
            basis: basis
        )
    }
}

public struct ViewportHit: Equatable, Sendable {
    public var featureID: FeatureID
    public var sceneNodeID: SceneNodeID?
    public var kind: ViewportSelectableKind
    public var pickingBackend: ViewportPickingBackend
    public var sketchEntityID: SketchEntityID?
    public var sketchPointHandle: SketchEntityPointHandle?
    public var sketchControlPointIndex: Int?
    public var bodyFace: ViewportBodyFace?
    public var bodyEdge: ViewportBodyEdge?
    public var bodyVertex: ViewportBodyVertex?
    public var selectionComponent: SelectionComponent?
    public var selectionReference: SelectionReference?

    public init(
        featureID: FeatureID,
        sceneNodeID: SceneNodeID? = nil,
        kind: ViewportSelectableKind,
        pickingBackend: ViewportPickingBackend = .projectedCPU,
        sketchEntityID: SketchEntityID? = nil,
        sketchPointHandle: SketchEntityPointHandle? = nil,
        sketchControlPointIndex: Int? = nil,
        bodyFace: ViewportBodyFace? = nil,
        bodyEdge: ViewportBodyEdge? = nil,
        bodyVertex: ViewportBodyVertex? = nil,
        selectionComponent: SelectionComponent? = nil,
        selectionReference: SelectionReference? = nil
    ) {
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.kind = kind
        self.pickingBackend = pickingBackend
        self.sketchEntityID = sketchEntityID
        self.sketchPointHandle = sketchPointHandle
        self.sketchControlPointIndex = sketchControlPointIndex
        self.bodyFace = bodyFace
        self.bodyEdge = bodyEdge
        self.bodyVertex = bodyVertex
        self.selectionComponent = selectionComponent
        self.selectionReference = selectionReference
    }
}

public enum ViewportSelectionIntent: Equatable, Sendable {
    case replace
    case toggle
}

public struct ViewportBodyTopologyHitTester {
    public var tolerance: CGFloat

    public init(tolerance: CGFloat = 8.0) {
        self.tolerance = tolerance
    }

    public func hitTest(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> ViewportBodyTopologyHit? {
        guard let topology = component.topology else {
            return nil
        }
        if selectionHitPolicy.allowsVertexHits,
           let vertex = hitVertex(in: topology, item: item, point: point, layout: layout) {
            return ViewportBodyTopologyHit(
                component: .vertex(vertex.componentID),
                score: vertex.score,
                depth: vertex.depth
            )
        }
        if selectionHitPolicy.allowsEdgeHits,
           let edge = hitEdge(in: topology, item: item, point: point, layout: layout) {
            return ViewportBodyTopologyHit(
                component: .edge(edge.componentID),
                score: edge.score,
                depth: edge.depth
            )
        }
        if selectionHitPolicy.allowsFaceHits,
           let face = hitFace(in: topology, item: item, point: point, layout: layout) {
            return ViewportBodyTopologyHit(
                component: .face(face.componentID),
                score: 6.0,
                depth: face.depth
            )
        }
        return nil
    }

    private func hitVertex(
        in topology: ViewportBodyTopology,
        item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat, depth: Double?)? {
        var bestVertex: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)?
        for vertex in topology.vertices {
            let distance = point.distance(to: layout.project(vertex.point, in: item))
            guard distance <= tolerance else {
                continue
            }
            let depth = layout.projectedDepth(vertex.point, in: item)
            let candidate = (componentID: vertex.componentID, score: distance, depth: depth)
            if let current = bestVertex {
                if isDistanceCandidate(candidate, betterThan: current) {
                    bestVertex = candidate
                }
            } else {
                bestVertex = candidate
            }
        }
        return bestVertex
    }

    private func hitEdge(
        in topology: ViewportBodyTopology,
        item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat, depth: Double?)? {
        var bestEdge: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)?
        for edge in topology.edges {
            let projectedStart = layout.project(edge.start, in: item)
            let projectedEnd = layout.project(edge.end, in: item)
            let distance = point.distanceToSegment(start: projectedStart, end: projectedEnd)
            guard distance <= tolerance else {
                continue
            }
            let parameter = closestSegmentParameter(
                point: point,
                start: projectedStart,
                end: projectedEnd
            )
            let depth = layout.projectedDepth(
                interpolatedPoint(from: edge.start, to: edge.end, parameter: parameter),
                in: item
            )
            let candidate = (componentID: edge.componentID, score: distance, depth: depth)
            if let current = bestEdge {
                if isDistanceCandidate(candidate, betterThan: current) {
                    bestEdge = candidate
                }
            } else {
                bestEdge = candidate
            }
        }
        return bestEdge
    }

    private func hitFace(
        in topology: ViewportBodyTopology,
        item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat, depth: Double?)? {
        var bestFace: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)?
        for face in topology.faces {
            let polygon = face.points.map { layout.project($0, in: item) }
            guard contains(point, in: polygon, tolerance: tolerance) else {
                continue
            }
            let center = polygonCenter(polygon)
            let score = min(point.distance(to: center) * 0.001, 1.0)
            let depth = faceDepth(face, item: item, point: point, layout: layout)
            let candidate = (componentID: face.componentID, score: score, depth: depth)
            if let current = bestFace {
                if isFaceCandidate(candidate, betterThan: current) {
                    bestFace = candidate
                }
            } else {
                bestFace = candidate
            }
        }
        return bestFace
    }

    private func contains(
        _ point: CGPoint,
        in polygon: [CGPoint],
        tolerance: CGFloat
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        if tolerance > 0.0,
           polygonBounds(polygon).insetBy(dx: -tolerance, dy: -tolerance).contains(point) == false {
            return false
        }

        var isInside = false
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

    private func polygonBounds(_ polygon: [CGPoint]) -> CGRect {
        var bounds = CGRect.null
        for point in polygon {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0))
        }
        return bounds
    }

    private func polygonCenter(_ polygon: [CGPoint]) -> CGPoint {
        let sum = polygon.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = max(CGFloat(polygon.count), 1.0)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private func isDistanceCandidate(
        _ candidate: (componentID: SelectionComponentID, score: CGFloat, depth: Double?),
        betterThan current: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)
    ) -> Bool {
        let scoreDelta = candidate.score - current.score
        if abs(scoreDelta) > 1.0e-6 {
            return scoreDelta < 0.0
        }
        return isNearer(candidate.depth, than: current.depth)
    }

    private func isFaceCandidate(
        _ candidate: (componentID: SelectionComponentID, score: CGFloat, depth: Double?),
        betterThan current: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)
    ) -> Bool {
        if let candidateDepth = candidate.depth,
           let currentDepth = current.depth,
           abs(candidateDepth - currentDepth) > 1.0e-9 {
            return candidateDepth > currentDepth
        }
        let scoreDelta = candidate.score - current.score
        if abs(scoreDelta) > 1.0e-6 {
            return scoreDelta < 0.0
        }
        return isNearer(candidate.depth, than: current.depth)
    }

    private func isNearer(_ candidateDepth: Double?, than currentDepth: Double?) -> Bool {
        guard let candidateDepth else {
            return false
        }
        guard let currentDepth else {
            return true
        }
        return candidateDepth > currentDepth
    }

    private func faceDepth(
        _ face: ViewportBodyTopology.Face,
        item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> Double? {
        let transformedFace = ViewportBodyTopology.Face(
            componentID: face.componentID,
            points: face.points.map { layout.transformedPoint($0, in: item) }
        )
        if let worldPoint = ViewportFaceSurfacePointResolver().worldPoint(
            for: point,
            face: transformedFace,
            layout: layout
        ) {
            return layout.projectedDepth(worldPoint)
        }
        guard !face.points.isEmpty else {
            return nil
        }
        let transformedPoints = transformedFace.points
        let sum = transformedPoints.reduce(Point3D(x: 0.0, y: 0.0, z: 0.0)) { partial, point in
            Point3D(
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        let count = Double(transformedPoints.count)
        return layout.projectedDepth(
            Point3D(x: sum.x / count, y: sum.y / count, z: sum.z / count),
        )
    }

    private func closestSegmentParameter(
        point: CGPoint,
        start: CGPoint,
        end: CGPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1.0e-12 else {
            return 0.0
        }
        let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        return Double(min(max(raw, 0.0), 1.0))
    }

    private func interpolatedPoint(
        from start: Point3D,
        to end: Point3D,
        parameter: Double
    ) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * parameter,
            y: start.y + (end.y - start.y) * parameter,
            z: start.z + (end.z - start.z) * parameter
        )
    }
}

public struct ViewportCanvasTarget: Equatable, Sendable {
    public var hit: ViewportHit?
    public var modelPoint: Point2D
    public var modelWorldPoint: Point3D?
    public var sketchPlane: SketchPlane
    public var selectionIntent: ViewportSelectionIntent
    public var modifierFlags: ViewportInputModifierFlags

    public init(
        hit: ViewportHit?,
        modelPoint: Point2D,
        modelWorldPoint: Point3D? = nil,
        sketchPlane: SketchPlane = .defaultWorkspacePlane,
        selectionIntent: ViewportSelectionIntent = .replace,
        modifierFlags: ViewportInputModifierFlags = ViewportInputModifierFlags()
    ) {
        self.hit = hit
        self.modelPoint = modelPoint
        self.modelWorldPoint = modelWorldPoint
        self.sketchPlane = sketchPlane
        self.selectionIntent = selectionIntent
        self.modifierFlags = modifierFlags
    }
}

public struct ViewportSelectionDragTarget: Equatable, Sendable {
    public var hits: [ViewportHit]
    public var selectionIntent: ViewportSelectionIntent

    public init(
        hits: [ViewportHit],
        selectionIntent: ViewportSelectionIntent = .replace
    ) {
        self.hits = hits
        self.selectionIntent = selectionIntent
    }
}

public struct ViewportBodyMoveDragTarget: Equatable, Sendable {
    public var featureID: FeatureID
    public var deltaX: Double
    public var deltaY: Double

    public init(
        featureID: FeatureID,
        deltaX: Double,
        deltaY: Double
    ) {
        self.featureID = featureID
        self.deltaX = deltaX
        self.deltaY = deltaY
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

public struct ViewportHitTester {
    public var tolerance: CGFloat

    private struct HitCandidate {
        var hit: ViewportHit
        var score: CGFloat
        var depth: Double?
    }

    public init(tolerance: CGFloat = 8.0) {
        self.tolerance = tolerance
    }

    public func hitTest(
        point: CGPoint,
        in scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> ViewportHit? {
        guard let layout = ViewportLayout(scene: scene, size: size, camera: camera, basis: basis) else {
            return nil
        }
        return hitTest(
            point: point,
            in: scene,
            layout: layout,
            selectionHitPolicy: selectionHitPolicy
        )
    }

    public func hitTest(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> ViewportHit? {
        var bestHit: HitCandidate?
        for item in scene.items {
            guard let itemHit = hitCandidate(
                for: item,
                point: point,
                layout: layout,
                selectionHitPolicy: selectionHitPolicy
            ) else {
                continue
            }
            if let current = bestHit {
                if isHitCandidate(itemHit, betterThan: current) {
                    bestHit = itemHit
                }
            } else {
                bestHit = itemHit
            }
        }
        return bestHit?.hit
    }

    private func hitCandidate(
        for item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> HitCandidate? {
        switch item.kind {
        case .sketch(let primitives):
            if (selectionHitPolicy.allowsObjectHits || selectionHitPolicy.allowsSketchEntityHits),
               let sketchHit = hitScoreForSketch(primitives, point: point, layout: layout) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        sketchEntityID: sketchHit.entityID,
                        sketchPointHandle: sketchHit.pointHandle,
                        sketchControlPointIndex: sketchHit.controlPointIndex
                    ),
                    score: sketchHit.score
                )
            }
            guard selectionHitPolicy.allowsRegionHits,
                  let regionHit = hitScoreForSketchRegion(item.sketchRegions, point: point, layout: layout) else {
                return nil
            }
            return HitCandidate(
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: item.kind.selectableKind,
                    selectionComponent: .region(regionHit.componentID)
                ),
                score: regionHit.score
            )
        case .body(let component):
            if selectionHitPolicy == .object,
               let objectHit = hitBodyObject(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return objectHit
            }
            if selectionHitPolicy.allowsVertexHits,
               let surfaceControlPointHit = hitSurfaceControlPointDisplay(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionReference: surfaceControlPointHit.reference
                    ),
                    score: surfaceControlPointHit.score,
                    depth: surfaceControlPointHit.depth
                )
            }
            if selectionHitPolicy.allowsVertexHits,
               let surfaceTrimEndpointHit = hitSurfaceTrimEndpointDisplay(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionReference: surfaceTrimEndpointHit.reference
                    ),
                    score: surfaceTrimEndpointHit.score,
                    depth: surfaceTrimEndpointHit.depth
                )
            }
            if selectionHitPolicy.allowsVertexHits,
               let surfaceTrimKnotHit = hitSurfaceTrimKnotDisplay(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionReference: surfaceTrimKnotHit.reference
                    ),
                    score: surfaceTrimKnotHit.score,
                    depth: surfaceTrimKnotHit.depth
                )
            }
            if selectionHitPolicy.allowsVertexHits,
               let surfaceTrimSpanHit = hitSurfaceTrimSpanDisplay(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionReference: surfaceTrimSpanHit.reference
                    ),
                    score: surfaceTrimSpanHit.score,
                    depth: surfaceTrimSpanHit.depth
                )
            }
            if selectionHitPolicy.allowsVertexHits,
               let surfaceKnotHit = hitSurfaceKnotDisplay(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionReference: surfaceKnotHit.reference
                    ),
                    score: surfaceKnotHit.score,
                    depth: surfaceKnotHit.depth
                )
            }
            if selectionHitPolicy.allowsVertexHits,
               let surfaceSpanHit = hitSurfaceSpanDisplay(
                   for: item,
                   component: component,
                   point: point,
                   layout: layout
               ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionReference: surfaceSpanHit.reference
                    ),
                    score: surfaceSpanHit.score,
                    depth: surfaceSpanHit.depth
                )
            }
            if let topologyHit = ViewportBodyTopologyHitTester(tolerance: tolerance).hitTest(
                item: item,
                component: component,
                point: point,
                layout: layout,
                selectionHitPolicy: selectionHitPolicy
            ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        selectionComponent: topologyHit.component
                    ),
                    score: topologyHit.score,
                    depth: topologyHit.depth
                )
            }
            if selectionHitPolicy.allowsVertexHits,
               let bodyVertex = hitBodyVertex(for: item, point: point, layout: layout) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        bodyVertex: bodyVertex.vertex
                    ),
                    score: bodyVertex.score
                )
            }
            if selectionHitPolicy.allowsEdgeHits,
               let bodyEdge = hitBodyEdge(for: item, point: point, layout: layout) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        bodyEdge: bodyEdge.edge
                    ),
                    score: bodyEdge.score
                )
            }
            if selectionHitPolicy.allowsFaceHits,
               let bodyFace = hitBodyFace(for: item, point: point, layout: layout) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: item.kind.selectableKind,
                        bodyFace: bodyFace.face
                    ),
                    score: bodyFace.score
                )
            }
            return nil
        }
    }

    private func hitSurfaceControlPointDisplay(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (reference: SelectionReference, score: CGFloat, depth: Double?)? {
        var bestHit: (reference: SelectionReference, score: CGFloat, depth: Double?)?
        let displayTolerance = max(tolerance, 10.0)
        for display in component.surfaceControlPointDisplays {
            let projectedPoint = layout.project(display.point, in: item)
            let distance = point.distance(to: projectedPoint)
            guard distance <= displayTolerance else {
                continue
            }
            let depth = layout.projectedDepth(display.point, in: item)
            let candidate = (reference: display.selectionReference, score: distance, depth: depth)
            if let current = bestHit {
                if isReferenceHitCandidate(candidate, betterThan: current) {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit
    }

    private func hitSurfaceTrimEndpointDisplay(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (reference: SelectionReference, score: CGFloat, depth: Double?)? {
        var bestHit: (reference: SelectionReference, score: CGFloat, depth: Double?)?
        let displayTolerance = max(tolerance, 10.0)
        for display in component.surfaceTrimEndpointDisplays {
            let projectedPoint = layout.project(display.point, in: item)
            let distance = point.distance(to: projectedPoint)
            guard distance <= displayTolerance else {
                continue
            }
            let depth = layout.projectedDepth(display.point, in: item)
            let candidate = (reference: display.selectionReference, score: distance, depth: depth)
            if let current = bestHit {
                if isReferenceHitCandidate(candidate, betterThan: current) {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit
    }

    private func hitSurfaceTrimKnotDisplay(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (reference: SelectionReference, score: CGFloat, depth: Double?)? {
        var bestHit: (reference: SelectionReference, score: CGFloat, depth: Double?)?
        let displayTolerance = max(tolerance, 8.0)
        for display in component.surfaceTrimKnotDisplays {
            let projectedPoint = layout.project(display.point, in: item)
            let distance = point.distance(to: projectedPoint)
            guard distance <= displayTolerance else {
                continue
            }
            let depth = layout.projectedDepth(display.point, in: item)
            let candidate = (reference: display.selectionReference, score: distance, depth: depth)
            if let current = bestHit {
                if isReferenceHitCandidate(candidate, betterThan: current) {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit
    }

    private func hitSurfaceTrimSpanDisplay(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (reference: SelectionReference, score: CGFloat, depth: Double?)? {
        var bestHit: (reference: SelectionReference, score: CGFloat, depth: Double?)?
        let displayTolerance = max(tolerance, 8.0)
        for display in component.surfaceTrimSpanDisplays {
            let projectedPoint = layout.project(display.point, in: item)
            let distance = point.distance(to: projectedPoint)
            guard distance <= displayTolerance else {
                continue
            }
            let depth = layout.projectedDepth(display.point, in: item)
            let candidate = (reference: display.selectionReference, score: distance, depth: depth)
            if let current = bestHit {
                if isReferenceHitCandidate(candidate, betterThan: current) {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit
    }

    private func hitSurfaceKnotDisplay(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (reference: SelectionReference, score: CGFloat, depth: Double?)? {
        var bestHit: (reference: SelectionReference, score: CGFloat, depth: Double?)?
        let displayTolerance = max(tolerance, 8.0)
        for display in component.surfaceKnotDisplays {
            let projectedPoint = layout.project(display.point, in: item)
            let distance = point.distance(to: projectedPoint)
            guard distance <= displayTolerance else {
                continue
            }
            let depth = layout.projectedDepth(display.point, in: item)
            let candidate = (reference: display.selectionReference, score: distance, depth: depth)
            if let current = bestHit {
                if isReferenceHitCandidate(candidate, betterThan: current) {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit
    }

    private func hitSurfaceSpanDisplay(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (reference: SelectionReference, score: CGFloat, depth: Double?)? {
        var bestHit: (reference: SelectionReference, score: CGFloat, depth: Double?)?
        let displayTolerance = max(tolerance, 8.0)
        for display in component.surfaceSpanDisplays {
            let projectedPoint = layout.project(display.point, in: item)
            let distance = point.distance(to: projectedPoint)
            guard distance <= displayTolerance else {
                continue
            }
            let depth = layout.projectedDepth(display.point, in: item)
            let candidate = (reference: display.selectionReference, score: distance, depth: depth)
            if let current = bestHit {
                if isReferenceHitCandidate(candidate, betterThan: current) {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit
    }

    private func isReferenceHitCandidate(
        _ candidate: (reference: SelectionReference, score: CGFloat, depth: Double?),
        betterThan current: (reference: SelectionReference, score: CGFloat, depth: Double?)
    ) -> Bool {
        let scoreDelta = candidate.score - current.score
        if abs(scoreDelta) > 1.0e-6 {
            return scoreDelta < 0.0
        }
        return isNearer(candidate.depth, than: current.depth)
    }

    private func isNearer(_ candidateDepth: Double?, than currentDepth: Double?) -> Bool {
        guard let candidateDepth else {
            return false
        }
        guard let currentDepth else {
            return true
        }
        return candidateDepth > currentDepth
    }

    private func hitBodyObject(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> HitCandidate? {
        if let topologyHit = ViewportBodyTopologyHitTester(tolerance: tolerance).hitTest(
            item: item,
            component: component,
            point: point,
            layout: layout,
            selectionHitPolicy: .face
        ) {
            return HitCandidate(
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: item.kind.selectableKind
                ),
                score: topologyHit.score,
                depth: topologyHit.depth
            )
        }
        if let bodyFace = hitBodyFace(for: item, point: point, layout: layout) {
            return HitCandidate(
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: item.kind.selectableKind
                ),
                score: bodyFace.score
            )
        }
        return nil
    }

    private func isHitCandidate(_ candidate: HitCandidate, betterThan current: HitCandidate) -> Bool {
        let scoreDelta = candidate.score - current.score
        if abs(scoreDelta) > 1.0e-6 {
            return scoreDelta < 0.0
        }
        guard let candidateDepth = candidate.depth else {
            return false
        }
        guard let currentDepth = current.depth else {
            return true
        }
        return candidateDepth > currentDepth
    }

    private func hitBodyVertex(
        for item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (vertex: ViewportBodyVertex, score: CGFloat)? {
        guard let projection = layout.bodyProjection(for: item) else {
            return nil
        }
        var bestVertex: (vertex: ViewportBodyVertex, score: CGFloat)?
        for vertex in ViewportBodyVertex.allCases {
            let distance = point.distance(to: projection.point(for: vertex))
            guard distance <= tolerance else {
                continue
            }
            if let current = bestVertex {
                if distance < current.score {
                    bestVertex = (vertex, distance)
                }
            } else {
                bestVertex = (vertex, distance)
            }
        }
        return bestVertex
    }

    private func hitBodyEdge(
        for item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (edge: ViewportBodyEdge, score: CGFloat)? {
        guard let projection = layout.bodyProjection(for: item) else {
            return nil
        }
        var bestEdge: (edge: ViewportBodyEdge, score: CGFloat)?
        for edge in ViewportBodyEdge.verticalCases {
            let segment = projection.segment(for: edge)
            let distance = point.distanceToSegment(start: segment.start, end: segment.end)
            guard distance <= tolerance else {
                continue
            }
            if let current = bestEdge {
                if distance < current.score {
                    bestEdge = (edge, distance)
                }
            } else {
                bestEdge = (edge, distance)
            }
        }
        return bestEdge
    }

    private func hitBodyFace(
        for item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (face: ViewportBodyFace, score: CGFloat)? {
        guard let projection = layout.bodyProjection(for: item) else {
            return nil
        }

        let faces: [(face: ViewportBodyFace, score: CGFloat)] = [
            (.front, 6.0),
            (.back, 6.1),
            (.top, 6.2),
            (.bottom, 6.3),
            (.left, 6.4),
            (.right, 6.5),
        ]
        for face in faces {
            let footprint = projection.footprint(for: face.face)
            if footprint.contains(point, tolerance: tolerance) {
                return face
            }
        }

        return nil
    }

    private func hitScoreForSketch(
        _ primitives: [ViewportSketchPrimitive],
        point: CGPoint,
        layout: ViewportLayout
    ) -> (entityID: SketchEntityID, pointHandle: SketchEntityPointHandle?, controlPointIndex: Int?, score: CGFloat)? {
        var bestHit: (
            entityID: SketchEntityID,
            pointHandle: SketchEntityPointHandle?,
            controlPointIndex: Int?,
            score: CGFloat
        )?
        for primitive in primitives {
            let distance: CGFloat?
            let pointHandle: SketchEntityPointHandle?
            let controlPointIndex: Int?
            switch primitive {
            case .point(_, let modelPoint):
                distance = point.distance(to: layout.project(modelPoint))
                pointHandle = .point
                controlPointIndex = nil
            case .line(_, let start, let end):
                let curveDistance = point.distanceToSegment(
                    start: layout.project(start),
                    end: layout.project(end)
                )
                let handles: [(handle: SketchEntityPointHandle, point: CGPoint)] = [
                    (handle: .lineStart, point: start),
                    (handle: .lineEnd, point: end),
                ]
                let handleHit = nearestSketchPointHandle(
                    handles,
                    point: point,
                    layout: layout
                )
                if let handleHit,
                   handleHit.distance <= curveDistance {
                    distance = handleHit.distance
                    pointHandle = handleHit.handle
                } else {
                    distance = curveDistance
                    pointHandle = nil
                }
                controlPointIndex = nil
            case .circle(_, let center, let radiusMeters):
                let curveDistance = distanceToProjectedCircle(
                    center: center,
                    radiusMeters: radiusMeters,
                    point: point,
                    layout: layout
                )
                let handles: [(handle: SketchEntityPointHandle, point: CGPoint)] = [
                    (handle: .circleCenter, point: center),
                ]
                let handleHit = nearestSketchPointHandle(
                    handles,
                    point: point,
                    layout: layout
                )
                if let handleHit,
                   handleHit.distance <= curveDistance {
                    distance = handleHit.distance
                    pointHandle = handleHit.handle
                } else {
                    distance = curveDistance
                    pointHandle = nil
                }
                controlPointIndex = nil
            case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
                let curveDistance = distanceToProjectedArc(
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle,
                    point: point,
                    layout: layout
                )
                let handles: [(handle: SketchEntityPointHandle, point: CGPoint)] = [
                    (handle: .arcCenter, point: center),
                    (handle: .arcStart, point: pointOnArc(center: center, radiusMeters: radiusMeters, angle: startAngle)),
                    (handle: .arcEnd, point: pointOnArc(center: center, radiusMeters: radiusMeters, angle: endAngle)),
                ]
                let handleHit = nearestSketchPointHandle(
                    handles,
                    point: point,
                    layout: layout
                )
                if let handleHit,
                   handleHit.distance <= curveDistance {
                    distance = handleHit.distance
                    pointHandle = handleHit.handle
                } else {
                    distance = curveDistance
                    pointHandle = nil
                }
                controlPointIndex = nil
            case .spline(_, let points, let controlPoints, _):
                guard let curveDistance = distanceToProjectedPolyline(
                    points: points,
                    point: point,
                    layout: layout
                ) else {
                    distance = nil
                    pointHandle = nil
                    controlPointIndex = nil
                    break
                }
                let controlPointHit = nearestProjectedControlPoint(
                    controlPoints,
                    point: point,
                    layout: layout
                )
                if let controlPointHit,
                   controlPointHit.distance <= curveDistance {
                    distance = controlPointHit.distance
                    pointHandle = nil
                    controlPointIndex = controlPointHit.index
                } else {
                    distance = curveDistance
                    pointHandle = nil
                    controlPointIndex = nil
                }
            }
            guard let distance else {
                continue
            }
            if let current = bestHit {
                if distance < current.score {
                    bestHit = (primitive.entityID, pointHandle, controlPointIndex, distance)
                }
            } else {
                bestHit = (primitive.entityID, pointHandle, controlPointIndex, distance)
            }
        }

        guard let bestHit, bestHit.score <= tolerance else {
            return nil
        }
        return bestHit
    }

    private func hitScoreForSketchRegion(
        _ regions: [ViewportSketchRegion],
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat)? {
        var bestHit: (componentID: SelectionComponentID, score: CGFloat)?
        for region in regions {
            let polygon = region.points.map(layout.project)
            guard contains(point, in: polygon) else {
                continue
            }
            let center = polygonCenter(polygon)
            let score = 12.0 + min(point.distance(to: center) * 0.001, 1.0)
            if let current = bestHit {
                if score < current.score {
                    bestHit = (region.componentID, score)
                }
            } else {
                bestHit = (region.componentID, score)
            }
        }
        return bestHit
    }

    private func contains(
        _ point: CGPoint,
        in polygon: [CGPoint]
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        var isInside = false
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
        return isInside
    }

    private func polygonCenter(_ polygon: [CGPoint]) -> CGPoint {
        let sum = polygon.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = max(CGFloat(polygon.count), 1.0)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private func pointOnArc(
        center: CGPoint,
        radiusMeters: Double,
        angle: Double
    ) -> CGPoint {
        let radius = CGFloat(max(radiusMeters, 1.0e-12))
        return CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }

    private func nearestSketchPointHandle(
        _ handles: [(handle: SketchEntityPointHandle, point: CGPoint)],
        point: CGPoint,
        layout: ViewportLayout
    ) -> (handle: SketchEntityPointHandle, distance: CGFloat)? {
        var bestHit: (handle: SketchEntityPointHandle, distance: CGFloat)?
        for handle in handles {
            let distance = point.distance(to: layout.project(handle.point))
            guard distance <= tolerance else {
                continue
            }
            if let current = bestHit {
                if distance < current.distance {
                    bestHit = (handle.handle, distance)
                }
            } else {
                bestHit = (handle.handle, distance)
            }
        }
        return bestHit
    }

    private func nearestProjectedControlPoint(
        _ controlPoints: [CGPoint],
        point: CGPoint,
        layout: ViewportLayout
    ) -> (index: Int, distance: CGFloat)? {
        var bestHit: (index: Int, distance: CGFloat)?
        for (index, controlPoint) in controlPoints.enumerated() {
            let distance = point.distance(to: layout.project(controlPoint))
            guard distance <= tolerance else {
                continue
            }
            if let current = bestHit {
                if distance < current.distance {
                    bestHit = (index, distance)
                }
            } else {
                bestHit = (index, distance)
            }
        }
        return bestHit
    }

    private func distanceToProjectedCircle(
        center: CGPoint,
        radiusMeters: Double,
        point: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var previousPoint: CGPoint?

        for index in 0 ... 64 {
            let angle = CGFloat(index) / 64.0 * CGFloat.pi * 2.0
            let modelPoint = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let projectedPoint = layout.project(modelPoint)
            if let previousPoint {
                bestDistance = min(
                    bestDistance,
                    point.distanceToSegment(
                        start: previousPoint,
                        end: projectedPoint
                    )
                )
            }
            previousPoint = projectedPoint
        }

        return bestDistance
    }

    private func distanceToProjectedArc(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        point: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var previousPoint: CGPoint?
        for projectedPoint in viewportSceneProjectedArcPoints(
            center: center,
            radiusMeters: radiusMeters,
            startAngleRadians: startAngleRadians,
            endAngleRadians: endAngleRadians,
            layout: layout,
            segmentCount: 64
        ) {
            if let previousPoint {
                bestDistance = min(
                    bestDistance,
                    point.distanceToSegment(
                        start: previousPoint,
                        end: projectedPoint
                    )
                )
            }
            previousPoint = projectedPoint
        }
        return bestDistance
    }

    private func distanceToProjectedPolyline(
        points: [CGPoint],
        point: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat? {
        guard points.count >= 2 else {
            return nil
        }
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var previousPoint: CGPoint?
        for modelPoint in points {
            let projectedPoint = layout.project(modelPoint)
            if let previousPoint {
                bestDistance = min(
                    bestDistance,
                    point.distanceToSegment(
                        start: previousPoint,
                        end: projectedPoint
                    )
                )
            }
            previousPoint = projectedPoint
        }
        return bestDistance
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
