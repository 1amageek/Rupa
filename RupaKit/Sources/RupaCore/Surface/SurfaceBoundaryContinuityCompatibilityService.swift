import SwiftCAD
import RupaCoreTypes

struct SurfaceBoundaryContinuityCompatibilityService: Sendable {
    private let profileBuilder = BSplineSurfaceBoundaryProfileBuilder()
    private let evaluator = BSplineSurfaceBoundaryContinuityCompatibilityEvaluator()
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    func compatibility(
        targetFeatureID: FeatureID,
        targetSelectionReference: SelectionReference,
        targetFeature: BSplineSurfaceFeature,
        targetSide: BSplineSurfaceBoundarySide,
        referenceFeatureID: FeatureID,
        referenceSelectionReference: SelectionReference,
        referenceFeature: BSplineSurfaceFeature,
        referenceSide: BSplineSurfaceBoundarySide
    ) throws -> SurfaceBoundaryContinuityCompatibilityResult {
        try targetFeature.validate(tolerance: tolerance)
        try referenceFeature.validate(tolerance: tolerance)

        let targetProfile = profileBuilder.profile(side: targetSide, surface: targetFeature.surface)
        let referenceProfile = profileBuilder.profile(side: referenceSide, surface: referenceFeature.surface)
        let isSameBoundary = targetFeatureID == referenceFeatureID && targetSide == referenceSide
        let evaluation = evaluator.evaluate(
            target: targetProfile,
            reference: referenceProfile,
            isSameBoundary: isSameBoundary
        )
        let referenceDirection = evaluation.supportedContinuityLevels.contains(.g0)
            ? recommendedReferenceDirection(
                target: targetFeature.surface,
                targetProfile: targetProfile,
                reference: referenceFeature.surface,
                referenceProfile: referenceProfile
            )
            : nil
        let matchSide = evaluation.supportedContinuityLevels.contains { $0.requiresFirstDerivative }
            ? recommendedMatchSide(
                target: targetFeature.surface,
                targetProfile: targetProfile,
                reference: referenceFeature.surface,
                referenceProfile: referenceProfile,
                referenceDirection: referenceDirection
            )
            : nil

        return SurfaceBoundaryContinuityCompatibilityResult(
            status: evaluation.supportedContinuityLevels.isEmpty ? .incompatible : .compatible,
            target: boundary(
                featureID: targetFeatureID,
                selectionReference: targetSelectionReference,
                profile: targetProfile
            ),
            reference: boundary(
                featureID: referenceFeatureID,
                selectionReference: referenceSelectionReference,
                profile: referenceProfile
            ),
            supportedContinuityLevels: evaluation.supportedContinuityLevels,
            maximumSupportedContinuityLevel: evaluation.supportedContinuityLevels.last,
            recommendedReferenceDirection: referenceDirection,
            recommendedMatchSide: matchSide,
            diagnostics: evaluation.diagnostics
        )
    }

    private func boundary(
        featureID: FeatureID,
        selectionReference: SelectionReference,
        profile: BSplineSurfaceBoundaryProfile
    ) -> SurfaceBoundaryContinuityCompatibilityResult.Boundary {
        SurfaceBoundaryContinuityCompatibilityResult.Boundary(
            featureID: featureID,
            selectionReference: selectionReference,
            role: profile.side.rawValue,
            boundaryDirection: profile.boundaryDirection,
            inwardDirection: profile.inwardDirection,
            boundaryDegree: profile.boundaryDegree,
            inwardDegree: profile.inwardDegree,
            boundaryControlPointCount: profile.boundaryControlPointCount,
            inwardControlPointCount: profile.inwardControlPointCount,
            isClamped: profile.isClamped,
            supportedContinuityLevels: profile.supportedContinuityLevels
        )
    }

    private func recommendedReferenceDirection(
        target: BSplineSurface3D,
        targetProfile: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurface3D,
        referenceProfile: BSplineSurfaceBoundaryProfile
    ) -> SurfaceBoundaryReferenceDirection? {
        guard targetProfile.boundaryControlPointCount == referenceProfile.boundaryControlPointCount,
              targetProfile.boundaryControlPointCount >= 2 else {
            return nil
        }
        var forwardDistance = 0.0
        var reversedDistance = 0.0
        let boundaryControlPointCount = targetProfile.boundaryControlPointCount
        for ordinal in 0..<boundaryControlPointCount {
            let targetPoint = point(
                atBoundaryOrdinal: ordinal,
                inwardOffset: 0,
                side: targetProfile.side,
                surface: target
            )
            let forwardReferencePoint = point(
                atBoundaryOrdinal: ordinal,
                inwardOffset: 0,
                side: referenceProfile.side,
                surface: reference
            )
            let reversedReferencePoint = point(
                atBoundaryOrdinal: boundaryControlPointCount - 1 - ordinal,
                inwardOffset: 0,
                side: referenceProfile.side,
                surface: reference
            )
            forwardDistance += distance(targetPoint, forwardReferencePoint)
            reversedDistance += distance(targetPoint, reversedReferencePoint)
        }
        guard forwardDistance.isFinite, reversedDistance.isFinite else {
            return nil
        }
        let tieDistance = ModelingTolerance.standard.distance * Double(boundaryControlPointCount)
        guard abs(forwardDistance - reversedDistance) > tieDistance else {
            return nil
        }
        return reversedDistance < forwardDistance ? .reversed : .forward
    }

    private func recommendedMatchSide(
        target: BSplineSurface3D,
        targetProfile: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurface3D,
        referenceProfile: BSplineSurfaceBoundaryProfile,
        referenceDirection: SurfaceBoundaryReferenceDirection?
    ) -> SurfaceBoundaryMatchSide? {
        guard let referenceDirection,
              targetProfile.boundaryControlPointCount == referenceProfile.boundaryControlPointCount,
              targetProfile.boundaryControlPointCount >= 2,
              targetProfile.inwardControlPointCount >= 2,
              referenceProfile.inwardControlPointCount >= 2 else {
            return nil
        }
        var cosineSum = 0.0
        var sampleCount = 0
        let lengthTolerance = ModelingTolerance.standard.distance
        for ordinal in 0..<targetProfile.boundaryControlPointCount {
            let referenceOrdinal = referenceDirection == .reversed
                ? referenceProfile.boundaryControlPointCount - 1 - ordinal
                : ordinal
            let targetBoundary = point(
                atBoundaryOrdinal: ordinal,
                inwardOffset: 0,
                side: targetProfile.side,
                surface: target
            )
            let targetInward = point(
                atBoundaryOrdinal: ordinal,
                inwardOffset: 1,
                side: targetProfile.side,
                surface: target
            ) - targetBoundary
            let referenceBoundary = point(
                atBoundaryOrdinal: referenceOrdinal,
                inwardOffset: 0,
                side: referenceProfile.side,
                surface: reference
            )
            let referenceInward = point(
                atBoundaryOrdinal: referenceOrdinal,
                inwardOffset: 1,
                side: referenceProfile.side,
                surface: reference
            ) - referenceBoundary
            let targetLength = targetInward.length
            let referenceLength = referenceInward.length
            guard targetLength > lengthTolerance,
                  referenceLength > lengthTolerance,
                  targetLength.isFinite,
                  referenceLength.isFinite else {
                continue
            }
            cosineSum += targetInward.dot(referenceInward) / (targetLength * referenceLength)
            sampleCount += 1
        }
        guard sampleCount > 0 else {
            return nil
        }
        let averageCosine = cosineSum / Double(sampleCount)
        guard abs(averageCosine) > ModelingTolerance.standard.angle else {
            return nil
        }
        return averageCosine < 0.0 ? .opposite : .same
    }

    private func point(
        atBoundaryOrdinal ordinal: Int,
        inwardOffset: Int,
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D
    ) -> Point3D {
        switch side {
        case .vMin, .vMax:
            return surface.controlPoints[side.inwardIndex(offset: inwardOffset, in: surface)][ordinal]
        case .uMin, .uMax:
            return surface.controlPoints[ordinal][side.inwardIndex(offset: inwardOffset, in: surface)]
        }
    }

    private func distance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
        (lhs - rhs).length
    }
}

struct BSplineSurfaceBoundaryContinuityCompatibilityEvaluator: Sendable {
    struct Evaluation: Equatable, Sendable {
        var supportedContinuityLevels: [SurfaceBoundaryContinuityLevel]
        var diagnostics: [SurfaceBoundaryContinuityCompatibilityResult.Diagnostic]
    }

    private let profileBuilder = BSplineSurfaceBoundaryProfileBuilder()

    func evaluate(
        target: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurfaceBoundaryProfile,
        isSameBoundary: Bool
    ) -> Evaluation {
        var diagnostics = baseDiagnostics(
            target: target,
            reference: reference,
            isSameBoundary: isSameBoundary
        )
        let baseIsCompatible = diagnostics.contains { $0.severity == .error } == false
        guard baseIsCompatible else {
            return Evaluation(supportedContinuityLevels: [], diagnostics: diagnostics)
        }

        var levels: [SurfaceBoundaryContinuityLevel] = [.g0]
        if supportsFirstDerivative(target: target, reference: reference) {
            levels.append(.g1)
        } else {
            diagnostics.append(.warning(
                code: "insufficientFirstInwardRows",
                message: "G1 continuity requires at least two control rows across each boundary."
            ))
        }
        if supportsSecondDerivative(target: target, reference: reference) {
            levels.append(.g2)
        } else {
            diagnostics.append(secondDerivativeLimitation(target: target, reference: reference))
        }
        let supportedLevelSummary = levels.map { $0.rawValue.uppercased() }.joined(separator: "/")
        diagnostics.append(.info(
            code: "compatibleBoundaryPair",
            message: "Boundary pair supports \(supportedLevelSummary) continuity matching."
        ))
        return Evaluation(supportedContinuityLevels: levels, diagnostics: diagnostics)
    }

    func validate(
        target: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurfaceBoundaryProfile,
        isSameBoundary: Bool,
        level: SurfaceBoundaryContinuityLevel,
        owner: String
    ) throws {
        guard isSameBoundary == false else {
            throw invalid("\(owner) requires distinct target and reference boundaries.")
        }
        guard target.boundaryControlPointCount == reference.boundaryControlPointCount else {
            throw invalid("\(owner) requires matching boundary control point counts.")
        }
        guard target.boundaryControlPointCount >= 2 else {
            throw invalid("\(owner) requires non-collapsed surface boundaries.")
        }
        guard target.isClamped, reference.isClamped else {
            throw invalid("\(owner) requires clamped outer boundaries so control rows map to surface boundaries.")
        }
        guard target.boundaryDegree == reference.boundaryDegree,
              profileBuilder.knotVectorsMatch(target.boundaryKnots, reference.boundaryKnots) else {
            throw invalid("\(owner) requires matching boundary degree and knot vectors.")
        }
        if level.requiresFirstDerivative {
            guard supportsFirstDerivative(target: target, reference: reference) else {
                throw invalid("\(owner) G1 continuity requires at least two control rows across each boundary.")
            }
        }
        if level.requiresSecondDerivative {
            guard target.inwardControlPointCount >= 3,
                  reference.inwardControlPointCount >= 3 else {
                throw invalid("\(owner) G2 continuity requires at least three control rows across each boundary.")
            }
            guard target.inwardDegree >= 2,
                  reference.inwardDegree >= 2 else {
                throw invalid("\(owner) G2 continuity requires quadratic or higher degree across each boundary.")
            }
        }
    }

    private func baseDiagnostics(
        target: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurfaceBoundaryProfile,
        isSameBoundary: Bool
    ) -> [SurfaceBoundaryContinuityCompatibilityResult.Diagnostic] {
        var diagnostics: [SurfaceBoundaryContinuityCompatibilityResult.Diagnostic] = []
        if isSameBoundary {
            diagnostics.append(.error(
                code: "sameBoundary",
                message: "Boundary continuity requires distinct target and reference boundaries."
            ))
        }
        if target.boundaryControlPointCount != reference.boundaryControlPointCount {
            diagnostics.append(.error(
                code: "boundaryControlPointCountMismatch",
                message: "Boundary continuity requires matching boundary control point counts."
            ))
        }
        if target.boundaryControlPointCount < 2 || reference.boundaryControlPointCount < 2 {
            diagnostics.append(.error(
                code: "collapsedBoundary",
                message: "Boundary continuity requires non-collapsed surface boundaries."
            ))
        }
        if target.isClamped == false || reference.isClamped == false {
            diagnostics.append(.error(
                code: "unclampedBoundary",
                message: "Boundary continuity requires clamped outer boundaries so control rows map to surface boundaries."
            ))
        }
        if target.boundaryDegree != reference.boundaryDegree
            || profileBuilder.knotVectorsMatch(target.boundaryKnots, reference.boundaryKnots) == false {
            diagnostics.append(.error(
                code: "boundaryBasisMismatch",
                message: "Boundary continuity requires matching boundary degree and knot vectors."
            ))
        }
        return diagnostics
    }

    private func supportsFirstDerivative(
        target: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurfaceBoundaryProfile
    ) -> Bool {
        target.inwardControlPointCount >= 2 && reference.inwardControlPointCount >= 2
    }

    private func supportsSecondDerivative(
        target: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurfaceBoundaryProfile
    ) -> Bool {
        target.inwardControlPointCount >= 3
            && reference.inwardControlPointCount >= 3
            && target.inwardDegree >= 2
            && reference.inwardDegree >= 2
    }

    private func secondDerivativeLimitation(
        target: BSplineSurfaceBoundaryProfile,
        reference: BSplineSurfaceBoundaryProfile
    ) -> SurfaceBoundaryContinuityCompatibilityResult.Diagnostic {
        if target.inwardControlPointCount < 3 || reference.inwardControlPointCount < 3 {
            return .warning(
                code: "insufficientSecondInwardRows",
                message: "G2 continuity requires at least three control rows across each boundary."
            )
        }
        return .warning(
            code: "insufficientSecondInwardDegree",
            message: "G2 continuity requires quadratic or higher degree across each boundary."
        )
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }
}

private extension SurfaceBoundaryContinuityCompatibilityResult.Diagnostic {
    static func info(code: String, message: String) -> Self {
        Self(severity: .info, code: code, message: message)
    }

    static func warning(code: String, message: String) -> Self {
        Self(severity: .warning, code: code, message: message)
    }

    static func error(code: String, message: String) -> Self {
        Self(severity: .error, code: code, message: message)
    }
}
