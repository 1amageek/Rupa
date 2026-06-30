import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportBridgeCurveEndpointAffordanceService: Sendable {
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
        let localTangentTip = CGPoint(
            x: handle.point.x + handle.outgoingTangent.x * 0.001,
            y: handle.point.y + handle.outgoingTangent.y * 0.001
        )
        let projectedPoint = layout.project(localPoint, in: item)
        let projectedTangentTip = layout.project(localTangentTip, in: item)
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
