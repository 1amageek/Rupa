import SwiftCAD

public struct SweepSelectionPlanningService: Sendable {
    /// The positional allowance a sweep is built within where it needs one (a twist, a Normal
    /// sweep along a curve, a Chord or Curve guide) and none is given: Plasticity asks for none.
    public static let defaultApproximationAllowance = CADExpression.length(0.000_001, .meter)

    private let document: DesignDocument
    private let selection: SelectionModel

    public init(
        document: DesignDocument,
        selection: SelectionModel
    ) {
        self.document = document
        self.selection = selection
    }

    public func preview(
        targetSceneNodeID: SceneNodeID? = nil
    ) -> SweepSelectionPreview {
        do {
            return try resolution(targetSceneNodeID: targetSceneNodeID).preview
        } catch {
            return SweepSelectionPreview(
                status: .invalid,
                message: error.localizedDescription
            )
        }
    }

    /// The sweep of the selection's section along its path, combined with `targets` when the
    /// options ask for a Boolean.
    public func command(
        targetSceneNodeID: SceneNodeID? = nil,
        name: String,
        options: SweepOptions = SweepOptions(),
        targets: [SweepTargetReference] = [],
        pathEdgeCurve: EdgeCurveSource? = nil
    ) throws -> EditorCommand {
        let resolution = try resolution(targetSceneNodeID: targetSceneNodeID)
        // A path along an edge is the edge's curve, added with the sweep.
        guard let section = resolution.section,
              let pathFeatureID = pathEdgeCurve?.id ?? resolution.pathFeatureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep tool requires one profile or curve section source, one separate path curve source, and optional guide curve selections."
            )
        }
        var resolvedOptions = options
        if resolvedOptions.approximationTolerance == nil {
            resolvedOptions.approximationTolerance = Self.defaultApproximationAllowance
        }
        if section.isClosedRegion == false {
            resolvedOptions.resultKind = .sheet
        }
        return .createSweep(
            name: name,
            sections: [section],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: resolution.guideFeatureIDs.map { SweepGuideReference(featureID: $0) },
            targets: targets,
            options: resolvedOptions,
            edgeCurves: pathEdgeCurve.map { [$0] } ?? []
        )
    }

    private struct Resolution {
        var section: SectionReference?
        var pathFeatureID: FeatureID?
        var guideFeatureIDs: [FeatureID]

        var preview: SweepSelectionPreview {
            guard let section else {
                return SweepSelectionPreview(
                    status: .missingSection,
                    pathFeatureID: pathFeatureID,
                    guideFeatureIDs: guideFeatureIDs,
                    message: "Sweep requires a profile or curve section source."
                )
            }
            guard let pathFeatureID else {
                return SweepSelectionPreview(
                    status: .missingPath,
                    section: section,
                    guideFeatureIDs: guideFeatureIDs,
                    message: "Sweep requires a separate path curve source."
                )
            }
            return SweepSelectionPreview(
                status: .ready,
                section: section,
                pathFeatureID: pathFeatureID,
                guideFeatureIDs: guideFeatureIDs,
                message: "Sweep source is ready with \(guideFeatureIDs.count) guide curve(s)."
            )
        }
    }

    private struct Candidate {
        var isTarget: Bool
        var profileReference: ProfileReference?
        var curveFeatureID: FeatureID?
        var face: FaceSectionReference?
    }

    private struct CandidateSceneNode {
        var id: SceneNodeID
        var isTarget: Bool
    }

    private func resolution(
        targetSceneNodeID: SceneNodeID?
    ) throws -> Resolution {
        var candidates: [Candidate] = []
        for sceneNode in orderedCandidateSceneNodes(targetSceneNodeID: targetSceneNodeID) {
            if let candidate = try sourceCandidate(for: sceneNode) {
                candidates.append(candidate)
            }
        }
        // A closed source selected last after a section is the path (a closed frame to sweep
        // around), not a second section.
        let orderedProfiles = candidates.compactMap(\.profileReference)
        if orderedProfiles.count + candidates.compactMap(\.face).count == 2, let last = candidates.last,
           let pathProfile = last.profileReference, candidates.contains(where: { $0.curveFeatureID != nil }) == false {
            candidates[candidates.count - 1] = Candidate(isTarget: last.isTarget, profileReference: nil, curveFeatureID: pathProfile.featureID)
        }
        let profileReferences = Set(candidates.compactMap(\.profileReference))
        let faces = candidates.compactMap(\.face)
        guard profileReferences.count + faces.count <= 1 else {
            throw EditorError(code: .commandInvalid,
                message: "Sweep requires one section profile or face. Use Loft for multiple profile sections.")
        }
        let profileReference = profileReferences.first
        let allCurveFeatureIDs = uniqueFeatureIDs(candidates.compactMap(\.curveFeatureID))
        let targetCurveFeatureID = candidates.last { $0.isTarget }?.curveFeatureID
        let section: SectionReference?
        let pathFeatureID: FeatureID?
        if let face = faces.first {
            // A face of a body sweeps like a profile along the last selected curve.
            section = .face(face)
            pathFeatureID = targetCurveFeatureID ?? allCurveFeatureIDs.last
        } else if let profileReference {
            section = .profile(profileReference)
            let curveFeatureIDs = allCurveFeatureIDs.filter { $0 != profileReference.featureID }
            pathFeatureID = targetCurveFeatureID.flatMap { target in
                target == profileReference.featureID ? nil : target
            } ?? curveFeatureIDs.last
        } else {
            let sectionCurveFeatureID: FeatureID?
            if let targetCurveFeatureID {
                pathFeatureID = targetCurveFeatureID
                sectionCurveFeatureID = allCurveFeatureIDs.first { $0 != targetCurveFeatureID }
            } else {
                sectionCurveFeatureID = allCurveFeatureIDs.first
                pathFeatureID = allCurveFeatureIDs.dropFirst().last
            }
            section = sectionCurveFeatureID.map {
                .curve(CurveSectionReference(featureID: $0))
            }
        }
        let reservedFeatureIDs = Set([pathFeatureID, section?.featureID].compactMap { $0 })
        return Resolution(
            section: section,
            pathFeatureID: pathFeatureID,
            guideFeatureIDs: uniqueFeatureIDs(
                allCurveFeatureIDs.filter { reservedFeatureIDs.contains($0) == false }
            )
        )
    }

    private func orderedCandidateSceneNodes(
        targetSceneNodeID: SceneNodeID?
    ) -> [CandidateSceneNode] {
        var sceneNodes = selection.selectedSceneNodeIDs.map {
            CandidateSceneNode(id: $0, isTarget: false)
        }
        if let targetSceneNodeID {
            sceneNodes.append(CandidateSceneNode(id: targetSceneNodeID, isTarget: true))
        }
        var ordered: [CandidateSceneNode] = []
        for sceneNode in sceneNodes {
            if let index = ordered.firstIndex(where: { $0.id == sceneNode.id }) {
                ordered[index].isTarget = ordered[index].isTarget || sceneNode.isTarget
            } else {
                ordered.append(sceneNode)
            }
        }
        return ordered
    }

    private func sourceCandidate(
        for candidateSceneNode: CandidateSceneNode
    ) throws -> Candidate? {
        guard let sceneNode = document.productMetadata.sceneNodes[candidateSceneNode.id] else {
            return nil
        }
        // A selected face of a body is a closed section of its own.
        if let faceTarget = selection.selectedTargets.first(where: { target in
            guard target.sceneNodeID == sceneNode.id, case .face = target.component else { return false }
            return true
        }) {
            // Planning runs on a document without the store's evaluation, so it reads its own.
            let reference = try document.faceSectionReference(for: faceTarget, operationName: "Sweep", currentEvaluation: nil)
            return Candidate(isTarget: candidateSceneNode.isTarget, profileReference: nil, curveFeatureID: nil, face: reference)
        }
        let referencedFeatureID = sceneNode.reference?.featureID
        if let referencedFeatureID,
           let section = try document.explicitModelingSectionReference(
               for: referencedFeatureID, sceneNodeID: sceneNode.id, selectedTargets: selection.selectedTargets) {
            switch section {
            case .profile(let reference):
                return Candidate(isTarget: candidateSceneNode.isTarget, profileReference: reference, curveFeatureID: nil)
            case .curve(let reference):
                guard isCurveFeature(reference.featureID) else {
                    throw EditorError(code: .commandInvalid, message: "Selected source does not produce a curve.")
                }
                return Candidate(isTarget: candidateSceneNode.isTarget, profileReference: nil, curveFeatureID: reference.featureID)
            case .face(let reference):
                return Candidate(isTarget: candidateSceneNode.isTarget, profileReference: nil, curveFeatureID: nil, face: reference)
            }
        }
        let sketchFeatureID = sceneNode.reference?.kind == .sketch ? referencedFeatureID : nil
        var profileReference: ProfileReference?
        for candidateReference in [
            sceneNode.object?.sourceSection?.profileReference,
            sketchFeatureID.map { ProfileReference(featureID: $0) },
        ].compactMap({ $0 }) {
            if try isSupportedProfile(candidateReference.featureID) {
                profileReference = candidateReference
                break
            }
        }
        let curveFeatureID: FeatureID?
        if profileReference == nil,
           let referencedFeatureID,
           isCurveFeature(referencedFeatureID) {
            curveFeatureID = referencedFeatureID
        } else {
            curveFeatureID = nil
        }
        guard profileReference != nil || curveFeatureID != nil else {
            return nil
        }
        return Candidate(
            isTarget: candidateSceneNode.isTarget,
            profileReference: profileReference,
            curveFeatureID: curveFeatureID
        )
    }

    private func isSupportedProfile(_ featureID: FeatureID) throws -> Bool {
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              feature.outputs.contains(where: { $0.role == .profile }),
              case .sketch = feature.operation else {
            return false
        }
        return try document.modelingSectionReference(for: featureID).isProfile
    }

    private func isCurveFeature(_ featureID: FeatureID) -> Bool {
        guard let feature = document.cadDocument.designGraph.nodes[featureID] else {
            return false
        }
        return feature.outputs.contains { $0.role == .curve }
    }

    private func uniqueFeatureIDs(_ featureIDs: [FeatureID]) -> [FeatureID] {
        var unique: [FeatureID] = []
        var seen: Set<FeatureID> = []
        for featureID in featureIDs where seen.insert(featureID).inserted {
            unique.append(featureID)
        }
        return unique
    }
}
