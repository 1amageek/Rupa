public struct CADInteractionQualityAssessmentService: Sendable {
    public init() {}

    public func assess() -> CADInteractionQualityAssessmentResult {
        let entries = Self.entries
        return CADInteractionQualityAssessmentResult(
            referenceDate: "2026-06-30",
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
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SketchDimensionSummaryServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/DesignDocumentTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SelectionDimensionCommandTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/DimensionCommandStateTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Generated cap edges resolve back to editable sketch curves.",
                        "Generated extrusion-depth edges resolve to object depth dimensions.",
                        "Generated solid face pairs resolve to SwiftCAD selection dimensions and evaluate through the shared CAD kernel.",
                    ]
                ),
            ],
            openWork: [
                "Fillet-size and sphere dimensions.",
                "General multi-reference solver dimensions.",
                "Drawing annotation dimensions separate from model-driving dimensions.",
            ],
            next: "Generalize Dimension from primitive-owned targets to reference-pair and generated-face contracts while keeping UI and Agent summaries non-mutating."
        ),
        entry(
            area: .sketchPrecision,
            workflow: "Sketch constraints, dimensions, numeric input, and precision construction",
            references: [
                "https://doc.plasticity.xyz/sketch",
                "https://doc.plasticity.xyz/tool/sketching-essentials",
                "https://doc.plasticity.xyz/tool/polygon",
                "https://doc.plasticity.xyz/common/dimension",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .implemented,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .verified,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .planned,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Source sketch precision contracts",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/SketchInputState.swift",
                        "RupaKit/Sources/RupaCore/SketchEntityDimensionKind.swift",
                        "RupaKit/Sources/RupaCore/SketchDimensionSummaryService.swift",
                        "RupaKit/Sources/RupaCore/PolygonToolState.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SketchDimensionSummaryServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SketchEntityEditCommandTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/DimensionCommandStateTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Source line, circle, arc, rectangle, polygon, spline, and Slot subsets keep typed editable source data.",
                        "Numeric input, dimensions, constraints, and Agent commands share Core mutation paths for supported sketch entities.",
                    ]
                ),
            ],
            openWork: [
                "General sketch solver coverage for arbitrary reference pairs and overconstraint diagnostics.",
                "Viewport constraint glyphs and multi-step construction handles beyond current supported tools.",
                "Persistent constraint migration across broader curve rebuild, split, trim, and generated-curve workflows.",
            ],
            next: "Raise sketch precision from supported source-entity subsets to a general solver-backed sketch workspace with visible constraint affordances and Agent-readable overconstraint diagnostics."
        ),
        entry(
            area: .filletingAndBlending,
            workflow: "Exact filleting, chamfering, and shell-grade blending",
            references: [
                "https://www.plasticity.xyz/product",
                "https://doc.plasticity.xyz/solid/fillet-shell",
                "https://doc.plasticity.xyz/sketch/fillet",
                "https://doc.plasticity.xyz/cad-essentials/fillet-order-of-operations",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .planned,
                .agentParity: .partial,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .planned,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Profile-owned fillet and chamfer subset",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaCore/EditableExtrudeProfileLoop.swift",
                        "RupaKit/Sources/RupaCore/BodyCornerEdge.swift",
                        "RupaKit/Sources/RupaCore/BodyCornerVertex.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaRendering/ViewportProfileEdgeFilletMapping.swift",
                        "RupaKit/Sources/RupaRendering/ViewportProfileEdgeChamferMapping.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/BodyEdgeChamferCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyVertexMoveCommandTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Body edge fillet and chamfer commands exist for generated profile-edge subsets.",
                        "The current fillet command does not yet expose shell-grade conic, G2, constant-width, variable-radius, or range-limited blend contracts.",
                    ]
                ),
            ],
            openWork: [
                "Exact shell-edge blend source ownership for arbitrary solid and sheet topology.",
                "Conic, G2, constant-width, variable-radius, and range-limited blend options.",
                "Blend failure diagnostics for self-intersection, tangent-chain ambiguity, and radius overconstraint.",
                "Viewport and inspector controls for ordered blend sets and per-edge radius editing.",
            ],
            next: "Promote profile-edge fillets into a kernel-backed blend feature contract with Agent-readable option coverage and explicit failure diagnostics before broadening viewport controls."
        ),
        entry(
            area: .booleanModeling,
            workflow: "Standalone and command-integrated boolean modeling",
            references: [
                "https://doc.plasticity.xyz/solid/boolean",
                "https://doc.plasticity.xyz/solid/sweep",
                "https://doc.plasticity.xyz/solid/revolve",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .implemented,
                .commandContract: .implemented,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .implemented,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Source-owned standalone and command-integrated Boolean subsets",
                    sourceFiles: [
                        "swift-CAD/Sources/CADIR/BooleanFeature.swift",
                        "swift-CAD/Sources/CADKernel/BooleanFeatureEvaluator.swift",
                        "swift-CAD/Sources/CADKernel/BoxBRepBooleanEvaluator.swift",
                        "swift-CAD/Sources/CADKernel/OrthogonalSolidOperand.swift",
                        "swift-CAD/Sources/CADIR/DesignGraph.swift",
                        "swift-CAD/Sources/CADKernel/PlanarSweepFeatureEvaluator.swift",
                        "swift-CAD/Sources/CADKernel/PlanarRevolveFeatureEvaluator.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+Solid.swift",
                        "RupaKit/Sources/RupaCore/EditorCommand.swift",
                        "RupaKit/Sources/RupaCore/CADDocumentStore.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationCommand.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationRunner.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaViewportScene/ViewportSceneBuilder.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceObjectOverviewInspectorStateBuilder.swift",
                    ],
                    tests: [
                        "swift-CAD/Tests/CADKernelTests/CADKernelTests.swift",
                        "swift-CAD/Tests/CADExchangeTests/CADExchangeTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BooleanCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SweepCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/RevolveCommandTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentSolidSweepRevolveIntegrationTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Standalone Boolean features now own target body references, one tool body reference, operation, and keep-tools policy in source data.",
                        "Core, Automation, and Agent can create exact axis-aligned box and orthogonal cell-union B-rep Boolean union, difference, intersect, and slice results through the shared command path.",
                        "SwiftCAD can extract occupied cells from supported orthogonal solid operands, so previous connected orthogonal cell-union Boolean results can become follow-on Boolean targets.",
                        "Boolean evaluation removes superseded target and tool generated names when keepTools is false, remaps kept tool names when keepTools is true, and returns typed failures for unsupported operands before invalid geometry is committed.",
                    ]
                ),
            ],
            openWork: [
                "Union, difference, intersect, and slice support across general non-orthogonal Solid and Sheet topology beyond the current orthogonal cell-union subset.",
                "Curved, non-planar, and non-axis-aligned operands with exact topology rather than cell decomposition.",
                "Targetless creation policies where the product workflow needs Boolean-style creation without replacing existing targets.",
                "Exact post-boolean topology naming for arbitrary follow-on selection, dimensions, and direct edits.",
            ],
            next: "Broaden standalone Boolean from orthogonal Solid operands into general Solid and Sheet operands while preserving typed source ownership, generated-name removal, keep-tools semantics, Agent execution, and explicit unsupported diagnostics."
        ),
        entry(
            area: .directModeling,
            workflow: "Direct face, edge, vertex, and surface-CV modeling",
            references: [
                "https://www.plasticity.xyz/product",
                "https://www.plasticity.xyz/faq",
                "https://doc.plasticity.xyz/solid/offset-face",
                "https://doc.plasticity.xyz/common/move.en",
                "https://doc.plasticity.xyz/solid/delete-face",
                "https://doc.plasticity.xyz/solid/match-face",
                "https://doc.plasticity.xyz/solid/draft-face.en",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .partial,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Direct edit commands for owned generated topology subsets",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+SolidFaceDelete.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+SolidFaceDraft.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+SolidEdgeMove.swift",
                        "RupaKit/Sources/RupaCore/EditorCommand.swift",
                        "RupaKit/Sources/RupaCore/GeneratedTopologySelectionResolver.swift",
                        "RupaKit/Sources/RupaCore/PolySplineSurfaceVertexEditingService.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceTopologyEditInspectorStateBuilder.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceTopologyEditInspectorView.swift",
                        "swift-CAD/Sources/CADIR/FaceDeleteFeature.swift",
                        "swift-CAD/Sources/CADKernel/FaceDeleteFeatureEvaluator.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/BodyFaceOffsetCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyFaceDeleteCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyEdgeChamferCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyEdgeMoveCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyVertexMoveCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/DesignDocumentTests.swift",
                        "RupaKit/Tests/RupaAutomationTests/AutomationRunnerTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentDirectModelingIntegrationTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/WorkspaceTopologyEditInspectorStateBuilderTests.swift",
                        "swift-CAD/Tests/CADKernelTests/CADKernelTests.swift",
                    ],
                    notes: [
                        "Face offset, non-healing generated face deletion to sheet bodies, edge chamfer/fillet, generated source line/circle/line-arc-line arc profile edge move, vertex move, and PolySpline surface vertex edits are routed through command contracts.",
                        "Workspace Inspector exposes non-healing Delete Face for selected generated face targets and routes it through the same Core command used by Automation and Agent.",
                        "Draft Face is available for the current generated planar side-face plus same-body neutral-face subset through Core, Automation, Agent, and Workspace Inspector two-face selection affordance.",
                        "Generated source line, circle, and line-arc-line arc profile edge moves rewrite the owning source sketch, preserve analytic source identity, and keep arc moves tangent-continuous by re-trimming adjacent source lines.",
                        "Healing Delete Face that refills, extends, or shrinks adjacent faces is not yet implemented; current Delete Face intentionally preserves an open sheet body result for the supported non-healing subset.",
                        "General push/pull, arbitrary edge move, Match Face, broader Draft Face topology, and proportional CV editing are not yet complete.",
                    ]
                ),
            ],
            openWork: [
                "General push/pull face edits with dependent offset, adjacent-angle, and grow policies.",
                "Broader edge movement beyond generated source line, circle, and line-arc-line arc profile edges, including arbitrary B-rep edges, non-line adjacent trim healing, and surface-boundary edges.",
                "Healing Delete Face with refill, adjacent-face extend/shrink, and closed-solid preservation policies.",
                "Match Face, broader Draft Face topology, and broader surface-CV proportional editing.",
                "Direct edit rollback diagnostics when topology cannot be healed exactly.",
            ],
            next: "Expand direct edits from owned generated topology subsets to general face, edge, vertex, and surface-CV contracts with stable topology names and non-destructive diagnostics."
        ),
        entry(
            area: .exchangeAndDrawings,
            workflow: "CAD exchange, technical drawing, and hidden-line export",
            references: [
                "https://www.plasticity.xyz/product",
                "https://doc.plasticity.xyz/plasticity-essentials/import-export",
                "https://doc.plasticity.xyz/plasticity-essentials/export-hidden-line",
                "https://doc.plasticity.xyz/plasticity-essentials/export-svg",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .partial,
                .viewportAffordance: .planned,
                .inspectorAffordance: .planned,
                .agentParity: .partial,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Document export and exchange-format foundation",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/DocumentExportService.swift",
                        "RupaKit/Sources/RupaCore/ExportOptions.swift",
                        "RupaKit/Sources/RupaCore/ExportPreset.swift",
                        "RupaKit/Sources/RupaCore/ExportResult.swift",
                        "swift-CAD/Sources/CADExchange/OfficialFormatExchange.swift",
                        "swift-CAD/Sources/CADExchange/PDFExporter.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/DesignDocumentTests.swift",
                        "swift-CAD/Tests/CADExchangeTests/CADExchangeTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Export service and exchange-format tests cover file-oriented output paths.",
                        "Hidden-line technical drawing generation, section hatching, and drawing annotation workflows remain separate gaps.",
                    ]
                ),
            ],
            openWork: [
                "Hidden-line export from selected views with occluded-line and style controls.",
                "Section hatching, radial hatching, and parametric hatching for technical drawings.",
                "Drawing-space annotations that are distinct from model-driving dimensions.",
                "Agent-readable import contract for supported exchange formats and failure recovery.",
            ],
            next: "Split exchange from drawing generation by adding a hidden-line drawing result contract with view, hatch, annotation, and export diagnostics."
        ),
        entry(
            area: .patternsAndArrays,
            workflow: "Rectangular, radial, curve, and instance-based arrays",
            references: [
                "https://doc.plasticity.xyz/common",
                "https://doc.plasticity.xyz/common/rectangular-array",
                "https://doc.plasticity.xyz/common/radial-array",
                "https://doc.plasticity.xyz/common/curve-array",
                "https://doc.plasticity.xyz/common/place",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .partial,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .implemented,
                .measurementDiagnostics: .partial,
                .verification: .partial,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Source-owned rectangular, radial, and curve component-instance array command",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/ComponentDefinition.swift",
                        "RupaKit/Sources/RupaCore/ComponentDefinitionDisplaySnapshot.swift",
                        "RupaKit/Sources/RupaCore/ComponentInstance.swift",
                        "RupaKit/Sources/RupaCore/ComponentInstanceDisplaySnapshot.swift",
                        "RupaKit/Sources/RupaCore/ComponentInstanceOwnershipDisplaySnapshot.swift",
                        "RupaKit/Sources/RupaCore/PatternArraySource.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayDisplaySnapshot.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayDefinitionIdentity.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayDefinitionIdentityService.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayFeatureIDTokenMapService.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayFeatureIDRemapper.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayFeatureStructureFingerprintService.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayStableDigest.swift",
                        "RupaKit/Sources/RupaCore/PatternArraySummary.swift",
                        "RupaKit/Sources/RupaCore/PatternArraySummaryResult.swift",
                        "RupaKit/Sources/RupaCore/PatternArraySummaryService.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayAnglePolicy.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayDistancePolicy.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayExpressionResolver.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayCurvePathGeometryService.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayIndependentCopyBuilder.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayDocumentSynchronizer.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayOwnershipResolver.swift",
                        "RupaKit/Sources/RupaCore/PatternArrayInstancePlanner.swift",
                        "RupaKit/Sources/RupaCore/DesignDisplaySnapshotService.swift",
                        "RupaKit/Sources/RupaCore/SceneNode.swift",
                        "RupaKit/Sources/RupaCore/ProductMetadata.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+PatternArray.swift",
                        "RupaKit/Sources/RupaCore/EditorCommand.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationCommand.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationRunner.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaUI/PatternArrayInspectorState.swift",
                        "RupaKit/Sources/RupaUI/PatternArrayEditingService.swift",
                        "RupaKit/Sources/RupaUI/PatternArrayExpressionWritebackService.swift",
                        "RupaKit/Sources/RupaUI/PatternArrayCurvePathCandidate.swift",
                        "RupaKit/Sources/RupaUI/PatternArrayCurvePathPickState.swift",
                        "RupaKit/Sources/RupaUI/PatternArrayCurvePathPickService.swift",
                        "RupaKit/Sources/RupaUI/PatternArraySummaryCache.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayPreview.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayPreviewService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArraySourceSelectionIndex.swift",
                        "RupaKit/Sources/RupaRendering/ViewportTransformUtilities.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayLinearAxisDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayLinearAxisAffordanceGeometry.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayLinearAxisAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIndependentCopyOutputSelectionIndex.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIndependentCopyExtrudeDistanceDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIndependentCopyExtrudeDistanceAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIndependentCopyBodyDimensionDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIndependentCopyBodyDimensionAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayRadialAngleDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayRadialAngleAffordanceGeometry.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayRadialAngleAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCopyCountDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCopyCountAffordanceGeometry.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCopyCountAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurveExtentDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurveExtentAffordanceGeometry.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurveExtentAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathPointDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathPointAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayOutputModeTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayOutputModeAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathReplacementPreviewRequest.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathReplacementPreviewService.swift",
                        "RupaKit/Sources/RupaRendering/Viewport.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/DesignDisplaySnapshotServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/PatternArraySummaryServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/CommandStackTests.swift",
                        "RupaKit/Tests/RupaCoreTests/PatternArrayOwnershipResolverTests.swift",
                        "RupaKit/Tests/RupaAutomationTests/AutomationRunnerTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/PatternArrayInspectorStateTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/PatternArrayEditingServiceTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/PatternArraySummaryCacheTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayPreviewServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayLinearAxisAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportIndependentCopyExtrudeDistanceAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportIndependentCopyBodyDimensionAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayRadialAngleAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCopyCountAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/PatternArrayExpressionResolverTests.swift",
                        "RupaKit/Tests/RupaCoreTests/PatternArrayCurvePathGeometryServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCurveExtentAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCurvePathPointAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayOutputModeAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCurvePathReplacementPreviewServiceTests.swift",
                    ],
                    notes: [
                        "Rectangular, radial, and curve arrays now persist a PatternArraySource and emit component instances or independent copied CAD feature geometry.",
                        "Rectangular spacing and extent modes support one- or two-axis lattices through Core, Automation, and Agent command paths.",
                        "Radial angle spacing/extent, center, axis, count, and optional radial repetition support Core, Automation, and Agent command paths.",
                        "Curve Array path distribution, twist, scale, Normal, Parallel, Transport, ratio extent, distance extent, explicit polyline paths, and source sketch-entity paths support Core, Automation, and Agent command paths.",
                        "Pattern Array source update and explode lifecycle commands support Core, Automation, and Agent command paths.",
                        "Pattern Array command mutation delegates output regeneration to a dedicated Core synchronizer and source-owned output lookup to a dedicated ownership resolver.",
                        "Component-instance Pattern Array explode materializes cloned CAD feature scene outputs before detaching source ownership.",
                        "Design display snapshots expose ComponentDefinition IDs, ComponentInstance IDs, typed component instance ownership, renderable root scene nodes, dependency feature closures, PatternArraySource IDs, output instance IDs, independent-copy output scene node feature IDs, independent-copy generation definition identity, per-output source-divergence state, root scene node IDs, distribution, and output mode for Agent lifecycle planning.",
                        "Design display snapshots keep invalid PatternArraySource records discoverable with diagnostics instead of dropping sources whose definition, root scene node, or generated outputs are missing.",
                        "Pattern Array summaries expose editable fields, lifecycle actions, source-owned scene output policy, cloned feature edit policy, output IDs, independent-copy generation definition identity, per-output source-divergence state, regeneration policy, and diagnostics without forcing CAD evaluation.",
                        "Pattern Array summary diagnostics mirror source-owned output invariants for missing instances, mismatched transforms, duplicate ownership, root child mapping, independent-copy feature closure checks, stale independent-copy definition identity, and downstream feature dependents that block output removal.",
                        "Independent-copy Pattern Array regeneration persists a SHA-256 ComponentDefinition identity over scene roots plus remapped feature operation payloads, reuses overlapping output scene roots only while that identity remains unchanged, and rebuilds output features when the source definition identity changes.",
                        "Independent-copy per-output source-divergence checks tokenize FeatureID references through the shared feature remapper, cache source fingerprints per summary pass, and use SHA-256 stable hashing instead of JSON string replacement or 64-bit digests.",
                        "The object Inspector now maps selected source roots, generated outputs, and independent-copy descendants back to their PatternArraySource and displays ownership, lifecycle actions, output mode, selected output index, cloned feature edit policy, independent-copy source-divergence state, regeneration policy, and diagnostics.",
                        "The Pattern Array Inspector exposes source-owned output mode plus rectangular first- and second-axis controls, radial center, axis, angular spacing or extent, radial repetition, and curve count, twist, scale, alignment, and extent controls that update the PatternArraySource instead of generated outputs.",
                        "The Pattern Array Inspector starts a dedicated viewport Curve Array path pick mode; viewport sketch line, circle, arc, or spline targets update the PatternArraySource path without replacing the active Pattern Array selection.",
                        "Curve Array ratio extent editing clamps UI and service inputs to the Core planner range before source-owned regeneration.",
                        "The Pattern Array Inspector reuses generation-keyed summary results so SwiftUI redraws do not repeatedly run transform planning or sketch curve extraction for unchanged documents.",
                        "The viewport resolves selected PatternArraySource roots, component-instance outputs, and independent-copy descendants into source-owned output outlines, copy markers, and count labels without scanning global component-instance references.",
                        "The viewport exposes rectangular Pattern Array first- and second-axis distance handles that resolve selected source roots or outputs back to PatternArraySource IDs and commit source-owned distance updates after drag completion.",
                        "The viewport exposes independent-copy cloned extrude distance handles that resolve selected output roots or descendants to clone feature IDs, derive normal directions from profile sketch planes, and commit cloned-feature distance edits after drag completion.",
                        "The viewport exposes independent-copy cloned box X/Z and cylinder radius handles that share the independent-copy output selection index, read current object dimensions, and commit direct cloned-feature body dimension edits after drag completion.",
                        "The viewport exposes radial Pattern Array angular spacing/extent handles and radial-axis distance handles through the shared PatternArray source-selection index.",
                        "The viewport exposes Pattern Array copy-count handles for rectangular axes, radial angular/radial axes, extent-density modes, and Curve Pattern Array density counts while preserving distance, angle, path extent, and source-owned output regeneration semantics.",
                        "The viewport exposes Curve Pattern Array extent handles that use the shared Core curve-path geometry resolver so viewport dragging and generated copy placement agree on path length and sampling.",
                        "The viewport exposes direct Curve Pattern Array polyline path-point handles that commit source-owned path point edits without mutating sketch-entity paths.",
                        "The viewport exposes Pattern Array output-mode badges that resolve selected source roots, generated outputs, and independent-copy descendants back to source-owned output mode regeneration.",
                        "The viewport previews Curve Pattern Array path replacement candidates with planner-derived ghost output markers before committing the pick-mode source update.",
                        "Viewport and inspector Pattern Array edits preserve direct parameter references by updating referenced ParameterTable values when quantity kinds match.",
                        "Pattern Array generation, curve path extent resolution, and viewport affordance placement share the same parameter-aware expression resolver so Agent-authored parametric arrays remain directly editable in the UI.",
                        "Agent and Automation can update independent-copy cloned extrude distances plus rectangular-box and cylinder dimensions by using patternArraySummary, designDisplaySnapshot, and objectDimensionSummary to discover clone FeatureIDs and current editable dimensions before dispatching direct feature-dimension commands through AutomationRunner to Core.",
                        "Viewport editing workflows for direct independent-copy cloned-feature handles beyond extrude distance, box X/Z, and cylinder radius remain open.",
                    ]
                ),
            ],
            openWork: [
                "Viewport direct controls for independent-copy cloned-feature edits beyond extrude distance, box X/Z, and cylinder radius.",
            ],
            next: "Extend viewport handles from independent-copy extrude distance and profile dimensions to additional cloned-feature edits."
        ),
        entry(
            area: .sectionAnalysis,
            workflow: "Section analysis, measurement, and inspection overlays",
            references: [
                "https://doc.plasticity.xyz/common/section-analysis",
                "https://doc.plasticity.xyz/tool/measure",
                "https://doc.plasticity.xyz/tool/measure-radius",
                "https://doc.plasticity.xyz/tool/measure-continuity",
                "https://doc.plasticity.xyz/solid/toggle-surface-curvature",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .verified,
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .partial,
                .viewportAffordance: .partial,
                .inspectorAffordance: .partial,
                .agentParity: .partial,
                .measurementDiagnostics: .implemented,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Measurements, surface continuity, and saved section-plane metadata",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/MeasurementService.swift",
                        "RupaKit/Sources/RupaCore/MeasurementAnnotation.swift",
                        "RupaKit/Sources/RupaCore/SelectionDimensionService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceContinuityService.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/CommandStackTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SelectionDimensionCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SurfaceContinuityServiceTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Measurement summaries, selection dimensions, surface continuity summaries, and section-plane creation are Agent-readable.",
                        "Virtual section clipping, section hatching, interference highlighting, and section-distance controls remain incomplete.",
                    ]
                ),
            ],
            openWork: [
                "Virtual section clipping through solids and meshes without mutating model geometry.",
                "Selection, CPlane, previous-plane, distance, and flip policies for Section Analysis.",
                "Interference highlighting and section hatching for drawing/export workflows.",
                "Persistent inspection overlay controls that share the measurement and topology contracts.",
            ],
            next: "Connect saved section planes to a non-mutating section analysis result that drives viewport clipping, hatching, interference diagnostics, and Agent-readable measurements."
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
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Visible UVN surface frame displays are resolved through the shared snap resolver as Agent-readable surfaceFrame candidates with query, world point, UV, and local frame axes.",
                        "Authored direct B-spline trim endpoints and strict interior p-curve control points resolve as Agent-readable surfaceTrim snap candidates with selection reference, UV address, world point, and local U/V/N frame axes.",
                    ]
                ),
            ],
            openWork: [
                "Broader construction-plane workflow coverage.",
                "Future generated-edge parameter support for non-line and non-circle edge kinds.",
                "Trim dimensioning and broader trim-curve snap workflows beyond authored endpoint and strict interior p-curve control-point anchors.",
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
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
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
                        "RupaKit/Sources/RupaRendering/ViewportPickingReadinessService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPickingReadinessSummary.swift",
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
                "Production-scene identity-buffer budget calibration from larger scene captures.",
            ],
            next: "Broaden remaining scope-specific edit-handle affordances and calibrate identity-buffer budgets against larger production scenes before retiring remaining CPU-projected topology hit heuristics."
        ),
        entry(
            area: .sweep,
            workflow: "Sweep and Loft profile-section workflows",
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
                    label: "Sweep and Loft source feature evaluation subsets",
                    sourceFiles: [
                        "swift-CAD/Sources/CADIR/LoftFeature.swift",
                        "swift-CAD/Sources/CADKernel/LoftFeatureEvaluator.swift",
                        "swift-CAD/Sources/CADKernel/SweepEvaluationCapabilities.swift",
                        "swift-CAD/Sources/CADKernel/PlanarSweepFeatureEvaluator.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+Solid.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationCommand.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaCLIKit/LoftModelCommand.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "swift-CAD/Tests/CADKernelTests/LoftFeatureTests.swift",
                        "swift-CAD/Tests/CADKernelTests/CADKernelTests.swift",
                        "RupaKit/Tests/RupaCoreTests/LoftCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SweepCommandTests.swift",
                        "RupaKit/Tests/RupaAutomationTests/LoftAutomationTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentLoftIntegrationTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                        "RupaKit/Tests/RupaCLITests/CLIResponseTests.swift",
                    ],
                    notes: [
                        "Loft now has a source-owned Swift-CAD IR, same-boundary-count ruled B-spline and smooth cubic section-direction B-spline B-rep evaluator modes, finite positive global and per-section smooth tangent scale control for automatic cubic section-direction handles, automatic or zero section tangent modes for authored section handle boundary conditions, linear section-scale interpolation for guide-inserted intermediate rings, optional guide curve references that lock first and last section seam samples by first-guide endpoint contact when explicit section starts are absent, multi-section multi-guide rail-following intermediate section rings, explicit per-section startSampleIndex seam starts, automatic cyclic section matching for unspecified seams, solid output, open sheet output, closed section-loop sheet output in ruled or smooth mode, RupaCore mutation, Automation, Agent command dispatch, CLI model loft surface-mode, tangent-scale, and tangent-mode creation, measurement, viewport scene display, and Inspector operation summaries.",
                    ]
                ),
            ],
            openWork: [
                "Loft viewport seam placement, continuity-driven smooth rail-surface solving, and G0/G1/G2/G3 section-continuity controls beyond tangent-handle boundary conditions.",
                "Rail deformation beyond the current affine, signed-axis, convex quadrilateral bilinear, convex mean-value cage, and radial point-guide sections.",
                "Non-box boolean operands.",
                "Stable result topology beyond current exact subsets.",
                "Full Sweep and Loft modal command-dialog parity, viewport section placement, and UVN/surfaceTrim-driven section placement beyond the typed CLI/Automation/Agent command path.",
            ],
            next: "Broaden exact swept and lofted surface support while keeping section, guide, seam, and boolean overconstraint diagnostics explicit."
        ),
        entry(
            area: .surfaceModeling,
            workflow: "PolySpline surface reconstruction and surface CV editing",
            references: [
                "https://doc.plasticity.xyz/solid/polyspline",
                "https://doc.plasticity.xyz/solid/slide-surface-cv",
                "https://doc.plasticity.xyz/cad-essentials/nurbs-overview",
                "https://doc.plasticity.xyz/cad-essentials/uvn-coordinate-system",
                "https://doc.plasticity.xyz/cad-essentials/continuity-curve-and-surface",
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
                        "RupaKit/Sources/RupaCore/SurfaceFrameService.swift",
                        "RupaKit/Sources/RupaCore/SnapResolver.swift",
                        "RupaKit/Sources/RupaCore/SurfaceAnalysisService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceContinuityService.swift",
                        "RupaKit/Sources/RupaCore/Surface/SurfaceSourceSummaryResult.swift",
                        "RupaKit/Sources/RupaCore/Surface/BSplineSurfaceSourceSummaryBuilder.swift",
                        "RupaKit/Sources/RupaCore/Surface/BSplineSurfaceKnotEditingService.swift",
                        "RupaKit/Sources/RupaCore/Surface/BSplineSurfaceBoundaryContinuityEditingService.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument+Surface.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationCommand.swift",
                        "RupaKit/Sources/RupaAgentProtocol/AgentMessage.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaCLIKit/SurfaceSplitSpanCommand.swift",
                        "RupaKit/Sources/RupaCLIKit/SurfaceSetKnotMultiplicityCommand.swift",
                        "RupaKit/Sources/RupaCLIKit/SurfaceMatchBoundaryContinuityCommand.swift",
                        "RupaKit/Sources/RupaUI/SurfaceParameterInspectorState.swift",
                        "RupaKit/Sources/RupaUI/SurfaceParameterInspectorView.swift",
                        "RupaKit/Sources/RupaUI/SurfaceBoundaryContinuityInspectorState.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceAnalysisOverlay.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceContinuityOverlay.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceFrameAxisAffordanceGeometry.swift",
                        "RupaKit/Sources/RupaRendering/Viewport.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SurfaceAnalysisServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SurfaceSourceSummaryServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SurfaceContinuityServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/DesignDocumentTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPolySplineSurfaceVertexSlideAffordanceGeometryTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportSurfaceFrameAxisAffordanceGeometryTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentSurfaceModelingTests.swift",
                        "RupaKit/Tests/RupaAutomationTests/AutomationRunnerTests.swift",
                        "RupaKit/Tests/RupaCLITests/CLIResponseTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/SurfaceParameterInspectorStateTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/WorkspaceSurfaceInspectorStateBuilderTests.swift",
                    ],
                    notes: [
                        "Surface source summaries expose Agent-readable B-spline degree, order, knot vectors, stable knot IDs, span IDs, CV weights, control-point selection references, trim-loop ownership, typed trim-edge roles, endpoint UVs, authored p-curve control-point indices and weights, boundary/inward directions, control-row references, supported direct B-spline G0/G1/G2 boundary-continuity levels, and generated topology links for supported PolySpline patches and direct B-spline surface sources.",
                        "Strict interior PolySpline CV weights are editable through the shared Core, Automation, and Agent command path while preserving CV position overrides.",
                        "Direct B-spline surface sources can be created through Core, Automation, Agent, and CLI, evaluate to selectable sheet topology, appear in surface source summaries with stored degree, knot vectors, weights, control-net references, editable knot and span references, rectangular trim-loop identity, authored trim-loop identity, selectable trim-edge references, Agent-readable authored p-curve control-point summary indices and weights, shared adaptive UV trim-loop validation, rational 2D B-spline p-curve trim preservation, and typed trim-edge continuity capability, and support direct CV position, CV weight, CV slide, internal knot-value mutation, shape-preserving knot insertion, fraction-based span splitting, explicit internal knot multiplicity editing, authored trim endpoint moves with loop-closure preservation, strict interior polyline and 2D B-spline trim p-curve control-point moves, 2D B-spline trim p-curve control-point weight edits, selected viewport trim endpoint handles, selected viewport trim interior control-point handles, authored B-spline trim p-curve span/knot UVN frame resolution and display persistence, and compatible clamped trim-boundary G0/G1/G2 matching with homogeneous inward derivative-scale solving.",
                        "Visible surface frame displays now feed SnapResolver surfaceFrame candidates so UI and Agent workflows can consume the UVN frame query, world point, UV address, and local U/V/N axes as a shared snap target.",
                        "Authored direct B-spline trim endpoints and strict interior p-curve control points now feed SnapResolver surfaceTrim candidates so future trim dimensioning and placement tools can consume the same selection reference, UV address, world point, and local U/V/N axes as Agent callers.",
                        "Selected Surface CVs can now use visible viewport surface-frame U/V/N axes as drag handles that commit through the existing Core moveSurfaceControlPointsInFrame contract.",
                    ]
                ),
            ],
            openWork: [
                "Direct B-spline surface source editing beyond existing CV, weight, slide, internal knot-value mutation, shape-preserving knot insertion, fraction-based span splitting, explicit knot multiplicity editing, authored trim endpoint moves, authored trim p-curve interior control-point moves, and compatible trim-boundary continuity matching, including remaining span editing beyond direct fraction splits and broader trim-curve handle workflows.",
                "Trim dimensioning, surface offset, and advanced sweep or loft section placement still need to consume the Agent-readable UVN frame and surfaceTrim snap contracts beyond visible-frame snap anchors, authored endpoint/control-point snap anchors, and viewport frame drag.",
                "Arbitrary B-rep adjacency solving, PolySpline continuity mutation, non-rectangular trim targets, and G0/G1/G2/G3 curve matching.",
                "Non-planar G2 multi-patch reconstruction.",
                "Patch merge and rounded-corner policy output.",
                "General trim-curve editing beyond endpoint and strict interior control-point moves, and remaining surface CV source editing beyond the current direct B-spline and PolySpline subsets.",
                "Viewport creation controls.",
            ],
            next: "Continue from the current direct B-spline edit subset into arbitrary adjacency continuity, trim dimensioning/snapping, surface offset, advanced sweep or loft section placement, broader trim-curve workflows, and broader NURBS/polysurface ownership before broadening surface tools."
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
                        "RupaKit/Sources/RupaCore/BridgeCurveEndpointSelectionResolver.swift",
                        "RupaKit/Sources/RupaCore/BridgeCurveEndpointHandleService.swift",
                        "RupaKit/Sources/RupaCore/BridgeCurveEndpointParameterProjectionService.swift",
                        "RupaKit/Sources/RupaCore/CurveAnalysisService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportBridgeCurveEndpointAffordanceService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportBridgeCurveEndpointDragTarget.swift",
                        "RupaKit/Sources/RupaRendering/ViewportCurveCurvatureComb.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceBridgeCurveInspectorView.swift",
                        "RupaKit/Sources/RupaUI/WorkspaceSketchEntityInspectorStateBuilder.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/BridgeCurveCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/CurveAnalysisServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportBridgeCurveEndpointAffordanceServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportCurveCurvatureCombTests.swift",
                        "RupaKit/Tests/RupaUIPackageTests/WorkspaceSketchEntityInspectorStateBuilderTests.swift",
                    ],
                    notes: [
                        "Bridge Curve endpoint selections now resolve from point-backed sketch selection targets into the same BridgeCurveEndpoint contract used by Core, Automation, Agent, and CLI.",
                        "Selected Bridge Curve sources now expose projected viewport endpoint handles with tangent guide rendering, hover hit-testing, press-state isolation, exact line/arc/spline Value projection, and command-backed endpoint parameter drag commits through setBridgeCurveParameters.",
                        "Bridge Curve Inspector Show Curvature controls now target the generated bridge spline through the same CurveCurvatureDisplay contract used by generic source curves, while generic curve display controls are suppressed for bridge-generated spline selections to avoid duplicate ownership.",
                        "Bridge Curve Trim Side is now an endpoint-owned Core value that chooses the retained start-side or end-side source segment independently from Sense, so Sense only controls tangent direction and Agent/UI callers can operate the same explicit contract.",
                    ]
                ),
            ],
            openWork: [
                "G3 bridge constraints.",
                "Edge and face endpoint bridge targets.",
                "Bridge Curve richer preview controls.",
            ],
            next: "Add edge, face, and surface-boundary Bridge Curve endpoint targets plus richer preview controls without bypassing the Core endpoint contract."
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
                        "RupaKit/Sources/RupaAgentProtocol/AgentMessage.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaCore/DesignDisplaySnapshotResult.swift",
                        "RupaKit/Sources/RupaCore/DesignDisplaySnapshotService.swift",
                        "RupaKit/Sources/RupaCore/SketchDisplaySnapshotService.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SketchDisplaySnapshotServiceTests.swift",
                    ],
                    notes: [
                        "Capabilities declare mutation behavior, discovery summaries, targets, and failure modes.",
                        "Agent-readable design display snapshots expose the same Core-owned sketch primitive, region, extrude, straight-prism sweep, body mesh, and generated topology display contract consumed by the viewport.",
                    ]
                ),
            ],
            openWork: [
                "Agent parity checks must be kept in lockstep with every new UI affordance.",
                "Rendered workflow verification is still deferred to the final UI pass.",
            ],
            next: "Use this assessment plus capability descriptors as the required preflight before exposing new workspace controls."
        ),
        entry(
            area: .performance,
            workflow: "Evaluation reuse, identity picking budgets, and zero-copy-oriented display paths",
            references: [
                "Rupa/CAD_QUALITY_MILESTONES.md",
                "swift-CAD/CAD_KERNEL_REQUIREMENTS.md",
            ],
            rating: .partial,
            gates: [
                .referenceContract: .implemented,
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .partial,
                .viewportAffordance: .partial,
                .inspectorAffordance: .planned,
                .agentParity: .partial,
                .measurementDiagnostics: .implemented,
                .verification: .partial,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Evaluated document reuse and viewport picking budgets",
                    sourceFiles: [
                        "RupaKit/Sources/RupaCore/DocumentEvaluationResult.swift",
                        "RupaKit/Sources/RupaCore/DocumentEvaluationContext.swift",
                        "RupaKit/Sources/RupaCore/DocumentEvaluationContextResolver.swift",
                        "RupaKit/Sources/RupaCore/EvaluationScheduler.swift",
                        "RupaKit/Sources/RupaCore/CADDocumentStore.swift",
                        "RupaKit/Sources/RupaCore/BodyDisplaySnapshotService.swift",
                        "RupaKit/Sources/RupaCore/MeasurementService.swift",
                        "RupaKit/Sources/RupaCore/MeshSummaryService.swift",
                        "RupaKit/Sources/RupaCore/TopologySummaryService.swift",
                        "RupaKit/Sources/RupaCore/SelectionDimensionService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceFrameService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceAnalysisService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceContinuityService.swift",
                        "RupaKit/Sources/RupaRendering/ViewportScene.swift",
                        "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                        "RupaKit/Sources/RupaRendering/ViewportIdentityHitResolver.swift",
                        "RupaKit/Sources/RupaRendering/ViewportPickingReadinessService.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/BodyDisplaySnapshotServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/CommandStackTests.swift",
                        "RupaKit/Tests/RupaCoreTests/DocumentEvaluationContextTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportSceneTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportIdentityBufferRendererTests.swift",
                    ],
                    notes: [
                        "EvaluationScheduler can return the evaluated document alongside the persistent evaluation snapshot.",
                        "Viewport scene construction, Inspector shape and surface panels, Agent display/mesh/topology/surface summaries, measurement, surface frame, and selection dimension read paths can consume a store-validated current evaluation context instead of forcing another CAD evaluation.",
                        "Evaluation context reuse now checks both document generation and CAD source fingerprint before returning an evaluated document.",
                        "Identity picking exposes render/readback metrics and budget fallback diagnostics.",
                    ]
                ),
            ],
            openWork: [
                "Measured dense-model budgets for sketch, sweep, mesh, surface, and exchange workflows.",
                "Borrowed or copy-on-write buffers for dense meshes, control nets, and imported byte ranges where API ownership permits.",
                "Inspector diagnostics for memory pressure and render budget fallback beyond current evaluation-cache reuse.",
            ],
            next: "Turn evaluation reuse and identity-picking metrics into enforced dense-model performance budgets with regression fixtures before broadening heavy CAD workflows."
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
            nextRequiredResult: next,
            designProcessPacket: designProcessPacket(
                area: area,
                references: references,
                rating: rating,
                gates: gates,
                evidence: evidence,
                openWork: openWork,
                next: next
            )
        )
    }

    private static func designProcessPacket(
        area: CADInteractionQualityArea,
        references: [String],
        rating: CADInteractionQualityRating,
        gates: [CADInteractionQualityGate: CADInteractionQualityRating],
        evidence: [CADInteractionQualityEvidence],
        openWork: [String],
        next: String
    ) -> DesignProcessPacket {
        let sourceFiles = unique(evidence.flatMap(\.sourceFiles))
        let testReferences = designProcessTestReferences(from: evidence)
        let gateAssessments = CADInteractionQualityGate.allCases.map { gate in
            CADInteractionQualityGateAssessment(
                gate: gate,
                rating: gates[gate] ?? .missing,
                evidence: evidence.map(\.label),
                openWork: gates[gate] == .verified ? [] : openWork
            )
        }
        let spec = CADInteractionDesignProcessSpec.spec(for: area)
        let routeMatrix = routeMatrix(
            area: area,
            spec: spec,
            gates: gates,
            evidence: evidence
        )
        let flowGraph = flowGraph(for: area, spec: spec)
        let observationSet = CADInteractionDesignProcessObservationSet.make(
            area: area,
            gateAssessments: gateAssessments,
            evidence: evidence,
            openWork: openWork,
            routeMatrix: routeMatrix,
            flowGraphValidation: flowGraph.validate()
        )

        let packet = DesignProcessPacket(
            id: "\(area.rawValue)-design-process",
            intent: DesignProcessIntent(
                capabilityID: area.rawValue,
                title: spec.capabilityTitle,
                outcome: next,
                area: area,
                sourceOfTruth: .core,
                referenceSources: references
            ),
            evaluation: DesignProcessEvaluationSpec(
                successCriteria: unique([
                    next,
                    "All required CAD quality gates must be represented by evidence, missing cases, and route coverage.",
                ] + spec.supportedCases.map(\.title)),
                diagnosticRequirements: unique(evidence.flatMap(\.notes)),
                performanceBudget: "performanceBudget gate is \((gates[.performanceBudget] ?? .missing).rawValue).",
                requiredEvidence: evidence.map(\.label)
            ),
            domain: DesignProcessDomainModel(
                sourceEntities: unique(spec.sourceEntities + sourceFiles),
                targetEntities: spec.targetEntities,
                generatedTopology: unique(spec.generatedTopology + generatedTopologyDescriptions(from: evidence)),
                units: "document units",
                tolerances: spec.tolerances,
                ownershipBoundaries: spec.ownershipBoundaries + [
                    "RupaCore owns the command and assessment contract.",
                    "Rupa UI, Automation, Agent, CLI, Kernel, Evaluation, Measurement, and Diagnostics routes must stay visible in the route matrix.",
                ]
            ),
            caseMatrix: caseMatrix(
                area: area,
                spec: spec,
                gateAssessments: gateAssessments,
                openWork: openWork,
                testReferences: testReferences
            ),
            routeMatrix: routeMatrix,
            constraintBinding: DesignProcessConstraintBinding(
                validationRules: CADInteractionQualityGate.allCases.map(\.rawValue),
                invariants: spec.invariants + [
                    DesignProcessInvariant(
                        id: "\(area.rawValue)-route-coverage",
                        title: "Required route coverage stays explicit",
                        requiredLayer: .evaluation,
                        verification: "DesignProcessPacket route matrix and FlowGraph validation"
                    ),
                ],
                sourceRewriteLimits: openWork,
                topologyIdentityRules: spec.generatedTopology + [
                    "Selection and generated topology routes must use stable IDs for shipped subsets.",
                    "Stale-generation mutations must be rejected or refreshed before commit.",
                ]
            ),
            resolution: DesignProcessResolution(
                selectedRouteIDs: selectedRouteIDs(from: routeMatrix),
                decisions: [
                    DesignProcessDecisionRecord(
                        id: "\(area.rawValue)-assessment-source",
                        conflictArea: spec.decisionConflictArea,
                        selectedRouteID: "\(area.rawValue)-core-kernel",
                        rejectedRouteIDs: [],
                        rationale: spec.decisionRationale,
                        followUpOwner: .evaluation
                    ),
                ],
                openQuestions: openWork
            ),
            validatedArtifact: DesignProcessValidatedArtifact(
                sourceFiles: sourceFiles,
                tests: testReferences,
                buildCommands: ["xcodebuild test -scheme RupaKit-Package -destination platform=macOS -only-testing:RupaCoreTests"],
                diagnostics: diagnosticRecords(from: gateAssessments).map(\.message),
                supportedClaims: gateAssessments
                    .filter { $0.rating.score >= CADInteractionQualityRating.implemented.score }
                    .map { "\($0.gate.rawValue): \($0.rating.rawValue)" }
            ),
            observations: observationSet.observations,
            flowGraph: flowGraph,
            confidence: observationSet.confidence(
                rating: rating,
                gates: gates,
                evidence: evidence
            )
        )
        return CADInteractionDesignProcessPerformanceBenchmarkService.recordBenchmarks(
            in: packet
        ) { packet in
            packet.confidence.notes = observationSet.confidenceNotes(
                rating: rating,
                calibrationAnchors: packet.confidence.calibrationAnchors,
                performanceMeasurements: packet.confidence.performanceMeasurements
            )
        }
    }

    private static func designProcessTestReferences(
        from evidence: [CADInteractionQualityEvidence]
    ) -> [DesignProcessTestReference] {
        unique(evidence.flatMap(\.tests)).map { test in
            DesignProcessTestReference(
                target: "RupaKit",
                name: test,
                file: test
            )
        }
    }

    private static func generatedTopologyDescriptions(
        from evidence: [CADInteractionQualityEvidence]
    ) -> [String] {
        let descriptions = unique(evidence.flatMap(\.notes)).filter { note in
            let lowered = note.lowercased()
            return lowered.contains("topology")
                || lowered.contains("generated")
                || lowered.contains("selection")
        }
        return descriptions.isEmpty ? ["No generated topology claim is verified by this packet yet."] : descriptions
    }

    private static func caseMatrix(
        area: CADInteractionQualityArea,
        spec: CADInteractionDesignProcessSpec,
        gateAssessments: [CADInteractionQualityGateAssessment],
        openWork: [String],
        testReferences: [DesignProcessTestReference]
    ) -> DesignProcessCaseMatrix {
        let gateEvidence = unique(gateAssessments.flatMap(\.evidence))
        let supported = scopedCases(
            spec.supportedCases,
            area: area,
            testReferences: testReferences,
            evidence: gateEvidence
        ) + gateAssessments
            .filter { $0.rating.score >= CADInteractionQualityRating.implemented.score }
            .map { assessment in
                DesignProcessCase(
                    id: "\(area.rawValue)-\(assessment.gate.rawValue)-supported",
                    title: "\(assessment.gate.rawValue) is \(assessment.rating.rawValue)",
                    status: assessment.rating == .verified ? .verified : .supported,
                    testReferences: testReferences,
                    evidence: assessment.evidence
                )
            }
        let boundary = scopedCases(
            spec.boundaryCases,
            area: area,
            testReferences: testReferences,
            evidence: gateEvidence
        ) + gateAssessments
            .filter { $0.rating == .partial || $0.rating == .planned }
            .map { assessment in
                DesignProcessCase(
                    id: "\(area.rawValue)-\(assessment.gate.rawValue)-boundary",
                    title: "\(assessment.gate.rawValue) needs expansion",
                    status: .planned,
                    diagnostic: DesignProcessDiagnostic(
                        id: "\(area.rawValue)-\(assessment.gate.rawValue)-boundary",
                        severity: .warning,
                        message: "Gate is \(assessment.rating.rawValue) and must remain visible as a boundary case.",
                        affectedLayer: layer(for: assessment.gate)
                    ),
                    evidence: assessment.evidence,
                    notes: assessment.openWork
                )
            }
        let rejected = scopedCases(
            spec.rejectedCases,
            area: area,
            testReferences: testReferences,
            evidence: gateEvidence
        ) + gateAssessments
            .filter { $0.rating.score < CADInteractionQualityRating.implemented.score }
            .map { assessment in
                DesignProcessCase(
                    id: "\(area.rawValue)-\(assessment.gate.rawValue)-rejected",
                    title: "\(assessment.gate.rawValue) is not ready for a verified claim",
                    status: assessment.rating == .missing ? .missing : .blocked,
                    diagnostic: DesignProcessDiagnostic(
                        id: "\(area.rawValue)-\(assessment.gate.rawValue)-not-implemented",
                        severity: assessment.rating == .missing ? .error : .warning,
                        message: "This gate has not reached implemented status.",
                        affectedLayer: layer(for: assessment.gate)
                    ),
                    notes: assessment.openWork
                )
            }
        let missing = openWork.enumerated().map { index, item in
            DesignProcessCase(
                id: "\(area.rawValue)-missing-\(index + 1)",
                title: item,
                status: .missing,
                diagnostic: DesignProcessDiagnostic(
                    id: "\(area.rawValue)-missing-\(index + 1)",
                    severity: .warning,
                    message: item,
                    affectedLayer: .evaluation
                )
            )
        }
        let performance = scopedCases(
            spec.performanceCases,
            area: area,
            testReferences: testReferences,
            evidence: gateEvidence
        ) + gateAssessments
            .filter { $0.gate == .performanceBudget }
            .map { assessment in
                DesignProcessCase(
                    id: "\(area.rawValue)-performance-budget",
                    title: "Performance budget is \(assessment.rating.rawValue)",
                    status: assessment.rating.score >= CADInteractionQualityRating.implemented.score ? .measured : .planned,
                    evidence: assessment.evidence,
                    notes: assessment.openWork
                )
            }

        return DesignProcessCaseMatrix(
            supported: DesignProcessCaseGroup(kind: .supported, cases: supported),
            boundary: DesignProcessCaseGroup(kind: .boundary, cases: boundary),
            degenerate: DesignProcessCaseGroup(
                kind: .degenerate,
                cases: scopedCases(
                    spec.degenerateCases,
                    area: area,
                    testReferences: testReferences,
                    evidence: gateEvidence
                )
            ),
            rejected: DesignProcessCaseGroup(kind: .rejected, cases: rejected),
            missing: DesignProcessCaseGroup(kind: .missing, cases: missing),
            performance: DesignProcessCaseGroup(kind: .performance, cases: performance)
        )
    }

    private static func scopedCases(
        _ cases: [DesignProcessCase],
        area: CADInteractionQualityArea,
        testReferences: [DesignProcessTestReference],
        evidence: [String]
    ) -> [DesignProcessCase] {
        cases.map { item in
            DesignProcessCase(
                id: "\(area.rawValue)-\(item.id)",
                title: item.title,
                status: item.status,
                diagnostic: scopedDiagnostic(item.diagnostic, area: area),
                testReferences: item.testReferences + testReferences,
                evidence: unique(item.evidence + evidence),
                notes: item.notes
            )
        }
    }

    private static func scopedDiagnostic(
        _ diagnostic: DesignProcessDiagnostic?,
        area: CADInteractionQualityArea
    ) -> DesignProcessDiagnostic? {
        guard let diagnostic else {
            return nil
        }
        return DesignProcessDiagnostic(
            id: "\(area.rawValue)-\(diagnostic.id)",
            severity: diagnostic.severity,
            message: diagnostic.message,
            affectedLayer: diagnostic.affectedLayer,
            source: diagnostic.source ?? area.rawValue
        )
    }

    private static func routeMatrix(
        area: CADInteractionQualityArea,
        spec: CADInteractionDesignProcessSpec,
        gates: [CADInteractionQualityGate: CADInteractionQualityRating],
        evidence: [CADInteractionQualityEvidence]
    ) -> DesignProcessRouteMatrix {
        let routeEvidence = DesignProcessRouteEvidence(
            sourceFiles: unique(evidence.flatMap(\.sourceFiles)),
            tests: designProcessTestReferences(from: evidence),
            diagnostics: unique(evidence.flatMap(\.notes)),
            notes: evidence.map(\.label)
        )
        return DesignProcessRouteMatrix(
            requiredPorts: [
                .documentation,
                .product,
                .ui,
                .core,
                .automation,
                .agent,
                .cli,
                .kernel,
                .evaluation,
                .measurement,
                .diagnostics,
            ],
            routes: [
                route(
                    area,
                    "documentation-product",
                    "Reference material to product capability contract",
                    .documentation,
                    spec.surfaces.documentation,
                    .product,
                    spec.capabilityTitle,
                    routeStatus(for: gates[.referenceContract] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "product-ui",
                    "Product capability to UI affordance",
                    .product,
                    spec.capabilityTitle,
                    .ui,
                    spec.surfaces.ui,
                    routeStatus(for: gates[.viewportAffordance] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "ui-core",
                    "UI affordance to Core command contract",
                    .ui,
                    spec.surfaces.ui,
                    .core,
                    spec.surfaces.core,
                    routeStatus(for: gates[.commandContract] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "core-automation",
                    "Core command to Automation route",
                    .core,
                    spec.surfaces.core,
                    .automation,
                    spec.surfaces.automation,
                    routeStatus(for: gates[.commandContract] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "automation-agent",
                    "Automation readback to Agent route",
                    .automation,
                    spec.surfaces.automation,
                    .agent,
                    spec.surfaces.agent,
                    routeStatus(for: gates[.agentParity] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "core-cli",
                    "Core command to CLI route",
                    .core,
                    spec.surfaces.core,
                    .cli,
                    spec.surfaces.cli,
                    routeStatus(for: gates[.commandContract] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "core-kernel",
                    "Core command to kernel evaluation",
                    .core,
                    spec.surfaces.core,
                    .kernel,
                    spec.surfaces.kernel,
                    routeStatus(for: lowestRating(gates[.sourceOwnership], gates[.commandContract])),
                    routeEvidence
                ),
                route(
                    area,
                    "kernel-evaluation",
                    "Kernel result to evaluation",
                    .kernel,
                    spec.surfaces.kernel,
                    .evaluation,
                    spec.surfaces.evaluation,
                    routeStatus(for: gates[.verification] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "evaluation-measurement",
                    "Evaluation to measurement readback",
                    .evaluation,
                    spec.surfaces.evaluation,
                    .measurement,
                    spec.surfaces.measurement,
                    routeStatus(for: gates[.measurementDiagnostics] ?? .missing),
                    routeEvidence
                ),
                route(
                    area,
                    "core-diagnostics",
                    "Core diagnostics to user and Agent readback",
                    .core,
                    spec.surfaces.core,
                    .diagnostics,
                    spec.surfaces.diagnostics,
                    routeStatus(for: gates[.measurementDiagnostics] ?? .missing),
                    routeEvidence
                ),
            ]
        )
    }

    private static func route(
        _ area: CADInteractionQualityArea,
        _ name: String,
        _ title: String,
        _ source: DesignProcessRoutePortKind,
        _ sourceTitle: String,
        _ target: DesignProcessRoutePortKind,
        _ targetTitle: String,
        _ status: DesignProcessRouteStatus,
        _ evidence: DesignProcessRouteEvidence
    ) -> DesignProcessRoute {
        DesignProcessRoute(
            id: "\(area.rawValue)-\(name)",
            title: title,
            source: routePort(kind: source, title: sourceTitle),
            target: routePort(kind: target, title: targetTitle),
            status: status,
            evidence: evidence
        )
    }

    private static func routePort(
        kind: DesignProcessRoutePortKind,
        title: String
    ) -> DesignProcessRoutePort {
        DesignProcessRoutePort(
            kind: kind,
            identifier: "\(kind.rawValue)-\(stableIdentifier(for: title))",
            title: title
        )
    }

    private static func routeStatus(
        for rating: CADInteractionQualityRating
    ) -> DesignProcessRouteStatus {
        switch rating {
        case .missing:
            .missing
        case .planned:
            .planned
        case .partial:
            .partial
        case .implemented:
            .connected
        case .verified:
            .verified
        }
    }

    private static func lowestRating(
        _ lhs: CADInteractionQualityRating?,
        _ rhs: CADInteractionQualityRating?
    ) -> CADInteractionQualityRating {
        [lhs ?? .missing, rhs ?? .missing].min { left, right in
            left.score < right.score
        } ?? .missing
    }

    private static func selectedRouteIDs(
        from routeMatrix: DesignProcessRouteMatrix
    ) -> [String] {
        routeMatrix.routes.map(\.id)
    }

    private static func diagnosticRecords(
        from assessments: [CADInteractionQualityGateAssessment]
    ) -> [DesignProcessDiagnostic] {
        assessments
            .filter { $0.rating.score < CADInteractionQualityRating.implemented.score }
            .map { assessment in
                DesignProcessDiagnostic(
                    id: "\(assessment.gate.rawValue)-\(assessment.rating.rawValue)",
                    severity: assessment.rating == .missing ? .error : .warning,
                    message: "\(assessment.gate.rawValue) is \(assessment.rating.rawValue).",
                    affectedLayer: layer(for: assessment.gate)
                )
            }
    }

    private static func flowGraph(
        for area: CADInteractionQualityArea,
        spec: CADInteractionDesignProcessSpec
    ) -> DesignProcessFlowGraph {
        DesignProcessFlowGraph(
            nodes: [
                flowNode(.documentation, title: spec.surfaces.documentation, ports: [("reference", .output)]),
                flowNode(.product, title: spec.capabilityTitle, ports: [("reference", .input), ("intent", .output)]),
                flowNode(.ui, title: spec.surfaces.ui, ports: [("intent", .input), ("command", .output)]),
                flowNode(.core, title: spec.surfaces.core, ports: [
                    ("command", .input),
                    ("automation", .output),
                    ("cli", .output),
                    ("kernel", .output),
                    ("diagnostic", .output),
                ]),
                flowNode(.automation, title: spec.surfaces.automation, ports: [("command", .input), ("agent", .output)]),
                flowNode(.agent, title: spec.surfaces.agent, ports: [("readback", .input)]),
                flowNode(.cli, title: spec.surfaces.cli, ports: [("command", .input)]),
                flowNode(.kernel, title: spec.surfaces.kernel, ports: [("request", .input), ("result", .output)]),
                flowNode(.evaluation, title: spec.surfaces.evaluation, ports: [("result", .input), ("measurement", .output)]),
                flowNode(.measurement, title: spec.surfaces.measurement, ports: [("readback", .input)]),
                flowNode(.diagnostics, title: spec.surfaces.diagnostics, ports: [("message", .input)]),
            ],
            edges: [
                flowEdge(area, "documentation-product", .documentation, "reference", .product, "reference"),
                flowEdge(area, "product-ui", .product, "intent", .ui, "intent"),
                flowEdge(area, "ui-core", .ui, "command", .core, "command"),
                flowEdge(area, "core-automation", .core, "automation", .automation, "command"),
                flowEdge(area, "automation-agent", .automation, "agent", .agent, "readback"),
                flowEdge(area, "core-cli", .core, "cli", .cli, "command"),
                flowEdge(area, "core-kernel", .core, "kernel", .kernel, "request"),
                flowEdge(area, "kernel-evaluation", .kernel, "result", .evaluation, "result"),
                flowEdge(area, "evaluation-measurement", .evaluation, "measurement", .measurement, "readback"),
                flowEdge(area, "core-diagnostics", .core, "diagnostic", .diagnostics, "message"),
            ],
            requiredPorts: [
                requirement(.documentation, "reference", .outgoing),
                requirement(.product, "reference", .incoming),
                requirement(.product, "intent", .outgoing),
                requirement(.ui, "intent", .incoming),
                requirement(.ui, "command", .outgoing),
                requirement(.core, "command", .incoming),
                requirement(.core, "automation", .outgoing),
                requirement(.automation, "command", .incoming),
                requirement(.automation, "agent", .outgoing),
                requirement(.agent, "readback", .incoming),
                requirement(.core, "cli", .outgoing),
                requirement(.cli, "command", .incoming),
                requirement(.core, "kernel", .outgoing),
                requirement(.kernel, "request", .incoming),
                requirement(.kernel, "result", .outgoing),
                requirement(.evaluation, "result", .incoming),
                requirement(.evaluation, "measurement", .outgoing),
                requirement(.measurement, "readback", .incoming),
                requirement(.core, "diagnostic", .outgoing),
                requirement(.diagnostics, "message", .incoming),
            ],
        )
    }

    private static func flowNode(
        _ layer: DesignProcessLayer,
        title: String,
        ports: [(String, DesignProcessFlowPortDirection)]
    ) -> DesignProcessFlowNode {
        DesignProcessFlowNode(
            id: layer.rawValue,
            title: title,
            layer: layer,
            ports: ports.map { id, direction in
                DesignProcessFlowPort(id: id, title: id, direction: direction)
            }
        )
    }

    private static func flowEdge(
        _ area: CADInteractionQualityArea,
        _ name: String,
        _ source: DesignProcessLayer,
        _ sourcePort: String,
        _ target: DesignProcessLayer,
        _ targetPort: String
    ) -> DesignProcessFlowEdge {
        DesignProcessFlowEdge(
            id: "\(area.rawValue)-\(name)",
            sourceNodeID: source.rawValue,
            sourcePortID: sourcePort,
            targetNodeID: target.rawValue,
            targetPortID: targetPort
        )
    }

    private static func requirement(
        _ layer: DesignProcessLayer,
        _ port: String,
        _ connection: DesignProcessFlowPortConnection
    ) -> DesignProcessFlowPortRequirement {
        DesignProcessFlowPortRequirement(
            nodeID: layer.rawValue,
            portID: port,
            connection: connection,
            reason: "\(layer.rawValue).\(port) is required for assessment route coverage."
        )
    }

    private static func layer(for gate: CADInteractionQualityGate) -> DesignProcessLayer {
        switch gate {
        case .referenceContract:
            .product
        case .sourceOwnership, .commandContract, .selectionTopology:
            .core
        case .viewportAffordance, .inspectorAffordance:
            .ui
        case .agentParity:
            .agent
        case .measurementDiagnostics:
            .diagnostics
        case .verification:
            .evaluation
        case .performanceBudget:
            .measurement
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func stableIdentifier(for value: String) -> String {
        let normalized = value.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let components = String(normalized).split(separator: "-")
        return components.joined(separator: "-")
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
