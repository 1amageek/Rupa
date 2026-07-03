import RupaCore

public struct ViewportPickIdentity: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public static let backgroundRawValue: UInt32 = 0

    public var rawValue: UInt32

    public init?(rawValue: UInt32) {
        guard rawValue != Self.backgroundRawValue else {
            return nil
        }
        self.rawValue = rawValue
    }

    fileprivate init(allocatedRawValue: UInt32) {
        self.rawValue = allocatedRawValue
    }

    public static func < (lhs: ViewportPickIdentity, rhs: ViewportPickIdentity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ViewportIdentityPickGeometry: Equatable, Sendable {
    case sketchEntity(SketchEntityID)
    case sketchControlPoint(entityID: SketchEntityID, controlPointIndex: Int)
    case sketchRegion(SelectionComponentID)
    case body
    case generatedFace(SelectionComponentID)
    case generatedEdge(SelectionComponentID)
    case generatedVertex(SelectionComponentID)
    case surfaceKnot(SelectionReference)
    case surfaceSpan(SelectionReference)
    case surfaceTrimKnot(SelectionReference)
    case surfaceTrimSpan(SelectionReference)
    case projectedBodyFace(ViewportBodyFace)
    case projectedBodyEdge(ViewportBodyEdge)
    case projectedBodyVertex(ViewportBodyVertex)
}

public struct ViewportIdentityPickRecord: Equatable, Sendable {
    public var identity: ViewportPickIdentity
    public var featureID: FeatureID
    public var geometry: ViewportIdentityPickGeometry
    public var hit: ViewportHit

    public init(
        identity: ViewportPickIdentity,
        featureID: FeatureID,
        geometry: ViewportIdentityPickGeometry,
        hit: ViewportHit
    ) {
        self.identity = identity
        self.featureID = featureID
        self.geometry = geometry
        self.hit = hit
    }
}

public struct ViewportIdentityPickIndex: Equatable, Sendable {
    public private(set) var records: [ViewportIdentityPickRecord]
    private var recordsByIdentity: [ViewportPickIdentity: ViewportIdentityPickRecord]

    fileprivate init(records: [ViewportIdentityPickRecord]) {
        self.records = records
        self.recordsByIdentity = Dictionary(
            uniqueKeysWithValues: records.map { record in
                (record.identity, record)
            }
        )
    }

    public var count: Int {
        records.count
    }

    public var isEmpty: Bool {
        records.isEmpty
    }

    public func record(for identity: ViewportPickIdentity) -> ViewportIdentityPickRecord? {
        recordsByIdentity[identity]
    }

    public func hit(for identity: ViewportPickIdentity) -> ViewportHit? {
        record(for: identity)?.hit
    }

    public func records(for featureID: FeatureID) -> [ViewportIdentityPickRecord] {
        records.filter { $0.featureID == featureID }
    }

    public func filtered(selectionHitPolicy: ViewportSelectionHitPolicy) -> ViewportIdentityPickIndex {
        guard selectionHitPolicy != .all else {
            return self
        }
        return ViewportIdentityPickIndex(
            records: records.filter { selectionHitPolicy.allows(geometry: $0.geometry) }
        )
    }
}

public struct ViewportIdentityPickIndexBuilder: Sendable {
    public var includesSketchControlPoints: Bool
    public var includesProjectedBodySubobjects: Bool
    public var sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy
    public var selectionHitPolicy: ViewportSelectionHitPolicy

    public init(
        includesSketchControlPoints: Bool = true,
        includesProjectedBodySubobjects: Bool = true,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy = .all,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) {
        self.includesSketchControlPoints = includesSketchControlPoints
        self.includesProjectedBodySubobjects = includesProjectedBodySubobjects
        self.sketchControlPointHitPolicy = sketchControlPointHitPolicy
        self.selectionHitPolicy = selectionHitPolicy
    }

    public func build(scene: ViewportScene) -> ViewportIdentityPickIndex {
        var allocator = ViewportPickIdentityAllocator()
        var records: [ViewportIdentityPickRecord] = []

        for item in scene.items {
            switch item.kind {
            case .sketch(let primitives):
                appendSketchRecords(
                    item: item,
                    primitives: primitives,
                    allocator: &allocator,
                    records: &records
                )
            case .body(let component):
                appendBodyRecords(
                    item: item,
                    component: component,
                    allocator: &allocator,
                    records: &records
                )
            }
        }

        return ViewportIdentityPickIndex(records: records)
    }

    private func appendSketchRecords(
        item: ViewportSceneItem,
        primitives: [ViewportSketchPrimitive],
        allocator: inout ViewportPickIdentityAllocator,
        records: inout [ViewportIdentityPickRecord]
    ) {
        for primitive in primitives {
            let entityID = primitive.entityID
            appendRecord(
                featureID: item.featureID,
                geometry: .sketchEntity(entityID),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .sketch,
                    pickingBackend: .identityBuffer,
                    sketchEntityID: entityID
                ),
                allocator: &allocator,
                records: &records
            )

            guard includesSketchControlPoints,
                  case .spline(let entityID, _, let controlPoints, _) = primitive,
                  sketchControlPointHitPolicy.allows(featureID: item.featureID, entityID: entityID) else {
                continue
            }
            for controlPointIndex in controlPoints.indices {
                appendRecord(
                    featureID: item.featureID,
                    geometry: .sketchControlPoint(
                        entityID: entityID,
                        controlPointIndex: controlPointIndex
                    ),
                    hit: ViewportHit(
                        featureID: item.featureID,
                        sceneNodeID: item.sceneNodeID,
                        kind: .sketch,
                        pickingBackend: .identityBuffer,
                        sketchEntityID: entityID,
                        sketchControlPointIndex: controlPointIndex
                    ),
                    allocator: &allocator,
                    records: &records
                )
            }
        }

        for region in item.sketchRegions {
            appendRecord(
                featureID: item.featureID,
                geometry: .sketchRegion(region.componentID),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .sketch,
                    pickingBackend: .identityBuffer,
                    selectionComponent: .region(region.componentID)
                ),
                allocator: &allocator,
                records: &records
            )
        }
    }

    private func appendBodyRecords(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        allocator: inout ViewportPickIdentityAllocator,
        records: inout [ViewportIdentityPickRecord]
    ) {
        appendRecord(
            featureID: item.featureID,
            geometry: .body,
            hit: ViewportHit(
                featureID: item.featureID,
                sceneNodeID: item.sceneNodeID,
                kind: .body,
                pickingBackend: .identityBuffer
            ),
            allocator: &allocator,
            records: &records
        )

        if let topology = component.topology,
           topologyHasTargets(topology) {
            appendGeneratedTopologyRecords(
                item: item,
                topology: topology,
                allocator: &allocator,
                records: &records
            )
        } else if includesProjectedBodySubobjects {
            appendProjectedBodySubobjectRecords(
                item: item,
                allocator: &allocator,
                records: &records
            )
        }
        appendSurfaceTrimParameterRecords(
            item: item,
            component: component,
            allocator: &allocator,
            records: &records
        )
    }

    private func appendSurfaceTrimParameterRecords(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        allocator: inout ViewportPickIdentityAllocator,
        records: inout [ViewportIdentityPickRecord]
    ) {
        for display in component.surfaceKnotDisplays {
            appendRecord(
                featureID: item.featureID,
                geometry: .surfaceKnot(display.selectionReference),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionReference: display.selectionReference
                ),
                allocator: &allocator,
                records: &records
            )
        }
        for display in component.surfaceSpanDisplays {
            appendRecord(
                featureID: item.featureID,
                geometry: .surfaceSpan(display.selectionReference),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionReference: display.selectionReference
                ),
                allocator: &allocator,
                records: &records
            )
        }
        for display in component.surfaceTrimKnotDisplays {
            appendRecord(
                featureID: item.featureID,
                geometry: .surfaceTrimKnot(display.selectionReference),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionReference: display.selectionReference
                ),
                allocator: &allocator,
                records: &records
            )
        }
        for display in component.surfaceTrimSpanDisplays {
            appendRecord(
                featureID: item.featureID,
                geometry: .surfaceTrimSpan(display.selectionReference),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionReference: display.selectionReference
                ),
                allocator: &allocator,
                records: &records
            )
        }
    }

    private func appendGeneratedTopologyRecords(
        item: ViewportSceneItem,
        topology: ViewportBodyTopology,
        allocator: inout ViewportPickIdentityAllocator,
        records: inout [ViewportIdentityPickRecord]
    ) {
        for face in topology.faces {
            appendRecord(
                featureID: item.featureID,
                geometry: .generatedFace(face.componentID),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionComponent: .face(face.componentID)
                ),
                allocator: &allocator,
                records: &records
            )
        }

        for edge in topology.edges {
            appendRecord(
                featureID: item.featureID,
                geometry: .generatedEdge(edge.componentID),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionComponent: .edge(edge.componentID)
                ),
                allocator: &allocator,
                records: &records
            )
        }

        for vertex in topology.vertices {
            appendRecord(
                featureID: item.featureID,
                geometry: .generatedVertex(vertex.componentID),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    selectionComponent: .vertex(vertex.componentID)
                ),
                allocator: &allocator,
                records: &records
            )
        }
    }

    private func appendProjectedBodySubobjectRecords(
        item: ViewportSceneItem,
        allocator: inout ViewportPickIdentityAllocator,
        records: inout [ViewportIdentityPickRecord]
    ) {
        for face in projectedBodyFaceCases {
            appendRecord(
                featureID: item.featureID,
                geometry: .projectedBodyFace(face),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    bodyFace: face
                ),
                allocator: &allocator,
                records: &records
            )
        }

        for edge in ViewportBodyEdge.verticalCases {
            appendRecord(
                featureID: item.featureID,
                geometry: .projectedBodyEdge(edge),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    bodyEdge: edge
                ),
                allocator: &allocator,
                records: &records
            )
        }

        for vertex in ViewportBodyVertex.allCases {
            appendRecord(
                featureID: item.featureID,
                geometry: .projectedBodyVertex(vertex),
                hit: ViewportHit(
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    kind: .body,
                    pickingBackend: .identityBuffer,
                    bodyVertex: vertex
                ),
                allocator: &allocator,
                records: &records
            )
        }
    }

    private var projectedBodyFaceCases: [ViewportBodyFace] {
        [.front, .back, .top, .bottom, .left, .right]
    }

    private func topologyHasTargets(_ topology: ViewportBodyTopology) -> Bool {
        topology.faces.isEmpty == false
            || topology.edges.isEmpty == false
            || topology.vertices.isEmpty == false
    }

    private func appendRecord(
        featureID: FeatureID,
        geometry: ViewportIdentityPickGeometry,
        hit: ViewportHit,
        allocator: inout ViewportPickIdentityAllocator,
        records: inout [ViewportIdentityPickRecord]
    ) {
        guard selectionHitPolicy.allows(geometry: geometry) else {
            return
        }
        records.append(
            ViewportIdentityPickRecord(
                identity: allocator.next(),
                featureID: featureID,
                geometry: geometry,
                hit: hit
            )
        )
    }
}

private struct ViewportPickIdentityAllocator {
    private var nextRawValue: UInt32 = ViewportPickIdentity.backgroundRawValue + 1

    mutating func next() -> ViewportPickIdentity {
        let identity = ViewportPickIdentity(allocatedRawValue: nextRawValue)
        nextRawValue += 1
        return identity
    }
}
