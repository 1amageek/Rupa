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
        case .extrude:
            return try remappedExtrudeOperation(operation)
        case .revolve:
            return try remappedRevolveOperation(operation)
        case .sweep:
            return try remappedSweepOperation(operation)
        case .loft:
            return try remappedLoftOperation(operation)
        case .boolean:
            return try remappedBooleanOperation(operation)
        case .polySpline:
            return operation
        case .bSplineSurface:
            return operation
        case .faceLoopOffset:
            return try remappedFaceLoopOffsetOperation(operation)
        case .edgeOffset:
            return try remappedEdgeOffsetOperation(operation)
        case .faceKnife:
            return try remappedFaceKnifeOperation(operation)
        case .faceDelete:
            return try remappedFaceDeleteOperation(operation)
        case .faceDraft:
            return try remappedFaceDraftOperation(operation)
        case .bridgeCurve:
            return operation
        case .curveEdit:
            return try remappedCurveEditOperation(operation)
        case .curveOffset:
            return try remappedCurveOffsetOperation(operation)
        case .curveTrim:
            return try remappedCurveTrimOperation(operation)
        case .primitive, .patchSurface, .bridgeSurface:
            return operation
        case .faceOffset:
            return try remappedFaceOffsetOperation(operation)
        case .faceMove:
            return try remappedFaceMoveOperation(operation)
        case .edgeMove:
            return try remappedEdgeMoveOperation(operation)
        case .vertexMove:
            return try remappedVertexMoveOperation(operation)
        case .linearPattern:
            return try remappedLinearPatternOperation(operation)
        case .radialPattern:
            return try remappedRadialPatternOperation(operation)
        case .gridPattern:
            return try remappedGridPatternOperation(operation)
        case .curveDrivenPattern:
            return try remappedCurveDrivenPatternOperation(operation)
        case .chamfer:
            return try remappedChamferOperation(operation)
        case .fillet:
            return try remappedFilletOperation(operation)
        case .g2Blend:
            return try remappedG2BlendOperation(operation)
        case .setbackCorner:
            return try remappedSetbackCornerOperation(operation)
        case .shell:
            return try remappedShellOperation(operation)
        case .thicken:
            return try remappedThickenOperation(operation)
        case .curveExtend:
            return try remappedCurveExtendOperation(operation)
        case .curveMatch:
            return try remappedCurveMatchOperation(operation)
        case .surfaceOffset:
            return try remappedSurfaceOffsetOperation(operation)
        case .surfaceTrim:
            return try remappedSurfaceTrimOperation(operation)
        case .surfaceExtend:
            return try remappedSurfaceExtendOperation(operation)
        case .surfaceMatch:
            return try remappedSurfaceMatchOperation(operation)
        }
    }

    @inline(never)
    private func remappedExtrudeOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .extrude(extrude) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a extrude operation."
            )
        }
        extrude.profile = try remappedProfileReference(extrude.profile)
        return .extrude(extrude)
    }

    @inline(never)
    private func remappedRevolveOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .revolve(revolve) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a revolve operation."
            )
        }
        revolve.profile = try remappedProfileReference(revolve.profile)
        return .revolve(revolve)
    }

    @inline(never)
    private func remappedSweepOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .sweep(sweep) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a sweep operation."
            )
        }
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
    }

    @inline(never)
    private func remappedLoftOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .loft(loft) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a loft operation."
            )
        }
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
    }

    @inline(never)
    private func remappedBooleanOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .boolean(boolean) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a boolean operation."
            )
        }
        boolean.targets = try boolean.targets.map {
            BooleanTargetReference(featureID: try remappedFeatureID($0.featureID))
        }
        boolean.tool = BooleanToolReference(
            featureID: try remappedFeatureID(boolean.tool.featureID)
        )
        return .boolean(boolean)
    }

    @inline(never)
    private func remappedFaceLoopOffsetOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .faceLoopOffset(faceLoopOffset) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a faceLoopOffset operation."
            )
        }
        faceLoopOffset.target = FaceLoopOffsetTargetReference(
            featureID: try remappedFeatureID(faceLoopOffset.target.featureID)
        )
        faceLoopOffset.face = try remappedStableSubshapeReference(faceLoopOffset.face)
        return .faceLoopOffset(faceLoopOffset)
    }

    @inline(never)
    private func remappedEdgeOffsetOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .edgeOffset(edgeOffset) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a edgeOffset operation."
            )
        }
        edgeOffset.target = EdgeOffsetTargetReference(
            featureID: try remappedFeatureID(edgeOffset.target.featureID)
        )
        edgeOffset.edge = try remappedStableSubshapeReference(edgeOffset.edge)
        edgeOffset.supportFace = try remappedStableSubshapeReference(edgeOffset.supportFace)
        return .edgeOffset(edgeOffset)
    }

    @inline(never)
    private func remappedFaceKnifeOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .faceKnife(faceKnife) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a faceKnife operation."
            )
        }
        faceKnife.target = FaceKnifeTargetReference(
            featureID: try remappedFeatureID(faceKnife.target.featureID)
        )
        faceKnife.face = try remappedStableSubshapeReference(faceKnife.face)
        return .faceKnife(faceKnife)
    }

    @inline(never)
    private func remappedFaceDeleteOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .faceDelete(faceDelete) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a faceDelete operation."
            )
        }
        faceDelete.target = FaceDeleteTargetReference(
            featureID: try remappedFeatureID(faceDelete.target.featureID)
        )
        faceDelete.faces = try faceDelete.faces.map(remappedStableSubshapeReference)
        return .faceDelete(faceDelete)
    }

    @inline(never)
    private func remappedFaceDraftOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .faceDraft(faceDraft) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a faceDraft operation."
            )
        }
        faceDraft.target = FaceDraftTargetReference(
            featureID: try remappedFeatureID(faceDraft.target.featureID)
        )
        faceDraft.faces = try faceDraft.faces.map(remappedStableSubshapeReference)
        faceDraft.neutralFace = try remappedStableSubshapeReference(faceDraft.neutralFace)
        return .faceDraft(faceDraft)
    }

    @inline(never)
    private func remappedCurveEditOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .curveEdit(curveEdit) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a curveEdit operation."
            )
        }
        curveEdit.source = try remappedCurveOutputReference(curveEdit.source)
        curveEdit.edits = try curveEdit.edits.map(remappedCurveEdit)
        return .curveEdit(curveEdit)
    }

    @inline(never)
    private func remappedCurveOffsetOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .curveOffset(curveOffset) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a curveOffset operation."
            )
        }
        curveOffset.source = try remappedCurveOutputReference(curveOffset.source)
        return .curveOffset(curveOffset)
    }

    @inline(never)
    private func remappedCurveTrimOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case var .curveTrim(curveTrim) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a curveTrim operation."
            )
        }
        curveTrim.source = try remappedCurveOutputReference(curveTrim.source)
        return .curveTrim(curveTrim)
    }

    @inline(never)
    private func remappedFaceOffsetOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .faceOffset(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a faceOffset operation."
            )
        }
        return .faceOffset(FaceOffsetFeature(
            target: FaceOffsetTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            face: try remappedStableSubshapeReference(feature.face),
            distance: feature.distance
        ))
    }

    @inline(never)
    private func remappedFaceMoveOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .faceMove(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a faceMove operation."
            )
        }
        return .faceMove(FaceMoveFeature(
            target: FaceMoveTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            face: try remappedStableSubshapeReference(feature.face),
            translation: feature.translation
        ))
    }

    @inline(never)
    private func remappedEdgeMoveOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .edgeMove(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a edgeMove operation."
            )
        }
        return .edgeMove(EdgeMoveFeature(
            target: EdgeMoveTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            edge: try remappedStableSubshapeReference(feature.edge),
            translation: feature.translation
        ))
    }

    @inline(never)
    private func remappedVertexMoveOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .vertexMove(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a vertexMove operation."
            )
        }
        return .vertexMove(VertexMoveFeature(
            target: VertexMoveTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            vertex: try remappedStableSubshapeReference(feature.vertex),
            translation: feature.translation
        ))
    }

    @inline(never)
    private func remappedLinearPatternOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .linearPattern(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a linearPattern operation."
            )
        }
        return .linearPattern(LinearPatternFeature(
            target: PatternTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            direction: feature.direction,
            spacing: feature.spacing,
            count: feature.count
        ))
    }

    @inline(never)
    private func remappedRadialPatternOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .radialPattern(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a radialPattern operation."
            )
        }
        return .radialPattern(RadialPatternFeature(
            target: PatternTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            axisOrigin: feature.axisOrigin,
            axisDirection: feature.axisDirection,
            angularSpacing: feature.angularSpacing,
            count: feature.count
        ))
    }

    @inline(never)
    private func remappedGridPatternOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .gridPattern(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a gridPattern operation."
            )
        }
        return .gridPattern(GridPatternFeature(
            target: PatternTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            firstDirection: feature.firstDirection,
            firstSpacing: feature.firstSpacing,
            firstCount: feature.firstCount,
            secondDirection: feature.secondDirection,
            secondSpacing: feature.secondSpacing,
            secondCount: feature.secondCount
        ))
    }

    @inline(never)
    private func remappedCurveDrivenPatternOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .curveDrivenPattern(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a curveDrivenPattern operation."
            )
        }
        return .curveDrivenPattern(CurveDrivenPatternFeature(
            target: PatternTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            path: CurveDrivenPatternPathReference(
                featureID: try remappedFeatureID(feature.path.featureID)
            ),
            anchor: feature.anchor,
            referenceDirection: feature.referenceDirection,
            count: feature.count
        ))
    }

    @inline(never)
    private func remappedChamferOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .chamfer(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a chamfer operation."
            )
        }
        return .chamfer(ChamferFeature(
            target: ChamferTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            edges: try feature.edges.map(remappedStableSubshapeReference),
            distance: feature.distance
        ))
    }

    @inline(never)
    private func remappedFilletOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .fillet(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a fillet operation."
            )
        }
        return .fillet(FilletFeature(
            target: FilletTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            edges: try feature.edges.map(remappedStableSubshapeReference),
            radius: feature.radius
        ))
    }

    @inline(never)
    private func remappedG2BlendOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .g2Blend(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a g2Blend operation."
            )
        }
        return .g2Blend(G2BlendFeature(
            target: G2BlendTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            edges: try feature.edges.map(remappedStableSubshapeReference),
            distance: feature.distance
        ))
    }

    @inline(never)
    private func remappedSetbackCornerOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .setbackCorner(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a setbackCorner operation."
            )
        }
        return .setbackCorner(SetbackCornerFeature(
            target: SetbackCornerTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            vertex: try remappedStableSubshapeReference(feature.vertex),
            radius: feature.radius
        ))
    }

    @inline(never)
    private func remappedShellOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .shell(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a shell operation."
            )
        }
        return .shell(ShellFeature(
            target: ShellTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            removedFaces: try feature.removedFaces.map(remappedStableSubshapeReference),
            thickness: feature.thickness
        ))
    }

    @inline(never)
    private func remappedThickenOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .thicken(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a thicken operation."
            )
        }
        return .thicken(ThickenFeature(
            target: ThickenTargetReference(
                featureID: try remappedFeatureID(feature.target.featureID)
            ),
            thickness: feature.thickness,
            side: feature.side
        ))
    }

    @inline(never)
    private func remappedCurveExtendOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .curveExtend(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a curveExtend operation."
            )
        }
        return .curveExtend(CurveExtendFeature(
            source: try remappedCurveOutputReference(feature.source),
            end: feature.end,
            distance: feature.distance
        ))
    }

    @inline(never)
    private func remappedCurveMatchOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .curveMatch(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a curveMatch operation."
            )
        }
        return .curveMatch(CurveMatchFeature(
            source: try remappedCurveOutputReference(feature.source),
            sourceEnd: feature.sourceEnd,
            target: try remappedCurveOutputReference(feature.target),
            targetEnd: feature.targetEnd,
            targetOrientation: feature.targetOrientation,
            continuity: feature.continuity
        ))
    }

    @inline(never)
    private func remappedSurfaceOffsetOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .surfaceOffset(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a surfaceOffset operation."
            )
        }
        return .surfaceOffset(SurfaceOffsetFeature(
            target: try remappedSurfaceOperationTarget(feature.target),
            distance: feature.distance
        ))
    }

    @inline(never)
    private func remappedSurfaceTrimOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .surfaceTrim(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a surfaceTrim operation."
            )
        }
        return .surfaceTrim(SurfaceTrimFeature(
            target: try remappedSurfaceOperationTarget(feature.target),
            loops: feature.loops
        ))
    }

    @inline(never)
    private func remappedSurfaceExtendOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .surfaceExtend(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a surfaceExtend operation."
            )
        }
        return .surfaceExtend(SurfaceExtendFeature(
            target: try remappedSurfaceOperationTarget(feature.target),
            uDomain: feature.uDomain,
            vDomain: feature.vDomain
        ))
    }

    @inline(never)
    private func remappedSurfaceMatchOperation(
        _ operation: FeatureOperation
    ) throws -> FeatureOperation {
        guard case let .surfaceMatch(feature) = operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array remapping dispatch expected a surfaceMatch operation."
            )
        }
        return .surfaceMatch(SurfaceMatchFeature(
            source: try remappedSurfaceOperationTarget(feature.source),
            target: try remappedSurfaceOperationTarget(feature.target),
            sourceParameter: feature.sourceParameter,
            targetParameter: feature.targetParameter,
            normalAlignment: feature.normalAlignment,
            continuity: feature.continuity
        ))
    }

    private func remappedSurfaceOperationTarget(
        _ reference: SurfaceOperationTargetReference
    ) throws -> SurfaceOperationTargetReference {
        SurfaceOperationTargetReference(
            featureID: try remappedFeatureID(reference.featureID),
            face: try remappedStableSubshapeReference(reference.face)
        )
    }

    func remappedStableSubshapeReference(
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
