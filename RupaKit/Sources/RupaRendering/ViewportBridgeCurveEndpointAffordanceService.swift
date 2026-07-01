import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportBridgeCurveEndpointAffordanceService: Sendable {
    static let tangentGuideViewportLength: CGFloat = 34.0

    private let handleService: BridgeCurveEndpointHandleService

    init(handleService: BridgeCurveEndpointHandleService = BridgeCurveEndpointHandleService()) {
        self.handleService = handleService
    }

    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) throws -> [ViewportBridgeCurveEndpointAffordanceCandidate] {
        let handles = try handleService.handles(for: selection, in: document)
        return handles.compactMap { handle in
            candidate(
                handle: handle,
                scene: scene,
                layout: layout
            )
        }
    }

    func candidatesOrEmpty(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportBridgeCurveEndpointAffordanceCandidate] {
        do {
            return try candidates(
                document: document,
                scene: scene,
                selection: selection,
                layout: layout
            )
        } catch {
            return []
        }
    }

    func target(
        at point: CGPoint,
        candidates: [ViewportBridgeCurveEndpointAffordanceCandidate],
        tolerance: CGFloat = 12.0
    ) -> ViewportBridgeCurveEndpointHandleTarget? {
        var nearest: (target: ViewportBridgeCurveEndpointHandleTarget, distance: CGFloat)?
        for candidate in candidates {
            let distance = point.distance(to: candidate.projectedPoint)
            guard distance <= tolerance else {
                continue
            }
            if let current = nearest {
                if distance < current.distance {
                    nearest = (candidate.target, distance)
                }
            } else {
                nearest = (candidate.target, distance)
            }
        }
        return nearest?.target
    }

    private func candidate(
        handle: BridgeCurveEndpointHandle,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportBridgeCurveEndpointAffordanceCandidate? {
        guard let item = scene.items.first(where: { item in
            item.featureID == handle.featureID
        }) else {
            return nil
        }
        let localPoint = CGPoint(x: handle.point.x, y: handle.point.y)
        let projectedPoint = layout.project(localPoint, in: item)
        let projectedTangentTip = Self.projectedTangentTip(
            point: handle.point,
            outgoingTangent: handle.outgoingTangent,
            modelTransform: item.modelTransform,
            layout: layout
        )
        let target = ViewportBridgeCurveEndpointHandleTarget(
            sourceID: handle.sourceID,
            featureID: handle.featureID,
            bridgeEntityID: handle.bridgeEntityID,
            role: handle.role,
            endpoint: handle.endpoint,
            referenceDescription: handle.referenceDescription,
            point: handle.point,
            modelTransform: item.modelTransform,
            projectedPoint: projectedPoint,
            projectedTangentTip: projectedTangentTip
        )
        return ViewportBridgeCurveEndpointAffordanceCandidate(
            target: target,
            projectedPoint: projectedPoint,
            projectedTangentTip: projectedTangentTip
        )
    }

    static func projectedTangentTip(
        point: Point2D,
        outgoingTangent: Point2D,
        modelTransform: Transform3D,
        layout: ViewportLayout,
        viewportLength: CGFloat = tangentGuideViewportLength
    ) -> CGPoint {
        let geometry = ViewportPlanarHandleDragGeometry(
            localPoint: Point3D(x: point.x, y: 0.0, z: point.y),
            modelTransform: modelTransform
        )
        if let endpoint = geometry.localAxisEndpoint(
            direction: Vector3D(
                x: outgoingTangent.x,
                y: 0.0,
                z: outgoingTangent.y
            ),
            viewportLength: viewportLength,
            layout: layout
        ) {
            return endpoint
        }

        let scale = max(layout.scale, CGFloat(1.0e-9))
        let fallbackLengthMeters = max(
            Double(viewportLength / scale),
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        let localTip = Point3D(
            x: point.x + outgoingTangent.x * fallbackLengthMeters,
            y: 0.0,
            z: point.y + outgoingTangent.y * fallbackLengthMeters
        )
        return layout.project(modelTransform.viewportTransformedPoint(localTip))
    }
}

struct ViewportBridgeCurveEndpointAffordanceCandidate: Equatable {
    var target: ViewportBridgeCurveEndpointHandleTarget
    var projectedPoint: CGPoint
    var projectedTangentTip: CGPoint
}

struct ViewportBridgeCurveEndpointHandleTarget: Equatable {
    var sourceID: BridgeCurveSourceID
    var featureID: FeatureID
    var bridgeEntityID: SketchEntityID
    var role: BridgeCurveEndpointHandleRole
    var endpoint: BridgeCurveEndpoint
    var referenceDescription: String
    var point: Point2D
    var modelTransform: Transform3D
    var projectedPoint: CGPoint
    var projectedTangentTip: CGPoint

    var identity: ViewportBridgeCurveEndpointHandleIdentity {
        ViewportBridgeCurveEndpointHandleIdentity(
            sourceID: sourceID,
            role: role
        )
    }

    var geometry: ViewportPlanarHandleDragGeometry {
        ViewportPlanarHandleDragGeometry(
            localPoint: Point3D(x: point.x, y: 0.0, z: point.y),
            modelTransform: modelTransform
        )
    }
}

struct ViewportBridgeCurveEndpointHandleIdentity: Equatable {
    var sourceID: BridgeCurveSourceID
    var role: BridgeCurveEndpointHandleRole
}
