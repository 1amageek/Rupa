import CoreGraphics
import RupaCore
import SwiftCAD

public struct ViewportSelectionRectangleHitTester: Sendable {
    public var sketchPadding: CGFloat
    public var sketchRegionPadding: CGFloat
    public var sketchControlPointRadius: CGFloat
    public var topologyVertexRadius: CGFloat
    public var topologyEdgePadding: CGFloat
    public var bodyVertexRadius: CGFloat
    public var bodyEdgePadding: CGFloat
    public var bodyPadding: CGFloat

    public init(
        sketchPadding: CGFloat = 8.0,
        sketchRegionPadding: CGFloat = 2.0,
        sketchControlPointRadius: CGFloat = 6.0,
        topologyVertexRadius: CGFloat = 6.0,
        topologyEdgePadding: CGFloat = 4.0,
        bodyVertexRadius: CGFloat = 6.0,
        bodyEdgePadding: CGFloat = 4.0,
        bodyPadding: CGFloat = 2.0
    ) {
        self.sketchPadding = sketchPadding
        self.sketchRegionPadding = sketchRegionPadding
        self.sketchControlPointRadius = sketchControlPointRadius
        self.topologyVertexRadius = topologyVertexRadius
        self.topologyEdgePadding = topologyEdgePadding
        self.bodyVertexRadius = bodyVertexRadius
        self.bodyEdgePadding = bodyEdgePadding
        self.bodyPadding = bodyPadding
    }

    public func hits(
        in rect: CGRect,
        scene: ViewportScene,
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy = .all,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> [ViewportHit] {
        let selectionRect = normalized(rect)
        var hits: [ViewportHit] = []
        var seenBodyFeatureIDs: Set<FeatureID> = []

        for item in scene.items {
            switch item.kind {
            case .sketch(let primitives):
                hits.append(contentsOf: sketchHits(
                    in: selectionRect,
                    item: item,
                    primitives: primitives,
                    layout: layout,
                    sketchControlPointHitPolicy: sketchControlPointHitPolicy,
                    selectionHitPolicy: selectionHitPolicy
                ))
            case .body(let component):
                if selectionHitPolicy.allowsVertexHits
                    || selectionHitPolicy.allowsEdgeHits
                    || selectionHitPolicy.allowsFaceHits {
                    let topologyHits = topologyHits(
                        in: selectionRect,
                        item: item,
                        component: component,
                        layout: layout,
                        selectionHitPolicy: selectionHitPolicy
                    )
                    if topologyHits.isEmpty {
                        hits.append(contentsOf: projectedBodySubobjectHits(
                            in: selectionRect,
                            item: item,
                            layout: layout,
                            selectionHitPolicy: selectionHitPolicy
                        ))
                    } else {
                        hits.append(contentsOf: topologyHits)
                    }
                }
                if selectionHitPolicy.allowsObjectHits,
                   let selectableBounds = selectionBounds(for: item, layout: layout),
                   selectionRect.intersects(selectableBounds),
                   seenBodyFeatureIDs.insert(item.featureID).inserted {
                    hits.append(ViewportHit(featureID: item.featureID, kind: .body))
                }
            }
        }

        return hits
    }

    private func sketchHits(
        in rect: CGRect,
        item: ViewportSceneItem,
        primitives: [ViewportSketchPrimitive],
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> [ViewportHit] {
        var hits: [ViewportHit] = []
        if selectionHitPolicy.allowsObjectHits || selectionHitPolicy.allowsSketchEntityHits {
            for primitive in primitives {
                let bounds = sketchSelectionBounds([primitive], layout: layout)
                    .insetBy(dx: -sketchPadding, dy: -sketchPadding)
                guard !bounds.isNull,
                      rect.intersects(bounds) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .sketch,
                        sketchEntityID: primitive.entityID
                    )
                )
                if selectionHitPolicy.allowsSketchEntityHits {
                    hits.append(
                        contentsOf: sketchControlPointHits(
                            primitive,
                            featureID: item.featureID,
                            in: rect,
                            layout: layout,
                            sketchControlPointHitPolicy: sketchControlPointHitPolicy
                        )
                    )
                }
            }
        }

        guard selectionHitPolicy.allowsRegionHits else {
            return hits
        }
        for region in item.sketchRegions {
            let projectedPoints = region.points.map(layout.project)
            let bounds = polygonBounds(projectedPoints)
                .insetBy(dx: -sketchRegionPadding, dy: -sketchRegionPadding)
            guard !bounds.isNull,
                  rect.intersects(bounds) else {
                continue
            }
            hits.append(
                ViewportHit(
                    featureID: item.featureID,
                    kind: .sketch,
                    selectionComponent: .region(region.componentID)
                )
            )
        }

        return hits
    }

    private func sketchControlPointHits(
        _ primitive: ViewportSketchPrimitive,
        featureID: FeatureID,
        in rect: CGRect,
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy
    ) -> [ViewportHit] {
        guard case .spline(let entityID, _, let controlPoints, _) = primitive,
              sketchControlPointHitPolicy.allows(featureID: featureID, entityID: entityID) else {
            return []
        }
        var hits: [ViewportHit] = []
        for (index, controlPoint) in controlPoints.enumerated() {
            let bounds = pointRect(layout.project(controlPoint), radius: sketchControlPointRadius)
            guard rect.intersects(bounds) else {
                continue
            }
            hits.append(
                ViewportHit(
                    featureID: featureID,
                    kind: .sketch,
                    sketchEntityID: entityID,
                    sketchControlPointIndex: index
                )
            )
        }
        return hits
    }

    private func topologyHits(
        in rect: CGRect,
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> [ViewportHit] {
        guard let topology = component.topology,
              topology.isEmpty == false else {
            return []
        }
        var hits: [ViewportHit] = []

        if selectionHitPolicy.allowsVertexHits {
            for vertex in topology.vertices {
                let bounds = pointRect(layout.project(vertex.point), radius: topologyVertexRadius)
                guard rect.intersects(bounds) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .body,
                        selectionComponent: .vertex(vertex.componentID)
                    )
                )
            }
        }

        if selectionHitPolicy.allowsEdgeHits {
            for edge in topology.edges {
                let bounds = segmentBounds(
                    start: layout.project(edge.start),
                    end: layout.project(edge.end)
                )
                .insetBy(dx: -topologyEdgePadding, dy: -topologyEdgePadding)
                guard rect.intersects(bounds) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .body,
                        selectionComponent: .edge(edge.componentID)
                    )
                )
            }
        }

        if selectionHitPolicy.allowsFaceHits {
            for face in topology.faces {
                let bounds = polygonBounds(face.points.map(layout.project))
                guard !bounds.isNull,
                      rect.intersects(bounds) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .body,
                        selectionComponent: .face(face.componentID)
                    )
                )
            }
        }

        return hits
    }

    private func projectedBodySubobjectHits(
        in rect: CGRect,
        item: ViewportSceneItem,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> [ViewportHit] {
        guard let projection = layout.bodyProjection(for: item) else {
            return []
        }
        var hits: [ViewportHit] = []

        if selectionHitPolicy.allowsVertexHits {
            for vertex in ViewportBodyVertex.allCases {
                let bounds = pointRect(projection.point(for: vertex), radius: bodyVertexRadius)
                guard rect.intersects(bounds) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .body,
                        bodyVertex: vertex
                    )
                )
            }
        }

        if selectionHitPolicy.allowsEdgeHits {
            for edge in ViewportBodyEdge.verticalCases {
                let segment = projection.segment(for: edge)
                let bounds = segmentBounds(start: segment.start, end: segment.end)
                    .insetBy(dx: -bodyEdgePadding, dy: -bodyEdgePadding)
                guard rect.intersects(bounds) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .body,
                        bodyEdge: edge
                    )
                )
            }
        }

        if selectionHitPolicy.allowsFaceHits {
            for face in projectedBodyFaceCases {
                guard projection.footprint(for: face).bounds.intersects(rect) else {
                    continue
                }
                hits.append(
                    ViewportHit(
                        featureID: item.featureID,
                        kind: .body,
                        bodyFace: face
                    )
                )
            }
        }

        return hits
    }

    private var projectedBodyFaceCases: [ViewportBodyFace] {
        [.front, .back, .top, .bottom, .left, .right]
    }

    private func selectionBounds(
        for item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> CGRect? {
        switch item.kind {
        case .sketch(let primitives):
            let primitiveBounds = sketchSelectionBounds(primitives, layout: layout)
            if primitiveBounds.isNull {
                return layout.projectedRect(item.modelBounds).insetBy(dx: -sketchPadding, dy: -sketchPadding)
            }
            return primitiveBounds.insetBy(dx: -sketchPadding, dy: -sketchPadding)
        case .body:
            guard let projection = layout.bodyProjection(for: item) else {
                return nil
            }
            return projection.hitBounds.insetBy(dx: -bodyPadding, dy: -bodyPadding)
        }
    }

    private func sketchSelectionBounds(
        _ primitives: [ViewportSketchPrimitive],
        layout: ViewportLayout
    ) -> CGRect {
        var bounds = CGRect.null
        for primitive in primitives {
            switch primitive {
            case .point(_, let point):
                bounds = bounds.union(pointRect(layout.project(point), radius: 2.0))
            case .line(_, let start, let end):
                bounds = bounds.union(pointRect(layout.project(start), radius: 2.0))
                bounds = bounds.union(pointRect(layout.project(end), radius: 2.0))
            case .circle(_, let center, let radiusMeters):
                let radius = max(CGFloat(radiusMeters), 1.0e-12)
                for index in 0 ... 32 {
                    let angle = CGFloat(index) / 32.0 * CGFloat.pi * 2.0
                    let modelPoint = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    bounds = bounds.union(pointRect(layout.project(modelPoint), radius: 2.0))
                }
            case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
                for modelPoint in arcBoundsPoints(
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ) {
                    bounds = bounds.union(pointRect(layout.project(modelPoint), radius: 2.0))
                }
            case .spline(_, let points, let controlPoints, _):
                for modelPoint in points {
                    bounds = bounds.union(pointRect(layout.project(modelPoint), radius: 2.0))
                }
                for modelPoint in controlPoints {
                    bounds = bounds.union(pointRect(layout.project(modelPoint), radius: 4.0))
                }
            }
        }
        return bounds
    }

    private func normalized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(rect.minX, rect.maxX),
            y: min(rect.minY, rect.maxY),
            width: abs(rect.width),
            height: abs(rect.height)
        )
    }

    private func pointRect(_ point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
    }

    private func segmentBounds(start: CGPoint, end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func polygonBounds(_ polygon: [CGPoint]) -> CGRect {
        var bounds = CGRect.null
        for point in polygon {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0))
        }
        return bounds
    }

    private func arcBoundsPoints(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double
    ) -> [CGPoint] {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        let start = CGFloat(startAngleRadians)
        let span = normalizedArcSpan(
            startAngleRadians: startAngleRadians,
            endAngleRadians: endAngleRadians
        )
        var points: [CGPoint] = [
            pointOnCircle(center: center, radius: radius, angle: start),
            pointOnCircle(center: center, radius: radius, angle: start + CGFloat(span)),
        ]
        for quadrant in 0 ..< 4 {
            let angle = CGFloat(quadrant) * CGFloat.pi / 2.0
            if angleIsOnArc(angle, start: start, span: CGFloat(span)) {
                points.append(pointOnCircle(center: center, radius: radius, angle: angle))
            }
        }
        return points
    }

    private func pointOnCircle(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func angleIsOnArc(_ angle: CGFloat, start: CGFloat, span: CGFloat) -> Bool {
        let fullCircle = CGFloat.pi * 2.0
        var relative = angle - start
        while relative < 0.0 {
            relative += fullCircle
        }
        while relative > fullCircle {
            relative -= fullCircle
        }
        return relative <= span + 1.0e-9
    }

    private func normalizedArcSpan(
        startAngleRadians: Double,
        endAngleRadians: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var span = endAngleRadians - startAngleRadians
        while span < -tolerance {
            span += fullCircle
        }
        while span > fullCircle + tolerance {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }
}

private extension ViewportBodyTopology {
    var isEmpty: Bool {
        faces.isEmpty && edges.isEmpty && vertices.isEmpty
    }
}
