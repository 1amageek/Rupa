import RupaCore

struct SurfaceBoundaryContinuityInspectorState: Equatable {
    struct TrimDomain: Equatable {
        var targetReference: SelectionReference
        var uLowerBound: Double
        var uUpperBound: Double
        var vLowerBound: Double
        var vUpperBound: Double
        var fullULowerBound: Double
        var fullUUpperBound: Double
        var fullVLowerBound: Double
        var fullVUpperBound: Double

        var isFullDomain: Bool {
            let uScale = max(abs(fullUUpperBound - fullULowerBound), 1.0)
            let vScale = max(abs(fullVUpperBound - fullVLowerBound), 1.0)
            return abs(uLowerBound - fullULowerBound) <= uScale * 1.0e-9
                && abs(uUpperBound - fullUUpperBound) <= uScale * 1.0e-9
                && abs(vLowerBound - fullVLowerBound) <= vScale * 1.0e-9
                && abs(vUpperBound - fullVUpperBound) <= vScale * 1.0e-9
        }
    }

    var selectedTrimCount: Int
    var targetReference: SelectionReference?
    var referenceReference: SelectionReference?
    var targetSupportedLevelSummary: String?
    var referenceSupportedLevelSummary: String?
    var pairSupportedLevelSummary: String?
    var supportedContinuityLevels: [SurfaceBoundaryContinuityLevel]
    var recommendedReferenceDirectionSummary: String?
    var recommendedMatchSideSummary: String?
    var diagnosticMessages: [String]
    var statusTitle: String
    var trimDomain: TrimDomain?

    var canMatch: Bool {
        targetReference != nil && referenceReference != nil && supportedContinuityLevels.isEmpty == false
    }

    init(
        selectedReferences: [SelectionReference],
        summaryResult: SurfaceSourceSummaryResult,
        compatibilityResult: SurfaceBoundaryContinuityCompatibilityResult? = nil,
        compatibilityErrorMessage: String? = nil
    ) {
        supportedContinuityLevels = []
        diagnosticMessages = []
        let trimReferences = selectedReferences.filter { reference in
            if case .surface(.trim) = reference {
                return true
            }
            return false
        }
        selectedTrimCount = trimReferences.count
        trimDomain = Self.trimDomain(for: trimReferences.first, in: summaryResult)

        let editableEdgesByReference = Self.editableDirectBSplineTrimEdgesByReference(in: summaryResult)
        let editableReferences = Set(editableEdgesByReference.keys)
        let selectedEditableReferences = trimReferences.filter { editableReferences.contains($0) }
        if selectedEditableReferences.count == 2 {
            targetReference = selectedEditableReferences[0]
            referenceReference = selectedEditableReferences[1]
            targetSupportedLevelSummary = Self.supportedLevelSummary(
                editableEdgesByReference[selectedEditableReferences[0]]?.supportedBoundaryContinuityLevels ?? []
            )
            referenceSupportedLevelSummary = Self.supportedLevelSummary(
                editableEdgesByReference[selectedEditableReferences[1]]?.supportedBoundaryContinuityLevels ?? []
            )
            if let compatibilityResult {
                supportedContinuityLevels = compatibilityResult.supportedContinuityLevels
                pairSupportedLevelSummary = Self.supportedLevelSummary(compatibilityResult.supportedContinuityLevels)
                recommendedReferenceDirectionSummary = compatibilityResult
                    .recommendedReferenceDirection?
                    .rawValue
                recommendedMatchSideSummary = compatibilityResult
                    .recommendedMatchSide?
                    .rawValue
                diagnosticMessages = compatibilityResult.diagnostics.map(\.message)
                switch compatibilityResult.status {
                case .compatible:
                    statusTitle = "Compatible"
                case .incompatible:
                    statusTitle = "Incompatible"
                }
            } else if let compatibilityErrorMessage {
                pairSupportedLevelSummary = nil
                recommendedReferenceDirectionSummary = nil
                recommendedMatchSideSummary = nil
                diagnosticMessages = [compatibilityErrorMessage]
                statusTitle = "Unavailable"
            } else {
                pairSupportedLevelSummary = nil
                recommendedReferenceDirectionSummary = nil
                recommendedMatchSideSummary = nil
                statusTitle = "Ready"
            }
        } else if trimReferences.count == 2 {
            targetReference = nil
            referenceReference = nil
            targetSupportedLevelSummary = nil
            referenceSupportedLevelSummary = nil
            pairSupportedLevelSummary = nil
            recommendedReferenceDirectionSummary = nil
            recommendedMatchSideSummary = nil
            statusTitle = "Supported direct B-spline trim edges required"
        } else {
            targetReference = nil
            referenceReference = nil
            targetSupportedLevelSummary = nil
            referenceSupportedLevelSummary = nil
            pairSupportedLevelSummary = nil
            recommendedReferenceDirectionSummary = nil
            recommendedMatchSideSummary = nil
            statusTitle = "Select two surface trims"
        }
    }

    func supports(_ level: SurfaceBoundaryContinuityLevel) -> Bool {
        supportedContinuityLevels.contains(level)
    }

    func resolvedContinuityLevel(
        preferred level: SurfaceBoundaryContinuityLevel
    ) -> SurfaceBoundaryContinuityLevel? {
        if supports(level) {
            return level
        }
        return supportedContinuityLevels.last
    }

    private static func editableDirectBSplineTrimEdgesByReference(
        in summary: SurfaceSourceSummaryResult
    ) -> [SelectionReference: SurfaceSourceSummaryResult.TrimLoop.Edge] {
        var edgesByReference: [SelectionReference: SurfaceSourceSummaryResult.TrimLoop.Edge] = [:]
        for source in summary.sources where source.kind == "bSplineSurface" {
            for patch in source.patches {
                for trimLoop in patch.trimLoops {
                    for edge in trimLoop.edges where edge.supportsBoundaryContinuityMatching {
                        guard let reference = edge.selectionReference else {
                            continue
                        }
                        edgesByReference[reference] = edge
                    }
                }
            }
        }
        return edgesByReference
    }

    private static func trimDomain(
        for reference: SelectionReference?,
        in summary: SurfaceSourceSummaryResult
    ) -> TrimDomain? {
        guard let reference else {
            return nil
        }
        for source in summary.sources where source.kind == "bSplineSurface" {
            for patch in source.patches {
                guard let fullUDomain = fullDomain(
                    knots: patch.basis.uKnots,
                    degree: patch.basis.uDegree
                ),
                let fullVDomain = fullDomain(
                    knots: patch.basis.vKnots,
                    degree: patch.basis.vDegree
                ) else {
                    continue
                }
                for trimLoop in patch.trimLoops {
                    for edge in trimLoop.edges where edge.selectionReference == reference {
                        return TrimDomain(
                            targetReference: reference,
                            uLowerBound: patch.uDomain.lowerBound,
                            uUpperBound: patch.uDomain.upperBound,
                            vLowerBound: patch.vDomain.lowerBound,
                            vUpperBound: patch.vDomain.upperBound,
                            fullULowerBound: fullUDomain.lowerBound,
                            fullUUpperBound: fullUDomain.upperBound,
                            fullVLowerBound: fullVDomain.lowerBound,
                            fullVUpperBound: fullVDomain.upperBound
                        )
                    }
                }
            }
        }
        return nil
    }

    private static func fullDomain(
        knots: [Double],
        degree: Int
    ) -> SurfaceSourceSummaryResult.ParameterRange? {
        guard knots.count > degree + 1 else {
            return nil
        }
        return SurfaceSourceSummaryResult.ParameterRange(
            lowerBound: knots[degree],
            upperBound: knots[knots.count - degree - 1]
        )
    }

    private static func supportedLevelSummary(_ levels: [SurfaceBoundaryContinuityLevel]) -> String {
        guard levels.isEmpty == false else {
            return "None"
        }
        return levels.map { level in
            switch level {
            case .g0:
                return "G0"
            case .g1:
                return "G1"
            case .g2:
                return "G2"
            }
        }
        .joined(separator: " / ")
    }
}
