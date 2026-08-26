import SwiftCAD

public struct SweepSelectionPlanningService: Sendable {
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

    public func command(
        targetSceneNodeID: SceneNodeID? = nil,
        name: String,
        options: SweepOptions = SweepOptions()
    ) throws -> EditorCommand {
        let resolution = try resolution(targetSceneNodeID: targetSceneNodeID)
        guard let section = resolution.section,
              let pathFeatureID = resolution.pathFeatureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep tool requires one profile or curve section source, one separate path curve source, and optional guide curve selections."
            )
        }
        var resolvedOptions = options
        if section.profile == nil {
            resolvedOptions.resultKind = .sheet
        }
        return .createSweep(
            name: name,
            sections: [section],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: resolution.guideFeatureIDs.map { SweepGuideReference(featureID: $0) },
            targets: [],
            options: resolvedOptions
        )
    }

    private struct Resolution {
        var section: SweepSectionReference?
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
        let profileReference = candidates.compactMap(\.profileReference).first
        let allCurveFeatureIDs = uniqueFeatureIDs(candidates.compactMap(\.curveFeatureID))
        let targetCurveFeatureID = candidates.last { $0.isTarget }?.curveFeatureID
        let section: SweepSectionReference?
        let pathFeatureID: FeatureID?
        if let profileReference {
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
                .curve(SweepCurveSectionReference(featureID: $0))
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
        let referencedFeatureID = sceneNode.reference?.featureID
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
              case .sketch(let sketch) = feature.operation else {
            return false
        }
        do {
            let parameters = try ParameterResolver().resolve(document.cadDocument.parameters)
            let profiles = try SketchProfileExtractor(
                tolerance: document.modelingSettings.tolerance
            ).extractProfiles(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: parameters
            )
            return profiles.isEmpty == false
        } catch {
            if error is SketchError || error is GeometryError || error is UnitError {
                return false
            }
            throw error
        }
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
