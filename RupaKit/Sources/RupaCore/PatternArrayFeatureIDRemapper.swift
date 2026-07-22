import SwiftCAD
import RupaCoreTypes

struct PatternArrayFeatureIDRemapper: Sendable {
    private let featureIDMap: [FeatureID: FeatureID]

    init(featureIDMap: [FeatureID: FeatureID]) {
        self.featureIDMap = featureIDMap
    }

    func remappedFeatureID(_ featureID: FeatureID) throws -> FeatureID {
        guard let remapped = featureIDMap[featureID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array feature remapping can only reference cloned source feature dependencies."
            )
        }
        return remapped
    }

    func remappedInput(_ input: FeatureInput) throws -> FeatureInput {
        FeatureInput(
            featureID: try remappedFeatureID(input.featureID),
            role: input.role
        )
    }

    func remappedOutput(_ output: FeatureOutput) throws -> FeatureOutput {
        FeatureOutput(role: output.role)
    }

    func remappedOperation(_ operation: FeatureOperation) throws -> FeatureOperation {
        switch operation {
        case .sketch:
            return operation
        case .extrude(var extrude):
            extrude.profile = try remappedProfileReference(extrude.profile)
            return .extrude(extrude)
        case .revolve(var revolve):
            revolve.profile = try remappedProfileReference(revolve.profile)
            return .revolve(revolve)
        case .sweep(var sweep):
            sweep.sections = try sweep.sections.map(remappedSweepSectionReference)
            sweep.path = SweepPathReference(
                featureID: try remappedFeatureID(sweep.path.featureID)
            )
            sweep.guides = try sweep.guides.map {
                SweepGuideReference(featureID: try remappedFeatureID($0.featureID))
            }
            sweep.targets = try sweep.targets.map {
                SweepTargetReference(featureID: try remappedFeatureID($0.featureID))
            }
            return .sweep(sweep)
        case .loft(var loft):
            loft.sections = try loft.sections.map { section in
                LoftSectionReference(
                    profile: try remappedProfileReference(section.profile),
                    startSampleIndex: section.startSampleIndex,
                    smoothTangentScale: section.smoothTangentScale,
                    smoothTangentMode: section.smoothTangentMode
                )
            }
            loft.guides = try loft.guides.map {
                LoftGuideReference(featureID: try remappedFeatureID($0.featureID))
            }
            return .loft(loft)
        case .boolean(var boolean):
            boolean.targets = try boolean.targets.map {
                BooleanTargetReference(featureID: try remappedFeatureID($0.featureID))
            }
            boolean.tool = BooleanToolReference(
                featureID: try remappedFeatureID(boolean.tool.featureID)
            )
            return .boolean(boolean)
        case .polySpline:
            return operation
        case .bSplineSurface:
            return operation
        case .faceLoopOffset(var faceLoopOffset):
            faceLoopOffset.target = FaceLoopOffsetTargetReference(
                featureID: try remappedFeatureID(faceLoopOffset.target.featureID)
            )
            faceLoopOffset.face = try remappedStableReference(faceLoopOffset.face)
            return .faceLoopOffset(faceLoopOffset)
        case .edgeOffset(var edgeOffset):
            edgeOffset.target = EdgeOffsetTargetReference(
                featureID: try remappedFeatureID(edgeOffset.target.featureID)
            )
            edgeOffset.edge = try remappedStableReference(edgeOffset.edge)
            edgeOffset.supportFace = try remappedStableReference(edgeOffset.supportFace)
            return .edgeOffset(edgeOffset)
        case .faceKnife(var faceKnife):
            faceKnife.target = FaceKnifeTargetReference(
                featureID: try remappedFeatureID(faceKnife.target.featureID)
            )
            faceKnife.face = try remappedStableReference(faceKnife.face)
            return .faceKnife(faceKnife)
        case .faceDelete(var faceDelete):
            faceDelete.target = FaceDeleteTargetReference(
                featureID: try remappedFeatureID(faceDelete.target.featureID)
            )
            faceDelete.faces = try faceDelete.faces.map(remappedStableReference)
            return .faceDelete(faceDelete)
        case .faceDraft(var faceDraft):
            faceDraft.target = FaceDraftTargetReference(
                featureID: try remappedFeatureID(faceDraft.target.featureID)
            )
            faceDraft.faces = try faceDraft.faces.map(remappedStableReference)
            faceDraft.neutralFace = try remappedStableReference(faceDraft.neutralFace)
            return .faceDraft(faceDraft)
        case .bridgeCurve:
            return operation
        case .curveEdit(var curveEdit):
            curveEdit.source = try remappedCurveOutputReference(curveEdit.source)
            curveEdit.edits = try curveEdit.edits.map(remappedCurveEdit)
            return .curveEdit(curveEdit)
        case .curveOffset(var curveOffset):
            curveOffset.source = try remappedCurveOutputReference(curveOffset.source)
            return .curveOffset(curveOffset)
        case .curveTrim(var curveTrim):
            curveTrim.source = try remappedCurveOutputReference(curveTrim.source)
            return .curveTrim(curveTrim)
        case .primitive,
             .patchSurface,
             .faceOffset,
             .faceMove,
             .edgeMove,
             .vertexMove,
             .linearPattern,
             .radialPattern,
             .gridPattern,
             .curveDrivenPattern,
             .chamfer,
             .fillet,
             .g2Blend,
             .setbackCorner,
             .shell,
             .thicken,
             .bridgeSurface,
             .curveExtend,
             .curveMatch,
             .surfaceOffset,
             .surfaceTrim,
             .surfaceExtend,
             .surfaceMatch:
            // Pattern-array cloning currently reaches this remapper for every source feature.
            // Forward feature operations are not yet cloned here, and must fail until every
            // embedded feature and stable-subshape reference is remapped deterministically.
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays do not yet support cloning this forward CAD operation."
            )
        }
    }

    func remappedStableReference(
        _ reference: StableSubshapeReference
    ) throws -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(
                featureID: try remappedFeatureID(reference.subshapeID.featureID),
                role: reference.subshapeID.role,
                ordinal: reference.subshapeID.ordinal
            ),
            geometrySignature: reference.geometrySignature
        )
    }

    private func remappedProfileReference(_ reference: ProfileReference) throws -> ProfileReference {
        ProfileReference(
            featureID: try remappedFeatureID(reference.featureID),
            profileIndex: reference.profileIndex
        )
    }

    func remappedBodySourceSectionReference(
        _ reference: BodySourceSectionReference
    ) throws -> BodySourceSectionReference {
        switch reference {
        case .profile(let profile):
            return .profile(try remappedProfileReference(profile))
        case .curve(let featureID):
            return .curve(try remappedFeatureID(featureID))
        }
    }

    private func remappedSweepSectionReference(
        _ reference: SweepSectionReference
    ) throws -> SweepSectionReference {
        switch reference {
        case .profile(let profile):
            return .profile(try remappedProfileReference(profile))
        case .curve(let curve):
            return .curve(SweepCurveSectionReference(featureID: try remappedFeatureID(curve.featureID)))
        }
    }

    private func remappedCurveEdit(_ edit: CurveEdit) throws -> CurveEdit {
        switch edit {
        case .setControlPoint(var controlPointEdit):
            controlPointEdit.target = CurveControlPointReference(
                curve: try remappedCurveOutputReference(controlPointEdit.target.curve),
                controlPointIndex: controlPointEdit.target.controlPointIndex
            )
            return .setControlPoint(controlPointEdit)
        case .setKnot(var knotEdit):
            knotEdit.target = CurveKnotReference(
                curve: try remappedCurveOutputReference(knotEdit.target.curve),
                knotIndex: knotEdit.target.knotIndex
            )
            return .setKnot(knotEdit)
        case .setWeight(var weightEdit):
            weightEdit.target = CurveControlPointReference(
                curve: try remappedCurveOutputReference(weightEdit.target.curve),
                controlPointIndex: weightEdit.target.controlPointIndex
            )
            return .setWeight(weightEdit)
        }
    }

    private func remappedCurveOutputReference(
        _ reference: CurveOutputReference
    ) throws -> CurveOutputReference {
        CurveOutputReference(
            featureID: try remappedFeatureID(reference.featureID),
            curveIndex: reference.curveIndex
        )
    }
}
