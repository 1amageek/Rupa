import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Join Curves on two or more curves of one sketch: every pair of free curve ends that meet
    /// becomes a joint holding them together at the chosen continuity, and the selected curves,
    /// with the joined curves some of them already belong to, become one joined curve. The ends
    /// already held by a joint are not free; a selected endpoint handle offers only that end.
    ///
    /// Refused when the curves do not meet end to end in one piece, when three or more free ends
    /// meet at one point, or when a curve was merged by a collinear line join.
    public mutating func joinSketchCurves(
        targets: [SelectionTarget],
        continuity: SketchCurveJoinContinuity = .g0,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard targets.count >= 2 else {
            throw EditorError(code: .commandInvalid, message: "Join Curves takes two or more curves.")
        }
        let selections = try targets.map { target in
            try editableSketchEntityBase(for: target, operationName: "Join Curves")
        }
        let featureID = selections[0].featureID
        guard selections.allSatisfy({ $0.featureID == featureID }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires every curve to belong to the same sketch."
            )
        }
        let selectedIDs = selections.map(\.entityID)
        guard Set(selectedIDs).count == selectedIDs.count else {
            throw EditorError(code: .commandInvalid, message: "Join Curves requires distinct source curves.")
        }
        let selectedIDSet = Set(selectedIDs)
        try validateSketchCurveChainJoinOwnership(featureID: featureID, selectedIDs: selectedIDSet)

        // The joined curves the selection reaches, in selection order.
        var groups: [JoinedCurveGroupSource] = []
        for entityID in selectedIDs {
            guard let group = productMetadata.joinedCurveGroupSources.values.first(where: { source in
                source.featureID == featureID && source.memberEntityIDs.contains(entityID)
            }), !groups.contains(where: { $0.id == group.id }) else { continue }
            groups.append(group)
        }
        let heldEnds = Set(groups.flatMap { group in
            group.joints.flatMap { [$0.firstReference, $0.secondReference] }
        })

        let sketch = selections[0].sketch
        var freeEnds: [[SketchReference]] = []
        for (target, selection) in zip(targets, selections) {
            freeEnds.append(try joinCurveEndpointCandidates(
                target: target,
                selection: selection,
                owner: "Join Curves"
            ).filter { !heldEnds.contains($0) })
        }
        var plans: [SketchCurveGroupJoinPlan] = []
        for first in selections.indices {
            for second in selections.indices where second > first {
                for firstEnd in freeEnds[first] {
                    for secondEnd in freeEnds[second] where try joinCurveEndpointsAreAligned(firstEnd, secondEnd, sketch: sketch) {
                        plans.append(SketchCurveGroupJoinPlan(
                            memberEntityIDs: [selectedIDs[first], selectedIDs[second]],
                            firstJoinedReference: firstEnd,
                            secondJoinedReference: secondEnd,
                            continuity: continuity
                        ))
                    }
                }
            }
        }
        guard !plans.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves requires the selected curves to meet end to end."
            )
        }
        let joinedEnds = plans.flatMap { [$0.firstJoinedReference, $0.secondJoinedReference] }
        guard Set(joinedEnds).count == joinedEnds.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves found three or more curve ends meeting at one point; select explicit endpoints to disambiguate."
            )
        }
        guard sketchCurveChainIsConnected(selectedIDs: selectedIDs, groups: groups, plans: plans) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves requires the selected curves to meet end to end in one chain."
            )
        }
        for plan in plans {
            try validateSketchCurveGroupJoinContinuity(plan, sketch: sketch)
        }

        var feature = selections[0].feature
        var joinedSketch = sketch
        let constraintsBeforeJoin = joinedSketch.constraints
        var newJoints: [JoinedCurveGroupJoint] = []
        var constraintsAfterFirstJoint = joinedSketch.constraints
        for plan in plans {
            let before = joinedSketch.constraints
            _ = try applySketchCurveGroupJoinConstraints(to: &joinedSketch, join: plan)
            if newJoints.isEmpty {
                constraintsAfterFirstJoint = joinedSketch.constraints
            }
            newJoints.append(JoinedCurveGroupJoint(
                firstReference: plan.firstJoinedReference,
                secondReference: plan.secondJoinedReference,
                continuity: plan.continuity,
                addedConstraints: JoinedCurveGroupJoint.constraintsAdded(to: before, in: joinedSketch.constraints)
            ))
        }

        let joined: JoinedCurveGroupSource
        if var base = groups.first {
            for group in groups.dropFirst() {
                base.memberEntityIDs += group.memberEntityIDs
                base.additionalJoints += group.joints
            }
            base.memberEntityIDs += selectedIDs.filter { !base.memberEntityIDs.contains($0) }
            base.additionalJoints += newJoints
            joined = base
        } else {
            let first = newJoints[0]
            joined = JoinedCurveGroupSource(
                featureID: featureID,
                memberEntityIDs: selectedIDs,
                firstJoinedReference: first.firstReference,
                secondJoinedReference: first.secondReference,
                continuity: first.continuity,
                constraintsBeforeJoin: constraintsBeforeJoin,
                dimensionsBeforeJoin: joinedSketch.dimensions,
                constraintsAfterJoin: constraintsAfterFirstJoint,
                dimensionsAfterJoin: joinedSketch.dimensions,
                additionalJoints: Array(newJoints.dropFirst())
            )
        }

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitJoin = false
        defer {
            if didCommitJoin == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        for group in groups {
            productMetadata.joinedCurveGroupSources.removeValue(forKey: group.id)
        }
        productMetadata.joinedCurveGroupSources[joined.id] = joined
        try commitSketchEntityEdit(
            featureID: featureID,
            feature: &feature,
            sketch: joinedSketch,
            objectRegistry: objectRegistry,
            errorOwner: "Join Curves"
        )
        didCommitJoin = true
    }

    /// Refuses curves a collinear line join merged, and curves a generated Bridge Curve names.
    private func validateSketchCurveChainJoinOwnership(
        featureID: FeatureID,
        selectedIDs: Set<SketchEntityID>
    ) throws {
        for source in productMetadata.joinedCurveSources.values where source.featureID == featureID {
            guard !selectedIDs.contains(source.retainedEntityID), !selectedIDs.contains(source.restoredEntityID) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot join curves that already carry joined-curve ownership metadata."
                )
            }
        }
        for source in productMetadata.bridgeCurveSources.values where source.featureID == featureID {
            guard bridgeEndpointReferencesAnyJoinEntity(source.firstEndpoint, affectedEntityIDs: selectedIDs) == false,
                  bridgeEndpointReferencesAnyJoinEntity(source.secondEndpoint, affectedEntityIDs: selectedIDs) == false,
                  selectedIDs.contains(source.entityID) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot preserve generated Bridge Curve source metadata for joined curves yet."
                )
            }
        }
    }

    /// Whether the selected curves form one piece through the new joints and the joined curves
    /// they already belong to.
    private func sketchCurveChainIsConnected(
        selectedIDs: [SketchEntityID],
        groups: [JoinedCurveGroupSource],
        plans: [SketchCurveGroupJoinPlan]
    ) -> Bool {
        var edges: [[SketchEntityID]] = plans.map(\.memberEntityIDs)
        edges += groups.map(\.memberEntityIDs)
        var reached: Set<SketchEntityID> = [selectedIDs[0]]
        var grew = true
        while grew {
            grew = false
            for edge in edges where edge.contains(where: reached.contains) {
                for entityID in edge where reached.insert(entityID).inserted {
                    grew = true
                }
            }
        }
        return selectedIDs.allSatisfy(reached.contains)
    }
}
