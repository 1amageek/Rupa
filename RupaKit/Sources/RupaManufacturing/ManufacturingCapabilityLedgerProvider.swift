import RupaCore

public enum ManufacturingCapabilityLedgerProvider {
    public static func entries() -> [CapabilityLedgerEntry] {
        [
            CapabilityLedgerEntry(
                id: ManufacturingDomain.validatePrintabilityCapabilityID.rawValue,
                category: .domainModule,
                title: "Manufacturing printability validation and export readiness",
                currentRating: .partial,
                gateAssessments: [
                    CADInteractionQualityGateAssessment(
                        gate: .referenceContract,
                        rating: .partial,
                        evidence: [
                            "RupaManufacturing registers the manufacturing namespace and validatePrintability capability.",
                            "ManufacturingPrintabilityOptions defines a typed process ID plus build-volume, material-assignment, export-readiness, overhang-limit, wall-thickness, and clearance requirements.",
                            "ManufacturingProcessCatalog injects validated process profiles with family and support-strategy contracts into discovery, lowering, analysis, and export preflight.",
                            "Scene node material assignments resolve into evaluated mesh/body material readback before manufacturing validation and export preflight.",
                            "Face-level material/process bindings are stored in RupaCore with generated topology targets and summarized as typed mesh material coverage.",
                        ],
                        openWork: [
                            "Define a persisted build frame, machine/material-specific process settings, and output-format-specific export schemas.",
                            "Replace untyped measurement dictionaries with quantities that carry units, thresholds, and tolerances.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .sourceOwnership,
                        rating: .partial,
                        evidence: [
                            "Object-level material ownership remains in RupaCore scene metadata and is projected into evaluated Swift-CAD mesh/body material fields through SceneMaterialAssignmentResolver.",
                            "Face-level material/process ownership remains in RupaCore topology material bindings and is resolved from generated persistent face names into current evaluated body/face references.",
                            "Process profile definitions remain domain-owned and are injected through ManufacturingProcessCatalog.",
                        ],
                        openWork: [
                            "Persist project-selected process and custom machine/material settings in a manufacturing semantic envelope.",
                            "Bind the persisted build frame and manufacturing settings to the projection dependency identity used by each report.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .commandContract,
                        rating: .partial,
                        evidence: [
                            "ManufacturingPrintabilityLowering routes validatePrintability into a non-mutating domain analysis plan.",
                            "ManufacturingPrintabilityQuery returns typed diagnostics and a structured SemanticJSONValue payload through an immutable query context.",
                            "ManufacturingMeshAnalyzer derives mesh quality, export-readiness, wall-thickness, clearance, and supportability metrics from an identified evaluated mesh artifact.",
                            "ManufacturingExportPreflightValidator connects STL, 3MF, and STEP export dry-runs and writes to the same printability diagnostics through DocumentExportService injection.",
                            "DocumentExportService materializes scene-node material assignments into the evaluated export document before preflight or exchange output.",
                            "Core exposes setTopologyMaterialBinding through the document command path and mesh summary reports typed material coverage for body, missing, partial-face, complete-face, and mixed-face cases.",
                            "Manufacturing lowering rejects unknown process IDs before analysis and validates explicit face-level process overrides against the selected profile.",
                        ],
                        openWork: [
                            "Add command-backed persistence and Inspector editing for project process, machine, and material settings.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .selectionTopology,
                        rating: .partial,
                        evidence: [
                            "Wall-thickness, clearance, overhang, and supportability findings return compressed triangle ranges bound to the exact mesh artifact identity.",
                            "The current report attaches generated body identifiers to body, build-volume, material, and export-readiness checks.",
                            "Face-level material bindings are resolved through generated persistent face names before mesh summary and manufacturing validation.",
                        ],
                        openWork: [
                            "Resolve artifact-bound regions into shared viewport overlays and expose typed source/topology subjects for non-mesh findings.",
                            "Add sampled-point and exact B-rep region forms for rules that cannot be represented by mesh triangles.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .viewportAffordance,
                        rating: .partial,
                        evidence: [
                            "The generic domain command panel renders process choices and typed manufacturing thresholds from the registered descriptor.",
                        ],
                        openWork: [
                            "Resolve and show wall thickness, clearance, overhang, and build-volume regions through the shared viewport overlay service.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .inspectorAffordance,
                        rating: .missing,
                        openWork: [
                            "Expose material/process settings and violation readback in the Inspector.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .agentParity,
                        rating: .partial,
                        evidence: [
                            "domain.execute can invoke manufacturing.validatePrintability through a registered DomainRegistry.",
                            "DomainExecutionResult carries the structured manufacturing payload for Agent and CLI readback.",
                            "Agent capability discovery publishes the same catalog-derived process choices and typed units as the Workspace UI.",
                            "DomainExecutionResult returns artifact-bound validation regions separately from human-readable diagnostics.",
                        ],
                        openWork: [
                            "Expose typed validation findings, measurement quantities, and reference resolution states without requiring payload JSON interpretation.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .measurementDiagnostics,
                        rating: .partial,
                        evidence: [
                            "Current diagnostics report process profile selection, face-level process conflicts, body presence, mesh triangle counts, configured build-volume fit, material coverage, mesh export-readiness, wall-thickness, clearance, angle-limited overhang area, and explicit powder escape-analysis limitations.",
                        ],
                        openWork: [
                            "Add persisted-orientation support regions, trapped-powder volume, escape-path analysis, and output-format-specific export-scale measurements.",
                            "Implement policy override provenance where a conformance profile explicitly permits an override.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .verification,
                        rating: .partial,
                        evidence: [
                            "RupaManufacturingTests cover catalog injection, process discovery, unknown-process rejection, powder-process limitation diagnostics, face-process conflict rejection, executor routing, dry-run behavior, unsupported payload rejection, missing-body diagnostics, build-volume pass/fail, material coverage, mesh readiness, artifact-bound violation regions, wall thickness, clearance, and STL/3MF/STEP export preflight gating.",
                        ],
                        openWork: [
                            "Add authoritative geometry fixtures for persisted build orientations, trapped-powder escape paths, exact-versus-mesh comparisons, and region resolution.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .performanceBudget,
                        rating: .missing,
                        openWork: [
                            "Replace quadratic wall-thickness and body-clearance scans with spatial acceleration or declare and enforce an input ceiling.",
                            "Measure wall-clock time, peak memory, cancellation latency, and geometry-copy budgets on named dense fixtures.",
                        ]
                    ),
                ],
                evidence: [
                    CADInteractionQualityEvidence(
                        label: "Initial manufacturing domain module",
                        sourceFiles: [
                            "RupaKit/Sources/RupaManufacturing/ManufacturingDomain.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingPrintabilityQuery.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingPrintabilityLowering.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingPrintabilityOptions.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingPrintabilityReport.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingProcessCatalog.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingProcessProfile.swift",
                            "RupaKit/Sources/RupaManufacturing/ManufacturingExportPreflightValidator.swift",
                        ],
                        tests: [
                            "RupaKit/Tests/RupaManufacturingTests/ManufacturingDomainTests.swift",
                        ],
                        notes: [
                            "This entry remains partial because artifact-bound mesh regions and typed outcome/fidelity policy are implemented, while persisted machine/material/build-frame source, typed quantities, exact-geometry cases, trapped-powder analysis, format-specific per-face export mapping, shared overlay resolution, and performance budgets remain open.",
                        ]
                    ),
                ],
                openWork: [
                    "Persist the build frame and project process, machine, and material settings as manufacturing semantic source.",
                    "Add orientation-aware support regions, trapped-powder volume, and powder escape-path analysis.",
                    "Implement format-specific face-material/process export validation.",
                    "Add typed quantities, policy override provenance, shared region resolution, and exact-geometry rules required by the profile.",
                    "Introduce spatial acceleration and enforce dense-mesh time, memory, cancellation, and copy budgets.",
                ],
                nextRequiredResult: "Manufacturing must persist project process, machine, material, and build-frame source; consume that identity in validation; and meet typed-measurement, exactness, region-resolution, export-mapping, override-provenance, and dense-mesh performance gates."
            ),
        ]
    }
}
