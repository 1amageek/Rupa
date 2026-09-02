import RupaAgentProtocol
import RupaAutomation
import RupaCapabilities
import RupaCore
import RupaDomainFoundation

public enum AgentCapabilityCatalog {
    static let descriptors: [AgentCapabilityDescriptor] =
        DedicatedAutomationCapabilityID.allCases.map(\.descriptor) + [
        capability(
            "listParameters",
            category: .read,
            summary: "Read all document parameters without mutating source or undo history.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.parameters],
            targets: [.document],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "cadInteractionQualityAssessment",
            category: .read,
            summary: "Read the objective CAD interaction quality assessment across reference contract, source ownership, command contract, selection topology, viewport affordance, Inspector affordance, Agent parity, diagnostics, verification, and performance gates.",
            access: .agentRequest,
            stateEffect: .readOnly,
            requiresSession: false,
            requiresExpectedSourceGeneration: false,
            discovery: [.cadInteractionQualityAssessment],
            targets: [.document],
            failureMode: "Does not inspect or mutate a session; reports the current static product-quality assessment model."
        ),
        capability(
            "patternArraySummary",
            category: .read,
            summary: "List source-owned Pattern Array edit candidates, output ownership, lifecycle actions, and diagnostics without mutating the document.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.patternArraySummary, .designDisplaySnapshot],
            targets: [.sceneNode, .componentInstance],
            failureMode: "Rejects stale generations before reading; reports source-owned component-instance and independent-copy output policies so Agents do not direct-edit generated outputs."
        ),
        capability(
            "constructionPlaneSummary",
            category: .read,
            summary: "Return structured saved construction-plane IDs, names, sketch planes, scene-node IDs, and active state for Agent planning.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.constructionPlaneSummary],
            targets: [.constructionPlane],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "sceneGraphSnapshot",
            category: .read,
            summary: "Return deterministic Product scene-node identity, hierarchy, source linkage, visibility, lock state, and local transforms without evaluating CAD or Mesh geometry.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.sceneGraphSnapshot],
            targets: [.document, .sceneNode, .componentInstance, .body],
            failureMode: "Rejects stale generations before reading and returns no evaluated geometry buffers."
        ),
        capability(
            "viewportSnapshot",
            category: .read,
            summary: "Return the exact visible items, navigation identities, selected source authority, world placement, bounds, checked Mesh counts, and copy telemetry from the published application viewport without serializing geometry buffers.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.viewportSnapshot],
            targets: [.document, .sceneNode, .componentInstance, .body],
            failureMode: "Rejects stale generations, missing navigation, malformed Mesh counts or ranges, and count overflow before returning a geometry-buffer-free result."
        ),
        capability(
            "designDisplaySnapshot",
            category: .read,
            summary: "Return workspace scale, viewport grid scale, interaction scale defaults, ordered UI-visible sketch primitives, profile regions, component definitions, component instances, pattern arrays, saved views, extrude and straight-prism sweep display bodies, evaluated body meshes, and generated topology for Agent viewport planning.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.designDisplaySnapshot, .sketchEntitySummary, .topologySummary, .savedViews],
            targets: [.document, .componentInstance, .sketchEntity, .region, .body, .face, .edge, .vertex, .savedView],
            failureMode: "Rejects stale generations before reading; reports normalized workspace scale, Core-owned viewport grid and interaction scale defaults, display-ready source snapshots, reusable component definitions, placed component instances, and generated pattern sources, not raw CAD kernel internals."
        ),
        capability(
            "booleanEvaluationPlan",
            category: .read,
            summary: "Preflight a proposed standalone Boolean without mutating the document, returning the exact operand subset, output topology kind, topology name scheme, topology slots that resolve to post-create persistent names, B-rep topology counts, primitive counts, unsupported code, and stage-specific ordered checks used by the shared Boolean evaluation contract.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.topologySummary, .booleanEvaluationPlan],
            targets: [.body],
            failureMode: "Rejects stale generations before evaluation; returns structured unsupported results at requestContract, sourceBodies, operandTopology, or capabilityDecision gates for duplicate targets, a tool that is also a target, missing references, sheet operands, empty results, or intersecting curved and non-orthogonal result topology outside the supported subsets before createBoolean mutates the document.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "operation",
                    supportedValues: ["union", "difference", "intersect", "slice"],
                    notes: [
                        "Use the result before createBoolean to avoid committing unsupported topology.",
                        "The current exact subset supports axis-aligned box solids, orthogonal cell-union solids, and separated solid-body union.",
                        "Topology slots use the SwiftCAD Boolean slot contract and can be matched against topologySummary after createBoolean returns the new generation."
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "outputTopologyKind",
                    supportedValues: ["singleBox", "separatedBoxes", "orthogonalCellUnion", "zThroughFrame", "disjointSolidUnion"],
                    notes: [
                        "singleBox and separatedBoxes keep box primitives explicit",
                        "orthogonalCellUnion preserves connected orthogonal solid results",
                        "zThroughFrame reports exact through-cut frame topology",
                        "disjointSolidUnion copies separated source B-rep topology into one result body with copiedSourceTopology names"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "keepTools",
                    supportedValues: ["false", "true"],
                    notes: [
                        "false replaces target and tool B-rep output during evaluation",
                        "true keeps target and tool output and adds the Boolean result body"
                    ]
                ),
            ]
        ),
        capability(
            "sweepEvaluationPlan",
            category: .read,
            summary: "Preflight a proposed Sweep without mutating the document, returning the resolved path shape, section state, evaluation kind, output topology, boolean support, guide strategy candidates, resolved guide strategy, per-candidate guide resolution statuses, unsupported code, and ordered checks used by the shared sweep evaluation contract.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.sketchEntitySummary, .topologySummary, .sweepEvaluationPlan],
            targets: [.profile, .sketchEntity, .body],
            failureMode: "Rejects stale generations, missing references, invalid option quantities, disconnected or branched path chains, and unresolved target bodies; returns structured unsupported results for current kernel capability gaps and geometry contracts such as simplify output, sheet target booleans, profile-plane degenerate parallel alignment, round multi-curve corner-transition topology, and guide constraints that do not solve against the section and path frames before mutation, including failed guide strategy candidates.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "evaluationKind",
                    supportedValues: [
                        "exactStraightExtrude",
                        "pathNormalSectionSweep",
                        "profilePlaneParallelSweep",
                    ],
                    notes: [
                        "Use the result before createSweep to choose an exact straight extrusion, path-normal sweep, or profile-plane parallel sweep strategy.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "guideStrategyCandidates",
                    supportedValues: [
                        "none",
                        "pointSimilarity",
                        "pointNonUniformAffine",
                        "pointSignedAxisRail",
                        "pointBilinearQuadrilateralRail",
                        "pointMeanValueCageRail",
                        "pointRadialRail",
                        "chordDirectional",
                        "curveContact",
                    ],
                    notes: [
                        "The option axis lists possible guide strategies; guided preflight results also report resolvedGuideStrategy and guideStrategyResolutions, including typed unsupportedCode values for failed guide strategies, from the shared sweep constraint solver.",
                    ]
                ),
            ]
        ),
        capability(
            "evaluateDocument",
            category: .read,
            summary: "Validate and evaluate the document, updating evaluation diagnostics without adding undo history.",
            access: .agentRequest,
            stateEffect: .readOnly,
            targets: [.document],
            failureMode: "Rejects stale generations before evaluation."
        ),
        capability(
            "measureDocument",
            category: .read,
            summary: "Measure selected or whole-document source-derived geometry and report workspace precision/rebase and scale-preset guidance without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.measurement, .selectionState],
            targets: [.document, .sceneNode, .sketchEntity],
            failureMode: "Rejects stale generations before measuring."
        ),
        capability(
            "selectionMeasurement",
            category: .read,
            summary: "Measure a typed Swift-CAD SelectionReference as a point, distance, or angle without mutation, including topology, edge parameters, curve CVs, surface parameters, surface CVs, and surface trims.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.selectionMeasurement, .surfaceSourceSummary, .topologySummary, .sketchEntitySummary],
            targets: [.face, .edge, .vertex, .sketchEntity, .surface, .surfaceControlPoint, .surfaceTrim],
            failureMode: "Rejects stale generations, invalid selection references, unresolved generated topology, unsupported ambiguous body or surface-knot measurements, and evaluation failures before returning measured geometry."
        ),
        capability(
            "objectDimensionSummary",
            category: .read,
            summary: "List editable Dimension command candidates for selected object, face, generated face-normal, generated extrusion depth edge, or generated opposing face-pair targets without mutation, including box size axes, cylinder diameter, radius, depth, and supported face-distance candidates.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.objectDimensionSummary, .topologySummary],
            targets: [.body, .face, .edge],
            failureMode: "Rejects stale generations, non-body targets, unsupported edge or face-pair topology, unsupported source profiles, and invalid source expressions before returning candidates."
        ),
        capability(
            "sketchDimensionSummary",
            category: .read,
            summary: "List editable Dimension command candidates for selected sketch line, circle, arc, generated extrude cap edge, or supported generated arc edge targets without mutation, including fillet-radius readback for generated fillet arc edges.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.sketchDimensionSummary, .sketchEntitySummary, .topologySummary],
            targets: [.sketchEntity, .edge],
            failureMode: "Rejects stale generations, unsupported topology targets, unresolved source sketch curves, and invalid source expressions before returning candidates."
        ),
        capability(
            "selectionDimensionEvaluation",
            category: .read,
            summary: "Evaluate persistent CAD selection dimensions stored in the SwiftCAD document source.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.selectionDimensionEvaluation, .topologySummary, .sketchEntitySummary],
            targets: [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects stale generations, invalid CAD source, unresolved selection references, or missing dimension IDs before returning measured residuals."
        ),
        capability(
            "resolveSnap",
            category: .read,
            summary: "Resolve a model-space sketch input point against grid, measurement annotations, source sketch special points, source profile region centers, generated topology points, visible UVN surface frame handles, authored surface trim endpoints and p-curve control points, source spline CVs, closest curve points, supported curve intersections, reference-point curve-axis candidates, reference-point curve-coordinate-plane candidates, and reference-point tangent/perpendicular curve candidates without mutating the document.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.snapResolution, .sketchEntitySummary, .topologySummary, .surfaceSourceSummary, .surfaceFrames],
            targets: [.document, .sceneNode, .profile, .region, .sketchEntity, .face, .surfaceTrim],
            failureMode: "Rejects stale generations, invalid points, invalid snap options, or source expressions that cannot be resolved before returning candidates; object-targeting force enable, candidate-kind suppression, source-curve X/Y/Z axis candidates, and source-curve XY/YZ/ZX coordinate-plane candidates are supported through snap options."
        ),
        capability(
            "meshSummary",
            category: .read,
            summary: "Read evaluated mesh counts, bounds, and per-body mesh metadata without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.meshSummary],
            targets: [.document],
            failureMode: "Rejects stale generations or evaluation failures before returning mesh data."
        ),
        capability(
            "meshCatalog",
            category: .read,
            summary: "Read the bounded catalog of retained Authored Mesh sources, element counts, bounds, provenance, and Product Object representation references.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.meshCatalog],
            targets: [.document, .sceneNode, .body],
            failureMode: "Rejects stale generations, invalid read limits, missing Authored Mesh sources, and source identity mismatches without returning an unbounded catalog."
        ),
        capability(
            "meshPage",
            category: .read,
            summary: "Read one bounded page of Authored Mesh element records using an exact source handle and cursor.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.meshCatalog, .meshPage],
            targets: [.body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations, stale handle coordinates, invalid cursors, invalid read limits, and missing source elements."
        ),
        capability(
            "meshNeighborhood",
            category: .read,
            summary: "Read one bounded element neighborhood using an exact Authored Mesh source handle, origin, and depth.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.meshCatalog, .meshNeighborhood],
            targets: [.body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations, stale handle coordinates, invalid origins, invalid depth or read limits, and missing source elements."
        ),
        capability(
            "meshEditPreview",
            category: .directEditing,
            summary: "Evaluate one bounded declarative Authored Mesh edit plan without publishing project state.",
            access: .agentRequest,
            stateEffect: .readOnly,
            supportsDryRun: true,
            semanticSupportsCancellation: true,
            discovery: [.meshCatalog, .meshPage, .meshEditPreview],
            targets: [.body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations, stale handles, invalid plans, invalid limits, and cancellation without publishing or silently rebasing the proposal.",
            semanticEffect: .query,
            semanticResult: CapabilityResultDescriptor(
                kind: .validationReport,
                maximumFidelity: "exact-authored-mesh-edit-preview"
            ),
            semanticRetrySafe: true
        ),
        capability(
            "meshEditCommit",
            category: .directEditing,
            summary: "Commit one bounded declarative Authored Mesh edit plan through the project source authority and return the exact new source handle.",
            access: .agentRequest,
            stateEffect: .sourceMutation,
            semanticSupportsCancellation: true,
            discovery: [.meshCatalog, .meshPage, .meshEditPreview],
            targets: [.body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations, stale handles, invalid plans, invalid limits, and cancellation before publication; a post-publication projection failure returns a must-not-retry committed receipt.",
            semanticEffect: .sourceMutation,
            semanticResult: CapabilityResultDescriptor(kind: .sourceTransaction),
            semanticRetrySafe: false
        ),
        capability(
            "makeEditable",
            category: .directEditing,
            summary: "Promote one selected CAD body representation to an Authored Mesh representation without removing its CAD modeling authority.",
            access: .agentRequest,
            stateEffect: .sourceMutation,
            semanticSupportsCancellation: true,
            discovery: [.topologySummary, .meshCatalog, .makeEditable],
            targets: [.sceneNode, .body],
            failureMode: "Rejects stale generations, missing or non-CAD modeling bodies, duplicate source or representation identities, and cancellation before publication; a post-publication projection failure returns a must-not-retry committed receipt.",
            semanticEffect: .sourceMutation,
            semanticResult: CapabilityResultDescriptor(kind: .sourceTransaction),
            semanticRetrySafe: false
        ),
        capability(
            "polySplineMeshAnalysis",
            category: .read,
            summary: "Preflight a source mesh for PolySpline reconstruction and return structured support diagnostics plus quad patch graph candidates and partition data without mutating the document.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.meshSummary, .polySplineMeshAnalysis],
            targets: [.document],
            failureMode: "Rejects stale generations before analysis; reports invalid meshes, unsupported rounded-corner requests, non-manifold adjacency, inconsistent boundary winding, patch graph candidates, exact selected/rejected partitions, and unsupported G2 multi-patch reconstruction as structured diagnostics."
        ),
        capability(
            "sketchEntitySummary",
            category: .read,
            summary: "Discover editable source sketch entities, source profile regions, expressions, dimensions, constraints, and selection targets without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity, .region],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "curveAnalysis",
            category: .read,
            summary: "Evaluate source curves for samples, curvature, approximate length, and internal spline continuity without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects stale generations or invalid documents before curve analysis."
        ),
        capability(
            "topologySummary",
            category: .read,
            summary: "Discover generated faces, edges, vertices, persistent topology names, and selection targets without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.topologySummary],
            targets: [.face, .edge, .vertex],
            failureMode: "Rejects stale generations or evaluation failures before returning topology data."
        ),
        capability(
            "surfaceSourceSummary",
            category: .read,
            summary: "Discover source-owned surface contracts for editable PolySpline and direct B-spline surfaces, including patch IDs, degree and knot-vector basis, knot and span addresses, weighted CV targets, boundary CV targets, trim edge editability, authored p-curve control-point indices and weights, G0/G1/G2 continuity levels, span-center UVN frame samples, trim loops, support diagnostics, and generated topology links.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.surfaceSourceSummary, .polySplineMeshAnalysis, .topologySummary],
            targets: [.document, .body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations or invalid documents before returning source-owned surface contracts; reports unsupported PolySpline reconstruction options and invalid direct B-spline source data as structured diagnostics instead of exposing silent surface edit targets."
        ),
        capability(
            "surfaceAnalysis",
            category: .read,
            summary: "Sample generated B-spline faces for UV points, normals, principal directions, ordered trim-boundary point loops, and finite-difference surface curvature comb diagnostics without mutation; supports low, standard, and high sample density.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.topologySummary, .surfaceAnalysis],
            targets: [.face, .edge],
            failureMode: "Rejects stale generations, invalid documents, or unsupported unbounded B-spline domains before returning surface analysis data."
        ),
        capability(
            "surfaceFrames",
            category: .read,
            summary: "Resolve generated B-spline face UV addresses, surface selection references, or B-spline trim p-curve parameter references into oriented UVN local frames, derivative tangents, principal directions, and curvature values without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.topologySummary, .surfaceSourceSummary, .surfaceFrames],
            targets: [.face, .surfaceControlPoint, .surfaceTrim],
            failureMode: "Rejects stale generations, unresolved face persistent names, face IDs, or surface selection references, non-B-spline faces, unbounded domains, ambiguous UV input, whole trim edges, non-B-spline trim p-curves, and UV parameters outside the face surface domain."
        ),
        capability(
            "surfaceContinuitySummary",
            category: .read,
            summary: "Discover B-spline face adjacencies, shared edges, and observed G0/G1/G2 continuity status without mutation.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.topologySummary, .surfaceContinuitySummary],
            targets: [.face, .edge],
            failureMode: "Rejects stale generations or evaluation failures before returning surface continuity data; reports sampled curvature gaps for G2-capable UV trim curves and flags unresolved curvature continuity when a sampled boundary contract is unavailable."
        ),
        capability(
            "surfaceBoundaryContinuityCompatibility",
            category: .read,
            summary: "Preflight whether two source-owned direct B-spline trim boundaries can be matched at G0, G1, or G2 before mutating the target boundary control rows.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.surfaceSourceSummary, .surfaceBoundaryContinuityCompatibility],
            targets: [.surfaceTrim],
            failureMode: "Rejects stale generations, invalid selection references, non-direct B-spline trims, inner trims, and missing source features; returns structured diagnostics for identical boundaries, incompatible boundary bases, non-clamped boundaries, control-count mismatches, and insufficient cross-boundary control rows."
        ),
        capability(
            "selectTargets",
            category: .selection,
            summary: "Select Agent-discovered object, face, edge, vertex, region, or sketch-entity targets without mutating CAD source.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.topologySummary, .sketchEntitySummary],
            targets: [.sceneNode, .face, .edge, .vertex, .region, .sketchEntity],
            failureMode: "Rejects stale generations and targets incompatible with the current document."
        ),
        capability(
            "selectReferences",
            category: .selection,
            summary: "Select Agent-discovered Swift-CAD SelectionReference values, including Surface CV references, without mutating CAD source.",
            access: .agentRequest,
            stateEffect: .readOnly,
            discovery: [.surfaceSourceSummary, .topologySummary, .selectionMeasurement],
            targets: [.surface, .surfaceControlPoint, .surfaceTrim, .surfaceTrimSpan, .surfaceTrimKnot],
            failureMode: "Rejects stale generations and references incompatible with the current document."
        ),
        capability(
            "undo",
            category: .document,
            summary: "Undo the latest source mutation in the selected document session.",
            access: .agentRequest,
            stateEffect: .sourceMutation,
            targets: [.document],
            failureMode: "Rejects stale generations and sessions with no undo history."
        ),
        capability(
            "redo",
            category: .document,
            summary: "Redo the latest reverted source mutation in the selected document session.",
            access: .agentRequest,
            stateEffect: .sourceMutation,
            targets: [.document],
            failureMode: "Rejects stale generations and sessions with no redo history."
        ),
        capability(
            "saveDocument",
            category: .persistence,
            summary: "Save the registered project through the application-owned lifecycle without creating a second project authority.",
            access: .agentRequest,
            stateEffect: .readOnly,
            targets: [.document],
            failureMode: "Rejects stale generations and sessions without an application-owned canonical package destination."
        ),
        capability(
            "exportDocument",
            category: .persistence,
            summary: "Evaluate and export CAD-only project authority with a named preset or explicit export options; Mesh, mixed, and external authority are currently unavailable.",
            access: .agentRequest,
            stateEffect: .readOnly,
            supportsDryRun: true,
            semanticSupportsCancellation: true,
            targets: [.document],
            failureMode: "Returns commandUnsupported for Mesh-only, mixed CAD/Mesh, or external geometry authority; rejects stale generations, cancellation, unsupported formats, evaluation failures, and destination policy errors before atomically publishing staged output.",
            semanticEffect: .export,
            semanticResult: CapabilityResultDescriptor(kind: .exportArtifact),
            semanticRetrySafe: false
        ),
    ]

    enum DedicatedAutomationCapabilityID: String, CaseIterable {
        case describeDocument
        case validateDocument
        case setParameterExpression
        case setObjectDimensionExpression
        case setSketchEntityDimensionExpression
        case setSelectionDimensionTargetExpression
        case movePolySplineSurfaceVertex
        case setSurfaceFrameDisplay

        var descriptor: AgentCapabilityDescriptor {
            switch self {
            case .describeDocument:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .document,
                    summary: "Read the current document identity, generation, dirty state, and diagnostics.",
                    access: .agentRequest,
                    stateEffect: .readOnly,
                    targets: [.document],
                    failureMode: "Rejects stale generations before reading."
                )
            case .validateDocument:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .read,
                    summary: "Validate the current immutable project snapshot and return diagnostics without publishing project state.",
                    access: .agentRequest,
                    stateEffect: .readOnly,
                    targets: [.document],
                    failureMode: "Rejects stale generations before validation."
                )
            case .setParameterExpression:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .parameter,
                    summary: "Parse a user-facing expression string and upsert the resulting typed parameter using workspace-scale defaults when units are omitted.",
                    access: .agentRequest,
                    stateEffect: .sourceMutation,
                    discovery: [.parameters],
                    targets: [.document],
                    failureMode: "Rejects parse errors, dependency errors, kind mismatches, and stale generations before mutation.",
                    optionMatrix: [
                        AgentCapabilityDescriptor.OptionAxis(
                            name: "defaults",
                            supportedValues: [
                                "omitted uses current workspace display unit",
                                "explicit lengthUnit and angleUnit override document defaults",
                            ]
                        )
                    ]
                )
            case .setObjectDimensionExpression:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .solid,
                    summary: "Parse a user-facing length expression string and apply it to a supported selected object dimension.",
                    access: .agentRequest,
                    stateEffect: .sourceMutation,
                    discovery: [.topologySummary, .objectDimensionSummary],
                    targets: [.body, .face, .edge],
                    failureMode: "Rejects parse errors, non-length expressions, unsupported object dimensions, invalid values, and stale generations before mutation.",
                    optionMatrix: [
                        AgentCapabilityDescriptor.OptionAxis(
                            name: "expression",
                            supportedValues: [
                                "document parameters",
                                "explicit length units",
                                "architectural feet and inches",
                            ],
                            notes: [
                                "Expressions resolve through the current document parameter table.",
                                "Length units include micrometers through kilometers plus inches and feet.",
                                "Omit defaults to use the current workspace display unit for unitless length literals.",
                            ]
                        )
                    ]
                )
            case .setSketchEntityDimensionExpression:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .sourceCurveEditing,
                    summary: "Parse a user-facing length or angle expression string and apply it to a supported source sketch entity dimension.",
                    access: .agentRequest,
                    stateEffect: .sourceMutation,
                    discovery: [.sketchEntitySummary, .sketchDimensionSummary],
                    targets: [.sketchEntity],
                    failureMode: "Rejects parse errors, quantity-kind mismatches, unsupported sketch dimensions, fixed conflicts, invalid values, and stale generations before mutation.",
                    optionMatrix: [
                        AgentCapabilityDescriptor.OptionAxis(
                            name: "expression",
                            supportedValues: [
                                "document parameters",
                                "explicit length or angle units",
                                "architectural feet and inches for length dimensions",
                            ],
                            notes: [
                                "Line, radius, and diameter dimensions resolve as lengths.",
                                "Line angle and arc span dimensions resolve as angles.",
                                "Omit defaults to use the current workspace display unit for unitless length literals.",
                            ]
                        )
                    ]
                )
            case .setSelectionDimensionTargetExpression:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .sourceCurveEditing,
                    summary: "Parse a user-facing expression string and set the target of an existing persistent selection dimension.",
                    access: .agentRequest,
                    stateEffect: .sourceMutation,
                    discovery: [.selectionDimensionEvaluation],
                    targets: [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
                    failureMode: "Rejects missing selection dimension IDs, parse errors, quantity-kind mismatches, invalid values, and stale generations before mutation.",
                    optionMatrix: [
                        AgentCapabilityDescriptor.OptionAxis(
                            name: "quantityKind",
                            supportedValues: ["distance", "angle"],
                            notes: [
                                "The existing selection dimension determines whether the expression must resolve to length or angle.",
                                "Length targets share the same explicit-unit and architectural input support as object dimensions.",
                                "Omit defaults to use the current workspace display unit for unitless length literals.",
                            ]
                        )
                    ]
                )
            case .movePolySplineSurfaceVertex:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .solid,
                    summary: "Move a generated PolySpline patch boundary vertex by mutating its source mesh vertex through the undoable command pipeline.",
                    access: .agentRequest,
                    stateEffect: .sourceMutation,
                    discovery: [.topologySummary, .surfaceAnalysis, .surfaceContinuitySummary],
                    targets: [.vertex],
                    failureMode: "Rejects non-PolySpline generated vertices, stale generations, zero or invalid deltas, unsupported source meshes, moves that remove the selected patch, moves that change the selected boundary role, and moves that leave the evaluator unable to rebuild supported B-spline sheet topology."
                )
            case .setSurfaceFrameDisplay:
                AgentCapabilityCatalog.capability(
                    rawValue,
                    category: .solid,
                    summary: "Toggle session UVN surface frame display state for generated face UV queries, surface parameter references, Surface CV references, or trim p-curve parameter references.",
                    access: .agentRequest,
                    stateEffect: .workspaceMutation,
                    discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis],
                    targets: [.face, .surfaceControlPoint, .surfaceTrim],
                    failureMode: "Rejects unresolved references, ambiguous UV input, non-B-spline faces, stale generations, whole trim edges, unsupported surface span or knot references, and unsupported curve or sketch point references before mutation."
                )
            }
        }
    }

    public static func descriptors(
        domainRegistry: DomainRegistry,
        semanticOperationRegistry: SemanticOperationRegistry
    ) -> [AgentCapabilityDescriptor] {
        descriptors
            + semanticOperationRegistry.sortedDescriptors().map(semanticOperation)
            + domainRegistry.sortedCapabilityDescriptors().map(domainCapability)
    }

    public static func capabilityRegistry(
        domainRegistry: DomainRegistry
    ) throws -> CapabilityRegistry {
        try CapabilityRegistry(
            descriptors: (
                descriptors
                    + domainRegistry.sortedCapabilityDescriptors().map(domainCapability)
            ).map {
                try $0.capabilityDescriptor()
            }
        )
    }

    private static func capability(
        _ name: String,
        category: AgentCapabilityDescriptor.Category,
        summary: String,
        access: AgentCapabilityDescriptor.Access,
        stateEffect: AutomationCommandEffect,
        requiresSession: Bool = true,
        requiresExpectedSourceGeneration: Bool = true,
        requiresExpectedWorkspaceRevision: Bool? = nil,
        supportsDryRun: Bool = false,
        semanticSupportsCancellation: Bool? = nil,
        discovery: [AgentCapabilityDescriptor.Discovery] = [],
        targets: [AgentCapabilityDescriptor.Target] = [],
        failureMode: String,
        optionMatrix: [AgentCapabilityDescriptor.OptionAxis] = [],
        semanticEffect: CapabilityEffect? = nil,
        semanticResult: CapabilityResultDescriptor? = nil,
        semanticRetrySafe: Bool? = nil
    ) -> AgentCapabilityDescriptor {
        AgentCapabilityDescriptor(
            name: name,
            category: category,
            summary: summary,
            access: access,
            stateEffect: stateEffect,
            requiresSession: requiresSession,
            requiresExpectedSourceGeneration: requiresExpectedSourceGeneration,
            requiresExpectedWorkspaceRevision: requiresExpectedWorkspaceRevision
                ?? (stateEffect == .workspaceMutation),
            supportsDryRun: supportsDryRun,
            discovery: discovery,
            targets: targets,
            failureMode: failureMode,
            optionMatrix: optionMatrix,
            semanticEffect: semanticEffect,
            semanticResult: semanticResult,
            semanticRetrySafe: semanticRetrySafe,
            semanticSupportsCancellation: semanticSupportsCancellation
        )
    }

    private static func domainCapability(
        _ descriptor: DomainCapabilityDescriptor
    ) -> AgentCapabilityDescriptor {
        AgentCapabilityDescriptor(
            name: descriptor.id.rawValue,
            category: .domain,
            summary: descriptor.summary,
            access: .domainCapability,
            stateEffect: stateEffect(for: descriptor.effect),
            requiresSession: true,
            requiresExpectedSourceGeneration: true,
            supportsDryRun: descriptor.supportsDryRun,
            targets: descriptor.targetKinds.compactMap {
                AgentCapabilityDescriptor.Target(rawValue: $0.rawValue)
            },
            failureMode: descriptor.failureMode,
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "domain",
                    supportedValues: [descriptor.namespace.rawValue],
                    notes: ["Registered semantic domain namespace."]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "domainCapabilityID",
                    supportedValues: [descriptor.id.rawValue],
                    notes: ["Dispatch through the domain command lowering registry."]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "domainTargetKinds",
                    supportedValues: descriptor.targetKinds.map(\.rawValue),
                    notes: ["Domain-provided target kind names are preserved even when no generic Agent target enum exists."]
                ),
            ],
            inputParameters: descriptor.parameters,
            domainContract: AgentCapabilityDescriptor.DomainContract(
                effect: descriptor.effect,
                resultKind: descriptor.resultKind,
                targetKinds: descriptor.targetKinds,
                knownErrorCodes: descriptor.knownErrorCodes,
                supportsCancellation: descriptor.supportsCancellation,
                reportsProgress: descriptor.reportsProgress,
                determinism: descriptor.determinism,
                resultFidelity: descriptor.resultFidelity
            )
        )
    }

    private static func semanticOperation(
        _ descriptor: SemanticOperationDescriptor
    ) -> AgentCapabilityDescriptor {
        let operation = AgentSemanticOperationDescriptor(
            version: descriptor.version,
            inputs: descriptor.inputs.map {
                AgentSemanticOperationDescriptor.Input(
                    id: $0.id.rawValue,
                    type: $0.type,
                    isRequired: $0.isRequired
                )
            },
            outputs: descriptor.outputs.map {
                AgentSemanticOperationDescriptor.Output(
                    id: $0.id.rawValue,
                    type: $0.type,
                    selector: $0.selector
                )
            },
            route: descriptor.route,
            effect: descriptor.effect,
            invocationForms: [.direct, .program]
        )
        return AgentCapabilityDescriptor(
            name: descriptor.operationID.rawValue,
            category: .domain,
            summary: "Registered semantic operation.",
            access: .agentRequest,
            stateEffect: stateEffect(for: descriptor.effect),
            requiresSession: true,
            requiresExpectedSourceGeneration: true,
            requiresExpectedWorkspaceRevision: false,
            supportsDryRun: true,
            failureMode: "Uses the registered semantic operation descriptor and lowerer; rejects invalid values, stale coordinates, cancellation, and failed source publication without fallback.",
            semanticEffect: capabilityEffect(for: descriptor.effect),
            semanticResult: CapabilityResultDescriptor(
                kind: resultKind(for: descriptor.effect)
            ),
            semanticRetrySafe: descriptor.effect == .query,
            semanticSupportsCancellation: true,
            semanticOperation: operation
        )
    }

    private static func stateEffect(
        for semanticEffect: SemanticOperationEffect
    ) -> AutomationCommandEffect {
        switch semanticEffect {
        case .query, .export, .lifecycle, .externalJob: .readOnly
        case .sourceMutation, .meshMutation: .sourceMutation
        case .workspaceMutation: .workspaceMutation
        }
    }

    private static func capabilityEffect(
        for semanticEffect: SemanticOperationEffect
    ) -> CapabilityEffect {
        switch semanticEffect {
        case .query: .query
        case .sourceMutation, .meshMutation: .sourceMutation
        case .workspaceMutation: .workspaceMutation
        case .export: .export
        case .lifecycle: .decisionRecording
        case .externalJob: .externalJob
        }
    }

    private static func resultKind(
        for semanticEffect: SemanticOperationEffect
    ) -> CapabilityResultKind {
        switch semanticEffect {
        case .query: .semanticPayload
        case .sourceMutation, .meshMutation: .sourceTransaction
        case .workspaceMutation, .lifecycle: .workspaceTransaction
        case .export: .exportArtifact
        case .externalJob: .externalJob
        }
    }

    private static func stateEffect(
        for domainEffect: DomainCapabilityEffect
    ) -> AutomationCommandEffect {
        switch domainEffect {
        case .documentMutation:
            .sourceMutation
        case .query,
             .artifactGeneration,
             .export,
             .externalJob:
            .readOnly
        }
    }

}
