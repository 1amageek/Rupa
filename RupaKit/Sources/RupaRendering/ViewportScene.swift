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

public enum ViewportSketchPrimitive: Equatable {
    case point(CGPoint)
    case line(start: CGPoint, end: CGPoint)
    case circle(center: CGPoint, radiusMeters: Double)
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

    public init(
        typeID: ObjectTypeID? = nil,
        properties: ObjectPropertySet = ObjectPropertySet(),
        sizeXMeters: Double,
        sizeYMeters: Double,
        sizeZMeters: Double,
        yMinMeters: Double,
        yMaxMeters: Double,
        cylinder: ViewportCylinderComponent? = nil
    ) {
        self.typeID = typeID
        self.properties = properties
        self.sizeXMeters = sizeXMeters
        self.sizeYMeters = sizeYMeters
        self.sizeZMeters = sizeZMeters
        self.yMinMeters = yMinMeters
        self.yMaxMeters = yMaxMeters
        self.cylinder = cylinder
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

    public init(
        id: String,
        featureID: FeatureID,
        sourceFeatureID: FeatureID? = nil,
        modelBounds: CGRect,
        kind: ViewportSceneItemKind
    ) {
        self.id = id
        self.featureID = featureID
        self.sourceFeatureID = sourceFeatureID
        self.modelBounds = modelBounds
        self.kind = kind
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

    public init(
        start: Point2D,
        end: Point2D,
        sketchPlane: SketchPlane = .xy
    ) {
        self.start = start
        self.end = end
        self.sketchPlane = sketchPlane
    }
}

public struct ViewportCanvasDragPlaceholder: Equatable {
    public var modelBounds: CGRect
    public var footprint: ViewportProjectedRect

    public init?(
        drag: ViewportModelDrag,
        layout: ViewportLayout
    ) {
        self.init(
            start: drag.start,
            end: drag.end,
            layout: layout
        )
    }

    public init?(
        start: Point2D,
        end: Point2D,
        layout: ViewportLayout
    ) {
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite else {
            return nil
        }

        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
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
        sketchPlane: SketchPlane = .xy
    ) -> ViewportModelDrag {
        ViewportModelDrag(
            start: modelPoint(for: start),
            end: modelPoint(for: end),
            sketchPlane: sketchPlane
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
    public var bodyFace: ViewportBodyFace?

    public init(
        featureID: FeatureID,
        kind: ViewportSelectableKind,
        bodyFace: ViewportBodyFace? = nil
    ) {
        self.featureID = featureID
        self.kind = kind
        self.bodyFace = bodyFace
    }
}

public enum ViewportSelectionIntent: Equatable, Sendable {
    case replace
    case toggle
}

public struct ViewportCanvasTarget: Equatable, Sendable {
    public var hit: ViewportHit?
    public var modelPoint: Point2D
    public var sketchPlane: SketchPlane
    public var selectionIntent: ViewportSelectionIntent

    public init(
        hit: ViewportHit?,
        modelPoint: Point2D,
        sketchPlane: SketchPlane = .xy,
        selectionIntent: ViewportSelectionIntent = .replace
    ) {
        self.hit = hit
        self.modelPoint = modelPoint
        self.sketchPlane = sketchPlane
        self.selectionIntent = selectionIntent
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

public struct ViewportHitTester {
    public var tolerance: CGFloat

    public init(tolerance: CGFloat = 8.0) {
        self.tolerance = tolerance
    }

    public func hitTest(
        point: CGPoint,
        in scene: ViewportScene,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) -> ViewportHit? {
        guard let layout = ViewportLayout(scene: scene, size: size, camera: camera, basis: basis) else {
            return nil
        }
        return hitTest(point: point, in: scene, layout: layout)
    }

    public func hitTest(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportHit? {
        var bestHit: (hit: ViewportHit, score: CGFloat)?
        for item in scene.items {
            guard let itemHit = hitCandidate(for: item, point: point, layout: layout) else {
                continue
            }
            if let current = bestHit {
                if itemHit.score < current.score {
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
        layout: ViewportLayout
    ) -> (hit: ViewportHit, score: CGFloat)? {
        switch item.kind {
        case .sketch(let primitives):
            guard let score = hitScoreForSketch(primitives, point: point, layout: layout) else {
                return nil
            }
            return (
                ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind),
                score
            )
        case .body:
            guard let bodyFace = hitBodyFace(for: item, point: point, layout: layout) else {
                return nil
            }
            return (
                ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind, bodyFace: bodyFace.face),
                bodyFace.score
            )
        }
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
    ) -> CGFloat? {
        var bestDistance: CGFloat?
        for primitive in primitives {
            let distance: CGFloat?
            switch primitive {
            case .point(let modelPoint):
                distance = point.distance(to: layout.project(modelPoint))
            case .line(let start, let end):
                distance = point.distanceToSegment(
                    start: layout.project(start),
                    end: layout.project(end)
                )
            case .circle(let center, let radiusMeters):
                distance = distanceToProjectedCircle(
                    center: center,
                    radiusMeters: radiusMeters,
                    point: point,
                    layout: layout
                )
            }
            guard let distance else {
                continue
            }
            if let current = bestDistance {
                bestDistance = min(current, distance)
            } else {
                bestDistance = distance
            }
        }

        guard let bestDistance, bestDistance <= tolerance else {
            return nil
        }
        return bestDistance
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
}

public struct ViewportSceneBuilder {
    private let objectRegistry: ObjectTypeRegistry

    public init(objectRegistry: ObjectTypeRegistry = .builtIn) {
        self.objectRegistry = objectRegistry
    }

    public func build(document: DesignDocument) -> ViewportScene {
        let graph = document.cadDocument.designGraph
        let items = graph.order.compactMap { featureID -> ViewportSceneItem? in
            guard let feature = graph.nodes[featureID] else {
                return nil
            }

            switch feature.operation {
            case .sketch(let sketch):
                guard let bounds = sketchBounds(
                    sketch,
                    parameters: document.cadDocument.parameters
                ) else {
                    return nil
                }
                return ViewportSceneItem(
                    id: featureID.description,
                    featureID: featureID,
                    modelBounds: bounds,
                    kind: .sketch(
                        primitives: sketchPrimitives(
                            sketch,
                            parameters: document.cadDocument.parameters
                        )
                    )
                )
            case .extrude(let extrude):
                guard let sourceFeature = graph.nodes[extrude.profile.featureID],
                      case .sketch(let sketch) = sourceFeature.operation,
                      let bounds = sketchBounds(
                          sketch,
                          parameters: document.cadDocument.parameters
                      ),
                      let depthMeters = resolvedLength(
                          extrude.distance,
                          parameters: document.cadDocument.parameters
                      ) else {
                    return nil
                }
                let object = objectDescriptor(
                    featureID: featureID,
                    kind: .body,
                    document: document
                )
                let component = bodyComponent(
                    sketch: sketch,
                    bounds: bounds,
                    depthMeters: depthMeters,
                    direction: extrude.direction,
                    parameters: document.cadDocument.parameters,
                    declaredObjectTypeID: object?.typeID,
                    declaredProperties: object?.properties ?? ObjectPropertySet()
                )
                return ViewportSceneItem(
                    id: featureID.description,
                    featureID: featureID,
                    sourceFeatureID: extrude.profile.featureID,
                    modelBounds: bounds,
                    kind: .body(component: component)
                )
            }
        }
        return ViewportScene(items: items)
    }

    private func bodyComponent(
        sketch: Sketch,
        bounds: CGRect,
        depthMeters: Double,
        direction: ExtrudeDirection,
        parameters: ParameterTable,
        declaredObjectTypeID: ObjectTypeID?,
        declaredProperties: ObjectPropertySet
    ) -> ViewportBodyComponent {
        let sizeY = abs(depthMeters)
        let yExtents = bodyYExtents(depthMeters: depthMeters, direction: direction)
        let rawCylinder = cylinderComponent(sketch: sketch, parameters: parameters)
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
        sketch: Sketch,
        parameters: ParameterTable
    ) -> ViewportCylinderComponent? {
        guard sketch.entities.count == 1,
              let entity = sketch.entities.values.first,
              case .circle(let circle) = entity,
              let radius = resolvedLength(circle.radius, parameters: parameters) else {
            return nil
        }
        return ViewportCylinderComponent(
            topRadiusMeters: radius,
            bottomRadiusMeters: radius
        )
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

	    private func sketchBounds(
        _ sketch: Sketch,
        parameters: ParameterTable
    ) -> CGRect? {
        let modelPoints = sketch.entities.values.flatMap { entity in
            entityPoints(
                for: entity,
                plane: sketch.plane,
                parameters: parameters
            )
        }
        guard let firstPoint = modelPoints.first else {
            return nil
        }

        var minX = firstPoint.x
        var minY = firstPoint.y
        var maxX = firstPoint.x
        var maxY = firstPoint.y

        for point in modelPoints.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let width = maxX - minX
        let height = maxY - minY
        return CGRect(
            x: minX,
            y: minY,
            width: width > 0.001 ? width : 0.001,
            height: height > 0.001 ? height : 0.001
        )
    }

    private func sketchPrimitives(
        _ sketch: Sketch,
        parameters: ParameterTable
    ) -> [ViewportSketchPrimitive] {
        sketch.entities.values.compactMap { entity in
            switch entity {
            case .point(let point):
                guard let resolved = resolvedViewportPoint(
                    point,
                    plane: sketch.plane,
                    parameters: parameters
                ) else {
                    return nil
                }
                return .point(resolved)
            case .line(let line):
                guard let start = resolvedViewportPoint(
                    line.start,
                    plane: sketch.plane,
                    parameters: parameters
                ),
                      let end = resolvedViewportPoint(
                          line.end,
                          plane: sketch.plane,
                          parameters: parameters
                      ) else {
                    return nil
                }
                return .line(start: start, end: end)
            case .circle(let circle):
                guard let center = resolvedViewportPoint(
                    circle.center,
                    plane: sketch.plane,
                    parameters: parameters
                ),
                      let radius = resolvedLength(circle.radius, parameters: parameters) else {
                    return nil
                }
                return .circle(center: center, radiusMeters: radius)
            }
        }
    }

    private func entityPoints(
        for entity: SketchEntity,
        plane: SketchPlane,
        parameters: ParameterTable
    ) -> [CGPoint] {
        switch entity {
        case .point(let point):
            guard let resolved = resolvedViewportPoint(
                point,
                plane: plane,
                parameters: parameters
            ) else {
                return []
            }
            return [resolved]
        case .line(let line):
            guard let start = resolvedViewportPoint(
                line.start,
                plane: plane,
                parameters: parameters
            ),
                  let end = resolvedViewportPoint(
                      line.end,
                      plane: plane,
                      parameters: parameters
                  ) else {
                return []
            }
            return [start, end]
        case .circle(let circle):
            guard let center = resolvedViewportPoint(
                circle.center,
                plane: plane,
                parameters: parameters
            ),
                  let radius = resolvedLength(circle.radius, parameters: parameters) else {
                return []
            }
            let radiusValue = CGFloat(radius)
            return [
                CGPoint(x: center.x - radiusValue, y: center.y - radiusValue),
                CGPoint(x: center.x + radiusValue, y: center.y + radiusValue),
            ]
        }
    }

    private func resolvedViewportPoint(
        _ point: SketchPoint,
        plane: SketchPlane,
        parameters: ParameterTable
    ) -> CGPoint? {
        guard let localPoint = resolvedPoint(point, parameters: parameters) else {
            return nil
        }
        return viewportPoint(from: localPoint, on: plane)
    }

    private func viewportPoint(
        from localPoint: CGPoint,
        on plane: SketchPlane
    ) -> CGPoint {
        switch plane {
        case .xy, .yz, .plane:
            return localPoint
        case .zx:
            return CGPoint(
                x: localPoint.y,
                y: localPoint.x
            )
        }
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        parameters: ParameterTable
    ) -> CGPoint? {
        guard let x = resolvedLength(point.x, parameters: parameters),
              let y = resolvedLength(point.y, parameters: parameters) else {
            return nil
        }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    private func resolvedLength(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) -> Double? {
        do {
            let quantity = try parameters.resolvedValue(for: expression)
            guard quantity.kind == .length else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
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
