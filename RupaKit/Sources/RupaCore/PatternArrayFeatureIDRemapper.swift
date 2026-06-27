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
        FeatureOutput(
            role: output.role,
            persistentName: try output.persistentName.map {
                try remappedPersistentName($0)
            }
        )
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
        case .polySpline:
            return operation
        case .faceLoopOffset(var faceLoopOffset):
            faceLoopOffset.target = FaceLoopOffsetTargetReference(
                featureID: try remappedFeatureID(faceLoopOffset.target.featureID)
            )
            faceLoopOffset.facePersistentName = try remappedPersistentName(
                faceLoopOffset.facePersistentName
            )
            return .faceLoopOffset(faceLoopOffset)
        case .edgeOffset(var edgeOffset):
            edgeOffset.target = EdgeOffsetTargetReference(
                featureID: try remappedFeatureID(edgeOffset.target.featureID)
            )
            edgeOffset.edgePersistentName = try remappedPersistentName(edgeOffset.edgePersistentName)
            edgeOffset.supportFacePersistentName = try remappedPersistentName(
                edgeOffset.supportFacePersistentName
            )
            return .edgeOffset(edgeOffset)
        case .faceKnife(var faceKnife):
            faceKnife.target = FaceKnifeTargetReference(
                featureID: try remappedFeatureID(faceKnife.target.featureID)
            )
            faceKnife.facePersistentName = try remappedPersistentName(faceKnife.facePersistentName)
            return .faceKnife(faceKnife)
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
        }
    }

    func remappedPersistentName(_ name: PersistentName) throws -> PersistentName {
        PersistentName(components: try name.components.map { component in
            switch component {
            case .feature(let featureID):
                return .feature(try remappedFeatureID(featureID))
            case .generated, .subshape, .index:
                return component
            }
        })
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
