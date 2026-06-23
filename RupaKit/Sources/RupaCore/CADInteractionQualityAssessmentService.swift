public struct CADInteractionQualityAssessmentService: Sendable {
    public init() {}

    public func assess() -> CADInteractionQualityAssessmentResult {
        let entries = Self.entries
        return CADInteractionQualityAssessmentResult(
            referenceDate: "2026-06-22",
            scoringModel: "Average of all gate ratings where missing=0, planned=1, partial=2, implemented=3, verified=4.",
            score: Self.score(for: entries),
            counts: Self.counts(for: entries),
            entries: entries
        )
    }

    private static let entries: [CADInteractionQualityAssessmentEntry] = [
        entry(
            area: .dimensions,
            workflow: "Dimension command target editing",
            references: [
                "https://doc.plasticity.xyz/common/dimension",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .verified,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .verified,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .planned,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Source and object Dimension contracts",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/SketchDimensionSummaryService.swift",
                        "RupaKit/Sources/RupaCore/SketchDimensionTargetResolver.swift",
                        "RupaKit/Sources/RupaCore/ObjectDimensionSummaryService.swift",
                        "RupaKit/Sources/RupaCore/ObjectDimensionSourceResolver.swift",
                        "RupaKit/Sources/RupaUI/DimensionCommandState.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                        "RupaKit/Sources/RupaAgent/AgentServer.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SketchDimensionSummaryServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/DesignDocumentTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/DimensionCommandStateTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentServerTests.swift",
                    ],
                    notes: [
                        "Generated cap edges resolve back to editable sketch curves.",
                        "Generated extrusion-depth edges resolve to object depth dimensions.",
                    ]
                ),
            ],
            openWork: [
                "Solid face-distance pair dimensions.",
                "Fillet-size and sphere dimensions.",
                "General multi-reference solver dimensions.",
                "Drawing annotation dimensions separate from model-driving dimensions.",
            ],
            next: "Generalize Dimension from primitive-owned targets to reference-pair and generated-face contracts while keeping UI and Agent summaries non-mutating."
        ),
        entry(
            area: .snapping,
            workflow: "Snapping intelligence and temporary overrides",
            references: [
                "https://doc.plasticity.xyz/plasticity-essentials/plasticity-interface/snap",
            ],
            rating: .implemented,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .implemented,
                .selectionTopology: .implemented,
                .viewportAffordance: .implemented,
                .inspectorAffordance: .partial,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Shared snap resolver",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/SnapResolver.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceSnapOverrideState.swift",
                        "RupaKit/Sources/RupaRendering/Viewport.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SnapResolverTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/WorkspaceSnapOverrideStateTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentServerTests.swift",
                    ]
                ),
            ],
            openWork: [
                "Broader construction-plane workflow coverage.",
                "Future generated-edge parameter support for non-line and non-circle edge kinds.",
            ],
            next: "Connect broader CPlane creation/edit workflows to the same snap candidate contract instead of adding viewport-only snap special cases."
        ),
        entry(
            area: .constructionGeometry,
            workflow: "Construction planes as modeling inputs",
            references: [
                "https://doc.plasticity.xyz/plasticity-essentials/plasticity-interface/construction-plane",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .verified,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .implemented,
                .agentParity: .verified,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .planned,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Saved construction plane source and workspace routing",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/ConstructionPlaneSource.swift",
                        "RupaKit/Sources/RupaCore/ConstructionPlaneTargetResolver.swift",
                        "RupaKit/Sources/RupaUI/WorkspacePlaneModeControl.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/ConstructionPlaneTargetResolverTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/WorkspaceSnapOverrideStateTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentServerTests.swift",
                    ]
                ),
            ],
            openWork: [
                "Selectable and editable saved-plane handles.",
                "Full sketch-on-arbitrary-plane workflow verification.",
            ],
            next: "Make saved construction planes directly selectable/editable in the viewport and prove sketch creation uses the selected plane end to end."
        ),
        entry(
            area: .selection,
            workflow: "Object, face, edge, vertex, region, and sketch selection",
            references: [
                "https://doc.plasticity.xyz/plasticity-essentials/working-with-objects/selecting-objects",
                "https://doc.plasticity.xyz/plasticity-essentials/plasticity-interface/selection-mode",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .partial,
                .sourceOwnership: .implemented,
                .commandContract: .implemented,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .implemented,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Typed selection targets and generated topology summaries",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/SelectionTarget.swift",
                        "RupaKit/Sources/RupaCore/SelectionModel.swift",
                        "RupaKit/Sources/RupaCore/EdgeOffsetSupportFaceResolver.swift",
                        "RupaKit/Sources/RupaCore/TopologySummaryService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportScene.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSelectionHitPolicy.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIdentityBufferRenderer.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIdentityHitResolver.swift",
                        "RupaKit/Sources/RupaRendering/Viewport.swift",
                        "RupaKit/Sources/RupaRendering/ViewportEdgeOffsetAffordanceGeometry.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceSelectionScope.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SelectionModelTests.swift",
                        "RupaKit/Tests/RupaCoreTests/CommandStackTests.swift",
                        "RupaKit/Tests/RupaCoreTests/TopologySummaryServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportSceneTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportIdentityBufferRendererTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/WorkspaceSelectionScopeTests.swift",
                    ]
                ),
            ],
            openWork: [
                "Remaining selection-mode edit-handle affordance parity for all subobject scopes.",
                "Identity-buffer budget tuning against larger production scene captures.",
            ],
            next: "Broaden remaining scope-specific edit-handle affordances and tune identity-buffer budgets against larger production scenes before retiring remaining CPU-projected topology hit heuristics."
        ),
        entry(
            area: .sweep,
            workflow: "Sweep profile, path, guide, and boolean workflow",
            references: [
                "https://doc.plasticity.xyz/solid/sweep",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .verified,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Sweep source feature and guided evaluation subset",
                    sourceFiles: [
                        "swift-CAD/Sources/CADKernel/SweepEvaluationCapabilities.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaAgent/AgentServer.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SweepCommandTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentServerTests.swift",
                    ]
                ),
            ],
            openWork: [
                "Rail deformation beyond the current affine and signed-axis point-guide sections.",
                "Non-box boolean operands.",
                "Stable result topology beyond current exact subsets.",
                "Full modal command-dialog parity.",
            ],
            next: "Broaden exact swept-surface and boolean topology support while keeping guide overconstraint diagnostics explicit."
        ),
        entry(
            area: .surfaceModeling,
            workflow: "PolySpline surface reconstruction and surface CV editing",
            references: [
                "https://doc.plasticity.xyz/solid/polyspline",
                "https://doc.plasticity.xyz/solid/slide-surface-cv",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .verified,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .implemented,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "PolySpline analysis, topology, overlays, and boundary CV mutation",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/PolySplineMeshAnalysisService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceAnalysisService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceContinuityService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceAnalysisOverlay.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceContinuityOverlay.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SurfaceAnalysisServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SurfaceContinuityServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPolySplineSurfaceVertexSlideAffordanceGeometryTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentServerTests.swift",
                    ]
                ),
            ],
            openWork: [
                "Non-planar G2 multi-patch reconstruction.",
                "Patch merge and rounded-corner policy output.",
                "General trim-curve and surface CV source editing.",
                "Viewport creation controls.",
            ],
            next: "Promote PolySpline from generated-boundary editing to first-class surface source editing with explicit G2 diagnostics and creation affordances."
        ),
        entry(
            area: .curveContinuity,
            workflow: "Bridge curves, curvature combs, and continuity feedback",
            references: [
                "https://doc.plasticity.xyz/sketch/bridge-curve",
                "https://doc.plasticity.xyz/sketch/toggle-curve-curvature",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .verified,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .implemented,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .planned,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Bridge source metadata and curve analysis",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/BridgeCurveSource.swift",
                        "RupaKit/Sources/RupaCore/CurveAnalysisService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportCurveCurvatureComb.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/BridgeCurveCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/CurveAnalysisServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportCurveCurvatureCombTests.swift",
                    ]
                ),
            ],
            openWork: [
                "G3 bridge constraints.",
                "Edge and face endpoint bridge targets.",
                "Dedicated viewport bridge handles and side selection.",
            ],
            next: "Add endpoint-target and viewport-handle parity for Bridge Curve before broadening surface-boundary bridge workflows."
        ),
        entry(
            area: .agentOperability,
            workflow: "AI Agent parity for UI-visible CAD workflows",
            references: [
                "Rupa/CAD_INTERACTION_ARCHITECTURE.md",
                "Rupa/CAD_QUALITY_MILESTONES.md",
            ],
            rating: .implemented,
            gates: [
                .referenceContract: .implemented,
                .sourceOwnership: .implemented,
                .commandContract: .verified,
                .selectionTopology: .verified,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Structured capability descriptors and non-mutating summaries",
                    sourceFiles: [
                        "RupaKit/Sources/RupaAgent/AgentCapabilityDescriptor.swift",
                        "RupaKit/Sources/RupaAgent/AgentMessage.swift",
                        "RupaKit/Sources/RupaAgent/AgentServer.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaAgentTests/AgentServerTests.swift",
                    ],
                    notes: [
                        "Capabilities declare mutation behavior, discovery summaries, targets, and failure modes.",
                    ]
                ),
            ],
            openWork: [
                "Agent parity checks must be kept in lockstep with every new UI affordance.",
                "Rendered workflow verification is still deferred to the final UI pass.",
            ],
            next: "Use this assessment plus capability descriptors as the required preflight before exposing new workspace controls."
        ),
    ]

    private static func entry(
        area: CADInteractionQualityArea,
        workflow: String,
        references: [String],
        rating: CADInteractionQualityRating,
        gates: [CADInteractionQualityGate: CADInteractionQualityRating],
        evidence: [CADInteractionQualityEvidence],
        openWork: [String],
        next: String
    ) -> CADInteractionQualityAssessmentEntry {
        CADInteractionQualityAssessmentEntry(
            area: area,
            workflow: workflow,
            referenceSources: references,
            currentRating: rating,
            gateAssessments: CADInteractionQualityGate.allCases.map { gate in
                CADInteractionQualityGateAssessment(
                    gate: gate,
                    rating: gates[gate] ?? .missing,
                    evidence: evidence.map(\.label),
                    openWork: gates[gate] == .verified ? [] : openWork
                )
            },
            evidence: evidence,
            openWork: openWork,
            nextRequiredResult: next
        )
    }

    private static func counts(
        for entries: [CADInteractionQualityAssessmentEntry]
    ) -> CADInteractionQualityAssessmentCounts {
        CADInteractionQualityAssessmentCounts(
            entryCount: entries.count,
            verifiedCount: entries.filter { $0.currentRating == .verified }.count,
            implementedCount: entries.filter { $0.currentRating == .implemented }.count,
            partialCount: entries.filter { $0.currentRating == .partial }.count,
            plannedCount: entries.filter { $0.currentRating == .planned }.count,
            missingCount: entries.filter { $0.currentRating == .missing }.count,
            blockingGapCount: entries.reduce(0) { count, entry in
                count + entry.gateAssessments.filter { $0.rating.score < CADInteractionQualityRating.implemented.score }.count
            }
        )
    }

    private static func score(
        for entries: [CADInteractionQualityAssessmentEntry]
    ) -> Double {
        let assessments = entries.flatMap(\.gateAssessments)
        guard !assessments.isEmpty else {
            return 0.0
        }
        let total = assessments.reduce(0) { sum, assessment in
            sum + assessment.rating.score
        }
        return Double(total) / Double(assessments.count * CADInteractionQualityRating.verified.score)
    }
}
