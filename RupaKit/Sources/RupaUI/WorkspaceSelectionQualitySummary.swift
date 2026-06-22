import RupaCore

struct WorkspaceSelectionQualitySummary: Equatable, Sendable {
    var scope: WorkspaceSelectionScope
    var area: CADInteractionQualityArea
    var rating: CADInteractionQualityRating
    var attentionGate: CADInteractionQualityGate
    var nextRequiredResult: String

    init?(
        scope: WorkspaceSelectionScope,
        assessment: CADInteractionQualityAssessmentResult = CADInteractionQualityAssessmentService().assess()
    ) {
        let area = Self.area(for: scope)
        guard let entry = assessment.entries.first(where: { $0.area == area }) else {
            return nil
        }

        self.scope = scope
        self.area = area
        self.rating = entry.currentRating
        self.attentionGate = Self.attentionGate(in: entry)
        self.nextRequiredResult = entry.nextRequiredResult
    }

    var ratingTitle: String {
        switch rating {
        case .missing:
            "Missing"
        case .planned:
            "Planned"
        case .partial:
            "Partial"
        case .implemented:
            "Built"
        case .verified:
            "Verified"
        }
    }

    var attentionGateTitle: String {
        switch attentionGate {
        case .referenceContract:
            "Reference"
        case .sourceOwnership:
            "Source"
        case .commandContract:
            "Command"
        case .selectionTopology:
            "Targets"
        case .viewportAffordance:
            "Viewport"
        case .inspectorAffordance:
            "Inspector"
        case .agentParity:
            "Agent"
        case .measurementDiagnostics:
            "Diagnostics"
        case .verification:
            "Tests"
        case .performanceBudget:
            "Perf"
        }
    }

    private static func area(for scope: WorkspaceSelectionScope) -> CADInteractionQualityArea {
        switch scope {
        case .object, .face, .edge, .vertex, .region:
            .selection
        case .sketchEntity:
            .curveContinuity
        }
    }

    private static func attentionGate(
        in entry: CADInteractionQualityAssessmentEntry
    ) -> CADInteractionQualityGate {
        let preferredOrder: [CADInteractionQualityGate] = [
            .viewportAffordance,
            .selectionTopology,
            .inspectorAffordance,
            .agentParity,
            .measurementDiagnostics,
            .performanceBudget,
            .commandContract,
            .sourceOwnership,
            .referenceContract,
            .verification,
        ]
        let assessmentsByGate = Dictionary(
            uniqueKeysWithValues: entry.gateAssessments.map { ($0.gate, $0) }
        )

        for gate in preferredOrder {
            guard let assessment = assessmentsByGate[gate],
                  assessment.rating.score < CADInteractionQualityRating.implemented.score else {
                continue
            }
            return gate
        }

        return entry.gateAssessments
            .min { lhs, rhs in lhs.rating.score < rhs.rating.score }?
            .gate ?? .verification
    }
}
