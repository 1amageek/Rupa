import RupaCore

struct SurfaceBoundaryContinuityInspectorState: Equatable {
    var selectedTrimCount: Int
    var targetReference: SelectionReference?
    var referenceReference: SelectionReference?
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

        let editableReferences = Self.editableDirectBSplineTrimReferences(in: summaryResult)
        let selectedEditableReferences = trimReferences.filter { editableReferences.contains($0) }
        if selectedEditableReferences.count == 2 {
            targetReference = selectedEditableReferences[0]
            referenceReference = selectedEditableReferences[1]
            statusTitle = "Ready"
        } else if trimReferences.count == 2 {
            targetReference = nil
            referenceReference = nil
            statusTitle = "Direct B-spline trims required"
        } else {
            targetReference = nil
            referenceReference = nil
            statusTitle = "Select two surface trims"
        }
    }

    private static func editableDirectBSplineTrimReferences(
        in summary: SurfaceSourceSummaryResult
    ) -> Set<SelectionReference> {
        var references = Set<SelectionReference>()
        for source in summary.sources where source.kind == "bSplineSurface" {
            for patch in source.patches {
                for trimLoop in patch.trimLoops {
                    for reference in trimLoop.selectionReferences {
                        references.insert(reference)
                    }
                }
            }
        }
        return references
    }
}
