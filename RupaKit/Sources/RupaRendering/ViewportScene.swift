import CoreGraphics
import RupaCore

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

    public init(
        typeID: ObjectTypeID? = nil,
        properties: ObjectPropertySet = ObjectPropertySet(),
        sizeXMeters: Double,
        sizeYMeters: Double,
        sizeZMeters: Double,
        yMinMeters: Double,
        yMaxMeters: Double,
        cylinder: ViewportCylinderComponent? = nil,
        mesh: ViewportBodyMesh? = nil,
        topology: ViewportBodyTopology? = nil
    ) {
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
    }
}

public struct ViewportBodyMesh: Equatable {
    public var positions: [Point3D]
    public var indices: [UInt32]

    public init(positions: [Point3D], indices: [UInt32]) {
        self.positions = positions
        self.indices = indices
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

private extension ViewportBodyTopology {
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
    public var sourceFeatureID: FeatureID?
    public var modelBounds: CGRect
    public var kind: ViewportSceneItemKind
    public var sketchRegions: [ViewportSketchRegion]

    public init(
        id: String,
        featureID: FeatureID,
        sourceFeatureID: FeatureID? = nil,
        modelBounds: CGRect,
        kind: ViewportSceneItemKind,
        sketchRegions: [ViewportSketchRegion] = []
    ) {
        self.id = id
        self.featureID = featureID
        self.sourceFeatureID = sourceFeatureID
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
        let boundsPoints = arcBoundsPoints(
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
        self.projectedPoints = projectedArcPoints(
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

        let curvePoints = cubicBezierSamplePoints(
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
    public var scale: CGFloat
    public var center: CGPoint
    public var basis: ViewportProjectionBasis

    public init?(
        scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        guard let modelBounds = scene.modelBounds else {
            return nil
        }
        self.init(modelBounds: modelBounds, size: size, camera: camera, basis: basis)
    }

    public init(
        modelBounds: CGRect,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        let modelWidth = max(modelBounds.width, 1.0e-9)
        let modelHeight = max(modelBounds.height, 1.0e-9)
        let clampedCamera = camera.clamped()
        let projectedBounds = Self.projectedBounds(
            width: modelWidth,
            height: modelHeight,
            basis: basis
        )
        let usableWidth = max(size.width - 180.0, 1.0)
        let usableHeight = max(size.height - 140.0, 1.0)

        self.viewportSize = size
        self.modelBounds = modelBounds
        self.scale = min(
            usableWidth / max(projectedBounds.width, 1.0e-9),
            usableHeight / max(projectedBounds.height, 1.0e-9)
        ) * clampedCamera.zoom
        self.center = CGPoint(
            x: size.width / 2.0 + clampedCamera.pan.width,
            y: size.height / 2.0 + clampedCamera.pan.height
        )
        self.basis = basis
    }

    public func project(_ point: CGPoint) -> CGPoint {
        let x = point.x - modelBounds.midX
        let y = point.y - modelBounds.midY
        return CGPoint(
            x: center.x + (basis.xDirection.dx * x + basis.zDirection.dx * y) * scale,
            y: center.y + (basis.xDirection.dy * x + basis.zDirection.dy * y) * scale
        )
    }

    public func project(_ point: Point3D) -> CGPoint {
        let x = CGFloat(point.x) - modelBounds.midX
        let y = CGFloat(point.y)
        let z = CGFloat(point.z) - modelBounds.midY
        return CGPoint(
            x: center.x
                + (basis.xDirection.dx * x + basis.yDirection.dx * y + basis.zDirection.dx * z) * scale,
            y: center.y
                + (basis.xDirection.dy * x + basis.yDirection.dy * y + basis.zDirection.dy * z) * scale
        )
    }

    public func unproject(_ point: CGPoint) -> CGPoint {
        let viewportX = (point.x - center.x) / scale
        let viewportY = (point.y - center.y) / scale
        let determinant = basis.xDirection.dx * basis.zDirection.dy - basis.zDirection.dx * basis.xDirection.dy
        let modelX = (viewportX * basis.zDirection.dy - basis.zDirection.dx * viewportY) / determinant
        let modelY = (basis.xDirection.dx * viewportY - viewportX * basis.xDirection.dy) / determinant
        return CGPoint(
            x: modelBounds.midX + modelX,
            y: modelBounds.midY + modelY
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
        basis: ViewportProjectionBasis
    ) -> CGRect {
        let points = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: basis.xDirection.dx * width, y: basis.xDirection.dy * width),
            CGPoint(x: basis.zDirection.dx * height, y: basis.zDirection.dy * height),
            CGPoint(
                x: basis.xDirection.dx * width + basis.zDirection.dx * height,
                y: basis.xDirection.dy * width + basis.zDirection.dy * height
            ),
        ]
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
}

public struct ViewportModelCoordinateMapper {
    public var layout: ViewportLayout

    public init(
        document: DesignDocument,
        size: CGSize,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let modelBounds = Self.modelBounds(for: document, scene: scene)
        self.layout = ViewportLayout(
            modelBounds: modelBounds,
            size: size,
            camera: camera,
            basis: basis
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
        let span = max(
            document.ruler.visibleSpanMeters,
            document.ruler.majorTickMeters * 20.0,
            document.ruler.minorTickMeters * 40.0
        )
        let size = CGFloat(span)
        return CGRect(
            x: -size / 2.0,
            y: -size / 2.0,
            width: size,
            height: size
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
        return baseBounds.union(sceneBounds)
    }
}

public struct ViewportHit: Equatable, Sendable {
    public var featureID: FeatureID
    public var kind: ViewportSelectableKind
    public var pickingBackend: ViewportPickingBackend
    public var sketchEntityID: SketchEntityID?
    public var sketchPointHandle: SketchEntityPointHandle?
    public var sketchControlPointIndex: Int?
    public var bodyFace: ViewportBodyFace?
    public var bodyEdge: ViewportBodyEdge?
    public var bodyVertex: ViewportBodyVertex?
    public var selectionComponent: SelectionComponent?

    public init(
        featureID: FeatureID,
        kind: ViewportSelectableKind,
        pickingBackend: ViewportPickingBackend = .projectedCPU,
        sketchEntityID: SketchEntityID? = nil,
        sketchPointHandle: SketchEntityPointHandle? = nil,
        sketchControlPointIndex: Int? = nil,
        bodyFace: ViewportBodyFace? = nil,
        bodyEdge: ViewportBodyEdge? = nil,
        bodyVertex: ViewportBodyVertex? = nil,
        selectionComponent: SelectionComponent? = nil
    ) {
        self.featureID = featureID
        self.kind = kind
        self.pickingBackend = pickingBackend
        self.sketchEntityID = sketchEntityID
        self.sketchPointHandle = sketchPointHandle
        self.sketchControlPointIndex = sketchControlPointIndex
        self.bodyFace = bodyFace
        self.bodyEdge = bodyEdge
        self.bodyVertex = bodyVertex
        self.selectionComponent = selectionComponent
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
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> ViewportBodyTopologyHit? {
        guard let topology = component.topology else {
            return nil
        }
        if selectionHitPolicy.allowsVertexHits,
           let vertex = hitVertex(in: topology, point: point, layout: layout) {
            return ViewportBodyTopologyHit(
                component: .vertex(vertex.componentID),
                score: vertex.score,
                depth: vertex.depth
            )
        }
        if selectionHitPolicy.allowsEdgeHits,
           let edge = hitEdge(in: topology, point: point, layout: layout) {
            return ViewportBodyTopologyHit(
                component: .edge(edge.componentID),
                score: edge.score,
                depth: edge.depth
            )
        }
        if selectionHitPolicy.allowsFaceHits,
           let face = hitFace(in: topology, point: point, layout: layout) {
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
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat, depth: Double?)? {
        var bestVertex: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)?
        for vertex in topology.vertices {
            let distance = point.distance(to: layout.project(vertex.point))
            guard distance <= tolerance else {
                continue
            }
            let depth = projectedDepth(vertex.point, layout: layout)
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
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat, depth: Double?)? {
        var bestEdge: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)?
        for edge in topology.edges {
            let projectedStart = layout.project(edge.start)
            let projectedEnd = layout.project(edge.end)
            let distance = point.distanceToSegment(start: projectedStart, end: projectedEnd)
            guard distance <= tolerance else {
                continue
            }
            let parameter = closestSegmentParameter(
                point: point,
                start: projectedStart,
                end: projectedEnd
            )
            let depth = projectedDepth(
                interpolatedPoint(from: edge.start, to: edge.end, parameter: parameter),
                layout: layout
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
        point: CGPoint,
        layout: ViewportLayout
    ) -> (componentID: SelectionComponentID, score: CGFloat, depth: Double?)? {
        var bestFace: (componentID: SelectionComponentID, score: CGFloat, depth: Double?)?
        for face in topology.faces {
            let polygon = face.points.map { layout.project($0) }
            guard contains(point, in: polygon, tolerance: tolerance) else {
                continue
            }
            let center = polygonCenter(polygon)
            let score = min(point.distance(to: center) * 0.001, 1.0)
            let depth = faceDepth(face, point: point, layout: layout)
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
        point: CGPoint,
        layout: ViewportLayout
    ) -> Double? {
        if let worldPoint = ViewportFaceSurfacePointResolver().worldPoint(
            for: point,
            face: face,
            layout: layout
        ) {
            return projectedDepth(worldPoint, layout: layout)
        }
        guard !face.points.isEmpty else {
            return nil
        }
        let sum = face.points.reduce(Point3D(x: 0.0, y: 0.0, z: 0.0)) { partial, point in
            Point3D(
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        let count = Double(face.points.count)
        return projectedDepth(
            Point3D(x: sum.x / count, y: sum.y / count, z: sum.z / count),
            layout: layout
        )
    }

    private func projectedDepth(_ point: Point3D, layout: ViewportLayout) -> Double? {
        guard let viewNormal = layout.basis.viewNormal else {
            return nil
        }
        return point.x * viewNormal.x + point.y * viewNormal.y + point.z * viewNormal.z
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
            if let topologyHit = ViewportBodyTopologyHitTester(tolerance: tolerance).hitTest(
                component: component,
                point: point,
                layout: layout,
                selectionHitPolicy: selectionHitPolicy
            ) {
                return HitCandidate(
                    hit: ViewportHit(
                        featureID: item.featureID,
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
                    hit: ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind, bodyVertex: bodyVertex.vertex),
                    score: bodyVertex.score
                )
            }
            if selectionHitPolicy.allowsEdgeHits,
               let bodyEdge = hitBodyEdge(for: item, point: point, layout: layout) {
                return HitCandidate(
                    hit: ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind, bodyEdge: bodyEdge.edge),
                    score: bodyEdge.score
                )
            }
            if selectionHitPolicy.allowsFaceHits,
               let bodyFace = hitBodyFace(for: item, point: point, layout: layout) {
                return HitCandidate(
                    hit: ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind, bodyFace: bodyFace.face),
                    score: bodyFace.score
                )
            }
            return nil
        }
    }

    private func hitBodyObject(
        for item: ViewportSceneItem,
        component: ViewportBodyComponent,
        point: CGPoint,
        layout: ViewportLayout
    ) -> HitCandidate? {
        if let topologyHit = ViewportBodyTopologyHitTester(tolerance: tolerance).hitTest(
            component: component,
            point: point,
            layout: layout,
            selectionHitPolicy: .face
        ) {
            return HitCandidate(
                hit: ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind),
                score: topologyHit.score,
                depth: topologyHit.depth
            )
        }
        if let bodyFace = hitBodyFace(for: item, point: point, layout: layout) {
            return HitCandidate(
                hit: ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind),
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
        for projectedPoint in projectedArcPoints(
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

public struct ViewportSceneBuilder {
    private let objectRegistry: ObjectTypeRegistry

    public init(objectRegistry: ObjectTypeRegistry = .builtIn) {
        self.objectRegistry = objectRegistry
    }

    public func build(document: DesignDocument) -> ViewportScene {
        let graph = document.cadDocument.designGraph
        let designDisplaySnapshot = DesignDisplaySnapshotService().snapshot(document: document)
        let bodyDisplaySnapshots: [FeatureID: BodyDisplaySnapshot]
        do {
            bodyDisplaySnapshots = try BodyDisplaySnapshotService().snapshots(
                document: document,
                objectRegistry: objectRegistry
            )
        } catch {
            bodyDisplaySnapshots = [:]
        }

        let items = graph.order.compactMap { featureID -> ViewportSceneItem? in
            guard let feature = graph.nodes[featureID] else {
                return nil
            }

            switch feature.operation {
            case .sketch:
                guard let sketchSnapshot = designDisplaySnapshot.sketches[featureID] else {
                    return nil
                }
                let bounds = viewportBounds(sketchSnapshot.bounds)
                return ViewportSceneItem(
                    id: featureID.description,
                    featureID: featureID,
                    modelBounds: bounds,
                    kind: .sketch(
                        primitives: viewportSketchPrimitives(sketchSnapshot.primitives)
                    ),
                    sketchRegions: viewportSketchRegions(sketchSnapshot.regions)
                )
            case .extrude:
                guard let extrudeSnapshot = designDisplaySnapshot.extrudes[featureID],
                      let sketchSnapshot = designDisplaySnapshot.sketches[extrudeSnapshot.profileFeatureID] else {
                    return nil
                }
                let bounds = viewportBounds(sketchSnapshot.bounds)
                let object = objectDescriptor(
                    featureID: featureID,
                    kind: .body,
                    document: document
                )
                let component = bodyComponent(
                    sketchSnapshot: sketchSnapshot,
                    bounds: bounds,
                    depthMeters: extrudeSnapshot.depthMeters,
                    direction: extrudeSnapshot.direction,
                    declaredObjectTypeID: object?.typeID,
                    declaredProperties: object?.properties ?? ObjectPropertySet()
                )
                return ViewportSceneItem(
                    id: featureID.description,
                    featureID: featureID,
                    sourceFeatureID: extrudeSnapshot.profileFeatureID,
                    modelBounds: bounds,
                    kind: .body(component: component)
                )
            case .revolve(let revolve):
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: revolve.profile.featureID,
                    document: document,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .sweep(let sweep):
                guard let profile = sweep.profiles.first else {
                    return nil
                }
                if let sweepSnapshot = designDisplaySnapshot.straightPrismSweeps[featureID],
                   let sketchSnapshot = designDisplaySnapshot.sketches[sweepSnapshot.profileFeatureID] {
                    let bounds = viewportBounds(sketchSnapshot.bounds)
                    let object = objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )
                    let component = bodyComponent(
                        sketchSnapshot: sketchSnapshot,
                        bounds: bounds,
                        depthMeters: sweepSnapshot.depthMeters,
                        direction: sweepSnapshot.direction,
                        declaredObjectTypeID: object?.typeID,
                        declaredProperties: object?.properties ?? ObjectPropertySet()
                    )
                    return ViewportSceneItem(
                        id: featureID.description,
                        featureID: featureID,
                        sourceFeatureID: sweepSnapshot.profileFeatureID,
                        modelBounds: bounds,
                        kind: .body(component: component)
                    )
                }

                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: profile.featureID,
                    document: document,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .polySpline:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: nil,
                    document: document,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .faceLoopOffset:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )?.sourceProfileFeatureID,
                    document: document,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .edgeOffset:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )?.sourceProfileFeatureID,
                    document: document,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .faceKnife:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )?.sourceProfileFeatureID,
                    document: document,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .bridgeCurve:
                return nil
            case .curveEdit:
                return nil
            case .curveOffset:
                return nil
            case .curveTrim:
                return nil
            }
        }
        return ViewportScene(items: items)
    }

    private func evaluatedMeshBodyItem(
        featureID: FeatureID,
        sourceFeatureID: FeatureID?,
        document: DesignDocument,
        bodyDisplaySnapshots: [FeatureID: BodyDisplaySnapshot]
    ) -> ViewportSceneItem? {
        guard let snapshot = bodyDisplaySnapshots[featureID] else {
            return nil
        }
        let object = objectDescriptor(
            featureID: featureID,
            kind: .body,
            document: document
        )
        let resolvedTypeID = object?.typeID ?? .cube
        let properties = resolvedProperties(
            typeID: resolvedTypeID,
            declaredProperties: object?.properties ?? ObjectPropertySet()
        )
        let component = ViewportBodyComponent(
            typeID: resolvedTypeID,
            properties: properties,
            sizeXMeters: max(snapshot.bounds.maxX - snapshot.bounds.minX, 1.0e-9),
            sizeYMeters: max(snapshot.bounds.maxY - snapshot.bounds.minY, 1.0e-9),
            sizeZMeters: max(snapshot.bounds.maxZ - snapshot.bounds.minZ, 1.0e-9),
            yMinMeters: snapshot.bounds.minY,
            yMaxMeters: snapshot.bounds.maxY,
            mesh: ViewportBodyMesh(
                positions: snapshot.mesh.positions,
                indices: snapshot.mesh.indices
            ),
            topology: ViewportBodyTopology(snapshot.topology)
        )
        return ViewportSceneItem(
            id: featureID.description,
            featureID: featureID,
            sourceFeatureID: sourceFeatureID,
            modelBounds: CGRect(
                x: snapshot.bounds.minX,
                y: snapshot.bounds.minZ,
                width: max(snapshot.bounds.maxX - snapshot.bounds.minX, 1.0e-9),
                height: max(snapshot.bounds.maxZ - snapshot.bounds.minZ, 1.0e-9)
            ),
            kind: .body(component: component)
        )
    }

    private func bodyComponent(
        sketchSnapshot: SketchDisplaySnapshot,
        bounds: CGRect,
        depthMeters: Double,
        direction: ExtrudeDirection,
        declaredObjectTypeID: ObjectTypeID?,
        declaredProperties: ObjectPropertySet
    ) -> ViewportBodyComponent {
        let sizeY = abs(depthMeters)
        let yExtents = bodyYExtents(depthMeters: depthMeters, direction: direction)
        let rawCylinder = sketchSnapshot.singleCircleProfileRadiusMeters.map { radius in
            ViewportCylinderComponent(
                topRadiusMeters: radius,
                bottomRadiusMeters: radius
            )
        }
        let resolvedTypeID = declaredObjectTypeID ?? (rawCylinder == nil ? .cube : .cylinder)
        let properties = resolvedProperties(
            typeID: resolvedTypeID,
            declaredProperties: declaredProperties
        )
        let cylinder = rawCylinder.map {
            cylinderComponent($0, properties: properties)
        }
        if let cylinder {
            return ViewportBodyComponent(
                typeID: resolvedTypeID,
                properties: properties,
                sizeXMeters: Double(bounds.width),
                sizeYMeters: sizeY,
                sizeZMeters: Double(bounds.height),
                yMinMeters: yExtents.min,
                yMaxMeters: yExtents.max,
                cylinder: cylinder
            )
        }
        return ViewportBodyComponent(
            typeID: resolvedTypeID,
            properties: properties,
            sizeXMeters: Double(bounds.width),
            sizeYMeters: sizeY,
            sizeZMeters: Double(bounds.height),
            yMinMeters: yExtents.min,
            yMaxMeters: yExtents.max
        )
    }

    private func resolvedProperties(
        typeID: ObjectTypeID?,
        declaredProperties: ObjectPropertySet
    ) -> ObjectPropertySet {
        guard let definition = objectRegistry.definition(for: typeID) else {
            return declaredProperties
        }
        var values = definition.defaultProperties.values
        for (propertyID, value) in declaredProperties.values {
            values[propertyID] = value
        }
        return ObjectPropertySet(values: values)
    }

    private func objectDescriptor(
        featureID: FeatureID,
        kind: SceneNodeReference.Kind,
        document: DesignDocument
    ) -> ObjectDescriptor? {
        document.productMetadata.sceneNodes.values.first { node in
            node.reference?.kind == kind && node.reference?.featureID == featureID
        }?.object
    }

    private func viewportBounds(_ bounds: SketchDisplaySnapshot.Bounds) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 0.001),
            height: max(bounds.height, 0.001)
        )
    }

    private func viewportSketchPrimitives(
        _ primitives: [SketchDisplaySnapshot.Primitive]
    ) -> [ViewportSketchPrimitive] {
        primitives.map { primitive in
            switch primitive {
            case .point(let entityID, let point):
                return .point(entityID: entityID, point: viewportPoint(point))
            case .line(let entityID, let start, let end):
                return .line(
                    entityID: entityID,
                    start: viewportPoint(start),
                    end: viewportPoint(end)
                )
            case .circle(let entityID, let center, let radiusMeters):
                return .circle(
                    entityID: entityID,
                    center: viewportPoint(center),
                    radiusMeters: radiusMeters
                )
            case .arc(let entityID, let center, let radiusMeters, let startAngleRadians, let endAngleRadians):
                return .arc(
                    entityID: entityID,
                    center: viewportPoint(center),
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngleRadians,
                    endAngleRadians: endAngleRadians
                )
            case .spline(let entityID, let points, let controlPoints, let sketchPlane):
                return .spline(
                    entityID: entityID,
                    points: points.map(viewportPoint),
                    controlPoints: controlPoints.map(viewportPoint),
                    sketchPlane: sketchPlane
                )
            }
        }
    }

    private func viewportSketchRegions(
        _ regions: [SketchDisplaySnapshot.Region]
    ) -> [ViewportSketchRegion] {
        regions.map { region in
            ViewportSketchRegion(
                componentID: region.componentID,
                points: region.points.map(viewportPoint)
            )
        }
    }

    private func viewportPoint(_ point: Point2D) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    private func bodyYExtents(
        depthMeters: Double,
        direction: ExtrudeDirection
    ) -> (min: Double, max: Double) {
        let size = abs(depthMeters)
        switch direction {
        case .symmetric:
            return (-size / 2.0, size / 2.0)
        case .normal, .vector(_):
            if depthMeters >= 0.0 {
                return (0.0, size)
            }
            return (-size, 0.0)
        }
    }

    private func cylinderComponent(
        _ component: ViewportCylinderComponent,
        properties: ObjectPropertySet
    ) -> ViewportCylinderComponent {
        let radius = lengthProperty("radius", properties: properties) ?? component.topRadiusMeters
        return ViewportCylinderComponent(
            topRadiusMeters: max(radius, 1.0e-9),
            bottomRadiusMeters: max(radius, 1.0e-9),
            sideSegments: max(integerProperty("sides.x", properties: properties) ?? component.sideSegments, 3),
            verticalSegments: max(integerProperty("sides.y", properties: properties) ?? component.verticalSegments, 1),
            angleDegrees: angleProperty("angle", properties: properties) ?? component.angleDegrees,
            hasCaps: booleanProperty("caps", properties: properties) ?? component.hasCaps,
            hollowMeters: max(lengthProperty("hollow", properties: properties) ?? component.hollowMeters, 0.0),
            cornerRadiusMeters: max(lengthProperty("corner.radius", properties: properties) ?? component.cornerRadiusMeters, 0.0),
            cornerSideSegments: max(integerProperty("corner.sides", properties: properties) ?? component.cornerSideSegments, 1)
        )
    }

    private func lengthProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Double? {
        guard case .length(let meters) = properties[id] else {
            return nil
        }
        return meters.isFinite ? meters : nil
    }

    private func integerProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Int? {
        guard case .integer(let value) = properties[id] else {
            return nil
        }
        return value
    }

    private func angleProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Double? {
        guard case .angle(let value) = properties[id] else {
            return nil
        }
        return value.isFinite ? value : nil
    }

    private func booleanProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Bool? {
        guard case .boolean(let value) = properties[id] else {
            return nil
        }
        return value
    }

}

private func projectedArcPoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double,
    layout: ViewportLayout,
    segmentCount: Int
) -> [CGPoint] {
    arcSamplePoints(
        center: center,
        radiusMeters: radiusMeters,
        startAngleRadians: startAngleRadians,
        endAngleRadians: endAngleRadians,
        segmentCount: segmentCount
    ).map { layout.project($0) }
}

private func arcSamplePoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double,
    segmentCount: Int
) -> [CGPoint] {
    let radius = max(CGFloat(radiusMeters), 1.0e-12)
    let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
    let count = max(segmentCount, 2)
    return (0 ... count).map { index in
        let ratio = Double(index) / Double(count)
        let angle = startAngleRadians + span * ratio
        return CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }
}

private func arcBoundsPoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double
) -> [CGPoint] {
    let radius = max(CGFloat(radiusMeters), 1.0e-12)
    let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
    let angles = arcBoundsAngles(startAngle: startAngleRadians, span: span)
    return angles.map { angle in
        CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }
}

private func arcBoundsAngles(startAngle: Double, span: Double) -> [Double] {
    let fullCircle = Double.pi * 2.0
    let tolerance = 1.0e-12
    var angles = [startAngle, startAngle + span]
    for baseAngle in [0.0, Double.pi / 2.0, Double.pi, Double.pi * 1.5, fullCircle] {
        var angle = baseAngle
        while angle < startAngle - tolerance {
            angle += fullCircle
        }
        if angle <= startAngle + span + tolerance {
            angles.append(angle)
        }
    }
    return angles
}

private func normalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
    let fullCircle = Double.pi * 2.0
    let tolerance = 1.0e-12
    var span = endAngle - startAngle
    while span <= tolerance {
        span += fullCircle
    }
    while span > fullCircle + tolerance {
        span -= fullCircle
    }
    return min(span, fullCircle)
}

private func cubicBezierSamplePoints(
    controlPoints: [Point2D],
    segmentCount: Int
) -> [CGPoint] {
    guard controlPoints.count == 4 else {
        return []
    }
    let count = max(segmentCount, 2)
    return (0 ... count).map { index in
        let t = Double(index) / Double(count)
        let inverse = 1.0 - t
        let first = inverse * inverse * inverse
        let second = 3.0 * inverse * inverse * t
        let third = 3.0 * inverse * t * t
        let fourth = t * t * t
        return CGPoint(
            x: CGFloat(controlPoints[0].x * first
                + controlPoints[1].x * second
                + controlPoints[2].x * third
                + controlPoints[3].x * fourth),
            y: CGFloat(controlPoints[0].y * first
                + controlPoints[1].y * second
                + controlPoints[2].y * third
                + controlPoints[3].y * fourth)
        )
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
