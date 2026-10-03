import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

extension ViewportSpatialOverlayProducer {
    /// The continuity badges: each boundary's label beside its middle, a dot on the middle itself,
    /// the label clickable as an affordance whose click reports the boundary. Boundaries are found
    /// in the scene drawn; one it does not have draws no badge.
    static func appendContinuityBadges(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard snapshot.continuityBadges.isEmpty == false else { return }
        let scene = snapshot.selectionResolutionScene
        for badge in snapshot.continuityBadges {
            try Task.checkCancellation()
            // A boundary the drawn scene does not have (a preview that rebuilt its body) has no
            // place to draw a badge at; the dialog still lists its continuity.
            guard let item = scene.firstItem(sceneNodeID: badge.target.sceneNodeID) else { continue }
            let points: [Point3D]
            switch (item.kind, badge.target.component) {
            case (.body(let component), .edge(let componentID)):
                guard let edge = component.topology?.edges.first(where: { $0.componentID == componentID }) else { continue }
                points = edge.displayPoints
            case (.curve(let component), _):
                points = component.segments.flatMap(\.points)
            default:
                throw RealityViewportSpatialBatch.invalid("A continuity badge marks an edge of a body or a curve.")
            }
            guard let local = midpoint(of: points) else {
                throw RealityViewportSpatialBatch.invalid("A continuity badge's boundary has no middle.")
            }
            let anchor = item.modelTransform.point(local)
            let target = ViewportAffordanceTarget(
                featureID: item.featureID, selectionTarget: badge.target, action: .continuityBadge(badge.target)
            )
            let member = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
                occurrenceID: item.id, featureID: item.featureID, sceneNodeID: item.sceneNodeID,
                modelTransform: item.modelTransform, edit: ViewportObjectEditState(item: item)
            )
            let index = try handleIndex(
                for: .affordance(target: target, members: [member], groupEdit: nil, placement: nil),
                occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords
            )
            var value = try label(
                badge.label, anchor: anchor, offset: CGPoint(x: 0, y: -16),
                color: continuityBadgeColor, alignment: .center, heightPoints: 12
            )
            value.handleIndex = index
            value.hitRectPoints = CGRect(x: -18, y: -12, width: 36, height: 24)
            labels.append(.init(family: .transform, value: value))
            markers.append(.init(family: .transform, value: marker(anchor: anchor, diameterPoints: 6, color: continuityBadgeColor)))
        }
        activeFamilies.insert(.transform)
    }

    static let continuityBadgeColor = SIMD4<Float>(0.96, 0.96, 0.96, 1.0)
}
