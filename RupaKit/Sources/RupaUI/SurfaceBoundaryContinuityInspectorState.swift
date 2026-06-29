import RupaCore

struct SurfaceBoundaryContinuityInspectorState: Equatable {
    var selectedTrimCount: Int
    var targetReference: SelectionReference?
    var referenceReference: SelectionReference?
    var targetSupportedLevelSummary: String?
    var referenceSupportedLevelSummary: String?
    var statusTitle: String

    var canMatch: Bool {
        targetReference != nil && referenceReference != nil
    }

    init(
        selectedReferences: [SelectionReference],
        summaryResult: SurfaceSourceSummaryResult
    ) {
        let trimReferences = selectedReferences.filter { reference in
            if case .surface(.trim) = reference {
                return true
            }
            return false
        }
        selectedTrimCount = trimReferences.count

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
            statusTitle = "Ready"
        } else if trimReferences.count == 2 {
            targetReference = nil
            referenceReference = nil
            targetSupportedLevelSummary = nil
            referenceSupportedLevelSummary = nil
            statusTitle = "Supported direct B-spline trim edges required"
        } else {
            targetReference = nil
            referenceReference = nil
            targetSupportedLevelSummary = nil
            referenceSupportedLevelSummary = nil
            statusTitle = "Select two surface trims"
        }
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

    private static func supportedLevelSummary(_ levels: [SurfaceBoundaryContinuityLevel]) -> String {
        levels.map { level in
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
