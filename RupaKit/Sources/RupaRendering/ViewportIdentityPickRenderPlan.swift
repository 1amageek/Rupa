import CoreGraphics
import RupaCore

public enum ViewportIdentityPickPrimitive: Equatable, Sendable {
    case polygon(points: [CGPoint])
    case polyline(points: [CGPoint], radius: CGFloat, isClosed: Bool)
    case segment(start: CGPoint, end: CGPoint, radius: CGFloat)
    case point(center: CGPoint, radius: CGFloat)

    public var encodedPointCount: Int {
        switch self {
        case .polygon(let points):
            points.count
        case .polyline(let points, _, _):
            points.count
        case .segment:
            2
        case .point:
            1
        }
    }
}

public struct ViewportIdentityPickDrawItem: Equatable, Sendable {
    public var identity: ViewportPickIdentity
    public var featureID: FeatureID
    public var geometry: ViewportIdentityPickGeometry
    public var primitive: ViewportIdentityPickPrimitive
    public var meshStorageIdentity: ViewportBodyMesh.StorageIdentity?
    public var meshPrimitiveIndex: Int?
    public var depth: Double?
    public var hit: ViewportHit

    public init(
        identity: ViewportPickIdentity,
        featureID: FeatureID,
        geometry: ViewportIdentityPickGeometry,
        primitive: ViewportIdentityPickPrimitive,
        meshStorageIdentity: ViewportBodyMesh.StorageIdentity? = nil,
        meshPrimitiveIndex: Int? = nil,
        depth: Double? = nil,
        hit: ViewportHit
    ) {
        self.identity = identity
        self.featureID = featureID
        self.geometry = geometry
        self.primitive = primitive
        self.meshStorageIdentity = meshStorageIdentity
        self.meshPrimitiveIndex = meshPrimitiveIndex
        self.depth = depth
        self.hit = hit
    }
}

public struct ViewportIdentityPickRenderPlan: Equatable, Sendable {
    public var index: ViewportIdentityPickIndex
    public var drawItems: [ViewportIdentityPickDrawItem]

    public init(
        index: ViewportIdentityPickIndex,
        drawItems: [ViewportIdentityPickDrawItem]
    ) {
        self.index = index
        self.drawItems = drawItems
    }

    public var isEmpty: Bool {
        drawItems.isEmpty
    }

    public var encodedPointCount: Int {
        drawItems.reduce(0) { partialResult, item in
            partialResult + item.primitive.encodedPointCount
        }
    }

    public func drawItems(for identity: ViewportPickIdentity) -> [ViewportIdentityPickDrawItem] {
        drawItems.filter { $0.identity == identity }
    }
}

public struct ViewportIdentityPickRenderPlanBuilder: Sendable {
    public var curveRadius: CGFloat
    public var pointRadius: CGFloat
    public var controlPointRadius: CGFloat
    public var topologyEdgeRadius: CGFloat
    public var topologyVertexRadius: CGFloat
    public var bodyEdgeRadius: CGFloat
    public var bodyVertexRadius: CGFloat
    public var circleSampleCount: Int

    public init(
        curveRadius: CGFloat = 4.0,
        pointRadius: CGFloat = 6.0,
        controlPointRadius: CGFloat = 6.0,
        topologyEdgeRadius: CGFloat = 4.0,
        topologyVertexRadius: CGFloat = 6.0,
        bodyEdgeRadius: CGFloat = 4.0,
        bodyVertexRadius: CGFloat = 6.0,
        circleSampleCount: Int = 48
    ) {
        self.curveRadius = curveRadius
        self.pointRadius = pointRadius
        self.controlPointRadius = controlPointRadius
        self.topologyEdgeRadius = topologyEdgeRadius
        self.topologyVertexRadius = topologyVertexRadius
        self.bodyEdgeRadius = bodyEdgeRadius
        self.bodyVertexRadius = bodyVertexRadius
        self.circleSampleCount = circleSampleCount
    }

    public func build(
        scene: ViewportScene,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex? = nil,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> ViewportIdentityPickRenderPlan {
        let pickIndex = (index ?? ViewportIdentityPickIndexBuilder(
            selectionHitPolicy: selectionHitPolicy
        ).build(scene: scene))
        .filtered(selectionHitPolicy: selectionHitPolicy)
        var drawItems: [ViewportIdentityPickDrawItem] = []

        for item in scene.items {
            switch item.kind {
            case .sketch(let primitives):
                appendSketchDrawItems(
                    item: item,
                    primitives: primitives,
                    layout: layout,
                    index: pickIndex,
                    drawItems: &drawItems
                )
            case .body(let component):
                appendBodyDrawItems(
                    item: item,
                    component: component,
                    layout: layout,
                    index: pickIndex,
                    drawItems: &drawItems
                )
            }
        }

        return ViewportIdentityPickRenderPlan(index: pickIndex, drawItems: drawItems)
    }

    private func appendSketchDrawItems(
        item: ViewportSceneItem,
        primitives: [ViewportSketchPrimitive],
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        for primitive in primitives {
            appendSketchEntityDrawItem(
                item: item,
                primitive: primitive,
                layout: layout,
                index: index,
                drawItems: &drawItems
            )
            appendSketchControlPointDrawItems(
                item: item,
                primitive: primitive,
                layout: layout,
                index: index,
                drawItems: &drawItems
            )
        }

        for region in item.sketchRegions {
            guard let record = record(
                for: item,
                geometry: .sketchRegion(region.componentID),
                in: index
            ) else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .polygon(points: region.points.map(layout.project)),
                depth: nil,
                drawItems: &drawItems
            )
        }
    }

    private func appendSketchEntityDrawItem(
        item: ViewportSceneItem,
        primitive: ViewportSketchPrimitive,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        let geometry = ViewportIdentityPickGeometry.sketchEntity(primitive.entityID)
        guard let record = record(for: item, geometry: geometry, in: index),
              let pickPrimitive = sketchPrimitive(primitive, layout: layout) else {
            return
        }
        appendDrawItem(
            record: record,
            primitive: pickPrimitive,
            depth: nil,
            drawItems: &drawItems
        )
    }

    private func appendSketchControlPointDrawItems(
        item: ViewportSceneItem,
        primitive: ViewportSketchPrimitive,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        guard case .spline(let entityID, _, let controlPoints, _) = primitive else {
            return
        }
        for controlPointIndex in controlPoints.indices {
            let geometry = ViewportIdentityPickGeometry.sketchControlPoint(
                entityID: entityID,
                controlPointIndex: controlPointIndex
            )
            guard let record = record(for: item, geometry: geometry, in: index) else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .point(
                    center: layout.project(controlPoints[controlPointIndex]),
                    radius: controlPointRadius
                ),
                depth: nil,
                drawItems: &drawItems
            )
        }
    }

    private func appendBodyDrawItems(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        appendBodyObjectDrawItems(
            item: item,
            component: component,
            layout: layout,
            index: index,
            drawItems: &drawItems
        )
        if let topology = component.topology,
           topologyHasTargets(topology) {
            appendGeneratedTopologyDrawItems(
                item: item,
                topology: topology,
                layout: layout,
                index: index,
                drawItems: &drawItems
            )
        } else {
            appendProjectedBodySubobjectDrawItems(
                item: item,
                layout: layout,
                index: index,
                drawItems: &drawItems
            )
        }
    }

    private func appendBodyObjectDrawItems(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        guard let record = record(for: item, geometry: .body, in: index) else {
            return
        }

        if let topology = component.topology,
           topology.faces.isEmpty == false {
            for face in topology.faces {
                let points = face.points.map { layout.project($0, in: item) }
                guard points.count >= 3 else {
                    continue
                }
                appendDrawItem(
                    record: record,
                    primitive: .polygon(points: points),
                    depth: averageDepth(face.points, item: item, layout: layout),
                    drawItems: &drawItems
                )
            }
            return
        }

        if let mesh = component.mesh {
            appendMeshDrawItems(
                item: item,
                record: record,
                mesh: mesh,
                layout: layout,
                drawItems: &drawItems
            )
            return
        }

        guard let projection = layout.bodyProjection(for: item) else {
            return
        }
        for face in projectedBodyFaceCases {
            appendDrawItem(
                record: record,
                primitive: .polygon(points: projection.footprint(for: face).corners),
                depth: nil,
                drawItems: &drawItems
            )
        }
    }

    private func appendMeshDrawItems(
        item: ViewportSceneItem,
        record: ViewportIdentityPickRecord,
        mesh: ViewportBodyMesh,
        layout: ViewportLayout,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        var index = 0
        while index + 2 < mesh.indices.count {
            let meshPrimitiveIndex = index / 3
            let firstIndex = Int(mesh.indices[index])
            let secondIndex = Int(mesh.indices[index + 1])
            let thirdIndex = Int(mesh.indices[index + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                index += 3
                continue
            }

            let points = [
                mesh.positions[firstIndex],
                mesh.positions[secondIndex],
                mesh.positions[thirdIndex],
            ]
            appendDrawItem(
                record: record,
                primitive: .polygon(points: points.map { layout.project($0, in: item) }),
                meshStorageIdentity: mesh.storageIdentity,
                meshPrimitiveIndex: meshPrimitiveIndex,
                depth: averageDepth(points, item: item, layout: layout),
                drawItems: &drawItems
            )
            index += 3
        }
    }

    private func appendGeneratedTopologyDrawItems(
        item: ViewportSceneItem,
        topology: ViewportBodyTopology,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        for face in topology.faces {
            let geometry = ViewportIdentityPickGeometry.generatedFace(face.componentID)
            guard let record = record(for: item, geometry: geometry, in: index),
                  face.points.count >= 3 else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .polygon(points: face.points.map { layout.project($0, in: item) }),
                depth: averageDepth(face.points, item: item, layout: layout),
                drawItems: &drawItems
            )
        }

        for edge in topology.edges {
            let geometry = ViewportIdentityPickGeometry.generatedEdge(edge.componentID)
            guard let record = record(for: item, geometry: geometry, in: index) else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .segment(
                    start: layout.project(edge.start, in: item),
                    end: layout.project(edge.end, in: item),
                    radius: topologyEdgeRadius
                ),
                depth: averageDepth([edge.start, edge.end], item: item, layout: layout),
                drawItems: &drawItems
            )
        }

        for vertex in topology.vertices {
            let geometry = ViewportIdentityPickGeometry.generatedVertex(vertex.componentID)
            guard let record = record(for: item, geometry: geometry, in: index) else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .point(
                    center: layout.project(vertex.point, in: item),
                    radius: topologyVertexRadius
                ),
                depth: layout.projectedDepth(vertex.point, in: item),
                drawItems: &drawItems
            )
        }
    }

    private func appendProjectedBodySubobjectDrawItems(
        item: ViewportSceneItem,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        guard let projection = layout.bodyProjection(for: item) else {
            return
        }
        for face in projectedBodyFaceCases {
            let geometry = ViewportIdentityPickGeometry.projectedBodyFace(face)
            guard let record = record(for: item, geometry: geometry, in: index) else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .polygon(points: projection.footprint(for: face).corners),
                depth: nil,
                drawItems: &drawItems
            )
        }

        for edge in ViewportBodyEdge.verticalCases {
            let geometry = ViewportIdentityPickGeometry.projectedBodyEdge(edge)
            guard let record = record(for: item, geometry: geometry, in: index) else {
                continue
            }
            let segment = projection.segment(for: edge)
            appendDrawItem(
                record: record,
                primitive: .segment(
                    start: segment.start,
                    end: segment.end,
                    radius: bodyEdgeRadius
                ),
                depth: nil,
                drawItems: &drawItems
            )
        }

        for vertex in ViewportBodyVertex.allCases {
            let geometry = ViewportIdentityPickGeometry.projectedBodyVertex(vertex)
            guard let record = record(for: item, geometry: geometry, in: index) else {
                continue
            }
            appendDrawItem(
                record: record,
                primitive: .point(
                    center: projection.point(for: vertex),
                    radius: bodyVertexRadius
                ),
                depth: nil,
                drawItems: &drawItems
            )
        }
    }

    private func sketchPrimitive(
        _ primitive: ViewportSketchPrimitive,
        layout: ViewportLayout
    ) -> ViewportIdentityPickPrimitive? {
        switch primitive {
        case .point(_, let point):
            return .point(center: layout.project(point), radius: pointRadius)
        case .line(_, let start, let end):
            return .segment(
                start: layout.project(start),
                end: layout.project(end),
                radius: curveRadius
            )
        case .circle(_, let center, let radiusMeters):
            return .polyline(
                points: circlePoints(
                    center: center,
                    radiusMeters: radiusMeters,
                    layout: layout
                ),
                radius: curveRadius,
                isClosed: true
            )
        case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
            return .polyline(
                points: arcPoints(
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle,
                    layout: layout
                ),
                radius: curveRadius,
                isClosed: false
            )
        case .spline(_, let points, _, _):
            return .polyline(
                points: points.map(layout.project),
                radius: curveRadius,
                isClosed: false
            )
        }
    }

    private func circlePoints(
        center: CGPoint,
        radiusMeters: Double,
        layout: ViewportLayout
    ) -> [CGPoint] {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        let sampleCount = max(circleSampleCount, 8)
        return (0 ..< sampleCount).map { index in
            let angle = CGFloat(index) / CGFloat(sampleCount) * CGFloat.pi * 2.0
            return layout.project(CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
    }

    private func arcPoints(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        layout: ViewportLayout
    ) -> [CGPoint] {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        let span = normalizedArcSpan(
            startAngleRadians: startAngleRadians,
            endAngleRadians: endAngleRadians
        )
        let sampleCount = max(Int(ceil(abs(span) / (Double.pi / 24.0))), 2)
        return (0 ... sampleCount).map { index in
            let fraction = Double(index) / Double(sampleCount)
            let angle = CGFloat(startAngleRadians + span * fraction)
            return layout.project(CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
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
        if abs(span) <= tolerance,
           abs(endAngleRadians - startAngleRadians) > tolerance {
            return fullCircle
        }
        return span
    }

    private var projectedBodyFaceCases: [ViewportBodyFace] {
        [.front, .back, .top, .bottom, .left, .right]
    }

    private func record(
        for item: ViewportSceneItem,
        geometry: ViewportIdentityPickGeometry,
        in index: ViewportIdentityPickIndex
    ) -> ViewportIdentityPickRecord? {
        index.records.first { record in
            record.featureID == item.featureID
                && record.geometry == geometry
                && record.hit.sceneNodeID == item.sceneNodeID
        }
    }

    private func appendDrawItem(
        record: ViewportIdentityPickRecord,
        primitive: ViewportIdentityPickPrimitive,
        meshStorageIdentity: ViewportBodyMesh.StorageIdentity? = nil,
        meshPrimitiveIndex: Int? = nil,
        depth: Double?,
        drawItems: inout [ViewportIdentityPickDrawItem]
    ) {
        drawItems.append(
            ViewportIdentityPickDrawItem(
                identity: record.identity,
                featureID: record.featureID,
                geometry: record.geometry,
                primitive: primitive,
                meshStorageIdentity: meshStorageIdentity,
                meshPrimitiveIndex: meshPrimitiveIndex,
                depth: depth,
                hit: record.hit
            )
        )
    }

    private func topologyHasTargets(_ topology: ViewportBodyTopology) -> Bool {
        topology.faces.isEmpty == false
            || topology.edges.isEmpty == false
            || topology.vertices.isEmpty == false
    }

    private func averageDepth(
        _ points: [Point3D],
        item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> Double? {
        let depths = points.compactMap { layout.projectedDepth($0, in: item) }
        guard depths.isEmpty == false else {
            return nil
        }
        return depths.reduce(0.0, +) / Double(depths.count)
    }
}
