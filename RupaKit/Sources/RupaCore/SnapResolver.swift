import Foundation
import SwiftCAD
import RupaCoreTypes

public enum SnapCandidateKind: String, Codable, Equatable, Hashable, Sendable {
    case grid
    case sketchPoint
    case lineStart
    case lineEnd
    case lineMidpoint
    case lineClosest
    case circleCenter
    case circleQuarter
    case circleClosest
    case arcStart
    case arcEnd
    case arcCenter
    case arcMidpoint
    case arcClosest
    case splineStart
    case splineEnd
    case controlVertex
    case splineClosest
    case curveIntersection
    case curveAxis
    case curveCoordinatePlane
    case curvePerpendicular
    case curveTangent
    case referenceLine
    case measurementPoint
    case regionCenter
    case surfaceControlVertex
    case surfaceTrimEndpoint
    case surfaceTrimControlPoint
    case topologyVertex
    case edgeStart
    case edgeEnd
    case edgeMidpoint
    case faceCenter
    case surfaceFrame

    public var isReferenceLineAnchorSource: Bool {
        switch self {
        case .grid, .referenceLine:
            return false
        default:
            return true
        }
    }
}

public enum SnapObjectTargetingOverride: String, Codable, Equatable, Sendable {
    case none
    case forceEnabled
}

public enum SnapAxisKind: String, Codable, Equatable, Hashable, Sendable {
    case x
    case y
    case z

    public var label: String {
        rawValue.uppercased()
    }
}

public struct SnapAxisReference: Codable, Equatable, Sendable {
    public var kind: SnapAxisKind
    public var referencePoint: Point2D

    public init(kind: SnapAxisKind, referencePoint: Point2D) {
        self.kind = kind
        self.referencePoint = referencePoint
    }
}

public enum SnapCoordinatePlaneKind: String, Codable, Equatable, Hashable, Sendable {
    case xy
    case yz
    case zx

    public var label: String {
        rawValue.uppercased()
    }
}

public struct SnapCoordinatePlaneReference: Codable, Equatable, Sendable {
    public var kind: SnapCoordinatePlaneKind
    public var referencePoint: Point2D

    public init(kind: SnapCoordinatePlaneKind, referencePoint: Point2D) {
        self.kind = kind
        self.referencePoint = referencePoint
    }
}

public struct SnapTopologyReference: Codable, Equatable, Sendable {
    public var sceneNodeID: SceneNodeID
    public var component: SelectionComponent
    public var kind: TopologySummaryResult.Entry.Kind
    public var persistentName: String
    public var referenceID: String
    public var worldPoint: TopologySummaryResult.Entry.Point?

    public init(
        sceneNodeID: SceneNodeID,
        component: SelectionComponent,
        kind: TopologySummaryResult.Entry.Kind,
        persistentName: String,
        referenceID: String,
        worldPoint: TopologySummaryResult.Entry.Point? = nil
    ) {
        self.sceneNodeID = sceneNodeID
        self.component = component
        self.kind = kind
        self.persistentName = persistentName
        self.referenceID = referenceID
        self.worldPoint = worldPoint
    }

    public var selectionTarget: SelectionTarget {
        SelectionTarget(sceneNodeID: sceneNodeID, component: component)
    }
}

public struct SnapRegionReference: Codable, Equatable, Sendable {
    public var sceneNodeID: SceneNodeID?
    public var featureID: FeatureID
    public var profileIndex: Int
    public var center: Point2D

    public init(
        sceneNodeID: SceneNodeID?,
        featureID: FeatureID,
        profileIndex: Int,
        center: Point2D
    ) {
        self.sceneNodeID = sceneNodeID
        self.featureID = featureID
        self.profileIndex = profileIndex
        self.center = center
    }
}

public struct SnapMeasurementReference: Codable, Equatable, Sendable {
    public var measurementID: MeasurementAnnotationID
    public var sceneNodeID: SceneNodeID?
    public var name: String
    public var kind: MeasurementAnnotation.Kind
    public var anchorIndex: Int
    public var anchorKind: MeasurementAnchor.Kind
    public var role: MeasurementAnchor.Role
    public var worldPoint: Point3D
    public var sketchReference: MeasurementSketchAnchor?
    public var topologyReference: MeasurementTopologyAnchor?
    public var sketchCurveParameter: MeasurementSketchCurveAnchor?
    public var topologyEdgeParameter: MeasurementTopologyEdgeAnchor?

    public init(
        measurementID: MeasurementAnnotationID,
        sceneNodeID: SceneNodeID?,
        name: String,
        kind: MeasurementAnnotation.Kind,
        anchorIndex: Int,
        role: MeasurementAnchor.Role,
        worldPoint: Point3D,
        anchorKind: MeasurementAnchor.Kind = .worldPoint,
        sketchReference: MeasurementSketchAnchor? = nil,
        topologyReference: MeasurementTopologyAnchor? = nil,
        sketchCurveParameter: MeasurementSketchCurveAnchor? = nil,
        topologyEdgeParameter: MeasurementTopologyEdgeAnchor? = nil
    ) {
        self.measurementID = measurementID
        self.sceneNodeID = sceneNodeID
        self.name = name
        self.kind = kind
        self.anchorIndex = anchorIndex
        self.anchorKind = anchorKind
        self.role = role
        self.worldPoint = worldPoint
        self.sketchReference = sketchReference
        self.topologyReference = topologyReference
        self.sketchCurveParameter = sketchCurveParameter
        self.topologyEdgeParameter = topologyEdgeParameter
    }
}

public struct SnapSurfaceFrameReference: Codable, Equatable, Sendable {
    public var displayID: SurfaceFrameDisplayID
    public var query: SurfaceFrameQuery
    public var faceID: String
    public var facePersistentNames: [String]
    public var sourceFeatureID: String?
    public var sceneNodeID: String?
    public var u: Double
    public var v: Double
    public var worldPoint: Point3D
    public var uAxis: SurfaceAnalysisResult.Vector
    public var vAxis: SurfaceAnalysisResult.Vector
    public var normal: SurfaceAnalysisResult.Vector

    public init(
        displayID: SurfaceFrameDisplayID,
        query: SurfaceFrameQuery,
        faceID: String,
        facePersistentNames: [String],
        sourceFeatureID: String?,
        sceneNodeID: String?,
        u: Double,
        v: Double,
        worldPoint: Point3D,
        uAxis: SurfaceAnalysisResult.Vector,
        vAxis: SurfaceAnalysisResult.Vector,
        normal: SurfaceAnalysisResult.Vector
    ) {
        self.displayID = displayID
        self.query = query
        self.faceID = faceID
        self.facePersistentNames = facePersistentNames
        self.sourceFeatureID = sourceFeatureID
        self.sceneNodeID = sceneNodeID
        self.u = u
        self.v = v
        self.worldPoint = worldPoint
        self.uAxis = uAxis
        self.vAxis = vAxis
        self.normal = normal
    }
}

public enum SnapSurfaceTrimPointKind: String, Codable, Equatable, Sendable {
    case endpoint
    case controlPoint
}

public struct SnapSurfaceTrimReference: Codable, Equatable, Sendable {
    public var kind: SnapSurfaceTrimPointKind
    public var selectionReference: SelectionReference
    public var endpoint: SurfaceTrimEndpoint?
    public var controlPointIndex: Int?
    public var sourceFeatureID: String
    public var sceneNodeID: SceneNodeID?
    public var u: Double
    public var v: Double
    public var worldPoint: Point3D
    public var uAxis: SurfaceAnalysisResult.Vector
    public var vAxis: SurfaceAnalysisResult.Vector
    public var normal: SurfaceAnalysisResult.Vector

    public init(
        kind: SnapSurfaceTrimPointKind,
        selectionReference: SelectionReference,
        endpoint: SurfaceTrimEndpoint? = nil,
        controlPointIndex: Int? = nil,
        sourceFeatureID: String,
        sceneNodeID: SceneNodeID?,
        u: Double,
        v: Double,
        worldPoint: Point3D,
        uAxis: SurfaceAnalysisResult.Vector,
        vAxis: SurfaceAnalysisResult.Vector,
        normal: SurfaceAnalysisResult.Vector
    ) {
        self.kind = kind
        self.selectionReference = selectionReference
        self.endpoint = endpoint
        self.controlPointIndex = controlPointIndex
        self.sourceFeatureID = sourceFeatureID
        self.sceneNodeID = sceneNodeID
        self.u = u
        self.v = v
        self.worldPoint = worldPoint
        self.uAxis = uAxis
        self.vAxis = vAxis
        self.normal = normal
    }
}

public struct SnapResolutionOptions: Codable, Equatable, Sendable {
    public var usesGrid: Bool
    public var usesObjects: Bool
    public var objectTargetingOverride: SnapObjectTargetingOverride
    public var suppressedCandidateKinds: Set<SnapCandidateKind>
    public var constructionPlane: SketchPlane?
    public var gridIntervalMeters: Double?
    public var objectSearchRadiusMeters: Double?
    public var maximumCandidateCount: Int
    public var referencePoint: Point2D?
    public var referenceLineAnchors: [SketchReferenceLineAnchor]

    public init(
        usesGrid: Bool = true,
        usesObjects: Bool = true,
        objectTargetingOverride: SnapObjectTargetingOverride = .none,
        suppressedCandidateKinds: Set<SnapCandidateKind> = [],
        constructionPlane: SketchPlane? = nil,
        gridIntervalMeters: Double? = nil,
        objectSearchRadiusMeters: Double? = nil,
        maximumCandidateCount: Int = 12,
        referencePoint: Point2D? = nil,
        referenceLineAnchors: [SketchReferenceLineAnchor] = []
    ) {
        self.usesGrid = usesGrid
        self.usesObjects = usesObjects
        self.objectTargetingOverride = objectTargetingOverride
        self.suppressedCandidateKinds = suppressedCandidateKinds
        self.constructionPlane = constructionPlane
        self.gridIntervalMeters = gridIntervalMeters
        self.objectSearchRadiusMeters = objectSearchRadiusMeters
        self.maximumCandidateCount = maximumCandidateCount
        self.referencePoint = referencePoint
        self.referenceLineAnchors = referenceLineAnchors
    }

    private enum CodingKeys: String, CodingKey {
        case usesGrid
        case usesObjects
        case objectTargetingOverride
        case suppressedCandidateKinds
        case constructionPlane
        case gridIntervalMeters
        case objectSearchRadiusMeters
        case maximumCandidateCount
        case referencePoint
        case referenceLineAnchors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usesGrid = try container.decode(Bool.self, forKey: .usesGrid)
        usesObjects = try container.decode(Bool.self, forKey: .usesObjects)
        objectTargetingOverride = try container.decodeIfPresent(
            SnapObjectTargetingOverride.self,
            forKey: .objectTargetingOverride
        ) ?? .none
        suppressedCandidateKinds = try container.decodeIfPresent(
            Set<SnapCandidateKind>.self,
            forKey: .suppressedCandidateKinds
        ) ?? []
        constructionPlane = try container.decodeIfPresent(SketchPlane.self, forKey: .constructionPlane)
        gridIntervalMeters = try container.decodeIfPresent(Double.self, forKey: .gridIntervalMeters)
        objectSearchRadiusMeters = try container.decodeIfPresent(Double.self, forKey: .objectSearchRadiusMeters)
        maximumCandidateCount = try container.decode(Int.self, forKey: .maximumCandidateCount)
        referencePoint = try container.decodeIfPresent(Point2D.self, forKey: .referencePoint)
        referenceLineAnchors = try container.decodeIfPresent(
            [SketchReferenceLineAnchor].self,
            forKey: .referenceLineAnchors
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usesGrid, forKey: .usesGrid)
        try container.encode(usesObjects, forKey: .usesObjects)
        try container.encode(objectTargetingOverride, forKey: .objectTargetingOverride)
        try container.encode(suppressedCandidateKinds, forKey: .suppressedCandidateKinds)
        try container.encodeIfPresent(constructionPlane, forKey: .constructionPlane)
        try container.encodeIfPresent(gridIntervalMeters, forKey: .gridIntervalMeters)
        try container.encodeIfPresent(objectSearchRadiusMeters, forKey: .objectSearchRadiusMeters)
        try container.encode(maximumCandidateCount, forKey: .maximumCandidateCount)
        try container.encodeIfPresent(referencePoint, forKey: .referencePoint)
        try container.encode(referenceLineAnchors, forKey: .referenceLineAnchors)
    }

    public var resolvesObjects: Bool {
        usesObjects || objectTargetingOverride == .forceEnabled
    }

    public var usesConstructionPlaneProjection: Bool {
        constructionPlane != nil
    }
}

private struct ValidatedSnapResolutionOptions {
    var usesGrid: Bool
    var usesObjects: Bool
    var objectTargetingOverride: SnapObjectTargetingOverride
    var suppressedCandidateKinds: Set<SnapCandidateKind>
    var constructionPlane: SketchPlane?
    var gridIntervalMeters: Double
    var objectSearchRadiusMeters: Double
    var maximumCandidateCount: Int
    var referencePoint: Point2D?
    var referenceLineAnchors: [SketchReferenceLineAnchor]

    var resolvesObjects: Bool {
        usesObjects || objectTargetingOverride == .forceEnabled
    }

    var usesConstructionPlaneProjection: Bool {
        constructionPlane != nil
    }
}

public struct SnapSourceReference: Codable, Equatable, Hashable, Sendable {
    public var sceneNodeID: SceneNodeID?
    public var featureID: FeatureID
    public var entityID: SketchEntityID
    public var controlPointIndex: Int?

    public init(
        sceneNodeID: SceneNodeID?,
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPointIndex: Int? = nil
    ) {
        self.sceneNodeID = sceneNodeID
        self.featureID = featureID
        self.entityID = entityID
        self.controlPointIndex = controlPointIndex
    }

    public var selectionTarget: SelectionTarget? {
        guard let sceneNodeID else {
            return nil
        }
        return SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
    }
}

public struct SnapCandidate: Codable, Equatable, Sendable {
    public var kind: SnapCandidateKind
    public var point: Point2D
    public var distanceMeters: Double
    public var label: String
    public var source: SnapSourceReference?
    public var relatedSource: SnapSourceReference?
    public var topologySource: SnapTopologyReference?
    public var regionSource: SnapRegionReference?
    public var measurementSource: SnapMeasurementReference?
    public var surfaceFrameSource: SnapSurfaceFrameReference?
    public var surfaceTrimSource: SnapSurfaceTrimReference?
    public var axisSource: SnapAxisReference?
    public var coordinatePlaneSource: SnapCoordinatePlaneReference?

    public init(
        kind: SnapCandidateKind,
        point: Point2D,
        distanceMeters: Double,
        label: String,
        source: SnapSourceReference? = nil,
        relatedSource: SnapSourceReference? = nil,
        topologySource: SnapTopologyReference? = nil,
        regionSource: SnapRegionReference? = nil,
        measurementSource: SnapMeasurementReference? = nil,
        surfaceFrameSource: SnapSurfaceFrameReference? = nil,
        surfaceTrimSource: SnapSurfaceTrimReference? = nil,
        axisSource: SnapAxisReference? = nil,
        coordinatePlaneSource: SnapCoordinatePlaneReference? = nil
    ) {
        self.kind = kind
        self.point = point
        self.distanceMeters = distanceMeters
        self.label = label
        self.source = source
        self.relatedSource = relatedSource
        self.topologySource = topologySource
        self.regionSource = regionSource
        self.measurementSource = measurementSource
        self.surfaceFrameSource = surfaceFrameSource
        self.surfaceTrimSource = surfaceTrimSource
        self.axisSource = axisSource
        self.coordinatePlaneSource = coordinatePlaneSource
    }
}

public struct SnapResolutionResult: Codable, Equatable, Sendable {
    public var originalPoint: Point2D
    public var resolvedPoint: Point2D
    public var selectedCandidate: SnapCandidate?
    public var candidates: [SnapCandidate]

    public init(
        originalPoint: Point2D,
        resolvedPoint: Point2D,
        selectedCandidate: SnapCandidate?,
        candidates: [SnapCandidate]
    ) {
        self.originalPoint = originalPoint
        self.resolvedPoint = resolvedPoint
        self.selectedCandidate = selectedCandidate
        self.candidates = candidates
    }

    public var selectedTopologyWorldPoint: Point3D? {
        guard let point = selectedCandidate?.topologySource?.worldPoint else {
            return nil
        }
        return Point3D(x: point.x, y: point.y, z: point.z)
    }

    public var selectedWorldPoint: Point3D? {
        selectedTopologyWorldPoint
            ?? selectedCandidate?.measurementSource?.worldPoint
            ?? selectedSurfaceFrameWorldPoint
            ?? selectedSurfaceTrimWorldPoint
    }

    public var selectedSurfaceFrameWorldPoint: Point3D? {
        selectedCandidate?.surfaceFrameSource?.worldPoint
    }

    public var selectedSurfaceTrimWorldPoint: Point3D? {
        selectedCandidate?.surfaceTrimSource?.worldPoint
    }
}

public struct SnapResolver: Sendable {
    private static let exactHitToleranceMeters = 1.0e-10

    private let curveSampler: SketchCurveSampler

    public init(curveSampler: SketchCurveSampler = SketchCurveSampler()) {
        self.curveSampler = curveSampler
    }

    public func resolve(
        point: Point2D,
        in document: DesignDocument,
        ruler: RulerConfiguration,
        options: SnapResolutionOptions,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay] = [:]
    ) throws -> SnapResolutionResult {
        try validate(point: point)
        let normalizedOptions = try validated(options, ruler: ruler)
        let constructionPlane = try constructionPlaneCoordinateSystem(
            from: normalizedOptions,
            document: document
        )
        var candidates: [PrioritizedSnapCandidate] = []

        if normalizedOptions.resolvesObjects {
            candidates += try objectCandidates(
                near: point,
                in: document,
                searchRadiusMeters: normalizedOptions.objectSearchRadiusMeters,
                referencePoint: normalizedOptions.referencePoint,
                constructionPlane: constructionPlane,
                surfaceFrameDisplays: surfaceFrameDisplays
            )
        }
        candidates += referenceLineCandidates(
            near: point,
            anchors: normalizedOptions.referenceLineAnchors,
            searchRadiusMeters: normalizedOptions.objectSearchRadiusMeters
        )
        if normalizedOptions.usesGrid {
            candidates.append(
                gridCandidate(
                    near: point,
                    intervalMeters: normalizedOptions.gridIntervalMeters
                )
            )
        }

        let sortedCandidates = candidates
            .filter { !normalizedOptions.suppressedCandidateKinds.contains($0.candidate.kind) }
            .sorted { first, second in
                let firstIsExactHit = first.candidate.distanceMeters <= Self.exactHitToleranceMeters
                let secondIsExactHit = second.candidate.distanceMeters <= Self.exactHitToleranceMeters
                if firstIsExactHit != secondIsExactHit {
                    return firstIsExactHit
                }
                let firstPriority = effectivePriority(
                    for: first,
                    suppressedCandidateKinds: normalizedOptions.suppressedCandidateKinds
                )
                let secondPriority = effectivePriority(
                    for: second,
                    suppressedCandidateKinds: normalizedOptions.suppressedCandidateKinds
                )
                if firstPriority != secondPriority {
                    return firstPriority < secondPriority
                }
                if first.candidate.distanceMeters != second.candidate.distanceMeters {
                    return first.candidate.distanceMeters < second.candidate.distanceMeters
                }
                if first.candidate.label != second.candidate.label {
                    return first.candidate.label < second.candidate.label
                }
                return first.sortKey < second.sortKey
            }
            .map(\.candidate)
        let limitedCandidates = Array(sortedCandidates.prefix(normalizedOptions.maximumCandidateCount))
        let selectedCandidate = sortedCandidates.first

        return SnapResolutionResult(
            originalPoint: point,
            resolvedPoint: selectedCandidate?.point ?? point,
            selectedCandidate: selectedCandidate,
            candidates: limitedCandidates
        )
    }

    private func effectivePriority(
        for candidate: PrioritizedSnapCandidate,
        suppressedCandidateKinds: Set<SnapCandidateKind>
    ) -> Int {
        guard candidate.candidate.kind == .curveCoordinatePlane,
              suppressedCandidateKinds.contains(.curveAxis) ||
              suppressedCandidateKinds.contains(.curvePerpendicular) else {
            return candidate.priority
        }
        return -1
    }

    private func objectCandidates(
        near point: Point2D,
        in document: DesignDocument,
        searchRadiusMeters: Double,
        referencePoint: Point2D?,
        constructionPlane: SketchPlaneCoordinateSystem?,
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) throws -> [PrioritizedSnapCandidate] {
        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        var snapEntities: [SnapEntity] = []
        var candidates: [PrioritizedSnapCandidate] = []
        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation else {
                continue
            }
            let sceneNodeID = sceneNodeIDsByFeatureID[featureID]
            for (entityID, entity) in sketch.entities.sorted(by: { first, second in
                first.key.description < second.key.description
            }) {
                let source = SnapSourceReference(
                    sceneNodeID: sceneNodeID,
                    featureID: featureID,
                    entityID: entityID
                )
                let snapEntity = try snapEntity(
                    entity,
                    source: source,
                    sketchPlane: sketch.plane,
                    parameters: document.cadDocument.parameters,
                    constructionPlane: constructionPlane
                )
                snapEntities.append(snapEntity)
                candidates += snapEntity.discreteCandidates
                if let closestCandidate = closestCandidate(near: point, entity: snapEntity) {
                    candidates.append(closestCandidate)
                }
                if let referencePoint {
                    candidates += relationCandidates(
                        near: point,
                        referencePoint: referencePoint,
                        entity: snapEntity
                    )
                }
            }
        }
        for firstIndex in snapEntities.indices {
            for secondIndex in snapEntities.index(after: firstIndex) ..< snapEntities.endIndex {
                candidates += intersectionCandidates(
                    first: snapEntities[firstIndex],
                    second: snapEntities[secondIndex]
                )
            }
        }
        let topology = try snapTopologySummary(
            in: document,
            searchRadiusMeters: searchRadiusMeters
        )
        candidates += try measurementCandidates(
            in: document,
            topology: topology,
            constructionPlane: constructionPlane
        )
        candidates += try surfaceFrameCandidates(
            in: document,
            constructionPlane: constructionPlane,
            displays: surfaceFrameDisplays
        )
        candidates += try surfaceTrimCandidates(
            in: document,
            sceneNodeIDsByFeatureID: sceneNodeIDsByFeatureID,
            constructionPlane: constructionPlane
        )
        candidates += try regionCandidates(
            in: document,
            sceneNodeIDsByFeatureID: sceneNodeIDsByFeatureID,
            constructionPlane: constructionPlane
        )
        candidates += topologyCandidates(
            in: topology,
            constructionPlane: constructionPlane
        )
        return candidates.compactMap { candidate in
            var measuredCandidate = candidate
            measuredCandidate.candidate.distanceMeters = distance(point, candidate.candidate.point)
            return measuredCandidate.candidate.distanceMeters <= searchRadiusMeters ? measuredCandidate : nil
        }
    }

    private func regionCandidates(
        in document: DesignDocument,
        sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID],
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> [PrioritizedSnapCandidate] {
        let resolvedParameters = try ParameterResolver().resolve(document.cadDocument.parameters)
        let extractor = SketchProfileExtractor()
        var candidates: [PrioritizedSnapCandidate] = []

        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .profile }),
                  case .sketch(let sketch) = feature.operation else {
                continue
            }
            let profiles: [Profile]
            do {
                profiles = try extractor.extractProfiles(
                    from: sketch,
                    sourceFeatureID: featureID,
                    parameters: resolvedParameters
                )
            } catch is SketchError {
                continue
            } catch is GeometryError {
                continue
            } catch is UnitError {
                continue
            }
            let regionAnalyzer = ProfileRegionAnalyzer()
            for (profileIndex, profile) in profiles.enumerated() {
                let region: ProfileRegionSummary
                do {
                    region = try regionAnalyzer.summary(for: profile)
                } catch {
                    continue
                }
                let regionPoint = try projectedPoint(
                    region.center,
                    from: profile.plane,
                    onto: constructionPlane
                )
                candidates.append(
                    regionCandidate(
                        point: regionPoint,
                        featureID: featureID,
                        sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                        profileIndex: profileIndex
                    )
                )
            }
        }

        return candidates
    }

    private func surfaceFrameCandidates(
        in document: DesignDocument,
        constructionPlane: SketchPlaneCoordinateSystem?,
        displays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    ) throws -> [PrioritizedSnapCandidate] {
        let visibleDisplays = displays.values
            .filter(\.isVisible)
            .sorted { first, second in
                first.id.rawValue.localizedStandardCompare(second.id.rawValue) == .orderedAscending
            }
        guard visibleDisplays.isEmpty == false else {
            return []
        }

        let frames = try SurfaceFrameService().resolveFrames(
            document: document,
            queries: visibleDisplays.map(\.query)
        )
        return zip(visibleDisplays, frames).compactMap { display, frame in
            surfaceFrameCandidate(
                display: display,
                frame: frame,
                constructionPlane: constructionPlane
            )
        }
    }

    private func surfaceTrimCandidates(
        in document: DesignDocument,
        sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID],
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> [PrioritizedSnapCandidate] {
        var candidates: [PrioritizedSnapCandidate] = []
        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case let .bSplineSurface(surfaceFeature) = feature.operation,
                  surfaceFeature.trimLoops.isEmpty == false else {
                continue
            }
            let surfaceReference = SurfaceReference(faceName: PersistentName(components: [
                .feature(featureID),
                .generated("bSplineSurface"),
                .subshape("patch:0:face"),
            ]))
            for (loopIndex, trimLoop) in surfaceFeature.trimLoops.enumerated() {
                for (edgeIndex, edge) in trimLoop.edges.enumerated() {
                    let trimReference = SurfaceTrimReference(
                        surface: surfaceReference,
                        loopIndex: loopIndex,
                        edgeIndex: edgeIndex
                    )
                    let selectionReference = SelectionReference.surface(.trim(trimReference))
                    if let startCandidate = try surfaceTrimEndpointCandidate(
                        selectionReference: selectionReference,
                        endpoint: .start,
                        parameter: edge.startParameter(),
                        surface: surfaceFeature.surface,
                        featureID: featureID,
                        sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                        constructionPlane: constructionPlane
                    ) {
                        candidates.append(startCandidate)
                    }
                    if let endCandidate = try surfaceTrimEndpointCandidate(
                        selectionReference: selectionReference,
                        endpoint: .end,
                        parameter: edge.endParameter(),
                        surface: surfaceFeature.surface,
                        featureID: featureID,
                        sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                        constructionPlane: constructionPlane
                    ) {
                        candidates.append(endCandidate)
                    }
                    for controlPoint in surfaceTrimControlPointParameters(edge.parameterCurve) {
                        if let candidate = try surfaceTrimControlPointCandidate(
                            selectionReference: selectionReference,
                            controlPointIndex: controlPoint.index,
                            parameter: controlPoint.parameter,
                            surface: surfaceFeature.surface,
                            featureID: featureID,
                            sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                            constructionPlane: constructionPlane
                        ) {
                            candidates.append(candidate)
                        }
                    }
                }
            }
        }
        return candidates
    }

    private func surfaceTrimControlPointParameters(
        _ curve: SurfaceParameterCurve
    ) -> [(index: Int, parameter: SurfaceParameter)] {
        switch curve {
        case .constantU, .constantV:
            return []
        case let .polyline(points):
            guard points.count > 2 else {
                return []
            }
            return points.indices.dropFirst().dropLast().map { index in
                (index, points[index])
            }
        case let .bSpline(curve):
            guard curve.controlPoints.count > 2 else {
                return []
            }
            return curve.controlPoints.indices.dropFirst().dropLast().map { index in
                let point = curve.controlPoints[index]
                return (index, SurfaceParameter(u: point.x, v: point.y))
            }
        }
    }

    private func measurementCandidates(
        in document: DesignDocument,
        topology: TopologySnapshot?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> [PrioritizedSnapCandidate] {
        let measurements = document.productMetadata.measurements.values
            .sorted { first, second in
                if first.name != second.name {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.id.description < second.id.description
            }

        var candidates: [PrioritizedSnapCandidate] = []
        for measurement in measurements {
            for (index, anchor) in measurement.anchors.enumerated() {
                if let candidate = try measurementCandidate(
                    measurement: measurement,
                    anchor: anchor,
                    anchorIndex: index,
                    document: document,
                    topology: topology,
                    constructionPlane: constructionPlane
                ) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    private func snapTopologySummary(
        in document: DesignDocument,
        searchRadiusMeters: Double
    ) throws -> TopologySnapshot? {
        guard searchRadiusMeters > 0.0 || measurementsRequireTopology(in: document) else {
            return nil
        }
        return try TopologySnapshotService().snapshot(document: document)
    }

    private func measurementsRequireTopology(in document: DesignDocument) -> Bool {
        document.productMetadata.measurements.values.contains { measurement in
            measurement.anchors.contains { anchor in
                switch anchor.kind {
                case .topologyReference, .topologyEdgeParameter:
                    return true
                case .worldPoint, .sketchReference, .sketchCurveParameter:
                    return false
                }
            }
        }
    }

    private func topologyCandidates(
        in topology: TopologySnapshot?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) -> [PrioritizedSnapCandidate] {
        guard let topology else {
            return []
        }
        return topology.entries.flatMap { entry in
            topologyCandidates(from: entry, constructionPlane: constructionPlane)
        }
    }

    private func topologyCandidates(
        from entry: TopologySummaryResult.Entry,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) -> [PrioritizedSnapCandidate] {
        switch entry.kind {
        case .body:
            return []
        case .face:
            guard let center = entry.center else {
                return []
            }
            return [
                topologyCandidate(
                    kind: .faceCenter,
                    point: center,
                    projectedPoint: projectedTopologyPoint(center, onto: constructionPlane),
                    entry: entry,
                    label: "Face Center",
                    priority: 2,
                    sortSuffix: "center"
                ),
            ].compactMap { $0 }
        case .edge:
            guard let start = entry.start,
                  let end = entry.end else {
                return []
            }
            let midpoint = TopologySummaryResult.Entry.Point(
                x: (start.x + end.x) * 0.5,
                y: (start.y + end.y) * 0.5,
                z: (start.z + end.z) * 0.5
            )
            return [
                topologyCandidate(
                    kind: .edgeStart,
                    point: start,
                    projectedPoint: projectedTopologyPoint(start, onto: constructionPlane),
                    entry: entry,
                    label: "Edge End",
                    priority: 0,
                    sortSuffix: "start"
                ),
                topologyCandidate(
                    kind: .edgeEnd,
                    point: end,
                    projectedPoint: projectedTopologyPoint(end, onto: constructionPlane),
                    entry: entry,
                    label: "Edge End",
                    priority: 0,
                    sortSuffix: "end"
                ),
                topologyCandidate(
                    kind: .edgeMidpoint,
                    point: midpoint,
                    projectedPoint: projectedTopologyPoint(midpoint, onto: constructionPlane),
                    entry: entry,
                    label: "Edge Middle",
                    priority: 0,
                    sortSuffix: "middle"
                ),
            ].compactMap { $0 }
        case .vertex:
            guard let point = entry.start else {
                return []
            }
            if PolySplineSurfaceVertexTarget.canParsePersistentName(entry.persistentName) {
                return [
                    topologyCandidate(
                        kind: .surfaceControlVertex,
                        point: point,
                        projectedPoint: projectedTopologyPoint(point, onto: constructionPlane),
                        entry: entry,
                        label: "Surface CV",
                        priority: -1,
                        sortSuffix: "surfaceControlVertex"
                    ),
                ].compactMap { $0 }
            }
            return [
                topologyCandidate(
                    kind: .topologyVertex,
                    point: point,
                    projectedPoint: projectedTopologyPoint(point, onto: constructionPlane),
                    entry: entry,
                    label: "Vertex",
                    priority: 0,
                    sortSuffix: "vertex"
                ),
            ].compactMap { $0 }
        }
    }

    private func snapEntity(
        _ entity: SketchEntity,
        source: SnapSourceReference,
        sketchPlane: SketchPlane,
        parameters: ParameterTable,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> SnapEntity {
        let axisDirections = try axisDirections(
            sourcePlane: sketchPlane,
            constructionPlane: constructionPlane
        )
        let coordinatePlaneDirections = try coordinatePlaneDirections(
            sourcePlane: sketchPlane,
            constructionPlane: constructionPlane
        )
        switch entity {
        case .point(let point):
            let modelPoint = try modelPoint(
                from: point,
                on: sketchPlane,
                parameters: parameters,
                constructionPlane: constructionPlane
            )
            return SnapEntity(
                source: source,
                geometry: .point(modelPoint),
                axisDirections: axisDirections,
                coordinatePlaneDirections: coordinatePlaneDirections,
                discreteCandidates: [
                    candidate(
                        kind: .sketchPoint,
                        point: modelPoint,
                        label: "Sketch Point",
                        source: source
                    ),
                ]
            )
        case .line(let line):
            let start = try modelPoint(
                from: line.start,
                on: sketchPlane,
                parameters: parameters,
                constructionPlane: constructionPlane
            )
            let end = try modelPoint(
                from: line.end,
                on: sketchPlane,
                parameters: parameters,
                constructionPlane: constructionPlane
            )
            return SnapEntity(
                source: source,
                geometry: .line(start: start, end: end),
                axisDirections: axisDirections,
                coordinatePlaneDirections: coordinatePlaneDirections,
                discreteCandidates: [
                    candidate(kind: .lineStart, point: start, label: "Line Start", source: source),
                    candidate(kind: .lineEnd, point: end, label: "Line End", source: source),
                    candidate(kind: .lineMidpoint, point: midpoint(start, end), label: "Line Midpoint", source: source),
                ]
            )
        case .circle(let circle):
            let localCenter = try localPoint(
                from: circle.center,
                parameters: parameters
            )
            let center = try projectedPoint(
                localCenter,
                from: sketchPlane,
                onto: constructionPlane
            )
            let radius = try resolvedValue(circle.radius, kind: .length, parameters: parameters)
            let quarterAngles = [0.0, Double.pi / 2.0, Double.pi, Double.pi * 1.5]
            let quarterPoints = try quarterAngles.map { angle in
                try projectedPoint(
                    offset(localCenter, radius: radius, angle: angle),
                    from: sketchPlane,
                    onto: constructionPlane
                )
            }
            let geometry = try circularGeometry(
                center: center,
                radius: radius,
                startAngle: nil,
                endAngle: nil,
                localCenter: localCenter,
                sourcePlane: sketchPlane,
                constructionPlane: constructionPlane
            )
            return SnapEntity(
                source: source,
                geometry: geometry,
                axisDirections: axisDirections,
                coordinatePlaneDirections: coordinatePlaneDirections,
                discreteCandidates: [
                    candidate(kind: .circleCenter, point: center, label: "Circle Center", source: source),
                    candidate(kind: .circleQuarter, point: quarterPoints[0], label: "Circle Quarter", source: source),
                    candidate(kind: .circleQuarter, point: quarterPoints[1], label: "Circle Quarter", source: source),
                    candidate(kind: .circleQuarter, point: quarterPoints[2], label: "Circle Quarter", source: source),
                    candidate(kind: .circleQuarter, point: quarterPoints[3], label: "Circle Quarter", source: source),
                ]
            )
        case .arc(let arc):
            let localCenter = try localPoint(
                from: arc.center,
                parameters: parameters
            )
            let center = try projectedPoint(
                localCenter,
                from: sketchPlane,
                onto: constructionPlane
            )
            let radius = try resolvedValue(arc.radius, kind: .length, parameters: parameters)
            let startAngle = try resolvedValue(arc.startAngle, kind: .angle, parameters: parameters)
            let endAngle = try resolvedValue(arc.endAngle, kind: .angle, parameters: parameters)
            let midpointAngle = startAngle + normalizedArcSpan(startAngle: startAngle, endAngle: endAngle) / 2.0
            let startPoint = try projectedPoint(
                offset(localCenter, radius: radius, angle: startAngle),
                from: sketchPlane,
                onto: constructionPlane
            )
            let endPoint = try projectedPoint(
                offset(localCenter, radius: radius, angle: endAngle),
                from: sketchPlane,
                onto: constructionPlane
            )
            let midpoint = try projectedPoint(
                offset(localCenter, radius: radius, angle: midpointAngle),
                from: sketchPlane,
                onto: constructionPlane
            )
            let geometry = try circularGeometry(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                localCenter: localCenter,
                sourcePlane: sketchPlane,
                constructionPlane: constructionPlane
            )
            return SnapEntity(
                source: source,
                geometry: geometry,
                axisDirections: axisDirections,
                coordinatePlaneDirections: coordinatePlaneDirections,
                discreteCandidates: [
                    candidate(kind: .arcCenter, point: center, label: "Arc Center", source: source),
                    candidate(kind: .arcStart, point: startPoint, label: "Arc Start", source: source),
                    candidate(kind: .arcEnd, point: endPoint, label: "Arc End", source: source),
                    candidate(kind: .arcMidpoint, point: midpoint, label: "Arc Midpoint", source: source),
                ]
            )
        case .spline(let spline):
            let controlPoints = try spline.controlPoints.map {
                try modelPoint(
                    from: $0,
                    on: sketchPlane,
                    parameters: parameters,
                    constructionPlane: constructionPlane
                )
            }
            let discreteCandidates = controlPoints.enumerated().map { index, controlPoint in
                let kind: SnapCandidateKind
                if index == 0 {
                    kind = .splineStart
                } else if index == controlPoints.count - 1 {
                    kind = .splineEnd
                } else {
                    kind = .controlVertex
                }
                var indexedSource = source
                indexedSource.controlPointIndex = index
                return candidate(
                    kind: kind,
                    point: controlPoint,
                    label: kind == .controlVertex ? "CV" : "Spline Endpoint",
                    source: indexedSource
                )
            }
            return SnapEntity(
                source: source,
                geometry: .spline(controlPoints: controlPoints),
                axisDirections: axisDirections,
                coordinatePlaneDirections: coordinatePlaneDirections,
                discreteCandidates: discreteCandidates
            )
        }
    }

    private func sceneNodeIDsByFeatureID(in document: DesignDocument) -> [FeatureID: SceneNodeID] {
        var mapping: [FeatureID: SceneNodeID] = [:]
        for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
            guard let featureID = sceneNode.reference?.featureID else {
                continue
            }
            mapping[featureID] = sceneNodeID
        }
        return mapping
    }

    private func closestCandidate(
        near point: Point2D,
        entity: SnapEntity
    ) -> PrioritizedSnapCandidate? {
        let snapPoint: Point2D
        let kind: SnapCandidateKind
        switch entity.geometry {
        case .point:
            return nil
        case .line(let start, let end):
            snapPoint = closestPoint(onSegmentFrom: start, to: end, near: point)
            kind = .lineClosest
        case .circle(let center, let radius):
            guard let projected = closestPoint(onCircleCenter: center, radius: radius, near: point) else {
                return nil
            }
            snapPoint = projected
            kind = .circleClosest
        case .arc(let center, let radius, let startAngle, let endAngle):
            snapPoint = closestPoint(
                onArcCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                near: point
            )
            kind = .arcClosest
        case .spline(let controlPoints):
            guard let projected = closestPoint(onSplineControlPoints: controlPoints, near: point) else {
                return nil
            }
            snapPoint = projected
            kind = .splineClosest
        case .polyline(let points):
            guard let projected = closestPoint(onPolyline: points, near: point) else {
                return nil
            }
            snapPoint = projected
            kind = .splineClosest
        }
        return candidate(
            kind: kind,
            point: snapPoint,
            label: "Closest",
            source: entity.source,
            priority: 4
        )
    }

    private func relationCandidates(
        near point: Point2D,
        referencePoint: Point2D,
        entity: SnapEntity
    ) -> [PrioritizedSnapCandidate] {
        let groups: [(
            kind: SnapCandidateKind,
            label: String,
            axis: SnapAxisKind?,
            coordinatePlane: SnapCoordinatePlaneKind?,
            priority: Int,
            points: [Point2D]
        )] =
            entity.axisDirections.map { axisDirection in
                (
                    kind: .curveAxis,
                    label: axisDirection.kind.label,
                    axis: axisDirection.kind,
                    coordinatePlane: nil,
                    priority: axisDirection.priority,
                    points: axisPoints(
                        from: referencePoint,
                        direction: axisDirection.direction,
                        on: entity.geometry
                    )
                )
            } +
            entity.coordinatePlaneDirections.map { coordinatePlaneDirection in
                (
                    kind: .curveCoordinatePlane,
                    label: coordinatePlaneDirection.kind.label,
                    axis: nil,
                    coordinatePlane: coordinatePlaneDirection.kind,
                    priority: 3,
                    points: axisPoints(
                        from: referencePoint,
                        direction: coordinatePlaneDirection.direction,
                        on: entity.geometry
                    )
                )
            } + [
            (
                kind: .curvePerpendicular,
                label: "Perpendicular",
                axis: nil,
                coordinatePlane: nil,
                priority: 2,
                points: perpendicularPoints(from: referencePoint, on: entity.geometry)
            ),
            (
                kind: .curveTangent,
                label: "Tangent",
                axis: nil,
                coordinatePlane: nil,
                priority: 2,
                points: tangentPoints(from: referencePoint, near: point, on: entity.geometry)
            ),
        ]

        var candidates: [PrioritizedSnapCandidate] = []
        for group in groups {
            for snapPoint in uniquePoints(group.points) {
                guard isFinite(snapPoint),
                      distance(snapPoint, referencePoint) > 1.0e-10 else {
                    continue
                }
                candidates.append(
                    candidate(
                        kind: group.kind,
                        point: snapPoint,
                        label: group.label,
                        source: entity.source,
                        axisSource: group.axis.map {
                            SnapAxisReference(kind: $0, referencePoint: referencePoint)
                        },
                        coordinatePlaneSource: group.coordinatePlane.map {
                            SnapCoordinatePlaneReference(kind: $0, referencePoint: referencePoint)
                        },
                        priority: group.priority
                    )
                )
            }
        }
        return candidates
    }

    private func intersectionCandidates(
        first: SnapEntity,
        second: SnapEntity
    ) -> [PrioritizedSnapCandidate] {
        intersectionPoints(first.geometry, second.geometry)
            .filter { point in
                contains(point, in: first.geometry) && contains(point, in: second.geometry)
            }
            .reduce(into: [Point2D]()) { uniquePoints, point in
                guard uniquePoints.contains(where: { distance($0, point) <= 1.0e-10 }) == false else {
                    return
                }
                uniquePoints.append(point)
            }
            .map { point in
                candidate(
                    kind: .curveIntersection,
                    point: point,
                    label: "Intersection",
                    source: first.source,
                    relatedSource: second.source,
                    priority: 1
                )
            }
    }

    private func perpendicularPoints(
        from referencePoint: Point2D,
        on geometry: SnapGeometry
    ) -> [Point2D] {
        switch geometry {
        case .point:
            return []
        case .line(let start, let end):
            return [closestPoint(onSegmentFrom: start, to: end, near: referencePoint)]
        case .circle(let center, let radius):
            return radialCirclePoints(from: referencePoint, center: center, radius: radius)
        case .arc(let center, let radius, let startAngle, let endAngle):
            return radialCirclePoints(from: referencePoint, center: center, radius: radius)
                .filter { point in
                    angleIsOnArc(
                        atan2(point.y - center.y, point.x - center.x),
                        startAngle: startAngle,
                        endAngle: endAngle
                    )
                }
        case .spline(let controlPoints):
            return splineRelationPoints(
                from: referencePoint,
                controlPoints: controlPoints,
                relation: .perpendicular
            )
        case .polyline(let points):
            return closestPoint(onPolyline: points, near: referencePoint).map { [$0] } ?? []
        }
    }

    private func tangentPoints(
        from referencePoint: Point2D,
        near point: Point2D,
        on geometry: SnapGeometry
    ) -> [Point2D] {
        switch geometry {
        case .point:
            return []
        case .line(let start, let end):
            guard pointIsOnInfiniteLine(referencePoint, start: start, end: end) else {
                return []
            }
            return [closestPoint(onSegmentFrom: start, to: end, near: point)]
        case .circle(let center, let radius):
            return tangentCirclePoints(from: referencePoint, center: center, radius: radius)
        case .arc(let center, let radius, let startAngle, let endAngle):
            return tangentCirclePoints(from: referencePoint, center: center, radius: radius)
                .filter { point in
                    angleIsOnArc(
                        atan2(point.y - center.y, point.x - center.x),
                        startAngle: startAngle,
                        endAngle: endAngle
                    )
                }
        case .spline(let controlPoints):
            return splineRelationPoints(
                from: referencePoint,
                controlPoints: controlPoints,
                relation: .tangent
            )
        case .polyline(let points):
            return tangentPolylinePoints(
                from: referencePoint,
                near: point,
                points: points
            )
        }
    }

    private func axisPoints(
        from referencePoint: Point2D,
        direction: Point2D,
        on geometry: SnapGeometry
    ) -> [Point2D] {
        switch geometry {
        case .point:
            return []
        case .line(let start, let end):
            return axisLineSegmentIntersection(
                referencePoint: referencePoint,
                direction: direction,
                segmentStart: start,
                segmentEnd: end
            ).map { [$0] } ?? []
        case .circle(let center, let radius):
            return axisCircleIntersections(
                referencePoint: referencePoint,
                direction: direction,
                center: center,
                radius: radius
            )
        case .arc(let center, let radius, let startAngle, let endAngle):
            return axisCircleIntersections(
                referencePoint: referencePoint,
                direction: direction,
                center: center,
                radius: radius
            )
            .filter { point in
                angleIsOnArc(
                    atan2(point.y - center.y, point.x - center.x),
                    startAngle: startAngle,
                    endAngle: endAngle
                )
            }
        case .spline(let controlPoints):
            return splineAxisPoints(
                referencePoint: referencePoint,
                direction: direction,
                controlPoints: controlPoints
            )
        case .polyline(let points):
            return polylineAxisPoints(
                referencePoint: referencePoint,
                direction: direction,
                points: points
            )
        }
    }

    private func gridCandidate(
        near point: Point2D,
        intervalMeters: Double
    ) -> PrioritizedSnapCandidate {
        let snappedPoint = CADInputValueNormalizer.standard.point(
            Point2D(
                x: (point.x / intervalMeters).rounded() * intervalMeters,
                y: (point.y / intervalMeters).rounded() * intervalMeters
            )
        )
        return PrioritizedSnapCandidate(
            priority: 10,
            sortKey: "grid",
            candidate: SnapCandidate(
                kind: .grid,
                point: snappedPoint,
                distanceMeters: distance(point, snappedPoint),
                label: "Grid"
            )
        )
    }

    private func referenceLineCandidates(
        near point: Point2D,
        anchors: [SketchReferenceLineAnchor],
        searchRadiusMeters: Double
    ) -> [PrioritizedSnapCandidate] {
        anchors.enumerated().flatMap { index, anchor in
            let horizontalPoint = Point2D(x: point.x, y: anchor.point.y)
            let verticalPoint = Point2D(x: anchor.point.x, y: point.y)
            return [
                referenceLineCandidate(
                    point: horizontalPoint,
                    distanceMeters: abs(point.y - anchor.point.y),
                    label: "Reference X",
                    sortKey: "reference:\(index):x"
                ),
                referenceLineCandidate(
                    point: verticalPoint,
                    distanceMeters: abs(point.x - anchor.point.x),
                    label: "Reference Y",
                    sortKey: "reference:\(index):y"
                ),
            ]
        }
        .filter { candidate in
            candidate.candidate.distanceMeters <= searchRadiusMeters
        }
    }

    private func referenceLineCandidate(
        point: Point2D,
        distanceMeters: Double,
        label: String,
        sortKey: String
    ) -> PrioritizedSnapCandidate {
        PrioritizedSnapCandidate(
            priority: 3,
            sortKey: sortKey,
            candidate: SnapCandidate(
                kind: .referenceLine,
                point: point,
                distanceMeters: distanceMeters,
                label: label
            )
        )
    }

    private func regionCandidate(
        point: Point2D,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID?,
        profileIndex: Int
    ) -> PrioritizedSnapCandidate {
        PrioritizedSnapCandidate(
            priority: 2,
            sortKey: [
                "region",
                featureID.description,
                String(profileIndex),
            ].joined(separator: ":"),
            candidate: SnapCandidate(
                kind: .regionCenter,
                point: point,
                distanceMeters: 0.0,
                label: "Region Center",
                regionSource: SnapRegionReference(
                    sceneNodeID: sceneNodeID,
                    featureID: featureID,
                    profileIndex: profileIndex,
                    center: point
                )
            )
        )
    }

    private func measurementCandidate(
        measurement: MeasurementAnnotation,
        anchor: MeasurementAnchor,
        anchorIndex: Int,
        document: DesignDocument,
        topology: TopologySnapshot?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> PrioritizedSnapCandidate? {
        guard let resolvedAnchor = try resolvedMeasurementAnchor(
            anchor,
            in: document,
            topology: topology,
            constructionPlane: constructionPlane
        ) else {
            return nil
        }
        let snapPoint = resolvedAnchor.point
        guard isFinite(snapPoint) else {
            return nil
        }
        return PrioritizedSnapCandidate(
            priority: 2,
            sortKey: [
                "measurement",
                measurement.id.description,
                String(anchorIndex),
                anchor.role.rawValue,
            ].joined(separator: ":"),
            candidate: SnapCandidate(
                kind: .measurementPoint,
                point: snapPoint,
                distanceMeters: 0.0,
                label: "Measurement",
                measurementSource: SnapMeasurementReference(
                    measurementID: measurement.id,
                    sceneNodeID: measurement.sceneNodeID,
                    name: measurement.name,
                    kind: measurement.kind,
                    anchorIndex: anchorIndex,
                    role: anchor.role,
                    worldPoint: resolvedAnchor.worldPoint,
                    anchorKind: anchor.kind,
                    sketchReference: anchor.sketchReference,
                    topologyReference: anchor.topologyReference,
                    sketchCurveParameter: anchor.sketchCurveParameter,
                    topologyEdgeParameter: anchor.topologyEdgeParameter
                )
            )
        )
    }

    private func resolvedMeasurementAnchor(
        _ anchor: MeasurementAnchor,
        in document: DesignDocument,
        topology: TopologySnapshot?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> (worldPoint: Point3D, point: Point2D)? {
        guard let worldPoint = try MeasurementAnchorWorldPointResolver(
            curveSampler: curveSampler
        ).worldPoint(
            for: anchor,
            in: document,
            topology: topology
        ) else {
            return nil
        }
        return (
            worldPoint: worldPoint,
            point: projectedMeasurementPoint(worldPoint, onto: constructionPlane)
        )
    }

    private func topologyCandidate(
        kind: SnapCandidateKind,
        point: TopologySummaryResult.Entry.Point,
        projectedPoint: Point2D? = nil,
        entry: TopologySummaryResult.Entry,
        label: String,
        priority: Int,
        sortSuffix: String
    ) -> PrioritizedSnapCandidate? {
        guard let target = entry.selectionTarget() else {
            return nil
        }
        let snapPoint = projectedPoint ?? projectedTopologyPoint(point, onto: nil)
        guard isFinite(snapPoint) else {
            return nil
        }
        let topologyReference = SnapTopologyReference(
            sceneNodeID: target.sceneNodeID,
            component: target.component,
            kind: entry.kind,
            persistentName: entry.persistentName,
            referenceID: entry.referenceID,
            worldPoint: point
        )
        return PrioritizedSnapCandidate(
            priority: priority,
            sortKey: [
                "topology",
                entry.kind.rawValue,
                entry.persistentName,
                sortSuffix,
                kind.rawValue,
            ].joined(separator: ":"),
            candidate: SnapCandidate(
                kind: kind,
                point: snapPoint,
                distanceMeters: 0.0,
                label: label,
                topologySource: topologyReference
            )
        )
    }

    private func surfaceFrameCandidate(
        display: SurfaceFrameDisplay,
        frame: SurfaceFrameResult.Frame,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) -> PrioritizedSnapCandidate? {
        let worldPoint = Point3D(
            x: frame.position.x,
            y: frame.position.y,
            z: frame.position.z
        )
        guard isFinite(worldPoint) else {
            return nil
        }
        let snapPoint = projectedSurfaceFramePoint(worldPoint, onto: constructionPlane)
        guard isFinite(snapPoint) else {
            return nil
        }
        return PrioritizedSnapCandidate(
            priority: -1,
            sortKey: [
                "surfaceFrame",
                display.id.rawValue,
            ].joined(separator: ":"),
            candidate: SnapCandidate(
                kind: .surfaceFrame,
                point: snapPoint,
                distanceMeters: 0.0,
                label: "Surface Frame",
                surfaceFrameSource: SnapSurfaceFrameReference(
                    displayID: display.id,
                    query: display.query,
                    faceID: frame.faceID,
                    facePersistentNames: frame.facePersistentNames,
                    sourceFeatureID: frame.sourceFeatureID,
                    sceneNodeID: frame.sceneNodeID,
                    u: frame.u,
                    v: frame.v,
                    worldPoint: worldPoint,
                    uAxis: frame.uAxis,
                    vAxis: frame.vAxis,
                    normal: frame.normal
                )
            )
        )
    }

    private func surfaceTrimEndpointCandidate(
        selectionReference: SelectionReference,
        endpoint: SurfaceTrimEndpoint,
        parameter: SurfaceParameter,
        surface: BSplineSurface3D,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> PrioritizedSnapCandidate? {
        try surfaceTrimCandidate(
            kind: .surfaceTrimEndpoint,
            label: endpoint == .start ? "Surface Trim Start" : "Surface Trim End",
            pointKind: .endpoint,
            selectionReference: selectionReference,
            endpoint: endpoint,
            controlPointIndex: nil,
            parameter: parameter,
            surface: surface,
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            constructionPlane: constructionPlane
        )
    }

    private func surfaceTrimControlPointCandidate(
        selectionReference: SelectionReference,
        controlPointIndex: Int,
        parameter: SurfaceParameter,
        surface: BSplineSurface3D,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> PrioritizedSnapCandidate? {
        try surfaceTrimCandidate(
            kind: .surfaceTrimControlPoint,
            label: "Surface Trim CP",
            pointKind: .controlPoint,
            selectionReference: selectionReference,
            endpoint: nil,
            controlPointIndex: controlPointIndex,
            parameter: parameter,
            surface: surface,
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            constructionPlane: constructionPlane
        )
    }

    private func surfaceTrimCandidate(
        kind: SnapCandidateKind,
        label: String,
        pointKind: SnapSurfaceTrimPointKind,
        selectionReference: SelectionReference,
        endpoint: SurfaceTrimEndpoint?,
        controlPointIndex: Int?,
        parameter: SurfaceParameter,
        surface: BSplineSurface3D,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID?,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> PrioritizedSnapCandidate? {
        guard parameter.u.isFinite, parameter.v.isFinite else {
            return nil
        }
        let geometry = try surface.differentialGeometry(atU: parameter.u, v: parameter.v)
        let worldPoint = geometry.position
        guard isFinite(worldPoint),
              let uAxis = normalized(geometry.tangentU),
              let vAxis = normalized(geometry.tangentV),
              let normal = normalized(uAxis.cross(vAxis)) else {
            return nil
        }
        let snapPoint = projectedSurfaceTrimPoint(worldPoint, onto: constructionPlane)
        guard isFinite(snapPoint) else {
            return nil
        }
        return PrioritizedSnapCandidate(
            priority: -1,
            sortKey: [
                "surfaceTrim",
                featureID.description,
                String(describing: selectionReference),
                endpoint?.rawValue ?? "controlPoint:\(controlPointIndex ?? -1)",
            ].joined(separator: ":"),
            candidate: SnapCandidate(
                kind: kind,
                point: snapPoint,
                distanceMeters: 0.0,
                label: label,
                surfaceTrimSource: SnapSurfaceTrimReference(
                    kind: pointKind,
                    selectionReference: selectionReference,
                    endpoint: endpoint,
                    controlPointIndex: controlPointIndex,
                    sourceFeatureID: featureID.description,
                    sceneNodeID: sceneNodeID,
                    u: parameter.u,
                    v: parameter.v,
                    worldPoint: worldPoint,
                    uAxis: vector(uAxis),
                    vAxis: vector(vAxis),
                    normal: vector(normal)
                )
            )
        )
    }

    private func candidate(
        kind: SnapCandidateKind,
        point: Point2D,
        label: String,
        source: SnapSourceReference,
        relatedSource: SnapSourceReference? = nil,
        axisSource: SnapAxisReference? = nil,
        coordinatePlaneSource: SnapCoordinatePlaneReference? = nil,
        priority: Int = 0
    ) -> PrioritizedSnapCandidate {
        PrioritizedSnapCandidate(
            priority: priority,
            sortKey: sortKey(
                kind: kind,
                point: point,
                source: source
            ),
            candidate: SnapCandidate(
                kind: kind,
                point: point,
                distanceMeters: 0.0,
                label: label,
                source: source,
                relatedSource: relatedSource,
                axisSource: axisSource,
                coordinatePlaneSource: coordinatePlaneSource
            )
        )
    }

    private func projectedTopologyPoint(
        _ point: TopologySummaryResult.Entry.Point,
        onto constructionPlane: SketchPlaneCoordinateSystem?
    ) -> Point2D {
        let worldPoint = Point3D(x: point.x, y: point.y, z: point.z)
        guard let constructionPlane else {
            return Point2D(x: point.x, y: point.y)
        }
        return constructionPlane.project(worldPoint).point
    }

    private func projectedMeasurementPoint(
        _ point: Point3D,
        onto constructionPlane: SketchPlaneCoordinateSystem?
    ) -> Point2D {
        guard let constructionPlane else {
            return Point2D(x: point.x, y: point.y)
        }
        return constructionPlane.project(point).point
    }

    private func projectedSurfaceFramePoint(
        _ point: Point3D,
        onto constructionPlane: SketchPlaneCoordinateSystem?
    ) -> Point2D {
        guard let constructionPlane else {
            return Point2D(x: point.x, y: point.y)
        }
        return constructionPlane.project(point).point
    }

    private func projectedSurfaceTrimPoint(
        _ point: Point3D,
        onto constructionPlane: SketchPlaneCoordinateSystem?
    ) -> Point2D {
        guard let constructionPlane else {
            return Point2D(x: point.x, y: point.y)
        }
        return constructionPlane.project(point).point
    }

    private func normalized(_ vector: Vector3D) -> Vector3D? {
        let length = vector.length
        guard length > 1.0e-12 else {
            return nil
        }
        return Vector3D(
            x: vector.x / length,
            y: vector.y / length,
            z: vector.z / length
        )
    }

    private func vector(_ vector: Vector3D) -> SurfaceAnalysisResult.Vector {
        SurfaceAnalysisResult.Vector(
            x: vector.x,
            y: vector.y,
            z: vector.z
        )
    }

    private func modelPoint(
        from point: SketchPoint,
        on plane: SketchPlane,
        parameters: ParameterTable,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> Point2D {
        try projectedPoint(
            localPoint(from: point, parameters: parameters),
            from: plane,
            onto: constructionPlane
        )
    }

    private func localPoint(
        from point: SketchPoint,
        parameters: ParameterTable
    ) throws -> Point2D {
        Point2D(
            x: try resolvedValue(point.x, kind: .length, parameters: parameters),
            y: try resolvedValue(point.y, kind: .length, parameters: parameters)
        )
    }

    private func projectedPoint(
        _ localPoint: Point2D,
        from sourcePlane: SketchPlane,
        onto constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> Point2D {
        guard let constructionPlane else {
            return canvasPoint(from: localPoint, on: sourcePlane)
        }
        let sourceSystem = try SketchPlaneCoordinateSystem(plane: sourcePlane)
        let worldPoint = sourceSystem.point(from: localPoint)
        return constructionPlane.project(worldPoint).point
    }

    private func constructionPlaneCoordinateSystem(
        from options: ValidatedSnapResolutionOptions,
        document _: DesignDocument
    ) throws -> SketchPlaneCoordinateSystem? {
        guard let plane = options.constructionPlane else {
            return nil
        }
        return try SketchPlaneCoordinateSystem(plane: plane)
    }

    private func axisDirections(
        sourcePlane: SketchPlane,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> [SnapAxisDirection] {
        let coordinateSystem: SketchPlaneCoordinateSystem
        if let constructionPlane {
            coordinateSystem = constructionPlane
        } else {
            coordinateSystem = try SketchPlaneCoordinateSystem(plane: sourcePlane)
        }
        return [SnapAxisKind.x, .y, .z].compactMap { kind in
            guard var axisDirection = axisDirection(kind, on: coordinateSystem) else {
                return nil
            }
            axisDirection.priority = referenceAxisPriority(
                kind,
                sourcePlane: sourcePlane,
                usesConstructionPlane: constructionPlane != nil
            )
            if constructionPlane != nil {
                return axisDirection
            }
            guard let direction = normalizedCanvasDirection(
                fromLocal: axisDirection.direction,
                on: sourcePlane
            ) else {
                return nil
            }
            return SnapAxisDirection(
                kind: kind,
                priority: axisDirection.priority,
                direction: direction
            )
        }
    }

    private func coordinatePlaneDirections(
        sourcePlane: SketchPlane,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> [SnapCoordinatePlaneDirection] {
        let coordinateSystem: SketchPlaneCoordinateSystem
        if let constructionPlane {
            coordinateSystem = constructionPlane
        } else {
            coordinateSystem = try SketchPlaneCoordinateSystem(plane: sourcePlane)
        }
        return [SnapCoordinatePlaneKind.xy, .yz, .zx].compactMap { kind in
            guard let coordinatePlaneDirection = coordinatePlaneDirection(kind, on: coordinateSystem) else {
                return nil
            }
            if constructionPlane != nil {
                return coordinatePlaneDirection
            }
            guard let direction = normalizedCanvasDirection(
                fromLocal: coordinatePlaneDirection.direction,
                on: sourcePlane
            ) else {
                return nil
            }
            return SnapCoordinatePlaneDirection(kind: kind, direction: direction)
        }
    }

    private func axisDirection(
        _ kind: SnapAxisKind,
        on coordinateSystem: SketchPlaneCoordinateSystem
    ) -> SnapAxisDirection? {
        let worldAxis = worldAxisVector(for: kind)
        let projected = worldAxis - coordinateSystem.normal * worldAxis.dot(coordinateSystem.normal)
        let localX = projected.dot(coordinateSystem.u)
        let localY = projected.dot(coordinateSystem.v)
        let length = hypot(localX, localY)
        guard length > 1.0e-12 else {
            return nil
        }
        return SnapAxisDirection(
            kind: kind,
            priority: 2,
            direction: Point2D(x: localX / length, y: localY / length)
        )
    }

    private func referenceAxisPriority(
        _ kind: SnapAxisKind,
        sourcePlane: SketchPlane,
        usesConstructionPlane: Bool
    ) -> Int {
        if usesConstructionPlane {
            return -2
        }
        switch sourcePlane {
        case .xy:
            return kind == .x ? -2 : 2
        case .yz:
            return kind == .y ? -2 : 2
        case .zx:
            return kind == .x ? -2 : 2
        case .plane:
            return -2
        }
    }

    private func coordinatePlaneDirection(
        _ kind: SnapCoordinatePlaneKind,
        on coordinateSystem: SketchPlaneCoordinateSystem
    ) -> SnapCoordinatePlaneDirection? {
        let planeNormal = coordinatePlaneNormal(for: kind)
        let localNormalX = planeNormal.dot(coordinateSystem.u)
        let localNormalY = planeNormal.dot(coordinateSystem.v)
        let length = hypot(localNormalX, localNormalY)
        guard length > 1.0e-12 else {
            return nil
        }
        return SnapCoordinatePlaneDirection(
            kind: kind,
            direction: Point2D(
                x: -localNormalY / length,
                y: localNormalX / length
            )
        )
    }

    private func worldAxisVector(for kind: SnapAxisKind) -> Vector3D {
        switch kind {
        case .x:
            return .unitX
        case .y:
            return .unitY
        case .z:
            return .unitZ
        }
    }

    private func coordinatePlaneNormal(for kind: SnapCoordinatePlaneKind) -> Vector3D {
        switch kind {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        }
    }

    private func canvasPoint(
        from localPoint: Point2D,
        on plane: SketchPlane
    ) -> Point2D {
        SketchPlaneCanvasMapper(sketchPlane: plane)
            .canvasPoint(fromLocal: localPoint)
    }

    private func normalizedCanvasDirection(
        fromLocal direction: Point2D,
        on plane: SketchPlane
    ) -> Point2D? {
        SketchPlaneCanvasMapper(sketchPlane: plane)
            .normalizedCanvasDirection(fromLocal: direction)
    }

    private func resolvedValue(
        _ expression: CADExpression,
        kind: QuantityKind,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == kind else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Snap resolver expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func midpoint(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(
            x: (first.x + second.x) / 2.0,
            y: (first.y + second.y) / 2.0
        )
    }

    private func offset(_ center: Point2D, radius: Double, angle: Double) -> Point2D {
        Point2D(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func circularGeometry(
        center: Point2D,
        radius: Double,
        startAngle: Double?,
        endAngle: Double?,
        localCenter: Point2D,
        sourcePlane: SketchPlane,
        constructionPlane: SketchPlaneCoordinateSystem?
    ) throws -> SnapGeometry {
        guard let constructionPlane,
              try circularProjectionRequiresPolyline(from: sourcePlane, onto: constructionPlane) else {
            if let startAngle, let endAngle {
                return .arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
            }
            return .circle(center: center, radius: radius)
        }
        return .polyline(
            points: try projectedCircularSamples(
                localCenter: localCenter,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                sourcePlane: sourcePlane,
                constructionPlane: constructionPlane
            )
        )
    }

    private func circularProjectionRequiresPolyline(
        from sourcePlane: SketchPlane,
        onto constructionPlane: SketchPlaneCoordinateSystem
    ) throws -> Bool {
        let sourceSystem = try SketchPlaneCoordinateSystem(plane: sourcePlane)
        return sourceSystem.projectsParallel(to: constructionPlane) == false
    }

    private func projectedCircularSamples(
        localCenter: Point2D,
        radius: Double,
        startAngle: Double?,
        endAngle: Double?,
        sourcePlane: SketchPlane,
        constructionPlane: SketchPlaneCoordinateSystem
    ) throws -> [Point2D] {
        let span = startAngle.flatMap { start in
            endAngle.map { normalizedArcSpan(startAngle: start, endAngle: $0) }
        } ?? Double.pi * 2.0
        let start = startAngle ?? 0.0
        let sampleCount = max(16, Int(ceil(span / (Double.pi / 24.0))))
        return try (0 ... sampleCount).map { index in
            let ratio = Double(index) / Double(sampleCount)
            let angle = start + span * ratio
            return try projectedPoint(
                offset(localCenter, radius: radius, angle: angle),
                from: sourcePlane,
                onto: constructionPlane
            )
        }
    }

    private func closestPoint(
        onSegmentFrom start: Point2D,
        to end: Point2D,
        near point: Point2D
    ) -> Point2D {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 1.0e-24 else {
            return start
        }
        let t = max(
            0.0,
            min(
                1.0,
                ((point.x - start.x) * segmentX + (point.y - start.y) * segmentY) / lengthSquared
            )
        )
        return Point2D(
            x: start.x + segmentX * t,
            y: start.y + segmentY * t
        )
    }

    private func closestPoint(
        onCircleCenter center: Point2D,
        radius: Double,
        near point: Point2D
    ) -> Point2D? {
        let deltaX = point.x - center.x
        let deltaY = point.y - center.y
        let length = hypot(deltaX, deltaY)
        guard radius > 1.0e-12, length > 1.0e-12 else {
            return nil
        }
        return Point2D(
            x: center.x + deltaX / length * radius,
            y: center.y + deltaY / length * radius
        )
    }

    private func closestPoint(
        onArcCenter center: Point2D,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        near point: Point2D
    ) -> Point2D {
        guard let circlePoint = closestPoint(onCircleCenter: center, radius: radius, near: point) else {
            return offset(center, radius: radius, angle: startAngle)
        }
        let angle = atan2(circlePoint.y - center.y, circlePoint.x - center.x)
        let span = normalizedArcSpan(startAngle: startAngle, endAngle: endAngle)
        let delta = normalizedAngleDelta(from: startAngle, to: angle)
        if delta <= span {
            return circlePoint
        }
        let start = offset(center, radius: radius, angle: startAngle)
        let end = offset(center, radius: radius, angle: endAngle)
        return distance(point, start) <= distance(point, end) ? start : end
    }

    private func closestPoint(
        onSplineControlPoints controlPoints: [Point2D],
        near point: Point2D
    ) -> Point2D? {
        let samples = curveSampler.splineSamples(for: controlPoints).map(\.point)
        guard samples.count >= 2 else {
            return nil
        }
        var closestPoint = samples[0]
        var closestDistance = distance(point, closestPoint)
        for index in 1 ..< samples.count {
            let projected = self.closestPoint(
                onSegmentFrom: samples[index - 1],
                to: samples[index],
                near: point
            )
            let projectedDistance = distance(point, projected)
            if projectedDistance < closestDistance {
                closestPoint = projected
                closestDistance = projectedDistance
            }
        }
        return closestPoint
    }

    private func closestPoint(
        onPolyline points: [Point2D],
        near point: Point2D
    ) -> Point2D? {
        guard points.count >= 2 else {
            return nil
        }
        var nearestPoint = points[0]
        var closestDistance = distance(point, nearestPoint)
        for index in 1 ..< points.count {
            let projected = closestPoint(
                onSegmentFrom: points[index - 1],
                to: points[index],
                near: point
            )
            let projectedDistance = distance(point, projected)
            if projectedDistance < closestDistance {
                nearestPoint = projected
                closestDistance = projectedDistance
            }
        }
        return nearestPoint
    }

    private func radialCirclePoints(
        from referencePoint: Point2D,
        center: Point2D,
        radius: Double
    ) -> [Point2D] {
        guard radius > 1.0e-12,
              distance(referencePoint, center) > 1.0e-12 else {
            return []
        }
        let angle = atan2(referencePoint.y - center.y, referencePoint.x - center.x)
        return [
            offset(center, radius: radius, angle: angle),
            offset(center, radius: radius, angle: angle + Double.pi),
        ]
    }

    private func tangentCirclePoints(
        from referencePoint: Point2D,
        center: Point2D,
        radius: Double
    ) -> [Point2D] {
        let centerDistance = distance(referencePoint, center)
        guard radius > 1.0e-12,
              centerDistance > radius + 1.0e-12 else {
            return []
        }
        let baseAngle = atan2(referencePoint.y - center.y, referencePoint.x - center.x)
        let tangentOffset = acos(max(-1.0, min(1.0, radius / centerDistance)))
        return [
            offset(center, radius: radius, angle: baseAngle - tangentOffset),
            offset(center, radius: radius, angle: baseAngle + tangentOffset),
        ]
    }

    private func pointIsOnInfiniteLine(
        _ point: Point2D,
        start: Point2D,
        end: Point2D
    ) -> Bool {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = hypot(deltaX, deltaY)
        guard length > 1.0e-12 else {
            return false
        }
        let cross = (point.x - start.x) * deltaY - (point.y - start.y) * deltaX
        return abs(cross) / length <= 1.0e-8
    }

    private func tangentPolylinePoints(
        from referencePoint: Point2D,
        near point: Point2D,
        points: [Point2D]
    ) -> [Point2D] {
        guard points.count >= 2 else {
            return []
        }
        var candidates: [Point2D] = []
        for index in 1 ..< points.count {
            let start = points[index - 1]
            let end = points[index]
            guard pointIsOnInfiniteLine(referencePoint, start: start, end: end) else {
                continue
            }
            candidates.append(
                closestPoint(onSegmentFrom: start, to: end, near: point)
            )
        }
        return uniquePoints(candidates)
    }

    private func polylineAxisPoints(
        referencePoint: Point2D,
        direction: Point2D,
        points: [Point2D]
    ) -> [Point2D] {
        guard points.count >= 2 else {
            return []
        }
        let intersections = points.indices.dropFirst().compactMap { index in
            axisLineSegmentIntersection(
                referencePoint: referencePoint,
                direction: direction,
                segmentStart: points[index - 1],
                segmentEnd: points[index]
            )
        }
        return uniquePoints(intersections)
    }

    private func splineRelationPoints(
        from referencePoint: Point2D,
        controlPoints: [Point2D],
        relation: SnapCurveRelation
    ) -> [Point2D] {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let sampleCount = max(curveSampler.samplesPerSegment * 2, 32)
        var points: [Point2D] = []

        for segmentIndex in 0 ..< segmentCount {
            guard var previous = splineRelationValue(
                referencePoint: referencePoint,
                controlPoints: controlPoints,
                segmentIndex: segmentIndex,
                t: 0.0,
                relation: relation
            ) else {
                continue
            }
            if abs(previous.value) <= 1.0e-10 {
                points.append(previous.point)
            }
            for sampleIndex in 1 ... sampleCount {
                let t = Double(sampleIndex) / Double(sampleCount)
                guard let current = splineRelationValue(
                    referencePoint: referencePoint,
                    controlPoints: controlPoints,
                    segmentIndex: segmentIndex,
                    t: t,
                    relation: relation
                ) else {
                    continue
                }
                if abs(current.value) <= 1.0e-10 {
                    points.append(current.point)
                } else if previous.value * current.value < 0.0,
                          let root = splineRelationRoot(
                              referencePoint: referencePoint,
                              controlPoints: controlPoints,
                              segmentIndex: segmentIndex,
                              lowerT: previous.t,
                              lowerValue: previous.value,
                              upperT: current.t,
                              relation: relation
                          ) {
                    points.append(root)
                }
                previous = current
            }
        }

        return uniquePoints(points)
    }

    private func splineAxisPoints(
        referencePoint: Point2D,
        direction: Point2D,
        controlPoints: [Point2D]
    ) -> [Point2D] {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let sampleCount = max(curveSampler.samplesPerSegment * 2, 32)
        var points: [Point2D] = []

        for segmentIndex in 0 ..< segmentCount {
            guard var previous = splineAxisValue(
                referencePoint: referencePoint,
                direction: direction,
                controlPoints: controlPoints,
                segmentIndex: segmentIndex,
                t: 0.0
            ) else {
                continue
            }
            if abs(previous.value) <= 1.0e-10 {
                points.append(previous.point)
            }
            for sampleIndex in 1 ... sampleCount {
                let t = Double(sampleIndex) / Double(sampleCount)
                guard let current = splineAxisValue(
                    referencePoint: referencePoint,
                    direction: direction,
                    controlPoints: controlPoints,
                    segmentIndex: segmentIndex,
                    t: t
                ) else {
                    continue
                }
                if abs(current.value) <= 1.0e-10 {
                    points.append(current.point)
                } else if previous.value * current.value < 0.0,
                          let root = splineAxisRoot(
                              referencePoint: referencePoint,
                              direction: direction,
                              controlPoints: controlPoints,
                              segmentIndex: segmentIndex,
                              lowerT: previous.t,
                              lowerValue: previous.value,
                              upperT: current.t
                          ) {
                    points.append(root)
                }
                previous = current
            }
        }

        return uniquePoints(points)
    }

    private func splineAxisRoot(
        referencePoint: Point2D,
        direction: Point2D,
        controlPoints: [Point2D],
        segmentIndex: Int,
        lowerT: Double,
        lowerValue: Double,
        upperT: Double
    ) -> Point2D? {
        var lowT = lowerT
        var lowValue = lowerValue
        var highT = upperT
        var bestPoint: Point2D?

        for _ in 0 ..< 48 {
            let midT = (lowT + highT) / 2.0
            guard let mid = splineAxisValue(
                referencePoint: referencePoint,
                direction: direction,
                controlPoints: controlPoints,
                segmentIndex: segmentIndex,
                t: midT
            ) else {
                break
            }
            bestPoint = mid.point
            if abs(mid.value) <= 1.0e-12 {
                return mid.point
            }
            if lowValue * mid.value <= 0.0 {
                highT = midT
            } else {
                lowT = midT
                lowValue = mid.value
            }
        }

        return bestPoint
    }

    private func splineAxisValue(
        referencePoint: Point2D,
        direction: Point2D,
        controlPoints: [Point2D],
        segmentIndex: Int,
        t: Double
    ) -> SplineRelationValue? {
        guard let sample = curveSampler.splineSegmentSample(
            for: controlPoints,
            segmentIndex: segmentIndex,
            t: t
        ) else {
            return nil
        }
        let vector = Point2D(
            x: sample.point.x - referencePoint.x,
            y: sample.point.y - referencePoint.y
        )
        return SplineRelationValue(
            t: t,
            value: vector.x * direction.y - vector.y * direction.x,
            point: sample.point
        )
    }

    private func splineRelationRoot(
        referencePoint: Point2D,
        controlPoints: [Point2D],
        segmentIndex: Int,
        lowerT: Double,
        lowerValue: Double,
        upperT: Double,
        relation: SnapCurveRelation
    ) -> Point2D? {
        var lowT = lowerT
        var lowValue = lowerValue
        var highT = upperT
        var bestPoint: Point2D?

        for _ in 0 ..< 48 {
            let midT = (lowT + highT) / 2.0
            guard let mid = splineRelationValue(
                referencePoint: referencePoint,
                controlPoints: controlPoints,
                segmentIndex: segmentIndex,
                t: midT,
                relation: relation
            ) else {
                break
            }
            bestPoint = mid.point
            if abs(mid.value) <= 1.0e-12 {
                return mid.point
            }
            if lowValue * mid.value <= 0.0 {
                highT = midT
            } else {
                lowT = midT
                lowValue = mid.value
            }
        }

        return bestPoint
    }

    private func splineRelationValue(
        referencePoint: Point2D,
        controlPoints: [Point2D],
        segmentIndex: Int,
        t: Double,
        relation: SnapCurveRelation
    ) -> SplineRelationValue? {
        guard let sample = curveSampler.splineSegmentSample(
            for: controlPoints,
            segmentIndex: segmentIndex,
            t: t
        ) else {
            return nil
        }
        let vector = Point2D(
            x: sample.point.x - referencePoint.x,
            y: sample.point.y - referencePoint.y
        )
        let value: Double
        switch relation {
        case .tangent:
            value = vector.x * sample.tangent.y - vector.y * sample.tangent.x
        case .perpendicular:
            value = vector.x * sample.tangent.x + vector.y * sample.tangent.y
        }
        return SplineRelationValue(
            t: t,
            value: value,
            point: sample.point
        )
    }

    private func intersectionPoints(
        _ first: SnapGeometry,
        _ second: SnapGeometry
    ) -> [Point2D] {
        switch (first, second) {
        case let (.line(firstStart, firstEnd), .line(secondStart, secondEnd)):
            return lineLineIntersection(
                firstStart: firstStart,
                firstEnd: firstEnd,
                secondStart: secondStart,
                secondEnd: secondEnd
            ).map { [$0] } ?? []
        case let (.line(start, end), .circle(center, radius)),
             let (.circle(center, radius), .line(start, end)):
            return lineCircleIntersections(start: start, end: end, center: center, radius: radius)
        case let (.line(start, end), .arc(center, radius, _, _)),
             let (.arc(center, radius, _, _), .line(start, end)):
            return lineCircleIntersections(start: start, end: end, center: center, radius: radius)
        case let (.circle(firstCenter, firstRadius), .circle(secondCenter, secondRadius)):
            return circleCircleIntersections(
                firstCenter: firstCenter,
                firstRadius: firstRadius,
                secondCenter: secondCenter,
                secondRadius: secondRadius
            )
        case let (.circle(firstCenter, firstRadius), .arc(secondCenter, secondRadius, _, _)),
             let (.arc(secondCenter, secondRadius, _, _), .circle(firstCenter, firstRadius)),
             let (.arc(firstCenter, firstRadius, _, _), .arc(secondCenter, secondRadius, _, _)):
            return circleCircleIntersections(
                firstCenter: firstCenter,
                firstRadius: firstRadius,
                secondCenter: secondCenter,
                secondRadius: secondRadius
            )
        case (.point, _),
             (_, .point),
             (.spline, _),
             (_, .spline),
             (.polyline, _),
             (_, .polyline):
            return []
        }
    }

    private func lineLineIntersection(
        firstStart: Point2D,
        firstEnd: Point2D,
        secondStart: Point2D,
        secondEnd: Point2D
    ) -> Point2D? {
        let firstX = firstEnd.x - firstStart.x
        let firstY = firstEnd.y - firstStart.y
        let secondX = secondEnd.x - secondStart.x
        let secondY = secondEnd.y - secondStart.y
        let denominator = firstX * secondY - firstY * secondX
        guard abs(denominator) > 1.0e-14 else {
            return nil
        }
        let deltaX = secondStart.x - firstStart.x
        let deltaY = secondStart.y - firstStart.y
        let firstT = (deltaX * secondY - deltaY * secondX) / denominator
        let secondT = (deltaX * firstY - deltaY * firstX) / denominator
        guard firstT >= -1.0e-10,
              firstT <= 1.0 + 1.0e-10,
              secondT >= -1.0e-10,
              secondT <= 1.0 + 1.0e-10 else {
            return nil
        }
        return Point2D(
            x: firstStart.x + firstX * firstT,
            y: firstStart.y + firstY * firstT
        )
    }

    private func axisLineSegmentIntersection(
        referencePoint: Point2D,
        direction: Point2D,
        segmentStart: Point2D,
        segmentEnd: Point2D
    ) -> Point2D? {
        let segmentX = segmentEnd.x - segmentStart.x
        let segmentY = segmentEnd.y - segmentStart.y
        let denominator = direction.x * segmentY - direction.y * segmentX
        guard abs(denominator) > 1.0e-14 else {
            return nil
        }
        let deltaX = segmentStart.x - referencePoint.x
        let deltaY = segmentStart.y - referencePoint.y
        let segmentT = (deltaX * direction.y - deltaY * direction.x) / denominator
        guard segmentT >= -1.0e-10,
              segmentT <= 1.0 + 1.0e-10 else {
            return nil
        }
        let clampedT = max(0.0, min(1.0, segmentT))
        return Point2D(
            x: segmentStart.x + segmentX * clampedT,
            y: segmentStart.y + segmentY * clampedT
        )
    }

    private func axisCircleIntersections(
        referencePoint: Point2D,
        direction: Point2D,
        center: Point2D,
        radius: Double
    ) -> [Point2D] {
        guard radius > 1.0e-12 else {
            return []
        }
        let offsetX = referencePoint.x - center.x
        let offsetY = referencePoint.y - center.y
        let b = 2.0 * (offsetX * direction.x + offsetY * direction.y)
        let c = offsetX * offsetX + offsetY * offsetY - radius * radius
        let discriminant = b * b - 4.0 * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        if abs(discriminant) <= 1.0e-14 {
            let t = -b / 2.0
            return [axisPoint(referencePoint: referencePoint, direction: direction, parameter: t)]
        }
        let root = sqrt(max(discriminant, 0.0))
        return [
            axisPoint(referencePoint: referencePoint, direction: direction, parameter: (-b - root) / 2.0),
            axisPoint(referencePoint: referencePoint, direction: direction, parameter: (-b + root) / 2.0),
        ]
    }

    private func axisPoint(
        referencePoint: Point2D,
        direction: Point2D,
        parameter: Double
    ) -> Point2D {
        Point2D(
            x: referencePoint.x + direction.x * parameter,
            y: referencePoint.y + direction.y * parameter
        )
    }

    private func lineCircleIntersections(
        start: Point2D,
        end: Point2D,
        center: Point2D,
        radius: Double
    ) -> [Point2D] {
        let directionX = end.x - start.x
        let directionY = end.y - start.y
        let lengthSquared = directionX * directionX + directionY * directionY
        guard lengthSquared > 1.0e-24, radius > 1.0e-12 else {
            return []
        }
        let offsetX = start.x - center.x
        let offsetY = start.y - center.y
        let b = 2.0 * (offsetX * directionX + offsetY * directionY)
        let c = offsetX * offsetX + offsetY * offsetY - radius * radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        if abs(discriminant) <= 1.0e-14 {
            let t = -b / (2.0 * lengthSquared)
            return pointOnSegment(start: start, directionX: directionX, directionY: directionY, t: t)
        }
        let root = sqrt(max(discriminant, 0.0))
        let firstT = (-b - root) / (2.0 * lengthSquared)
        let secondT = (-b + root) / (2.0 * lengthSquared)
        return pointOnSegment(start: start, directionX: directionX, directionY: directionY, t: firstT) +
            pointOnSegment(start: start, directionX: directionX, directionY: directionY, t: secondT)
    }

    private func pointOnSegment(
        start: Point2D,
        directionX: Double,
        directionY: Double,
        t: Double
    ) -> [Point2D] {
        guard t >= -1.0e-10, t <= 1.0 + 1.0e-10 else {
            return []
        }
        let clampedT = max(0.0, min(1.0, t))
        return [
            Point2D(
                x: start.x + directionX * clampedT,
                y: start.y + directionY * clampedT
            ),
        ]
    }

    private func circleCircleIntersections(
        firstCenter: Point2D,
        firstRadius: Double,
        secondCenter: Point2D,
        secondRadius: Double
    ) -> [Point2D] {
        guard firstRadius > 1.0e-12, secondRadius > 1.0e-12 else {
            return []
        }
        let deltaX = secondCenter.x - firstCenter.x
        let deltaY = secondCenter.y - firstCenter.y
        let centerDistance = hypot(deltaX, deltaY)
        guard centerDistance > 1.0e-12,
              centerDistance <= firstRadius + secondRadius + 1.0e-12,
              centerDistance >= abs(firstRadius - secondRadius) - 1.0e-12 else {
            return []
        }
        let along = (
            firstRadius * firstRadius - secondRadius * secondRadius + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let heightSquared = firstRadius * firstRadius - along * along
        guard heightSquared >= -1.0e-14 else {
            return []
        }
        let baseX = firstCenter.x + along * deltaX / centerDistance
        let baseY = firstCenter.y + along * deltaY / centerDistance
        if abs(heightSquared) <= 1.0e-14 {
            return [Point2D(x: baseX, y: baseY)]
        }
        let height = sqrt(max(heightSquared, 0.0))
        let offsetX = -deltaY / centerDistance * height
        let offsetY = deltaX / centerDistance * height
        return [
            Point2D(x: baseX + offsetX, y: baseY + offsetY),
            Point2D(x: baseX - offsetX, y: baseY - offsetY),
        ]
    }

    private func contains(_ point: Point2D, in geometry: SnapGeometry) -> Bool {
        switch geometry {
        case .point(let candidate):
            return distance(point, candidate) <= 1.0e-10
        case .line(let start, let end):
            return distance(point, closestPoint(onSegmentFrom: start, to: end, near: point)) <= 1.0e-8
        case .circle(let center, let radius):
            return abs(distance(point, center) - radius) <= 1.0e-8
        case .arc(let center, let radius, let startAngle, let endAngle):
            guard abs(distance(point, center) - radius) <= 1.0e-8 else {
                return false
            }
            return angleIsOnArc(
                atan2(point.y - center.y, point.x - center.x),
                startAngle: startAngle,
                endAngle: endAngle
            )
        case .spline:
            return false
        case .polyline(let points):
            guard points.count >= 2 else {
                return false
            }
            return points.indices.dropFirst().contains { index in
                distance(
                    point,
                    closestPoint(
                        onSegmentFrom: points[index - 1],
                        to: points[index],
                        near: point
                    )
                ) <= 1.0e-8
            }
        }
    }

    private func normalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private func normalizedAngleDelta(from startAngle: Double, to angle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = angle - startAngle
        while delta < 0.0 {
            delta += fullCircle
        }
        while delta >= fullCircle {
            delta -= fullCircle
        }
        return delta
    }

    private func angleIsOnArc(
        _ angle: Double,
        startAngle: Double,
        endAngle: Double
    ) -> Bool {
        normalizedAngleDelta(from: startAngle, to: angle)
            <= normalizedArcSpan(startAngle: startAngle, endAngle: endAngle) + 1.0e-10
    }

    private func validated(
        _ options: SnapResolutionOptions,
        ruler: RulerConfiguration
    ) throws -> ValidatedSnapResolutionOptions {
        let ruler = ruler.normalizedForWorkspaceScale()
        let gridIntervalMeters = options.gridIntervalMeters ?? max(
            ruler.minorTickMeters,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        let objectSearchRadiusMeters = options.objectSearchRadiusMeters
            ?? defaultObjectSearchRadiusMeters(
                ruler: ruler,
                gridIntervalMeters: gridIntervalMeters
            )

        guard gridIntervalMeters.isFinite,
              objectSearchRadiusMeters.isFinite,
              gridIntervalMeters > 0.0,
              objectSearchRadiusMeters >= 0.0,
              options.maximumCandidateCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Snap resolution options must use finite positive grid interval, finite non-negative object radius, and positive candidate count."
            )
        }
        if let referencePoint = options.referencePoint {
            try validate(point: referencePoint)
        }
        for anchor in options.referenceLineAnchors {
            try validate(point: anchor.point)
        }
        return ValidatedSnapResolutionOptions(
            usesGrid: options.usesGrid,
            usesObjects: options.usesObjects,
            objectTargetingOverride: options.objectTargetingOverride,
            suppressedCandidateKinds: options.suppressedCandidateKinds,
            constructionPlane: options.constructionPlane,
            gridIntervalMeters: gridIntervalMeters,
            objectSearchRadiusMeters: objectSearchRadiusMeters,
            maximumCandidateCount: options.maximumCandidateCount,
            referencePoint: options.referencePoint,
            referenceLineAnchors: options.referenceLineAnchors
        )
    }

    private func defaultObjectSearchRadiusMeters(
        ruler: RulerConfiguration,
        gridIntervalMeters: Double
    ) -> Double {
        let gridScaledRadiusMeters = gridIntervalMeters * 2.0
        let visibleSpanPrecisionRadiusMeters = ruler.visibleSpanMeters * 1.0e-6
        return max(
            gridScaledRadiusMeters,
            visibleSpanPrecisionRadiusMeters,
            1.0e-6
        )
    }

    private func validate(point: Point2D) throws {
        guard point.x.isFinite, point.y.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Snap resolution requires a finite model point."
            )
        }
    }

    private func distance(_ first: Point2D, _ second: Point2D) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }

    private func isFinite(_ point: Point2D) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private func isFinite(_ point: Point3D) -> Bool {
        do {
            try point.validate()
            return true
        } catch {
            return false
        }
    }

    private func uniquePoints(
        _ points: [Point2D],
        tolerance: Double = 1.0e-10
    ) -> [Point2D] {
        points.reduce(into: [Point2D]()) { uniquePoints, point in
            guard uniquePoints.contains(where: { distance($0, point) <= tolerance }) == false else {
                return
            }
            uniquePoints.append(point)
        }
    }

    private func sortKey(
        kind: SnapCandidateKind,
        point: Point2D,
        source: SnapSourceReference
    ) -> String {
        [
            source.featureID.description,
            source.entityID.description,
            source.controlPointIndex.map(String.init) ?? "-",
            kind.rawValue,
            String(format: "%.17g", point.x),
            String(format: "%.17g", point.y),
        ].joined(separator: ":")
    }
}

private struct PrioritizedSnapCandidate: Equatable {
    var priority: Int
    var sortKey: String
    var candidate: SnapCandidate
}

private struct SnapEntity: Equatable {
    var source: SnapSourceReference
    var geometry: SnapGeometry
    var axisDirections: [SnapAxisDirection]
    var coordinatePlaneDirections: [SnapCoordinatePlaneDirection]
    var discreteCandidates: [PrioritizedSnapCandidate]
}

private struct SnapAxisDirection: Equatable {
    var kind: SnapAxisKind
    var priority: Int
    var direction: Point2D
}

private struct SnapCoordinatePlaneDirection: Equatable {
    var kind: SnapCoordinatePlaneKind
    var direction: Point2D
}

private enum SnapGeometry: Equatable {
    case point(Point2D)
    case line(start: Point2D, end: Point2D)
    case circle(center: Point2D, radius: Double)
    case arc(center: Point2D, radius: Double, startAngle: Double, endAngle: Double)
    case spline(controlPoints: [Point2D])
    case polyline(points: [Point2D])
}

private enum SnapCurveRelation: Equatable {
    case tangent
    case perpendicular
}

private struct SplineRelationValue: Equatable {
    var t: Double
    var value: Double
    var point: Point2D
}
