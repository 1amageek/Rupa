public struct CADInteractionQualityAssessmentService: Sendable {
    public init() {}

    public func assess() -> CADInteractionQualityAssessmentResult {
        let entries = Self.entries
        return CADInteractionQualityAssessmentResult(
            referenceDate: "2026-06-24",
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                .sourceOwnership: .partial,
                .commandContract: .partial,
                .selectionTopology: .implemented,
                .viewportAffordance: .partial,
                .inspectorAffordance: .planned,
                .agentParity: .partial,
                .measurementDiagnostics: .partial,
                .verification: .verified,
                .performanceBudget: .partial,
            ],
            evidence: [
                CADInteractionQualityEvidence(
                    label: "Boolean operation options on evaluated feature subsets",
                    sourceFiles: [
                        "swift-CAD/Sources/CADKernel/BoxBRepBooleanEvaluator.swift",
                        "swift-CAD/Sources/CADKernel/PlanarSweepFeatureEvaluator.swift",
                        "swift-CAD/Sources/CADKernel/PlanarRevolveFeatureEvaluator.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaCore/EditorCommand.swift",
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
                    ],
                    tests: [
                        "swift-CAD/Tests/CADKernelTests/CADKernelTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SweepCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/RevolveCommandTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Sweep and revolve expose boolean operation options through Agent capability descriptors.",
                        "Standalone Boolean target/tool workflows and mixed Solid/Sheet operations remain gap items.",
                    ]
                ),
            ],
            openWork: [
                "Standalone Boolean command with target/tool selection contracts.",
                "Union, difference, and intersect support across general Solid and Sheet topology.",
                "Keep Tools, Slice, and targetless creation policies.",
                "Exact post-boolean topology naming for follow-on selection, dimensions, and direct edits.",
            ],
            next: "Add a standalone Boolean feature contract that reuses command-integrated boolean options but owns target/tool selection, exact topology output, and failure diagnostics."
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
                        "RupaKit/Sources/RupaCore/EditorCommand.swift",
                        "RupaKit/Sources/RupaCore/GeneratedTopologySelectionResolver.swift",
                        "RupaKit/Sources/RupaCore/PolySplineSurfaceVertexEditingService.swift",
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/BodyFaceOffsetCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyEdgeChamferCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/BodyVertexMoveCommandTests.swift",
                        "RupaKit/Tests/RupaCoreTests/DesignDocumentTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ],
                    notes: [
                        "Face offset, edge chamfer/fillet, vertex move, and PolySpline surface vertex edits are routed through command contracts.",
                        "General push/pull, move edge, delete face, match face, draft face, and proportional CV editing are not yet complete.",
                    ]
                ),
            ],
            openWork: [
                "General push/pull face edits with dependent offset, adjacent-angle, and grow policies.",
                "Move planar and circular edges while preserving analytic geometry.",
                "Delete Face, Match Face, Draft Face, and broader surface-CV proportional editing.",
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                        "RupaKit/Sources/RupaCore/PatternArrayInstancePlanner.swift",
                        "RupaKit/Sources/RupaCore/DesignDisplaySnapshotService.swift",
                        "RupaKit/Sources/RupaCore/SceneNode.swift",
                        "RupaKit/Sources/RupaCore/ProductMetadata.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaCore/EditorCommand.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationCommand.swift",
                        "RupaKit/Sources/RupaAutomation/AutomationRunner.swift",
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                        "swift-CAD/Sources/CADKernel/PlanarSweepFeatureEvaluator.swift",
                        "RupaKit/Sources/RupaCore/DesignDocument.swift",
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
                        "RupaKit/Sources/RupaUI/MainView.swift",
                    ],
                    tests: [
                        "swift-CAD/Tests/CADKernelTests/CADKernelTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SweepCommandTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ]
                ),
            ],
            openWork: [
                "Rail deformation beyond the current affine, signed-axis, convex quadrilateral bilinear, convex mean-value cage, and radial point-guide sections.",
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
                        "RupaKit/Sources/RupaCore/SurfaceAnalysisService.swift",
                        "RupaKit/Sources/RupaCore/SurfaceContinuityService.swift",
                        "RupaKit/Sources/RupaAgent/AgentMessage.swift",
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceAnalysisOverlay.swift",
                        "RupaKit/Sources/RupaRendering/ViewportSurfaceContinuityOverlay.swift",
                    ],
                    tests: [
                        "RupaKit/Tests/RupaCoreTests/SurfaceAnalysisServiceTests.swift",
                        "RupaKit/Tests/RupaCoreTests/SurfaceContinuityServiceTests.swift",
                        "RupaKit/Tests/RupaRenderingTests/ViewportPolySplineSurfaceVertexSlideAffordanceGeometryTests.swift",
                        "RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift",
                    ]
                ),
            ],
            openWork: [
                "First-class NURBS and B-spline source entities with degree, order, knot vectors, weights, spans, stable CV/knot/span IDs, and trim-loop ownership.",
                "Viewport surface-frame handles, snap consumption, trim editing, offset, and sweep or loft section placement that consume the Agent-readable UVN frame contract.",
                "Typed continuity contracts for G0/G1/G2 surface boundaries and G0/G1/G2/G3 curve matching.",
                "Non-planar G2 multi-patch reconstruction.",
                "Patch merge and rounded-corner policy output.",
                "General trim-curve and surface CV source editing.",
                "Viewport creation controls.",
            ],
            next: "Promote PolySpline from generated-boundary editing to a shared parametric surface foundation with NURBS/B-spline source ownership, UI-consumable UVN frame affordances, and explicit continuity diagnostics before broadening surface tools."
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
                        "RupaKit/Sources/RupaAgent/AgentCommandController.swift",
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
