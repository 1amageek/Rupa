struct CADInteractionDesignProcessSpec: Sendable {
    struct RouteSurface: Sendable {
        var documentation: String
        var ui: String
        var core: String
        var automation: String
        var agent: String
        var cli: String
        var kernel: String
        var evaluation: String
        var measurement: String
        var diagnostics: String

        init(
            documentation: String,
            ui: String,
            core: String,
            automation: String,
            agent: String,
            cli: String,
            kernel: String,
            evaluation: String,
            measurement: String,
            diagnostics: String
        ) {
            self.documentation = documentation
            self.ui = ui
            self.core = core
            self.automation = automation
            self.agent = agent
            self.cli = cli
            self.kernel = kernel
            self.evaluation = evaluation
            self.measurement = measurement
            self.diagnostics = diagnostics
        }
    }

    var capabilityTitle: String
    var sourceEntities: [String]
    var targetEntities: [String]
    var generatedTopology: [String]
    var tolerances: [String]
    var ownershipBoundaries: [String]
    var supportedCases: [DesignProcessCase]
    var boundaryCases: [DesignProcessCase]
    var degenerateCases: [DesignProcessCase]
    var rejectedCases: [DesignProcessCase]
    var performanceCases: [DesignProcessCase]
    var surfaces: RouteSurface
    var invariants: [DesignProcessInvariant]
    var decisionConflictArea: String
    var decisionRationale: String

    static func spec(for area: CADInteractionQualityArea) -> CADInteractionDesignProcessSpec {
        switch area {
        case .dimensions:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Dimension command target editing",
                sourceEntities: ["selection dimension source", "sketch dimension source", "object dimension source", "generated topology reference"],
                targetEntities: ["model-driving dimension", "dimension candidate", "dimension diagnostic"],
                generatedTopology: ["cap edge", "arc edge", "face-normal target", "opposing face pair"],
                tolerances: ["length tolerance", "angle tolerance", "source rewrite tolerance"],
                ownershipBoundaries: ["RupaCore resolves dimension targets", "SwiftCAD evaluates selection measurements", "UI and Agent consume non-mutating summaries"],
                supportedCases: [
                    caseItem("source-curve-dimension", "Source line, circle, and arc dimension summaries are editable.", .verified, .core),
                    caseItem("generated-face-pair-distance", "Supported generated face pairs resolve into object dimension edits.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("reference-pair-solver", "Arbitrary reference-pair dimensions require a general solver contract.", .planned, .core),
                ],
                degenerateCases: [
                    caseItem("fixed-conflict", "Fixed or overconstrained dimension edits reject before mutation.", .rejected, .core),
                ],
                rejectedCases: [
                    caseItem("drawing-annotation-as-model-driving", "Drawing annotation dimensions are not model-driving dimensions.", .rejected, .documentation),
                ],
                performanceCases: [
                    caseItem("bulk-dimension-summary", "Large selection dimension summaries need measured readback budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Dimension reference contract",
                    ui: "Dimension context panel and callout handles",
                    core: "Selection and object dimension commands",
                    automation: "Dimension automation commands",
                    agent: "Dimension summary and mutation commands",
                    cli: "Inspect and model dimension commands",
                    kernel: "SwiftCAD selection measurement",
                    evaluation: "Dimension evaluation context",
                    measurement: "Selection/object measurement summaries",
                    diagnostics: "Dimension unsupported diagnostics"
                ),
                invariants: [
                    invariant("dimension-summary-before-mutation", "Dimension candidates must be readable before mutation.", .core),
                    invariant("dimension-source-owned", "Dimension edits must rewrite source-owned geometry or reject.", .core),
                ],
                decisionConflictArea: "Dimension source ownership",
                decisionRationale: "Dimension editing remains Core-owned so UI and Agent perform the same target resolution before mutation."
            )
        case .sketchPrecision:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Sketch constraints, dimensions, numeric input, and precision construction",
                sourceEntities: ["sketch entity", "sketch constraint", "sketch dimension", "numeric input state"],
                targetEntities: ["solver-backed sketch edit", "profile region", "constraint diagnostic"],
                generatedTopology: ["source profile loop", "point handle", "spline control point", "constraint graph"],
                tolerances: ["constraint tolerance", "profile closure tolerance", "numeric input tolerance"],
                ownershipBoundaries: ["RupaCore owns sketch mutations", "SwiftCAD owns sketch validation", "UI and Agent share command contracts"],
                supportedCases: [
                    caseItem("source-entity-edit", "Line, circle, arc, spline, rectangle, polygon, and Slot source subsets are editable.", .supported, .core),
                    caseItem("constraint-add-remove", "Supported constraints add, solve, remove, undo, and redo through Core.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("general-solver", "General reference-pair solving and overconstraint diagnostics remain explicit D2 work.", .planned, .core),
                ],
                degenerateCases: [
                    caseItem("overdefined-sketch", "Overdefined or conflicting fixed anchors reject with diagnostics.", .rejected, .core),
                ],
                rejectedCases: [
                    caseItem("ui-only-constraint", "Viewport-only constraint glyphs cannot claim support without Core commands.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("large-sketch-solver", "Large sketch solver and summary paths require measured budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Sketch precision reference",
                    ui: "Sketch tool palette, numeric fields, and Inspector",
                    core: "Sketch entity and constraint commands",
                    automation: "Sketch automation commands",
                    agent: "Sketch summary and mutation commands",
                    cli: "Sketch inspect/model commands",
                    kernel: "SwiftCAD sketch validation",
                    evaluation: "Sketch profile evaluation",
                    measurement: "Sketch dimension and curve analysis summaries",
                    diagnostics: "Sketch constraint diagnostics"
                ),
                invariants: [
                    invariant("sketch-command-owned", "Sketch changes must pass through undoable Core commands.", .core),
                    invariant("profile-validity", "Profile closure and solver validity must be checked before feature use.", .evaluation),
                ],
                decisionConflictArea: "Sketch solver ownership",
                decisionRationale: "Sketch precision must centralize in Core so UI controls and Agent commands share solver diagnostics."
            )
        case .filletingAndBlending:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Exact filleting, chamfering, and shell-grade blending",
                sourceEntities: ["edge blend request", "profile corner source", "radius law", "continuity intent"],
                targetEntities: ["blend feature", "chamfer feature", "blend failure diagnostic"],
                generatedTopology: ["affected edge chain", "blend face", "trimmed adjacent face"],
                tolerances: ["blend radius tolerance", "self-intersection tolerance", "continuity tolerance"],
                ownershipBoundaries: ["SwiftCAD owns exact blend evaluation", "RupaCore owns target selection and command preflight"],
                supportedCases: [
                    caseItem("profile-edge-fillet", "Supported profile-owned edge fillet/chamfer subsets rewrite source profiles.", .supported, .core),
                    caseItem("generated-edge-selection", "Generated vertical edge subsets resolve back to editable profile sources.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("variable-radius-g2", "Variable-radius, conic, G2, and range-limited blends need a kernel feature contract.", .planned, .kernel),
                ],
                degenerateCases: [
                    caseItem("radius-overconstraint", "Radius overconstraint or blend self-intersection rejects before mutation.", .rejected, .kernel),
                ],
                rejectedCases: [
                    caseItem("mesh-only-blend", "Mesh-only smoothing cannot satisfy CAD blend support.", .rejected, .kernel),
                ],
                performanceCases: [
                    caseItem("ordered-blend-set", "Ordered multi-edge blend sets need measured evaluation budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Fillet and blend reference",
                    ui: "Selected-edge fillet/chamfer handles",
                    core: "Blend target command contract",
                    automation: "Blend automation commands",
                    agent: "Blend capability and mutation commands",
                    cli: "Blend model command",
                    kernel: "SwiftCAD blend evaluator",
                    evaluation: "Blend topology evaluation",
                    measurement: "Blend radius and continuity measurement",
                    diagnostics: "Blend failure diagnostics"
                ),
                invariants: [
                    invariant("blend-preflight", "Blend self-intersection and radius validity must be checked before mutation.", .kernel),
                    invariant("blend-topology-names", "Blend outputs must expose stable affected topology where supported.", .evaluation),
                ],
                decisionConflictArea: "Blend kernel boundary",
                decisionRationale: "Broad UI controls must wait for a kernel-backed blend feature contract rather than extending profile rewrites ad hoc."
            )
        case .booleanModeling:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Standalone and command-integrated boolean modeling",
                sourceEntities: ["target body reference", "tool body reference", "boolean operation", "keep-tool policy"],
                targetEntities: ["boolean feature", "result topology", "boolean diagnostic"],
                generatedTopology: ["result body", "kept tool", "split shell", "semantic boolean names"],
                tolerances: ["boolean intersection tolerance", "topology merge tolerance"],
                ownershipBoundaries: ["SwiftCAD owns exact boolean evaluation", "RupaCore owns target/tool command semantics"],
                supportedCases: [
                    caseItem("sweep-integrated-box-boolean", "Sweep-integrated axis-aligned box-prism boolean subsets evaluate exactly.", .supported, .kernel),
                    caseItem("standalone-target-tool-box-boolean", "Standalone target/tool body references evaluate exact axis-aligned box Boolean subsets through Core, Automation, and Agent.", .supported, .core),
                    caseItem("chained-orthogonal-cell-union-boolean", "Previous orthogonal cell-union Boolean results can become target operands for follow-on Boolean operations.", .supported, .kernel),
                    caseItem("keep-tools-generated-name-policy", "Standalone Boolean removes superseded target/tool generated names or remaps kept tool names according to keep-tools policy.", .supported, .evaluation),
                    caseItem("targetless-rejection", "Invalid targetless/new-body boolean option combinations reject before mutation.", .verified, .core),
                ],
                boundaryCases: [
                    caseItem("general-solid-sheet-target-tool", "General non-orthogonal Solid and Sheet target/tool operands must preserve exact topology and diagnostics beyond the current orthogonal subset.", .planned, .kernel),
                ],
                degenerateCases: [
                    caseItem("empty-result", "Empty or separated-fragment results require typed result diagnostics.", .planned, .evaluation),
                ],
                rejectedCases: [
                    caseItem("mesh-boolean-only", "Mesh-only booleans do not satisfy exact CAD boolean support.", .rejected, .kernel),
                ],
                performanceCases: [
                    caseItem("dense-boolean-operands", "Dense and non-box operands need measured intersection budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Boolean reference contract",
                    ui: "Boolean target/tool selection workflow",
                    core: "Boolean source feature contract",
                    automation: "Boolean automation command",
                    agent: "Boolean Agent capability",
                    cli: "Boolean model command",
                    kernel: "SwiftCAD boolean evaluator",
                    evaluation: "Boolean topology evaluation",
                    measurement: "Boolean mass-property readback",
                    diagnostics: "Boolean failure diagnostics"
                ),
                invariants: [
                    invariant("boolean-target-tool", "Boolean operations must carry typed target/tool ownership.", .core),
                    invariant("boolean-topology", "Boolean output topology names must be stable for supported subsets.", .evaluation),
                ],
                decisionConflictArea: "Standalone boolean contract",
                decisionRationale: "Standalone booleans must reuse exact source contracts and diagnostics rather than hiding inside individual feature commands."
            )
        case .directModeling:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Direct face, edge, vertex, and surface-CV modeling",
                sourceEntities: ["generated face target", "generated edge target", "generated vertex target", "surface control point"],
                targetEntities: ["source-owned direct edit", "unsupported direct-edit diagnostic"],
                generatedTopology: ["persistent generated face", "persistent generated edge", "persistent generated vertex", "surface CV reference"],
                tolerances: ["selection tolerance", "rewrite validity tolerance", "surface frame tolerance"],
                ownershipBoundaries: ["RupaCore maps generated targets to source-owned edits", "SwiftCAD validates rewritten CAD source"],
                supportedCases: [
                    caseItem("rectangle-face-offset", "Supported rectangle and cylinder face offsets rewrite source-owned bodies.", .supported, .core),
                    caseItem("generated-profile-edge-move", "Generated line and circle profile edges rewrite their source sketch line or circle while preserving analytic identity.", .supported, .core),
                    caseItem("surface-cv-edit", "Supported PolySpline boundary/interior CV edits stay source-owned.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("arbitrary-topology-edit", "Arbitrary face/edge/vertex edits need stable rewrite policies.", .planned, .core),
                ],
                degenerateCases: [
                    caseItem("unresolved-generated-target", "Generated targets that cannot resolve to source must reject before mutation.", .rejected, .core),
                ],
                rejectedCases: [
                    caseItem("transient-topology-edit", "Transient mesh IDs cannot be accepted as direct-edit sources.", .rejected, .evaluation),
                    caseItem("generated-arc-edge-move", "Generated arc profile edge movement rejects until connected trim healing can preserve adjacent source curves.", .rejected, .core),
                ],
                performanceCases: [
                    caseItem("identity-picking-budget", "Identity picking and direct-edit previews need production-scene budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Direct modeling reference",
                    ui: "Subobject edit handles",
                    core: "Direct edit source-rewrite commands",
                    automation: "Direct edit automation commands",
                    agent: "Direct edit Agent commands",
                    cli: "Direct edit CLI commands",
                    kernel: "SwiftCAD source rewrite validation",
                    evaluation: "Generated topology resolution",
                    measurement: "Subobject measurement summaries",
                    diagnostics: "Direct edit rejection diagnostics"
                ),
                invariants: [
                    invariant("direct-edit-source-owned", "Direct edits must rewrite source-owned state or reject.", .core),
                    invariant("stable-target-resolution", "Generated topology targets must resolve through persistent references.", .evaluation),
                ],
                decisionConflictArea: "Generated topology rewrite safety",
                decisionRationale: "Direct modeling must not mutate display geometry; every shipped edit must resolve to source-owned CAD state."
            )
        case .exchangeAndDrawings:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "CAD exchange, technical drawing, and hidden-line export",
                sourceEntities: ["evaluated document", "export preset", "drawing view", "section plane"],
                targetEntities: ["exchange artifact", "hidden-line drawing result", "export diagnostic"],
                generatedTopology: ["visible edge", "hidden edge", "section hatch", "annotation reference"],
                tolerances: ["tessellation tolerance", "hidden-line classification tolerance", "export unit tolerance"],
                ownershipBoundaries: ["Rupa export owns product metadata", "SwiftCAD exchange owns CAD artifact generation"],
                supportedCases: [
                    caseItem("exchange-export-preset", "Exchange export uses presets, output units, dry-run, and diagnostics.", .supported, .core),
                    caseItem("mesh-drawing-separation", "Drawing output remains separate from viewport screenshots.", .supported, .evaluation),
                ],
                boundaryCases: [
                    caseItem("hidden-line-result", "Hidden-line output needs structured view, hatch, and stroke metadata.", .planned, .evaluation),
                ],
                degenerateCases: [
                    caseItem("unsafe-export", "Unsafe or unsupported exports must refuse unless explicitly overridden.", .rejected, .diagnostics),
                ],
                rejectedCases: [
                    caseItem("screenshot-drawing", "Viewport screenshots cannot satisfy technical drawing output.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("large-export-budget", "Large exchange and hidden-line outputs need deterministic performance fixtures.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Exchange and drawing reference",
                    ui: "Export and drawing inspector workflow",
                    core: "Document export service",
                    automation: "Export automation command",
                    agent: "Export and drawing Agent commands",
                    cli: "rupa export and inspect commands",
                    kernel: "SwiftCAD exchange writer",
                    evaluation: "Drawing/hidden-line evaluation",
                    measurement: "Export validation summaries",
                    diagnostics: "Export diagnostics"
                ),
                invariants: [
                    invariant("export-dry-run", "Export workflows must support diagnostics before writing output.", .core),
                    invariant("drawing-not-screenshot", "Drawing output must be structured analysis output.", .evaluation),
                ],
                decisionConflictArea: "Drawing versus exchange boundary",
                decisionRationale: "Exchange and drawings share evaluated geometry but require distinct structured result contracts."
            )
        case .patternsAndArrays:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Rectangular, radial, curve, and instance-based arrays",
                sourceEntities: ["pattern array source", "component definition", "curve path", "parameter expression"],
                targetEntities: ["array output instances", "independent copy", "array diagnostic"],
                generatedTopology: ["output scene root", "copy marker", "curve path sample", "cloned feature reference"],
                tolerances: ["transform tolerance", "path sampling tolerance", "expression resolution tolerance"],
                ownershipBoundaries: ["RupaCore owns array source and regeneration", "UI and Agent mutate the same source contract"],
                supportedCases: [
                    caseItem("rectangular-radial-curve-array", "Rectangular, radial, and curve array source contracts are represented.", .supported, .core),
                    caseItem("independent-copy-edit", "Independent-copy cloned feature edits preserve source divergence diagnostics.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("broader-cloned-feature-edits", "Additional cloned-feature edits need route and preview coverage.", .planned, .core),
                ],
                degenerateCases: [
                    caseItem("invalid-path-density", "Invalid path extent or density clamps/rejects through Core policy.", .rejected, .core),
                ],
                rejectedCases: [
                    caseItem("output-only-array-edit", "Generated outputs cannot be edited as source array definitions.", .rejected, .core),
                ],
                performanceCases: [
                    caseItem("large-array-preview", "Large array previews need generation-keyed and viewport budget fixtures.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Pattern and array reference",
                    ui: "Pattern Array Inspector and viewport handles",
                    core: "PatternArraySource command contract",
                    automation: "Pattern array automation commands",
                    agent: "Pattern array summary and mutation commands",
                    cli: "Pattern array inspection commands",
                    kernel: "SwiftCAD transform/evaluation support",
                    evaluation: "Pattern output regeneration",
                    measurement: "Pattern summary and bounds readback",
                    diagnostics: "Pattern source ownership diagnostics"
                ),
                invariants: [
                    invariant("array-source-owned", "Array edits must mutate PatternArraySource, not generated outputs.", .core),
                    invariant("array-identity", "Independent-copy identity must remain deterministic across regeneration.", .evaluation),
                ],
                decisionConflictArea: "Array source versus generated output",
                decisionRationale: "Pattern Array workflows remain source-owned so UI and Agent can safely regenerate and inspect outputs."
            )
        case .sectionAnalysis:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Section analysis, measurement, and inspection overlays",
                sourceEntities: ["section plane", "saved view", "evaluated body", "measurement query"],
                targetEntities: ["section analysis result", "hatch result", "interference diagnostic"],
                generatedTopology: ["section curve", "cut face", "visible/hidden classification"],
                tolerances: ["section intersection tolerance", "hatch tolerance", "measurement tolerance"],
                ownershipBoundaries: ["Section analysis is non-mutating", "RupaCore owns saved section-plane metadata"],
                supportedCases: [
                    caseItem("saved-section-plane", "Saved section planes exist as source metadata.", .supported, .core),
                    caseItem("inspection-readback", "Inspection summaries can read evaluated state without mutation.", .supported, .evaluation),
                ],
                boundaryCases: [
                    caseItem("virtual-clipping", "Virtual section clipping and hatching require structured analysis output.", .planned, .evaluation),
                ],
                degenerateCases: [
                    caseItem("nonintersecting-section", "Nonintersecting section planes must return empty structured results.", .planned, .evaluation),
                ],
                rejectedCases: [
                    caseItem("mutating-section-analysis", "Section analysis cannot mutate source geometry.", .rejected, .core),
                ],
                performanceCases: [
                    caseItem("dense-section-budget", "Dense section and interference analysis need measured budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Section analysis reference",
                    ui: "Section analysis overlay controls",
                    core: "Section plane source metadata",
                    automation: "Section analysis automation readback",
                    agent: "Section analysis Agent readback",
                    cli: "inspect section commands",
                    kernel: "SwiftCAD section evaluator",
                    evaluation: "Section analysis result",
                    measurement: "Section measurement summaries",
                    diagnostics: "Section analysis diagnostics"
                ),
                invariants: [
                    invariant("section-non-mutating", "Section analysis must not mutate CAD source.", .evaluation),
                    invariant("section-plane-source", "Saved section planes must remain source metadata.", .core),
                ],
                decisionConflictArea: "Analysis versus modeling command",
                decisionRationale: "Section analysis should be a non-mutating readback pipeline that can later feed drawing output."
            )
        case .snapping:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Snapping intelligence and temporary overrides",
                sourceEntities: ["snap candidate source", "construction plane", "reference line", "measurement anchor"],
                targetEntities: ["resolved snap point", "snap reference", "snap diagnostic"],
                generatedTopology: ["topology snap candidate", "surface CV candidate", "measurement snap anchor"],
                tolerances: ["screen snap tolerance", "model snap tolerance", "construction-plane projection tolerance"],
                ownershipBoundaries: ["SnapResolver is non-mutating", "UI and Agent consume the same candidate contract"],
                supportedCases: [
                    caseItem("shared-snap-resolver", "Grid, source, topology, measurement, and relation candidates share SnapResolver.", .supported, .core),
                    caseItem("temporary-overrides", "Ctrl force-enable and Shift+X suppression are represented in options.", .supported, .ui),
                ],
                boundaryCases: [
                    caseItem("broader-cplane-workflow", "Broader construction-plane workflows must feed the same snap contract.", .planned, .core),
                ],
                degenerateCases: [
                    caseItem("suppressed-candidate-kind", "Suppressed candidate kinds must not leak back into resolution.", .verified, .core),
                ],
                rejectedCases: [
                    caseItem("viewport-only-snap", "Viewport-only snap behavior cannot bypass SnapResolver.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("dense-snap-candidates", "Dense candidate sets need ranked-resolution budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Snap reference",
                    ui: "Viewport snap tips and overrides",
                    core: "SnapResolver",
                    automation: "Snap automation readback",
                    agent: "resolveSnap Agent command",
                    cli: "inspect snap command",
                    kernel: "SwiftCAD geometry query support",
                    evaluation: "Candidate evaluation",
                    measurement: "Snap distance ranking",
                    diagnostics: "Snap rejection diagnostics"
                ),
                invariants: [
                    invariant("snap-non-mutating", "Snap resolution must not mutate generation.", .core),
                    invariant("snap-shared-contract", "UI and Agent must use the same resolver options.", .agent),
                ],
                decisionConflictArea: "Snap resolver ownership",
                decisionRationale: "Snapping must stay centralized in Core so UI and Agent observe identical candidate ordering and diagnostics."
            )
        case .constructionGeometry:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Construction planes as modeling inputs",
                sourceEntities: ["saved construction plane", "face target", "region target", "edge target", "point target"],
                targetEntities: ["active construction plane", "sketch plane", "plane diagnostic"],
                generatedTopology: ["plane scene node", "generated face plane", "midplane target"],
                tolerances: ["plane normal tolerance", "coplanarity tolerance", "point-plane tolerance"],
                ownershipBoundaries: ["RupaCore owns plane source metadata", "Viewport alignment consumes Core plane state"],
                supportedCases: [
                    caseItem("saved-plane-source", "Saved construction planes can be created, activated, and renamed.", .supported, .core),
                    caseItem("target-derived-plane", "Face/region/edge/point target sets can create construction planes.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("editable-plane-handles", "Selectable/editable plane handles remain open work.", .planned, .ui),
                ],
                degenerateCases: [
                    caseItem("coplanar-midplane", "Coplanar midplane requests reject before mutation.", .verified, .core),
                ],
                rejectedCases: [
                    caseItem("implicit-sketch-plane", "Implicit viewport plane state cannot replace saved construction-plane source.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("plane-snap-projection", "Large documents need measured plane-projected snap budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Construction plane reference",
                    ui: "Plane rail and viewport alignment controls",
                    core: "ConstructionPlaneSource commands",
                    automation: "Construction plane automation commands",
                    agent: "Construction plane Agent commands",
                    cli: "inspect construction-planes",
                    kernel: "SwiftCAD plane geometry validation",
                    evaluation: "Plane scene evaluation",
                    measurement: "Plane target measurement",
                    diagnostics: "Construction plane diagnostics"
                ),
                invariants: [
                    invariant("plane-source-owned", "Construction planes must be source metadata, not viewport-only state.", .core),
                    invariant("sketch-plane-consumption", "Sketch creation must consume the selected construction plane end to end.", .ui),
                ],
                decisionConflictArea: "Construction plane source ownership",
                decisionRationale: "Planes become first-class modeling inputs only when Core owns source state and UI consumes that state."
            )
        case .selection:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Object, face, edge, vertex, region, and sketch selection",
                sourceEntities: ["selection target", "selection component", "identity-buffer ID", "persistent topology name"],
                targetEntities: ["selection state", "hover state", "selection diagnostic"],
                generatedTopology: ["generated face", "generated edge", "generated vertex", "sketch region"],
                tolerances: ["hit-test screen tolerance", "depth tie-break tolerance", "identity render budget"],
                ownershipBoundaries: ["RupaRendering resolves hits", "RupaCore owns SelectionTarget semantics", "Agent consumes selection readback"],
                supportedCases: [
                    caseItem("identity-picking", "Identity-buffer and CPU fallback selection routes report backend and hit targets.", .supported, .ui),
                    caseItem("subobject-selection", "Object, face, edge, vertex, region, and sketch entity scopes share SelectionTarget conversion.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("remaining-edit-handles", "Remaining scope-specific edit-handle affordances need route coverage.", .planned, .ui),
                ],
                degenerateCases: [
                    caseItem("overlapping-depth", "Overlapping generated candidates use view-depth tie-breaks.", .supported, .ui),
                ],
                rejectedCases: [
                    caseItem("zero-identity-id", "Zero identity-buffer IDs cannot represent selectable topology.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("identity-buffer-production-budget", "Identity-buffer budgets must be calibrated against production scenes.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Selection architecture",
                    ui: "Viewport hit and rectangle selection",
                    core: "SelectionTarget model",
                    automation: "Selection automation commands",
                    agent: "selectTargets and selection readback",
                    cli: "selection inspect commands",
                    kernel: "Generated topology references",
                    evaluation: "Topology summary evaluation",
                    measurement: "Selection measurement readback",
                    diagnostics: "Picking readiness diagnostics"
                ),
                invariants: [
                    invariant("selection-stable-id", "Selection must use stable target references where possible.", .core),
                    invariant("picking-budget-visible", "Identity render budget fallback must be visible before relying on exact picking.", .diagnostics),
                ],
                decisionConflictArea: "Picking backend and selection semantics",
                decisionRationale: "Viewport hit resolution can vary by backend, but the resulting SelectionTarget contract must remain stable."
            )
        case .sweep:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Sweep profile, path, guide, and boolean workflow",
                sourceEntities: ["profile reference", "path reference", "guide reference", "boolean target reference"],
                targetEntities: ["sweep feature", "swept solid", "swept sheet", "sweep diagnostic"],
                generatedTopology: ["sweep ring vertex", "rail edge", "side face", "boolean result topology"],
                tolerances: ["path-frame tolerance", "guide contact tolerance", "swept topology tolerance"],
                ownershipBoundaries: ["RupaCore owns command/preflight", "SwiftCAD owns sweep evaluation and topology generation"],
                supportedCases: [
                    caseItem("guided-sweep-preflight", "Guide overconstraint and degenerate swept topology reject before mutation.", .verified, .core),
                    caseItem("straight-exact-and-polygonal-sweep", "Supported straight exact and curved polygonal sweep outputs evaluate with topology names.", .supported, .kernel),
                ],
                boundaryCases: [
                    caseItem("non-box-boolean-operands", "Non-box boolean operands and broader exact surfaces remain explicit work.", .planned, .kernel),
                ],
                degenerateCases: [
                    caseItem("collapsed-guide-section", "Collapsed, flipped, or self-intersecting guided sections reject.", .verified, .kernel),
                ],
                rejectedCases: [
                    caseItem("sheet-boolean", "Boolean target operations with sheet output reject before mutation.", .rejected, .core),
                ],
                performanceCases: [
                    caseItem("dense-sweep-sections", "Dense sweep sections and rail deformation need measured evaluation budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Sweep reference",
                    ui: "Sweep profile/path/guide picker",
                    core: "SweepFeature command contract",
                    automation: "Sweep automation command",
                    agent: "Sweep capability and evaluation plan",
                    cli: "Sweep model command",
                    kernel: "SwiftCAD sweep evaluator",
                    evaluation: "Sweep topology evaluation plan",
                    measurement: "Sweep mass-property readback",
                    diagnostics: "Sweep preflight diagnostics"
                ),
                invariants: [
                    invariant("sweep-preflight-before-mutation", "Sweep guide and boolean constraints must preflight before mutation.", .core),
                    invariant("sweep-topology-semantic", "Supported sweep outputs must expose semantic topology names.", .evaluation),
                ],
                decisionConflictArea: "Sweep guide and boolean preflight",
                decisionRationale: "Sweep expansion must keep guide compatibility and topology diagnostics explicit before broadening exact geometry."
            )
        case .surfaceModeling:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Direct B-spline and PolySpline surface modeling foundation",
                sourceEntities: ["mesh patch graph", "B-spline surface source", "surface CV", "trim boundary"],
                targetEntities: ["surface body", "surface frame", "surface continuity diagnostic"],
                generatedTopology: ["B-spline face", "trim edge", "control point", "UVN frame"],
                tolerances: ["surface continuity tolerance", "UV parameter tolerance", "trim boundary tolerance"],
                ownershipBoundaries: ["SwiftCAD owns surface representation and UV trim-loop p-curves", "RupaCore owns source-owned CV, knot, span, trim-domain, trim-loop, trim p-curve control-point position and weight, trim-continuity edits, and summaries"],
                supportedCases: [
                    caseItem("polyspline-patch", "Supported single-quad and planar unmerged PolySpline patches become B-spline sheet B-reps.", .supported, .kernel),
                    caseItem("surface-cv-frame", "Surface source summaries expose CV references and UVN frame readback.", .supported, .core),
                    caseItem("direct-bspline-source", "Direct B-spline surface sources expose stable CV, weight, knot, span, face, rectangular trim references, source-owned rectangular outer trim domains, authored UV p-curve trim loops, Agent-readable authored p-curve control-point summary indices and weights, shared adaptive UV trim-loop validation, rational 2D B-spline p-curve trim preservation, authored trim endpoint and strict interior p-curve control-point handles, and p-curve-first mesh tessellation for current direct surface trims.", .supported, .core),
                    caseItem("direct-bspline-parameter-edits", "Direct B-spline surface sources support CV moves/slides, CV weights, knot value edits, shape-preserving knot insertion, fraction-based span split, knot multiplicity edits, rectangular trim-domain edits, authored trim-loop edits, source-owned authored trim endpoint moves, source-owned strict interior polyline and 2D B-spline trim p-curve control-point moves, source-owned 2D B-spline trim p-curve control-point weight edits, and compatible G0/G1/G2 boundary matching for full-domain rectangular surfaces.", .supported, .core),
                ],
                boundaryCases: [
                    caseItem("arbitrary-nurbs-trim-foundation", "Arbitrary NURBS sources, exact arbitrary NURBS trim-edge reconstruction, watertight polysurfaces, remaining span policies, continuity solving on authored interior trims, and arbitrary adjacency solving remain next foundation work.", .planned, .kernel),
                ],
                degenerateCases: [
                    caseItem("nonplanar-g2-network", "Unsupported non-planar G2 patch networks report unresolved continuity constraints.", .rejected, .kernel),
                ],
                rejectedCases: [
                    caseItem("trimless-general-surface-claim", "Surface support cannot claim general trims without trim-source ownership.", .rejected, .kernel),
                ],
                performanceCases: [
                    caseItem("surface-analysis-density", "Surface analysis density and CV overlays need measured budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "NURBS, UVN, continuity, and PolySpline references",
                    ui: "Surface Inspector and CV handles",
                    core: "Surface source summary and CV edit commands",
                    automation: "Surface automation commands",
                    agent: "Surface analysis/frame/continuity commands",
                    cli: "inspect surfaces commands",
                    kernel: "SwiftCAD B-spline surface evaluator",
                    evaluation: "Surface analysis and continuity evaluation",
                    measurement: "Surface curvature and trim summaries",
                    diagnostics: "Surface reconstruction diagnostics"
                ),
                invariants: [
                    invariant("surface-source-owned", "Surface CV, knot, span, trim-domain, trim-loop, and trim-continuity edits must be source-owned and frame-addressable.", .core),
                    invariant("surface-continuity-diagnostic", "Continuity gaps must remain typed diagnostics before patch broadening.", .evaluation),
                ],
                decisionConflictArea: "Surface foundation before tool breadth",
                decisionRationale: "General surface tools must build on the current direct B-spline source identity, frame, knot/span, rectangular trim-domain, authored UV trim-loop, trim p-curve control-point position and weight, and continuity contracts before broadening into exact arbitrary trim reconstruction, arbitrary adjacency, and full NURBS polysurfaces."
            )
        case .curveContinuity:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Bridge curves, curvature combs, and continuity feedback",
                sourceEntities: ["source curve", "bridge endpoint", "continuity constraint", "curvature display"],
                targetEntities: ["bridge curve source", "curve analysis result", "continuity diagnostic"],
                generatedTopology: ["spline control point", "curve sample", "curvature comb", "endpoint tangent"],
                tolerances: ["G0 distance tolerance", "G1 tangent angle tolerance", "G2 curvature tolerance"],
                ownershipBoundaries: ["RupaCore owns bridge and curve source commands", "SwiftCAD owns curve evaluation"],
                supportedCases: [
                    caseItem("bridge-curve-source", "Bridge Curve stores endpoint targets, values, sense, trim, tension, and continuity intent.", .supported, .core),
                    caseItem("curvature-comb-analysis", "Curve and surface analysis expose curvature comb and continuity readback.", .supported, .evaluation),
                ],
                boundaryCases: [
                    caseItem("dedicated-bridge-handles", "Dedicated viewport bridge handles and endpoint-target parity remain open.", .planned, .ui),
                ],
                degenerateCases: [
                    caseItem("unsupported-continuity-combo", "Unsupported G2/G3 or constrained trim migrations reject before mutation.", .rejected, .core),
                ],
                rejectedCases: [
                    caseItem("visual-only-comb", "Visual combs cannot claim continuity support without analysis readback.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("dense-comb-sampling", "Dense curve/surface comb sampling needs measured display budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Continuity and bridge curve reference",
                    ui: "Bridge and curvature controls",
                    core: "BridgeCurveSource and curve commands",
                    automation: "Curve continuity automation commands",
                    agent: "curveAnalysis and bridge commands",
                    cli: "inspect curves command",
                    kernel: "SwiftCAD curve evaluator",
                    evaluation: "Curve continuity analysis",
                    measurement: "Curvature and continuity summaries",
                    diagnostics: "Continuity diagnostics"
                ),
                invariants: [
                    invariant("continuity-analysis-readback", "Continuity claims must be backed by analysis readback.", .evaluation),
                    invariant("bridge-source-stable", "Bridge endpoints and trim state must remain source-owned.", .core),
                ],
                decisionConflictArea: "Bridge source and continuity readback",
                decisionRationale: "Bridge and continuity tools need shared source and analysis contracts before UI-only handle expansion."
            )
        case .agentOperability:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "AI Agent parity for UI-visible CAD workflows",
                sourceEntities: ["capability descriptor", "Automation command", "Agent request", "selection reference"],
                targetEntities: ["Agent response", "structured diagnostic", "design process packet"],
                generatedTopology: ["Agent-readable topology summary", "surface reference", "snap reference"],
                tolerances: ["codec stability tolerance", "generation staleness policy", "selection identity policy"],
                ownershipBoundaries: ["RupaAgentProtocol owns transport schema", "RupaCore owns command semantics", "AgentRuntime bridges live sessions"],
                supportedCases: [
                    caseItem("assessment-design-packet", "CAD quality assessment is Agent-readable with design process packets.", .verified, .agent),
                    caseItem("command-summary-parity", "Implemented workflows expose structured summary and mutation commands.", .supported, .agent),
                ],
                boundaryCases: [
                    caseItem("preflight-before-ui-exposure", "New workspace controls must expose Agent descriptors before broad UI claims.", .planned, .agent),
                ],
                degenerateCases: [
                    caseItem("stale-generation", "Stale live-generation mutations reject or require refresh.", .verified, .core),
                ],
                rejectedCases: [
                    caseItem("private-ui-state-command", "Agent commands cannot depend on private UI-only state.", .rejected, .ui),
                ],
                performanceCases: [
                    caseItem("large-json-readback", "Large summaries and design packets need payload-size and latency budgets.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Automation protocol",
                    ui: "Workspace Agent host",
                    core: "Core command and readback contracts",
                    automation: "AutomationRunner",
                    agent: "AgentCommandController",
                    cli: "rupa live/file/auto modes",
                    kernel: "SwiftCAD command/evaluation bridge",
                    evaluation: "Agent-readable evaluation summaries",
                    measurement: "Agent measurement readback",
                    diagnostics: "Agent error envelopes"
                ),
                invariants: [
                    invariant("agent-codec-roundtrip", "Agent-visible assessment and commands must survive Codable round trip.", .agent),
                    invariant("agent-no-private-ui-state", "Agent operations must not require private UI-only state.", .agent),
                ],
                decisionConflictArea: "Agent parity as product requirement",
                decisionRationale: "Agent operability is part of product completeness, so every new workflow needs discoverable readback and mutation contracts."
            )
        case .performance:
            CADInteractionDesignProcessSpec(
                capabilityTitle: "Evaluation reuse, identity picking budgets, and zero-copy-oriented display paths",
                sourceEntities: ["evaluated document cache", "identity pick render plan", "mesh summary", "analysis result"],
                targetEntities: ["reuse context", "performance diagnostic", "budget rejection"],
                generatedTopology: ["cached evaluated body", "identity buffer", "render metrics", "analysis samples"],
                tolerances: ["cache fingerprint tolerance", "identity buffer budget", "analysis density budget"],
                ownershipBoundaries: ["RupaCore owns evaluation cache validity", "RupaRendering owns identity-buffer metrics", "Agent reads diagnostics"],
                supportedCases: [
                    caseItem("evaluation-context-reuse", "Evaluation context reuse checks generation and CAD source fingerprint.", .supported, .core),
                    caseItem("identity-picking-budget-report", "Identity picking reports render cost and budget fallback diagnostics.", .supported, .ui),
                ],
                boundaryCases: [
                    caseItem("enforced-dense-budget", "Dense-model budgets are not yet enforced by regression fixtures.", .planned, .measurement),
                ],
                degenerateCases: [
                    caseItem("stale-cache", "Stale evaluation cache entries must not be reused.", .verified, .core),
                ],
                rejectedCases: [
                    caseItem("silent-budget-fallback", "Silent render-budget fallback is not acceptable for CAD selection.", .rejected, .diagnostics),
                ],
                performanceCases: [
                    caseItem("zero-copy-buffer-ownership", "Borrowed or copy-on-write buffers require ownership-specific benchmarks.", .planned, .measurement),
                ],
                surfaces: RouteSurface(
                    documentation: "Performance and exchange roadmap",
                    ui: "Picking readiness and Inspector diagnostics",
                    core: "Evaluation context cache",
                    automation: "Performance-aware readback commands",
                    agent: "Performance diagnostics readback",
                    cli: "inspect/eval/mesh commands",
                    kernel: "SwiftCAD evaluated document reuse",
                    evaluation: "Evaluation scheduler",
                    measurement: "Render/readback timing metrics",
                    diagnostics: "Performance budget diagnostics"
                ),
                invariants: [
                    invariant("cache-generation-fingerprint", "Evaluation cache reuse must match generation and CAD source fingerprint.", .core),
                    invariant("budget-visible", "Budget fallback must be visible to UI and Agent diagnostics.", .diagnostics),
                ],
                decisionConflictArea: "Performance as a first-class CAD gate",
                decisionRationale: "Dense CAD workflows cannot broaden safely until cache reuse, identity picking, and zero-copy paths have measurable budgets."
            )
        }
    }

    private static func caseItem(
        _ suffix: String,
        _ title: String,
        _ status: DesignProcessCaseStatus,
        _ layer: DesignProcessLayer
    ) -> DesignProcessCase {
        DesignProcessCase(
            id: suffix,
            title: title,
            status: status,
            diagnostic: status == .rejected || status == .missing || status == .blocked
                ? DesignProcessDiagnostic(
                    id: "\(suffix)-diagnostic",
                    severity: status == .rejected ? .error : .warning,
                    message: title,
                    affectedLayer: layer
                )
                : nil
        )
    }

    private static func invariant(
        _ id: String,
        _ title: String,
        _ layer: DesignProcessLayer
    ) -> DesignProcessInvariant {
        DesignProcessInvariant(
            id: id,
            title: title,
            requiredLayer: layer,
            verification: "Design process packet, route matrix, and focused regression tests"
        )
    }
}
