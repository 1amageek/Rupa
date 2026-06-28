import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore

public final class AgentCommandController: AgentClientProtocol {
    public var name: String
    public var socketPath: String?
    private let registry: WorkspaceRegistry
    private let runner: AutomationRunner
    private let exportService: DocumentExportService
    private let fileService: DocumentFileService

    public init(
        name: String = "Rupa Agent",
        socketPath: String? = nil,
        registry: WorkspaceRegistry = WorkspaceRegistry(),
        runner: AutomationRunner = AutomationRunner(),
        exportService: DocumentExportService = DocumentExportService(),
        fileService: DocumentFileService = DocumentFileService()
    ) {
        self.name = name
        self.socketPath = socketPath
        self.registry = registry
        self.runner = runner
        self.exportService = exportService
        self.fileService = fileService
    }

    public func capabilities() -> [String] {
        capabilityDescriptors().map(\.name)
    }

    public func capabilityDescriptors() -> [AgentCapabilityDescriptor] {
        Self.capabilityCatalog
    }

    private static let capabilityCatalog: [AgentCapabilityDescriptor] = [
        capability(
            "describeDocument",
            category: .document,
            summary: "Read the current document identity, generation, dirty state, and diagnostics.",
            access: .automationCommand,
            mutatesDocument: false,
            targets: [.document],
            failureMode: "Fails only when the active session cannot be resolved."
        ),
        capability(
            "setDisplayUnit",
            category: .document,
            summary: "Change the display unit used by UI, summaries, measurements, and command feedback.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects stale generations before mutation."
        ),
        capability(
            "renameDocument",
            category: .document,
            summary: "Rename the document through the undoable command pipeline.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects stale generations before mutation."
        ),
        capability(
            "upsertParameter",
            category: .parameter,
            summary: "Create or update a typed document parameter from a structured expression.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.parameters],
            targets: [.document],
            failureMode: "Rejects invalid expressions, kind mismatches, and stale generations before mutation."
        ),
        capability(
            "deleteParameter",
            category: .parameter,
            summary: "Delete a parameter that is not referenced by current source expressions.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.parameters],
            targets: [.document],
            failureMode: "Rejects referenced, missing, or stale parameters before mutation."
        ),
        capability(
            "setParameterExpression",
            category: .parameter,
            summary: "Parse a user-facing expression string and upsert the resulting typed parameter.",
            access: .agentRequest,
            mutatesDocument: true,
            discovery: [.parameters],
            targets: [.document],
            failureMode: "Rejects parse errors, dependency errors, kind mismatches, and stale generations before mutation."
        ),
        capability(
            "listParameters",
            category: .read,
            summary: "Read all document parameters without mutating source or undo history.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.parameters],
            targets: [.document],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "cadInteractionQualityAssessment",
            category: .read,
            summary: "Read the objective CAD interaction quality assessment across reference contract, source ownership, command contract, selection topology, viewport affordance, Inspector affordance, Agent parity, diagnostics, verification, and performance gates.",
            access: .agentRequest,
            mutatesDocument: false,
            requiresSession: false,
            requiresExpectedGeneration: false,
            discovery: [.cadInteractionQualityAssessment],
            targets: [.document],
            failureMode: "Does not inspect or mutate a session; reports the current static product-quality assessment model."
        ),
        capability(
            "createComponentDefinition",
            category: .component,
            summary: "Create a reusable component definition from existing root scene nodes.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.sceneNode],
            failureMode: "Rejects missing roots, invalid hierarchy references, and stale generations before mutation."
        ),
        capability(
            "createComponentInstance",
            category: .component,
            summary: "Place a component definition instance with a local transform.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.sceneNode],
            failureMode: "Rejects missing definitions, invalid transforms, duplicate names, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "definitionID",
                    supportedValues: ["designDisplaySnapshot.componentDefinitions"],
                    notes: [
                        "Use renderable component definitions from the display snapshot when placing reusable instances.",
                        "Use designDisplaySnapshot.componentInstances ownership.kind to distinguish directly editable placed instances from pattern-owned outputs before creating duplicates."
                    ]
                )
            ]
        ),
        capability(
            "createPatternArray",
            category: .pattern,
            summary: "Create a source-owned pattern array from a component definition with rectangular, radial, or curve distribution, emitting lightweight component instances or cloned independent CAD feature copies.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.sceneNode],
            failureMode: "Rejects missing component definitions, invalid linear or angular axis directions, invalid curve paths, non-positive copy counts, non-length distances, non-angle rotations, non-scalar ratio or scale values, zero spacing, zero angles, duplicate array names, stale output transforms, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "distribution",
                    supportedValues: ["rectangular", "radial", "curve"],
                    notes: [
                        "Rectangular distributions support one- or two-axis linear spacing or extent.",
                        "Radial distributions support center, rotation axis, angle spacing or extent, copy count, and optional radial repetition.",
                        "Curve distributions support explicit polyline paths or source sketch-entity paths with twist, scale, alignment, and extent controls.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "spacingMode",
                    supportedValues: ["spacing", "extent"],
                    notes: [
                        "Linear spacing uses the resolved distance as each copy step.",
                        "Linear extent distributes generated copies evenly across the resolved distance.",
                        "Angular spacing uses the resolved angle as each copy step.",
                        "Angular extent distributes generated copies evenly across the resolved angle.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "axisCount",
                    supportedValues: ["one", "two", "angular", "angularWithRadialRepetition", "curvePath"],
                    notes: [
                        "Two-axis arrays generate the rectangular lattice excluding the original source position.",
                        "Radial repetition generates additional rings while excluding the original source position.",
                        "Curve path arrays place generated copies along the resolved path excluding the original source position.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "curveAlignment",
                    supportedValues: ["normal", "parallel", "transport"],
                    notes: [
                        "Normal aligns generated copies to the path tangent and local normal frame.",
                        "Parallel preserves the original orientation while following path positions.",
                        "Transport follows the path while minimizing frame flips along complex paths.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "outputMode",
                    supportedValues: ["componentInstance", "independentCopy"],
                    notes: [
                        "Use designDisplaySnapshot.componentDefinitions to choose a renderable ComponentDefinitionID.",
                        "componentInstance preserves source ownership with lightweight shared component definition instances.",
                        "independentCopy clones the source CAD feature dependency graph into direct scene outputs owned by the pattern source.",
                    ]
                ),
            ]
        ),
        capability(
            "updatePatternArray",
            category: .pattern,
            summary: "Edit an existing source-owned pattern array by replacing its name, component definition, distribution, or output mode, then regenerate owned outputs.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.sceneNode],
            failureMode: "Rejects missing pattern sources, duplicate names, missing component definitions, invalid distributions, stale output groups, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "editableFields",
                    supportedValues: ["name", "definitionID", "distribution", "outputMode"],
                    notes: [
                        "Use designDisplaySnapshot.patternArrays to discover the existing PatternArraySourceID.",
                        "Omitted fields keep their current source values.",
                        "Distribution updates reuse existing output instances where counts overlap and remove stale generated outputs.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "distribution",
                    supportedValues: ["rectangular", "radial", "curve"],
                    notes: [
                        "Rectangular updates can replace one- or two-axis linear spacing or extent.",
                        "Radial updates can replace center, rotation axis, angle spacing or extent, copy count, and optional radial repetition.",
                        "Curve updates can replace explicit or sketch-entity path distribution controls, twist, scale, alignment, and extent.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "spacingMode",
                    supportedValues: ["spacing", "extent"],
                    notes: [
                        "Linear spacing and extent update PatternArrayLinearAxis.distanceMode.",
                        "Angular spacing and extent update PatternArrayAngularAxis.angleMode.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "axisCount",
                    supportedValues: ["one", "two", "angular", "angularWithRadialRepetition", "curvePath"],
                    notes: [
                        "Omit rectangular secondAxis to keep a one-axis array.",
                        "Omit radial radialAxis to keep angular-only repetition.",
                        "Curve path arrays regenerate from the supplied path and copy count.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "curveAlignment",
                    supportedValues: ["normal", "parallel", "transport"],
                    notes: [
                        "Use normal for path-local frames, parallel to preserve source orientation, and transport to minimize frame flips.",
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "outputMode",
                    supportedValues: ["componentInstance", "independentCopy"],
                    notes: [
                        "Generated component instance transforms remain source-owned until the array is exploded.",
                        "Independent-copy outputs expose cloned feature IDs in designDisplaySnapshot.patternArrays outputs.",
                    ]
                ),
            ]
        ),
        capability(
            "explodePatternArray",
            category: .pattern,
            summary: "Detach generated pattern outputs from a pattern array source; component-instance arrays are materialized as cloned CAD feature scene outputs before detaching.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.sceneNode],
            failureMode: "Rejects missing pattern sources, stale output groups, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "sourceDiscovery",
                    supportedValues: ["designDisplaySnapshot.patternArrays"],
                    notes: [
                        "Use the snapshot PatternArraySourceID to detach generated component instances from their source."
                    ]
                ),
            ]
        ),
        capability(
            "patternArraySummary",
            category: .read,
            summary: "List source-owned Pattern Array edit candidates, output ownership, lifecycle actions, and diagnostics without mutating the document.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.patternArraySummary, .designDisplaySnapshot],
            targets: [.sceneNode, .componentInstance],
            failureMode: "Rejects stale generations before reading; reports source-owned component-instance and independent-copy output policies so Agents do not direct-edit generated outputs."
        ),
        capability(
            "setSceneNodeVisibility",
            category: .component,
            summary: "Set visibility on a scene node without changing CAD feature source.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.sceneNode],
            failureMode: "Rejects missing scene nodes and stale generations before mutation."
        ),
        capability(
            "setSceneNodeLock",
            category: .component,
            summary: "Set lock state on a scene node without changing CAD feature source.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.sceneNode],
            failureMode: "Rejects missing scene nodes and stale generations before mutation."
        ),
        capability(
            "setSceneNodeTransform",
            category: .component,
            summary: "Replace a scene node local transform.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.sceneNode],
            failureMode: "Rejects missing scene nodes, invalid transforms, and stale generations before mutation."
        ),
        capability(
            "setComponentInstanceVisibility",
            category: .component,
            summary: "Set visibility on a directly editable document-owned component instance.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.componentInstance],
            failureMode: "Rejects missing instances, pattern-owned output instances, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "componentInstanceID",
                    supportedValues: ["designDisplaySnapshot.componentInstances"],
                    notes: [
                        "Use only component instances whose ownership.kind is document.",
                        "Pattern-owned outputs must be edited through updatePatternArray or detached with explodePatternArray before direct edits."
                    ]
                )
            ]
        ),
        capability(
            "setComponentInstanceLock",
            category: .component,
            summary: "Set lock state on a directly editable document-owned component instance.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.componentInstance],
            failureMode: "Rejects missing instances, pattern-owned output instances, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "componentInstanceID",
                    supportedValues: ["designDisplaySnapshot.componentInstances"],
                    notes: [
                        "Use only component instances whose ownership.kind is document.",
                        "Pattern-owned outputs must be edited through updatePatternArray or detached with explodePatternArray before direct edits."
                    ]
                )
            ]
        ),
        capability(
            "setComponentInstanceTransform",
            category: .component,
            summary: "Replace a directly editable document-owned component instance local transform.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot],
            targets: [.componentInstance],
            failureMode: "Rejects missing instances, pattern-owned output instances, invalid transforms, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "componentInstanceID",
                    supportedValues: ["designDisplaySnapshot.componentInstances"],
                    notes: [
                        "Use only component instances whose ownership.kind is document.",
                        "Pattern-owned outputs must be edited through updatePatternArray or detached with explodePatternArray before direct edits."
                    ]
                )
            ]
        ),
        capability(
            "createSectionPlane",
            category: .sketch,
            summary: "Create a construction section plane scene node.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects stale generations before mutation."
        ),
        capability(
            "describeConstructionPlanes",
            category: .sketch,
            summary: "Read saved construction planes, their scene-node linkage, and the active construction plane without mutating source.",
            access: .automationCommand,
            mutatesDocument: false,
            discovery: [.constructionPlaneSummary],
            targets: [.constructionPlane],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "constructionPlaneSummary",
            category: .read,
            summary: "Return structured saved construction-plane IDs, names, sketch planes, scene-node IDs, and active state for Agent planning.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.constructionPlaneSummary],
            targets: [.constructionPlane],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "designDisplaySnapshot",
            category: .read,
            summary: "Return ordered UI-visible sketch primitives, profile regions, component definitions, component instances, pattern arrays, extrude and straight-prism sweep display bodies, evaluated body meshes, and generated topology for Agent viewport planning.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.designDisplaySnapshot, .sketchEntitySummary, .topologySummary],
            targets: [.document, .componentInstance, .sketchEntity, .region, .body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations before reading; reports only display-ready source snapshots, reusable component definitions, placed component instances, and generated pattern sources, not raw CAD kernel internals."
        ),
        capability(
            "createConstructionPlane",
            category: .sketch,
            summary: "Create a saved construction plane from a named SketchPlane source, add it to the construction scene, and optionally make it active for subsequent sketch creation.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.constructionPlaneSummary],
            targets: [.document],
            failureMode: "Rejects empty or duplicate names, invalid plane origin or normal, and stale generations before mutation."
        ),
        capability(
            "createConstructionPlaneFromTarget",
            category: .sketch,
            summary: "Create a saved construction plane aligned to a selected generated face or source sketch region target, add it to the construction scene, and optionally make it active.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .sketchEntitySummary, .selectionState, .constructionPlaneSummary],
            targets: [.face, .region, .constructionPlane],
            failureMode: "Rejects non-face/non-region targets, unresolved topology or source regions, invalid resolved planes, duplicate names, and stale generations before mutation."
        ),
        capability(
            "createConstructionPlaneFromTargets",
            category: .sketch,
            summary: "Create a saved construction plane from selected targets: single face/region alignment, face plus edge perpendicular plane, multi-face/region midplane, or generated/source point targets including sketch point handles and spline control points with explicit view-normal support for two-point planes.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .sketchEntitySummary, .selectionState, .constructionPlaneSummary],
            targets: [.face, .edge, .vertex, .region, .sketchEntity, .sketchPointHandle, .sketchControlPoint, .constructionPlane],
            failureMode: "Rejects empty selections, unsupported target mixes, unresolved topology, source regions, source point handles, or source control points, nonparallel or non-opposing midplane targets, two-point planes without a valid view normal, collinear three-plus point targets, invalid face-edge perpendicular planes, duplicate names, and stale generations before mutation."
        ),
        capability(
            "createViewAlignedConstructionPlane",
            category: .sketch,
            summary: "Create a saved construction plane parallel to an explicit view normal through a supplied origin, matching the current-view construction-plane workflow.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.constructionPlaneSummary],
            targets: [.document],
            failureMode: "Rejects invalid origins, zero or non-finite view normals, duplicate names, and stale generations before mutation."
        ),
        capability(
            "setActiveConstructionPlane",
            category: .sketch,
            summary: "Set or clear the active saved construction plane used by construction-plane-aware sketch creation.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.constructionPlaneSummary],
            targets: [.constructionPlane],
            failureMode: "Rejects missing construction plane IDs and stale generations before mutation."
        ),
        capability(
            "renameConstructionPlane",
            category: .sketch,
            summary: "Rename a saved construction plane and its linked construction scene node through one undoable document mutation.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.constructionPlaneSummary],
            targets: [.constructionPlane],
            failureMode: "Rejects missing construction plane IDs, empty names, duplicate names, and stale generations before mutation."
        ),
        capability(
            "createSketch",
            category: .sketch,
            summary: "Create a source sketch containing one or more typed sketch entities, including connected open multi-entity curve chains for Sweep paths.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects empty sketches, invalid sketch expressions, non-sketch geometry roles, and stale generations before mutation; downstream feature evaluation rejects disconnected, branched, or unsupported curve-chain topology."
        ),
        capability(
            "createLineSketch",
            category: .sketch,
            summary: "Create a source sketch containing one line entity.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid points, zero-length geometry, and stale generations before mutation."
        ),
        capability(
            "createCircleSketch",
            category: .sketch,
            summary: "Create a source sketch containing one positive-radius circle entity.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid centers, non-positive radius, and stale generations before mutation."
        ),
        capability(
            "createArcSketch",
            category: .sketch,
            summary: "Create a source sketch containing one positive-radius partial circular arc entity.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects full circles, invalid angles, non-positive radius, and stale generations before mutation."
        ),
        capability(
            "createSplineSketch",
            category: .sketch,
            summary: "Create a source sketch containing one cubic Bezier spline entity.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid cubic control-point counts, non-finite points, and stale generations before mutation."
        ),
        capability(
            "createRectangleSketch",
            category: .sketch,
            summary: "Create a source rectangle sketch profile from positive width and height.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid dimensions and stale generations before mutation."
        ),
        capability(
            "createPolygonSketch",
            category: .sketch,
            summary: "Create a regular polygon source sketch profile from a center, positive sizing radius, sizing mode, construction-plane-relative inclination mode, side count, and rotation angle.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid centers, non-positive sizing radius, side counts outside 3...256, invalid angles, and stale generations before mutation."
        ),
        capability(
            "createFaceKnife",
            category: .directEditing,
            summary: "Apply the Polygon Knife subset by cutting a selected generated planar face with a closed world-space polygon loop.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .snapResolution],
            targets: [.face],
            failureMode: "Rejects non-face targets, unresolved generated topology, loop counts below three, non-finite points, off-plane loops, outside or boundary-touching loops, non-convex loops, non-planar target faces, target faces with inner loops, non-line target face loops, unsupported target topology, and stale generations before mutation."
        ),
        capability(
            "projectSketchCurvesToConstructionPlane",
            category: .sketch,
            summary: "Alternative Duplicate and Duplicate Curve and Project subset: project selected source sketch curves or generated line/circular edges onto the active or supplied construction plane along that plane normal, creating a new source curve sketch for downstream editing.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .topologySummary, .constructionPlaneSummary],
            targets: [.sketchEntity, .edge, .constructionPlane],
            failureMode: "Rejects empty target lists, duplicate targets, non-curve sketch entities, unresolved source sketches, unresolved generated edges, generated edge targets outside the selected body, generated edge kinds other than line or circle, collapsed projected lines, invalid target planes, nonparallel source or generated circular projections until exact conic projection sources exist, invalid output sketches, and stale generations before mutation."
        ),
        capability(
            "projectCurvesToGeneratedFace",
            category: .sketch,
            summary: "Project Curve Body planar-face subset: project selected source sketch curves or generated line/circular edges onto a selected generated planar face along that face normal, creating a new source curve sketch on the face plane for downstream editing.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .topologySummary],
            targets: [.sketchEntity, .edge, .face],
            failureMode: "Rejects empty target lists, duplicate source targets, non-curve sketch entities, unresolved source sketches, unresolved generated edges or faces, non-planar generated faces, generated edge targets outside the selected body, generated edge kinds other than line or circle, collapsed projected lines, nonparallel source or generated circular projections until exact conic projection sources exist, invalid output sketches, and stale generations before mutation."
        ),
        capability(
            "projectBodyOutlinesToConstructionPlane",
            category: .sketch,
            summary: "Project Outline subset: project selected generated body outlines onto the active or supplied construction plane along that plane normal, creating a new source curve sketch for downstream editing.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .constructionPlaneSummary],
            targets: [.body, .constructionPlane],
            failureMode: "Rejects empty target lists, duplicate body targets, subobject targets, non-body scene nodes, bodies without generated edge topology, generated outline edge kinds other than line or circle, invalid target planes, nonparallel circular outline projections until exact conic projection sources exist, empty non-collapsed projected outlines, invalid output sketches, and stale generations before mutation."
        ),
        capability(
            "addSketchConstraint",
            category: .sourceCurveEditing,
            summary: "Attach and immediately solve supported line, circular, and spline sketch constraints, including smooth spline knots, spline endpoint tangency to lines, tangent spline endpoints, and smooth spline endpoints, on an existing sketch feature.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects duplicate, unsupported, over-constrained, missing-reference, invalid spline control-point, unsmoothable fixed handles, unsatisfied fixed spline tangent handles or endpoints, and stale constraint mutations before commit."
        ),
        capability(
            "removeSketchConstraint",
            category: .sourceCurveEditing,
            summary: "Remove one existing sketch constraint from a sketch feature without changing the current solved geometry.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects missing sketch features, non-sketch features, nonexistent constraints, invalid post-removal sketch state, and stale constraint mutations before commit."
        ),
        capability(
            "createBridgeCurve",
            category: .sourceCurveEditing,
            summary: "Create a multi-span cubic Bezier bridge source curve between two sketch curve positions, with optional endpoint parameter and sense, optional source-curve Trim, endpoint-specific Tension 1/2/3 values, and endpoint-specific G0/G1/G2 continuity constraints where persistent endpoint constraints are available; G3 is reported as unsupported before mutation.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects missing sketch features, unsupported curve references, invalid endpoint parameters, collapsed bridge spans, non-positive tension values, duplicate endpoint positions, same-source Trim requests, Trim requests against constrained or dimensioned source curves, invalid persistent continuity requests, and stale generations before mutation."
        ),
        capability(
            "setBridgeCurveParameters",
            category: .sourceCurveEditing,
            summary: "Edit an existing bridge source curve by regenerating its multi-span cubic Bezier control points from stored or updated curve references, endpoint parameters, sense flags, optional source-curve Trim, endpoint-specific Tension 1/2/3 values, and endpoint-specific G0/G1/G2 continuity intent while preserving the generated spline entity ID.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects missing bridge source IDs, unsupported curve references, invalid endpoint parameters, bridge self-references, non-positive tension values, invalid persistent continuity requests, collapsed spans, same-source Trim requests, Trim requests against constrained or dimensioned source curves, disabling already-applied Trim, invalid generated spline ownership, and stale generations before mutation."
        ),
        capability(
            "offsetCurve",
            category: .sourceCurveEditing,
            summary: "Dispatch Offset Curve targets. Supported source line, circle, and arc targets create new planar source curves without modifying the original curve, including one-sided or symmetric offsets plus gap-fill intent for future joined curves; Slot mode on a selected source line, connected open source line-chain, open source arc, or connected open line/arc chain creates the tangent-capped Slot profile through the same Offset Curve command path; supported source profile region targets create one-sided or symmetric closed line-loop source regions with Round, Linear, or Natural gap fill for convex regions, Natural gap fill for simple concave regions, and Linear gap fill that miter-connects concave corners while adding straight extra-vertex connections only at convex corners; supported generated face targets route to the Offset Face Loop feature for the current single rectangular planar face subset and create a direct-edit body with persistent offset edges; supported generated edge targets route to Offset Edge when options include a generated support face on the same body scene node, when the session selection contains the edge target plus exactly one same-body generated support face, or when the selected edge lies on exactly one generated start/end cap face that can be inferred as the support face, producing a direct-edit body with a persistent offset edge; symmetric generated edge offsets split the selected support face and the single opposite adjacent rectangular support face sharing the selected edge; supported source line or arc endpoint targets with a vertex handle route to Offset Vertex and edit the owning sketch; supported generated body vertex targets on normal extrudes resolve back to source line or arc endpoints and route to the same Offset Vertex branch.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .topologySummary, .snapResolution],
            targets: [.sketchEntity, .region, .face, .edge, .vertex],
            failureMode: "Rejects zero or collapsing distances, including either side of symmetric circular offsets and collapsing, inverted, or self-intersecting one-sided or symmetric-side region offsets, source point entities without adjacent curve-side identity, unsupported planar spline offset targets outside Slot mode, non-line source regions, Round gap fill for concave source regions, Slot mode combined with vertex handles, planar symmetric or gap-fill options in Slot mode, Slot support targets, closed/branched/point Slot targets, closed spline Slot targets, Slot arc widths that collapse the inner radius, disconnected line/arc Slot joins, face-loop symmetric offsets, non-positive face-loop distances, non-rectangular or non-planar face loops outside the current kernel subset, edge support targets on non-edge dispatch, edge vertex handles, missing or ambiguous edge support-face context, symmetric edge offsets without exactly one opposite adjacent support face sharing the selected edge, edge/support-face scene-node mismatches, non-positive edge distances, generated edge/support-face topology outside the current kernel rectangular planar support subset, generated vertex targets that cannot resolve to a normal-extrude source line or arc endpoint, planar offset options on vertex dispatch, object-only selections, and stale generations before mutation."
        ),
        capability(
            "offsetRegions",
            category: .sourceCurveEditing,
            summary: "Offset multiple selected source profile regions in one undoable command. Individual mode creates separate source-owned offset regions; combined mode creates one source sketch containing independent disjoint offset loops or a Natural/Linear polygon-union loop when same-plane line-loop offsets overlap or touch, including simple concave outer boundaries.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .snapResolution],
            targets: [.region],
            failureMode: "Rejects empty selections, mixed-plane combined regions, Round gap-fill unions that require curved polygon union, Round gap fill for concave source regions, nested, touching, or intersecting same-sketch loops without region-union extraction, polygon unions with holes or multiple outer boundaries, non-line source regions, collapsing, inverted, or self-intersecting one-sided or symmetric-side offsets, object-only selections, and stale generations before mutation."
        ),
        capability(
            "offsetSketchVertex",
            category: .sourceCurveEditing,
            summary: "Insert two new source vertices on both sides of a selected source line/arc sketch corner while preserving the source sketch loop.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-line/arc handles, corners without exactly one adjacent line or arc endpoint, distances that collapse either adjacent curve side, disconnected arc-span dimension migrations, unsupported affected constraints beyond coincident plus horizontal/vertical on line sides, unsupported spline vertices, and stale generations before mutation."
        ),
        capability(
            "applySketchCornerTreatment",
            category: .sourceCurveEditing,
            summary: "Apply the source-sketch Fillet command subset to a selected connected line/arc endpoint or to a line/arc curve pair supplied as target plus adjacentTarget. Fillet trims both source curves and inserts an exact circular arc; Chamfer trims both source curves by path distance and inserts a straight chamfer segment.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .snapResolution],
            targets: [.sketchEntity],
            failureMode: "Rejects stale generations, unsupported non-endpoint single targets, non-line/arc corners, curve pairs without exactly one shared connected endpoint, missing or ambiguous adjacent endpoints, generated Bridge Curve sources, non-positive distances, tangent or unsolvable fillet corners, distances that collapse either adjacent curve, and unsupported affected constraints beyond moved-endpoint coincidence, unaffected endpoint references, horizontal/vertical line constraints, and parallel/perpendicular line relationships."
        ),
        capability(
            "createSlotSketch",
            category: .sourceCurveEditing,
            summary: "Create a closed Slot sketch profile from a selected open source line, connected open source line-chain, open source arc, connected open line/arc chain, or open cubic Bezier spline by offsetting both sides symmetrically and closing each end with tangent semicircular arcs. The same supported subset is also reachable through offsetCurve with Slot mode.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects non-positive widths, closed or branched line/arc chain targets, closed spline targets, closed circle targets, point targets, arc widths that collapse the inner radius, disconnected line/arc joins, full-circle arc targets, sampled spline/profile self-intersection, and stale generations before mutation."
        ),
        capability(
            "offsetBodyFace",
            category: .directEditing,
            summary: "Push or pull supported generated or fixed body face targets through source-owned edits.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary],
            targets: [.face],
            failureMode: "Rejects unsupported body types, unsupported face roles, invalid distances, and stale generations before mutation."
        ),
        capability(
            "chamferBodyEdges",
            category: .directEditing,
            summary: "Chamfer supported generated or fixed body edge targets by rewriting source profile loops.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary],
            targets: [.edge],
            failureMode: "Rejects unsupported topology, constrained or parameterized profile loops, collapsing distances, and stale generations before mutation."
        ),
        capability(
            "filletBodyEdges",
            category: .directEditing,
            summary: "Fillet supported generated or fixed body edge targets with exact circular source arcs.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary],
            targets: [.edge],
            failureMode: "Rejects unsupported topology, constrained or parameterized profile loops, tangent-continuous targets, invalid radii, and stale generations before mutation."
        ),
        capability(
            "moveBodyVertex",
            category: .directEditing,
            summary: "Move supported body vertex targets through source profile edits.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary],
            targets: [.vertex],
            failureMode: "Rejects unsupported vertex mappings, invalid deltas, fixed conflicts, and stale generations before mutation."
        ),
        capability(
            "moveSketchEntityPoint",
            category: .sourceCurveEditing,
            summary: "Move a supported point handle on a point, line, circle, or arc sketch entity.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-movable handles, fixed conflicts, invalid deltas, unsupported propagated constraints, and stale generations before mutation."
        ),
        capability(
            "moveSketchSplineControlPoint",
            category: .sourceCurveEditing,
            summary: "Move one control point of a selected cubic Bezier spline source entity.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-spline targets, out-of-range indexes, invalid deltas, invalid spline geometry, and stale generations before mutation."
        ),
        capability(
            "alignSketchVertex",
            category: .sourceCurveEditing,
            summary: "Align Vertex for source sketch vertices: use ordered point-handle or spline-CV target/reference selections to add persistent G0 coincidence, with supported G1 line/arc/spline endpoint continuity and G2 spline-endpoint smooth continuity through the shared constraint solver.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects stale generations, non-point-backed selections, different sketch features, identical target/reference vertices, reference parameter requests, CV continuity distance controls, command-scoped curvature display requests, unsupported G1/G2 endpoint combinations, fixed conflicts, and over-constrained continuity before mutation."
        ),
        capability(
            "slideSketchSplineControlPoints",
            category: .sourceCurveEditing,
            summary: "Slide selected spline CVs using the official Slide Curve CV contract: Positive U, Negative U, or Normal control-cage direction with an explicit distance.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-spline targets, empty, duplicate, negative, or out-of-range indexes, zero distances, collapsed control-cage directions, invalid spline geometry, fixed conflicts, and stale generations before mutation."
        ),
        capability(
            "insertSketchSplineControlPoint",
            category: .sourceCurveEditing,
            summary: "Insert CV into an open cubic Bezier spline at a scalar fraction by preserving the curve shape and expanding the source control-point chain.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-spline targets, closed splines, generated Bridge Curve sources, endpoint or existing-knot fractions, replaced-handle references, unsupported smooth-boundary constraints, and stale generations before mutation."
        ),
        capability(
            "setSketchCircleParameters",
            category: .sourceCurveEditing,
            summary: "Set supported circle center and radius parameters on a selected source circle.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-circle targets, invalid radius, fixed conflicts, unsupported propagated constraints, and stale generations before mutation."
        ),
        capability(
            "setSketchArcParameters",
            category: .sourceCurveEditing,
            summary: "Set supported arc center, radius, start angle, and end angle parameters on a selected source arc.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-arc targets, full-circle arcs, invalid radius or angles, fixed conflicts, and stale generations before mutation."
        ),
        capability(
            "setSketchEntityDimension",
            category: .sourceCurveEditing,
            summary: "Set supported persistent source dimensions for selected line, circle, arc, or rectangle-derived sketch entities.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .sketchDimensionSummary],
            targets: [.sketchEntity],
            failureMode: "Rejects unsupported dimension kinds, fixed conflicts, invalid values, unsupported propagation, and stale generations before mutation."
        ),
        capability(
            "setObjectDimension",
            category: .solid,
            summary: "Set supported selected object dimensions for rectangle-extrude bodies, circle-extrude cylinder bodies, generated face-normal candidates, generated extrusion depth edges, and object-dimension candidates discovered from opposing generated face pairs.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .objectDimensionSummary],
            targets: [.body, .face, .edge],
            failureMode: "Rejects non-body targets, unsupported edge or face-pair topology, unsupported dimension kinds, invalid values, non-extruded sources, and stale generations before mutation."
        ),
        capability(
            "setSelectionDimensionTarget",
            category: .solid,
            summary: "Set the target expression of an existing persistent CAD selection dimension by SelectionDimensionID after evaluating current selection dimensions.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.selectionDimensionEvaluation],
            targets: [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects missing selection dimension IDs, target quantity kinds that do not match the stored selection dimension kind, invalid values, and stale generations before mutation."
        ),
        capability(
            "applySelectionDimensionTarget",
            category: .sourceCurveEditing,
            summary: "Apply the stored target of an existing persistent CAD selection dimension to supported source line length, source sketch point-to-point distance including solved arc endpoint and spline control-point distances, source circle/arc radius, source line relative angle, source arc span angle, or generated opposing editable body face-pair distance dimensions by SelectionDimensionID.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.selectionDimensionEvaluation, .sketchEntitySummary, .topologySummary, .objectDimensionSummary],
            targets: [.document, .face, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects missing selection dimension IDs, unsupported source line length, point-distance, circular radius, line angle, arc span, or face-pair references, impossible arc endpoint distance targets, mismatched or stale endpoint/control-point parameters, invalid target values, fixed conflicts, unsupported propagated constraints, unsupported generated face pairs, and stale generations before mutation."
        ),
        capability(
            "setExtrudeDistance",
            category: .solid,
            summary: "Set an existing extrude feature distance directly by FeatureID, including independent-copy Pattern Array cloned body features discovered from summaries.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot, .patternArraySummary],
            targets: [.body, .sceneNode],
            failureMode: "Rejects missing feature IDs, non-extrude features, invalid length expressions, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "featureIDDiscovery",
                    supportedValues: [
                        "patternArraySummary.independentCopyOutputs.featureIDs",
                        "designDisplaySnapshot.extrudes.featureID",
                    ],
                    notes: [
                        "Use independent-copy output feature IDs when editing cloned Pattern Array outputs directly.",
                        "Use source feature IDs when editing a document-owned extrude source."
                    ]
                ),
            ]
        ),
        capability(
            "setCubeDimensions",
            category: .solid,
            summary: "Set an editable rectangular extrude body's X, Y, and Z dimensions directly by FeatureID, including independent-copy Pattern Array cloned box features.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot, .patternArraySummary, .objectDimensionSummary],
            targets: [.body, .sceneNode],
            failureMode: "Rejects missing feature IDs, non-extrude features, non-rectangle profiles, invalid length expressions, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "featureIDDiscovery",
                    supportedValues: [
                        "patternArraySummary.independentCopyOutputs.featureIDs",
                        "designDisplaySnapshot.extrudes.featureID",
                    ],
                    notes: [
                        "Use independent-copy output feature IDs when editing cloned Pattern Array boxes directly.",
                        "Use objectDimensionSummary to read current box size candidates before preserving unchanged axes."
                    ]
                ),
            ]
        ),
        capability(
            "setCylinderDimensions",
            category: .solid,
            summary: "Set an editable circular extrude body's radius and Y dimension directly by FeatureID, including independent-copy Pattern Array cloned cylinder features.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.designDisplaySnapshot, .patternArraySummary, .objectDimensionSummary],
            targets: [.body, .sceneNode],
            failureMode: "Rejects missing feature IDs, non-extrude features, non-circle profiles, invalid length expressions, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "featureIDDiscovery",
                    supportedValues: [
                        "patternArraySummary.independentCopyOutputs.featureIDs",
                        "designDisplaySnapshot.extrudes.featureID",
                    ],
                    notes: [
                        "Use independent-copy output feature IDs when editing cloned Pattern Array cylinders directly.",
                        "Use objectDimensionSummary to read current cylinder radius and depth candidates before preserving unchanged dimensions."
                    ]
                ),
            ]
        ),
        capability(
            "addSelectionDimension",
            category: .solid,
            summary: "Add a persistent CAD selection dimension between measurable topology or sketch curve targets without storing it as Rupa product metadata.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .sketchEntitySummary, .selectionDimensionEvaluation],
            targets: [.face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects object-wide targets, profile regions, unresolved generated topology, unsupported sketch point handles or control points, invalid target quantities, and stale generations before mutation."
        ),
        capability(
            "removeSelectionDimension",
            category: .solid,
            summary: "Remove one persistent CAD selection dimension by SelectionDimensionID after discovering or evaluating existing dimensions.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.selectionDimensionEvaluation],
            targets: [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects missing selection dimension IDs and stale generations before mutation."
        ),
        capability(
            "convertSketchLineToArc",
            category: .sourceCurveEditing,
            summary: "Convert a selected source line into a circular arc with a signed sagitta.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-line targets, invalid sagitta, unsupported constraints, open reference failures, and stale generations before mutation."
        ),
        capability(
            "convertSketchLineToSpline",
            category: .sourceCurveEditing,
            summary: "Convert a selected source line into a cubic Bezier spline with editable control points while preserving endpoint point references and migratable spline endpoint tangencies.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-line, line-specific constrained, zero-length, and stale targets before mutation; migrates supported endpoint fixed, coincident, distance, angle, and spline endpoint tangent references."
        ),
        capability(
            "reverseSketchCurve",
            category: .sourceCurveEditing,
            summary: "Reverse the direction of a selected source line or cubic Bezier spline curve while preserving physical endpoint references.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects point, circle, arc, invalid, and stale targets before mutation; rewrites fixed, coincident, dimension, spline endpoint, and bridge curve metadata references."
        ),
        capability(
            "rebuildSketchCurve",
            category: .sourceCurveEditing,
            summary: "Rebuild Curve for the current source subset: rebuild an open cubic Bezier spline with Points, Refit tolerance, or degree-3 Explicit Control methods, including Keep Corners for sharp internal knots, weighted explicit spans, and an analytic cubic Bezier deviation report.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects non-spline targets, closed splines, generated Bridge Curve sources, unsupported non-cubic Explicit Control degrees, invalid Explicit Control spans or weights, non-positive Refit tolerance, invalid point counts, internal control-point references that cannot be mapped to preserved knots, whole-spline relationship constraints, and stale generations before mutation."
        ),
        capability(
            "extendSketchCurve",
            category: .sourceCurveEditing,
            summary: "Extend Curve for the current source subset: extend a selected line endpoint, arc endpoint, or spline endpoint by a distance using a typed extension shape.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects stale generations, non-endpoint targets, generated Bridge Curve sources, non-positive distances, constrained or dimensioned source curves, unsupported shape/entity combinations, closed splines, and target-dependent curve or solid matching until that interaction phase is implemented."
        ),
        capability(
            "joinSketchCurves",
            category: .sourceCurveEditing,
            summary: "Join Curves for source-owned sketch curves: merge two same-sketch collinear source lines with exactly one aligned endpoint pair into one retained source line, or group same-sketch line/arc endpoints non-destructively with G0 or validated G1 continuity intent for exact Unjoin and curve-analysis readback.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects different sketches, same-curve pairs, ambiguous endpoint pairs, unsupported curve kinds, non-collinear source-line merge pairs, unsupported G2 continuity, G1 pairs that are not one line plus one arc or are not already tangent, dimensions or constraints attached to destructive line-join interior endpoints, removed-line whole-curve relationships, generated Bridge Curve source metadata, existing joined ownership, and stale generations before mutation."
        ),
        capability(
            "unjoinSketchCurve",
            category: .sourceCurveEditing,
            summary: "Unjoin Curve for source-owned Join Curves: restore a retained destructive line join from its stored ownership snapshot into the original two source lines or restore a non-destructive joined line/arc group back to its pre-join constraints and dimensions.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects targets without joined-curve ownership, changed joined-line geometry, changed constraints or dimensions, entity ID collisions, missing joined group members, generated Bridge Curve source metadata, and stale generations before mutation."
        ),
        capability(
            "splitSketchCurve",
            category: .sourceCurveEditing,
            summary: "Split Segment for a selected source line, source arc, or cubic Bezier spline at a scalar fraction, preserving physical start/end references and inserting a coincident split vertex.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects point, circle, generated Bridge Curve sources, endpoint fractions, unsupported whole-curve constraints, unsupported arc center/radius references, unsupported circular constraints or dimensions, unsupported spline internal control-point references, and stale targets before mutation."
        ),
        capability(
            "trimSketchCurveSegment",
            category: .sourceCurveEditing,
            summary: "Trim an already bounded source curve segment by removing the selected line, arc, or open spline entity and its attached segment-local constraints.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects point and circle targets, closed spline targets, generated Bridge Curve sources, segments used by Bridge Curve metadata, missing targets, and stale generations before mutation. Intersection-defined temporary segment boundaries remain a Cut Curve responsibility."
        ),
        capability(
            "cutSketchCurve",
            category: .sourceCurveEditing,
            summary: "Cut Curve for the current source curve subset: cut a target source line, source arc, sampled open cubic Bezier spline, or unconstrained source circle at its intersections with a distinct source line, circle, arc, or sampled open cubic Bezier spline cutter, optionally extending a line cutter or using an arc cutter's base circle.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects non-line/non-arc/non-spline/non-circle targets, closed spline targets, constrained or dimensioned circle targets, non-line/circle/arc/spline cutters, closed spline cutters, same-curve target/cutter pairs, different sketch planes, parallel or endpoint-only intersections, tangent circle-target cuts with fewer than two distinct intersections, line cutter misses without extendsCutter, coincident circular curve intersections, unsupported spline-cutter extension, screen-space direction requests, unsupported constraints inherited from Split Segment, and stale generations before mutation."
        ),
        capability(
            "extrudeProfile",
            category: .solid,
            summary: "Extrude an existing supported closed profile reference into a solid body.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.profile],
            failureMode: "Rejects open, unsupported, missing, or invalid profiles and stale generations before mutation."
        ),
        capability(
            "createRevolve",
            category: .solid,
            summary: "Create a Revolve source feature from an existing supported closed profile, an explicit 3D axis, and a finite angle into a solid body.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .topologySummary],
            targets: [.profile],
            failureMode: "Rejects missing or unsupported closed profiles, axes that do not lie in the profile plane, profiles crossing the rotation axis, zero or over-full-turn angles, collapsed axes, unsupported conical or curved profile boundaries until analytic surface-of-revolution support exists, invalid generated topology, and stale generations before mutation.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "axis",
                    supportedValues: ["explicit 3D line lying in the profile plane"],
                    notes: [
                        "the profile must remain on one side of the axis",
                        "the axis may coincide with one profile boundary segment"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "angle",
                    supportedValues: ["nonzero angle up to 360 degrees"],
                    notes: [
                        "partial angles create start and end caps",
                        "full turns create closed cylindrical and planar side topology without seam-cap faces"
                    ]
                ),
            ]
        ),
        capability(
            "createSweep",
            category: .solid,
            summary: "Create a Sweep source feature from closed-profile or curve sections, a path, optional guide references, and explicit twist, scale, alignment, distance, corner, guide, boolean, keep-tools, simplify, and result-kind options.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.profile, .sketchEntity, .body],
            failureMode: "Rejects missing section, path, guide, or target body features, solid output from curve sections, duplicate references, invalid option quantities, disconnected or branched open path chains, closed path chains, round corner style on multi-curve paths until corner-transition blend topology exists, profile-plane degenerate parallel alignment, simplify output, boolean target operations with sheet output, stale generations, targetless boolean operations, new-body target references, collapsed section scale, non-contacting point/chord guide starts, curve-guide path/section contact failures, conflicting signed-axis rail guides, flipped or self-intersecting bilinear quadrilateral or mean-value cage rail guides, overconstrained guide sets, and degenerate swept topology before committing invalid geometry through the shared typed sweep evaluation contract; evaluates mitre corner style for connected open single- or multi-curve path chains; evaluates round corner style for single-curve paths where no corner-transition topology is required; evaluates straight-path normal alignment as a path-normal section sweep, straight-path parallel identity sections as profile-plane-preserving exact extrusion when the path has a profile-normal component, straight-path parallel transformed or guided sections as profile-plane parallel section sweeps when the path has a profile-normal component, curve sections as new-body sheet sweeps, curved-path parallel alignment as a profile-plane parallel section sweep with twist, scale, and profile-plane guide projection, straight-path exact swept-sheet side surfaces for identity section transforms without guides, polygonal swept-solid new-body subsets for connected open curved or multi-curve paths, twisted, scaled, compatible multiple point/chord guide constraints, non-uniform affine, signed-axis, convex quadrilateral bilinear, and convex mean-value cage point-guide rail deformation, and curve-guide contact constraints, and polygonal swept-sheet subsets for curved, transformed, or guided sheet inputs; evaluates exact box-prism union, difference, intersection, and slice boolean sweeps with target replacement, separated-fragment difference output, z-through rectangular-frame difference output, orthogonal cell-union connected box difference output, or keep-tools generated-name coverage; reports unsupported evaluation for non-box boolean operands, connected boolean topology outside the axis-aligned box cell-union subset, exact swept surfaces outside the straight identity analytic-boundary subset, corner-transition blend topology outside the current single-curve round subset, and guide constraints outside the affine, signed-axis, convex quadrilateral bilinear, convex mean-value cage, chord, or curve-contact subsets.",
            optionMatrix: [
                AgentCapabilityDescriptor.OptionAxis(
                    name: "alignment",
                    supportedValues: ["parallel", "normal"],
                    notes: [
                        "parallel preserves the profile plane when the path has a nonzero profile-normal component",
                        "normal uses path-normal section frames"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "guideMethod",
                    supportedValues: ["point", "chord", "curve"],
                    notes: [
                        "point supports similarity, non-uniform affine, signed-axis, bilinear quadrilateral, mean-value cage rail deformation, and radial point rail deformation when guide geometry satisfies those contracts",
                        "chord supports directional compatible guide rotation",
                        "curve requires initial path/profile contact and validates curve-contact constraints"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "booleanOperation",
                    supportedValues: ["newBody", "union", "difference", "intersect", "slice"],
                    notes: [
                        "target boolean operations require at least one target body",
                        "newBody must not declare target bodies",
                        "target boolean operations require solid resultKind"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "resultKind",
                    supportedValues: ["solid", "sheet"],
                    notes: [
                        "sheet is supported for new-body outputs only",
                        "closed-profile sections create solid output by default while curve sections require sheet output",
                        "straight identity sheets preserve exact analytic side surfaces for line and circular-arc profile boundaries",
                        "curved, transformed, or guided sheet outputs are polygonal"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "cornerStyle",
                    supportedValues: ["mitre", "round"],
                    notes: [
                        "mitre is supported for connected open single- or multi-curve path chains",
                        "round is accepted for single-curve paths only until multi-curve corner-transition blend topology is implemented"
                    ]
                ),
                AgentCapabilityDescriptor.OptionAxis(
                    name: "simplify",
                    supportedValues: ["false"],
                    notes: ["simplify is rejected so generated topology remains explicit and selectable"]
                ),
            ]
        ),
        capability(
            "sweepEvaluationPlan",
            category: .read,
            summary: "Preflight a proposed Sweep without mutating the document, returning the resolved path shape, section state, evaluation kind, output topology, boolean support, guide strategies, unsupported code, and ordered checks used by the shared sweep evaluation contract.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.sketchEntitySummary, .topologySummary, .sweepEvaluationPlan],
            targets: [.profile, .sketchEntity, .body],
            failureMode: "Rejects stale generations, missing references, invalid option quantities, disconnected or branched path chains, and unresolved target bodies; returns structured unsupported results for current kernel capability gaps and geometry contracts such as simplify output, sheet target booleans, profile-plane degenerate parallel alignment, round multi-curve corner-transition topology, and guide constraints that do not solve against the section and path frames before mutation.",
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
                    name: "guideStrategies",
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
                        "Guide strategies reflect the shared sweep capability matrix after source geometry and guide paths are resolved.",
                    ]
                ),
            ]
        ),
        capability(
            "createBSplineSurface",
            category: .solid,
            summary: "Create a direct source-owned B-spline or NURBS sheet surface from stored degree, knot vectors, control net, and weights.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis, .topologySummary],
            targets: [.document],
            failureMode: "Accepts finite validated B-spline surface source data with positive weights and matching U/V degree, knot-vector, and control-net dimensions; rejects invalid knots, non-positive weights, degenerate domains, stale generations, and invalid evaluated sheet topology before mutation."
        ),
        capability(
            "createPolySplineSurface",
            category: .solid,
            summary: "Create a PolySpline source surface from a supported source mesh and emit a B-spline sheet body.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.meshSummary, .polySplineMeshAnalysis, .topologySummary, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.document],
            failureMode: "Accepts a single quad mesh or a planar unmerged quad patch network and creates cubic B-spline sheet topology with exact boundary interpolation; rejects rounded-corner requests, non-planar unresolved G2 patch networks, merge-patch reconstruction, triangle/ngon patch networks, invalid meshes, and stale generations before mutation."
        ),
        capability(
            "movePolySplineSurfaceVertex",
            category: .solid,
            summary: "Move a generated PolySpline patch boundary vertex by mutating its source mesh vertex through the undoable command pipeline.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.vertex],
            failureMode: "Rejects non-PolySpline generated vertices, stale generations, zero or invalid deltas, unsupported source meshes, moves that remove the selected patch, moves that change the selected boundary role, and moves that leave the current evaluator unable to rebuild supported B-spline sheet topology."
        ),
        capability(
            "moveSurfaceControlPoint",
            category: .solid,
            summary: "Move a source-owned surface control point from a Swift-CAD SelectionReference without requiring UI scene-node targeting; direct B-spline surfaces mutate their stored control net.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .selectionMeasurement, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceControlPoint],
            failureMode: "Accepts direct B-spline surface control-net references, PolySpline patch corner control point references, and strict interior PolySpline B-spline control point references discovered from surfaceSourceSummary; rejects non-control-point references, non-editable surface sources, boundary edge-only CV indexes, stale generations, zero or invalid deltas, unsupported source meshes, moves that change selected PolySpline corner boundary roles, and invalid rebuilt B-spline sheet topology."
        ),
        capability(
            "moveSurfaceControlPointsInFrame",
            category: .solid,
            summary: "Move source-owned surface control points by distances along a resolved surface UVN frame from surfaceSourceSummary frame samples or surfaceFrames queries.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceControlPoint, .face],
            failureMode: "Accepts editable surface control-point references discovered from surfaceSourceSummary and a resolvable face, surface parameter, or control-point frame query discovered from surfaceSourceSummary frameSamples or surfaceFrames; rejects empty or duplicate targets, unresolved frames, stale generations, non-control-point references, zero UVN offsets, non-editable surface sources, invalid unit axes, and invalid rebuilt B-spline sheet topology."
        ),
        capability(
            "setSurfaceControlPointWeight",
            category: .solid,
            summary: "Set a source-owned B-spline surface control-point weight from a Swift-CAD SelectionReference, preserving the control point position while making the evaluated surface rational; direct B-spline surfaces mutate their stored weight net.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceControlPoint],
            failureMode: "Accepts direct B-spline surface control-net references and strict interior PolySpline B-spline control point references discovered from surfaceSourceSummary; rejects PolySpline boundary CV weights, non-control-point references, non-scalar or non-positive weights, non-editable surface sources, stale generations, unsupported source meshes, and invalid rebuilt rational B-spline sheet topology."
        ),
        capability(
            "setSurfaceKnotValue",
            category: .solid,
            summary: "Set an existing direct B-spline surface internal knot value from a Swift-CAD SelectionReference discovered in surfaceSourceSummary.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceKnot],
            failureMode: "Accepts editable direct B-spline surface internal knot references discovered from surfaceSourceSummary; rejects boundary knots, PolySpline generated knots, non-knot references, non-scalar values, values outside strict neighboring knot bounds, stale generations, non-editable surface sources, and invalid rebuilt B-spline sheet topology."
        ),
        capability(
            "insertSurfaceKnot",
            category: .solid,
            summary: "Insert a direct B-spline surface knot inside a selected editable surface span, or duplicate a selected editable internal knot to increase multiplicity, while preserving the represented surface shape and increasing the control net in that parameter direction.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceSpan, .surfaceKnot],
            failureMode: "Accepts editable direct B-spline surface span references and editable internal knot references discovered from surfaceSourceSummary; rejects boundary-only or missing spans, boundary knots, PolySpline generated spans or knots, non-span and non-knot references, non-scalar values, values outside the selected span, values that do not match a selected existing knot, saturated knot multiplicity, stale generations, non-editable surface sources, and invalid rebuilt B-spline sheet topology."
        ),
        capability(
            "setSurfaceKnotMultiplicity",
            category: .solid,
            summary: "Set an editable direct B-spline surface internal knot to an explicit higher multiplicity by shape-preserving knot insertion, allowing agents to control local continuity without changing the represented surface shape.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceKnot],
            failureMode: "Accepts editable direct B-spline surface internal knot references discovered from surfaceSourceSummary and a requested multiplicity greater than the current multiplicity and no greater than the surface degree in that direction; rejects boundary knots, PolySpline generated knots, non-knot references, lower or equal multiplicities, saturated knot multiplicity, stale generations, non-editable surface sources, and invalid rebuilt B-spline sheet topology."
        ),
        capability(
            "slidePolySplineSurfaceVertices",
            category: .solid,
            summary: "Slide generated PolySpline patch boundary CVs along local surface hull U, V, or normal directions with an explicit distance.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.topologySummary, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.vertex],
            failureMode: "Rejects non-PolySpline generated vertices, stale generations, empty or duplicate source-vertex targets, zero or invalid distances, collapsed local U/V/normal directions, unsupported source meshes, slides that remove the selected patch, slides that change the selected boundary role, and slides that leave the current evaluator unable to rebuild supported B-spline sheet topology."
        ),
        capability(
            "slideSurfaceControlPoints",
            category: .solid,
            summary: "Slide source-owned surface control points from Swift-CAD SelectionReference values along local U, V, or normal directions; direct B-spline CVs use their stored control net and strict interior PolySpline CVs use the override-aware B-spline control-hull frame.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .selectionMeasurement, .surfaceAnalysis, .surfaceContinuitySummary],
            targets: [.surfaceControlPoint],
            failureMode: "Accepts direct B-spline surface control-net references, PolySpline patch corner control point references, and strict interior PolySpline B-spline control point references discovered from surfaceSourceSummary; boundary corner slides route through generated source-mesh patch hull directions, direct B-spline CVs and strict interior PolySpline CVs resolve local control-hull U/V/N directions; rejects non-control-point references, non-editable surface sources, boundary edge-only CV indexes, stale generations, empty or duplicate targets, zero or invalid distances, collapsed local U/V/normal directions, slides that change selected PolySpline corner boundary roles, and invalid rebuilt B-spline sheet topology."
        ),
        capability(
            "createExtrudedRectangle",
            category: .solid,
            summary: "Create a rectangle sketch source and normal or symmetric extruded body.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid dimensions and stale generations before mutation."
        ),
        capability(
            "createExtrudedRectangleFromCorners",
            category: .solid,
            summary: "Create a rectangle sketch source from two corners and extrude it into a body.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects coincident corners, invalid depth, and stale generations before mutation."
        ),
        capability(
            "createExtrudedCircle",
            category: .solid,
            summary: "Create a circular sketch source and extrude it into a cylinder-like body.",
            access: .automationCommand,
            mutatesDocument: true,
            targets: [.document],
            failureMode: "Rejects invalid radius, invalid depth, and stale generations before mutation."
        ),
        capability(
            "evaluateDocument",
            category: .read,
            summary: "Validate and evaluate the document, updating evaluation diagnostics without adding undo history.",
            access: .agentRequest,
            mutatesDocument: false,
            targets: [.document],
            failureMode: "Rejects stale generations before evaluation."
        ),
        capability(
            "measureDocument",
            category: .read,
            summary: "Measure selected or whole-document source-derived geometry without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.selectionState],
            targets: [.document, .sceneNode, .sketchEntity],
            failureMode: "Rejects stale generations before measuring."
        ),
        capability(
            "selectionMeasurement",
            category: .read,
            summary: "Measure a typed Swift-CAD SelectionReference as a point, distance, or angle without mutation, including topology, edge parameters, curve CVs, surface parameters, surface CVs, and surface trims.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.selectionMeasurement, .surfaceSourceSummary, .topologySummary, .sketchEntitySummary],
            targets: [.face, .edge, .vertex, .sketchEntity, .surface, .surfaceControlPoint, .surfaceTrim],
            failureMode: "Rejects stale generations, invalid selection references, unresolved generated topology, unsupported ambiguous body or surface-knot measurements, and evaluation failures before returning measured geometry."
        ),
        capability(
            "objectDimensionSummary",
            category: .read,
            summary: "List editable Dimension command candidates for selected object, face, generated face-normal, generated extrusion depth edge, or generated opposing face-pair targets without mutation, including box size axes, cylinder diameter, radius, depth, and supported face-distance candidates.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.objectDimensionSummary, .topologySummary],
            targets: [.body, .face, .edge],
            failureMode: "Rejects stale generations, non-body targets, unsupported edge or face-pair topology, unsupported source profiles, and invalid source expressions before returning candidates."
        ),
        capability(
            "sketchDimensionSummary",
            category: .read,
            summary: "List editable Dimension command candidates for selected sketch line, circle, arc, generated extrude cap edge, or supported generated arc edge targets without mutation, including fillet-radius readback for generated fillet arc edges.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.sketchDimensionSummary, .sketchEntitySummary, .topologySummary],
            targets: [.sketchEntity, .edge],
            failureMode: "Rejects stale generations, unsupported topology targets, unresolved source sketch curves, and invalid source expressions before returning candidates."
        ),
        capability(
            "selectionDimensionEvaluation",
            category: .read,
            summary: "Evaluate persistent CAD selection dimensions stored in the SwiftCAD document source.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.selectionDimensionEvaluation, .topologySummary, .sketchEntitySummary],
            targets: [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint],
            failureMode: "Rejects stale generations, invalid CAD source, unresolved selection references, or missing dimension IDs before returning measured residuals."
        ),
        capability(
            "resolveSnap",
            category: .read,
            summary: "Resolve a model-space sketch input point against grid, measurement annotations, source sketch special points, source profile region centers, generated topology points, source spline CVs, closest curve points, supported curve intersections, reference-point curve-axis candidates, reference-point curve-coordinate-plane candidates, and reference-point tangent/perpendicular curve candidates without mutating the document.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.snapResolution, .sketchEntitySummary, .topologySummary],
            targets: [.document, .sceneNode, .profile, .region, .sketchEntity],
            failureMode: "Rejects stale generations, invalid points, invalid snap options, or source expressions that cannot be resolved before returning candidates; object-targeting force enable, candidate-kind suppression, source-curve X/Y/Z axis candidates, and source-curve XY/YZ/ZX coordinate-plane candidates are supported through snap options."
        ),
        capability(
            "meshSummary",
            category: .read,
            summary: "Read evaluated mesh counts, bounds, and per-body mesh metadata without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.meshSummary],
            targets: [.document],
            failureMode: "Rejects stale generations or evaluation failures before returning mesh data."
        ),
        capability(
            "polySplineMeshAnalysis",
            category: .read,
            summary: "Preflight a source mesh for PolySpline reconstruction and return structured support diagnostics plus quad patch graph candidates and partition data without mutating the document.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.meshSummary, .polySplineMeshAnalysis],
            targets: [.document],
            failureMode: "Rejects stale generations before analysis; reports invalid meshes, unsupported rounded-corner requests, non-manifold adjacency, inconsistent boundary winding, patch graph candidates, exact selected/rejected partitions, and unsupported G2 multi-patch reconstruction as structured diagnostics."
        ),
        capability(
            "sketchEntitySummary",
            category: .read,
            summary: "Discover editable source sketch entities, source profile regions, expressions, dimensions, constraints, and selection targets without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity, .region],
            failureMode: "Rejects stale generations before reading."
        ),
        capability(
            "curveAnalysis",
            category: .read,
            summary: "Evaluate source curves for samples, curvature, approximate length, and internal spline continuity without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects stale generations or invalid documents before curve analysis."
        ),
        capability(
            "setCurveCurvatureDisplay",
            category: .sourceCurveEditing,
            summary: "Toggle persistent viewport curvature-comb display for a source curve target and set the comb scale used by the curve-quality overlay.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary, .curveAnalysis],
            targets: [.sketchEntity],
            failureMode: "Rejects stale generations, non-sketch-entity targets, source points, missing source curves, or non-positive comb scales before mutation."
        ),
        capability(
            "setPointDisplay",
            category: .sourceCurveEditing,
            summary: "Toggle persistent source-curve point display for curve vertices and spline CV layouts.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.sketchEntitySummary],
            targets: [.sketchEntity],
            failureMode: "Rejects stale generations, non-sketch-entity targets, standalone point entities, or missing source curves before mutation."
        ),
        capability(
            "setSurfaceControlPointDisplay",
            category: .solid,
            summary: "Toggle persistent Agent-visible Surface CV point display state for PolySpline and direct B-spline surface control points discovered from surfaceSourceSummary.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .selectionMeasurement, .surfaceAnalysis],
            targets: [.surfaceControlPoint],
            failureMode: "Accepts PolySpline and direct B-spline surface control point selection references discovered from surfaceSourceSummary; rejects non-control-point references, unsupported PolySpline source meshes, missing patches, out-of-range indexes, stale generations, invalid direct B-spline control-net indexes, or missing source features before mutation."
        ),
        capability(
            "setSurfaceFrameDisplay",
            category: .solid,
            summary: "Toggle persistent Agent-visible UVN surface frame display state for generated face UV queries, surface parameter references, or Surface CV references.",
            access: .automationCommand,
            mutatesDocument: true,
            discovery: [.surfaceSourceSummary, .surfaceFrames, .surfaceAnalysis],
            targets: [.face, .surfaceControlPoint],
            failureMode: "Accepts generated B-spline face UV queries, surface parameter references, or Surface CV references resolvable by surfaceFrames; rejects unresolved references, ambiguous UV input, non-B-spline faces, stale generations, and unsupported surface trim, span, knot, edge, curve, or sketch point references before mutation."
        ),
        capability(
            "topologySummary",
            category: .read,
            summary: "Discover generated faces, edges, vertices, persistent topology names, and selection targets without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary],
            targets: [.face, .edge, .vertex],
            failureMode: "Rejects stale generations or evaluation failures before returning topology data."
        ),
        capability(
            "surfaceSourceSummary",
            category: .read,
            summary: "Discover source-owned surface contracts for editable PolySpline and direct B-spline surfaces, including patch IDs, degree and knot-vector basis, knot and span addresses, weighted CV targets, boundary CV targets, span-center UVN frame samples, trim loops, support diagnostics, and generated topology links.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.surfaceSourceSummary, .polySplineMeshAnalysis, .topologySummary],
            targets: [.document, .body, .face, .edge, .vertex],
            failureMode: "Rejects stale generations or invalid documents before returning source-owned surface contracts; reports unsupported PolySpline reconstruction options and invalid direct B-spline source data as structured diagnostics instead of exposing silent surface edit targets."
        ),
        capability(
            "surfaceAnalysis",
            category: .read,
            summary: "Sample generated B-spline faces for UV points, normals, principal directions, ordered trim-boundary point loops, and finite-difference surface curvature comb diagnostics without mutation; supports low, standard, and high sample density.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary, .surfaceAnalysis],
            targets: [.face, .edge],
            failureMode: "Rejects stale generations, invalid documents, or unsupported unbounded B-spline domains before returning surface analysis data."
        ),
        capability(
            "surfaceFrames",
            category: .read,
            summary: "Resolve generated B-spline face UV addresses or surface selection references into oriented UVN local frames, derivative tangents, principal directions, and curvature values without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary, .surfaceSourceSummary, .surfaceFrames],
            targets: [.face, .surfaceControlPoint],
            failureMode: "Rejects stale generations, unresolved face persistent names, face IDs, or surface selection references, non-B-spline faces, unbounded domains, ambiguous UV input, and UV parameters outside the face surface domain."
        ),
        capability(
            "surfaceContinuitySummary",
            category: .read,
            summary: "Discover B-spline face adjacencies, shared edges, and observed G0/G1/G2 continuity status without mutation.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary, .surfaceContinuitySummary],
            targets: [.face, .edge],
            failureMode: "Rejects stale generations or evaluation failures before returning surface continuity data; reports sampled curvature gaps for G2-capable UV trim curves and flags unresolved curvature continuity when a sampled boundary contract is unavailable."
        ),
        capability(
            "selectTargets",
            category: .selection,
            summary: "Select Agent-discovered object, face, edge, vertex, region, or sketch-entity targets without mutating CAD source.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary, .sketchEntitySummary],
            targets: [.sceneNode, .face, .edge, .vertex, .region, .sketchEntity],
            failureMode: "Rejects stale generations and targets incompatible with the current document."
        ),
        capability(
            "selectReferences",
            category: .selection,
            summary: "Select Agent-discovered Swift-CAD SelectionReference values, including Surface CV references, without mutating CAD source.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.surfaceSourceSummary, .topologySummary, .selectionMeasurement],
            targets: [.surface, .surfaceControlPoint, .surfaceTrim],
            failureMode: "Rejects stale generations and references incompatible with the current document."
        ),
        capability(
            "saveDocument",
            category: .persistence,
            summary: "Persist the open document back to its registered path and mark the session clean.",
            access: .agentRequest,
            mutatesDocument: false,
            targets: [.document],
            failureMode: "Rejects pathless sessions, stale generations, and save errors before reporting success."
        ),
        capability(
            "exportDocument",
            category: .persistence,
            summary: "Evaluate and export the document with a named preset or explicit export options.",
            access: .agentRequest,
            mutatesDocument: false,
            targets: [.document],
            failureMode: "Rejects stale generations, unsupported formats, evaluation failures, and destination policy errors."
        ),
        capability(
            "validateDocument",
            category: .read,
            summary: "Run the validation command and publish the resulting diagnostics.",
            access: .automationCommand,
            mutatesDocument: false,
            targets: [.document],
            failureMode: "Rejects stale generations before validation."
        ),
    ]

    private static func capability(
        _ name: String,
        category: AgentCapabilityDescriptor.Category,
        summary: String,
        access: AgentCapabilityDescriptor.Access,
        mutatesDocument: Bool,
        requiresSession: Bool = true,
        requiresExpectedGeneration: Bool = true,
        discovery: [AgentCapabilityDescriptor.Discovery] = [],
        targets: [AgentCapabilityDescriptor.Target] = [],
        failureMode: String,
        optionMatrix: [AgentCapabilityDescriptor.OptionAxis] = []
    ) -> AgentCapabilityDescriptor {
        AgentCapabilityDescriptor(
            name: name,
            category: category,
            summary: summary,
            access: access,
            mutatesDocument: mutatesDocument,
            requiresSession: requiresSession,
            requiresExpectedGeneration: requiresExpectedGeneration,
            discovery: discovery,
            targets: targets,
            failureMode: failureMode,
            optionMatrix: optionMatrix
        )
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        registry.register(session: session, path: path, id: id)
    }

    public func unregister(id: UUID) {
        registry.unregister(id: id)
    }

    public func handle(_ request: AgentRequest) -> AgentResponse {
        do {
            switch request {
            case .capabilities:
                return .capabilities(capabilityDescriptors())
            case .status:
                return .status(
                    AgentStatus(
                        running: true,
                        socketPath: socketPath,
                        sessionCount: registry.summaries().count
                    )
                )
            case .sessions:
                return .sessions(registry.summaries())
            case .cadInteractionQualityAssessment:
                return .cadInteractionQualityAssessment(
                    CADInteractionQualityAssessmentService().assess()
                )
            case let .execute(sessionID, command, expectedGeneration):
                let session = try registry.session(id: sessionID)
                let result = try runner.executeBatch(
                    AutomationBatch(
                        commands: [command],
                        expectedGeneration: expectedGeneration
                    ),
                    in: session
                )
                guard let commandResult = result.first else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Agent command produced no result."
                    )
                }
                return .command(commandResult)
            case let .parameters(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .parameters(
                    ParameterListResult(
                        document: session.document,
                        generation: session.generation,
                        dirty: session.isDirty,
                        diagnostics: session.diagnostics
                    )
                )
            case let .setParameterExpression(sessionID, name, expression, kind, defaults, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let parsedExpression = try ParameterExpressionParser().parseForUpsert(
                    expression,
                    parameterName: name,
                    parameters: session.document.cadDocument.parameters,
                    targetKind: kind,
                    defaults: defaults
                )
                let result = try runner.execute(
                    .upsertParameter(
                        name: name,
                        expression: parsedExpression,
                        kind: kind
                    ),
                    in: session
                )
                return .command(result)
            case let .evaluate(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                let result = try runner.executeBatch(
                    AutomationBatch(
                        commands: [.validateDocument],
                        expectedGeneration: expectedGeneration
                    ),
                    in: session
                )
                guard result.first != nil else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Agent evaluation produced no result."
                    )
                }
                return .evaluation(session.evaluationSnapshot)
            case let .measure(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .measurement(
                    try MeasurementService().measure(
                        document: session.document,
                        selection: session.selection,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .selectionMeasurement(sessionID, query, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .selectionMeasurement(
                    try SelectionMeasurementService().measure(
                        query: query,
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .resolveSnap(sessionID, point, options, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .snapResolution(
                    try SnapResolver().resolve(
                        point: point,
                        in: session.document,
                        options: options
                    )
                )
            case let .constructionPlaneSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .constructionPlaneSummary(
                    ConstructionPlaneSummaryService().summarize(
                        document: session.document
                    )
                )
            case let .designDisplaySnapshot(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .designDisplaySnapshot(
                    try DesignDisplaySnapshotService().result(
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        generation: session.generation,
                        dirty: session.isDirty
                    )
                )
            case let .patternArraySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .patternArraySummary(
                    PatternArraySummaryService().summarize(
                        document: session.document,
                        generation: session.generation,
                        dirty: session.isDirty
                    )
                )
            case let .meshSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .meshSummary(
                    try MeshSummaryService().summarize(
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .polySplineMeshAnalysis(sessionID, sourceMesh, options, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .polySplineMeshAnalysis(
                    PolySplineMeshAnalysisService().analyze(
                        sourceMesh: sourceMesh,
                        options: options
                    )
                )
            case let .sketchEntitySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .sketchEntitySummary(
                    try SketchEntitySummaryService().summarize(
                        document: session.document,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .sketchDimensionSummary(sessionID, targets, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let resolvedTargets = targets.isEmpty ? session.selection.selectedTargets : targets
                return .sketchDimensionSummary(
                    try SketchDimensionSummaryService().summarize(
                        document: session.document,
                        targets: resolvedTargets,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .selectionDimensionEvaluation(sessionID, dimensionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .selectionDimensionEvaluation(
                    try SelectionDimensionService().evaluate(
                        document: session.document,
                        dimensionID: dimensionID,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .curveAnalysis(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .curveAnalysis(
                    try CurveAnalysisService().analyze(
                        document: session.document,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .topologySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .topologySummary(
                    try TopologySummaryService().summarize(
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .sweepEvaluationPlan(
                sessionID,
                sections,
                path,
                guides,
                targets,
                options,
                expectedGeneration
            ):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .sweepEvaluationPlan(
                    try SweepEvaluationPlanService().plan(
                        document: session.document.cadDocument,
                        sections: sections,
                        path: path,
                        guides: guides,
                        targets: targets,
                        options: options
                    )
                )
            case let .objectDimensionSummary(sessionID, targets, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let resolvedTargets = targets.isEmpty ? session.selection.selectedTargets : targets
                return .objectDimensionSummary(
                    try ObjectDimensionSummaryService().summarize(
                        document: session.document,
                        targets: resolvedTargets,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .surfaceSourceSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceSourceSummary(
                    try SurfaceSourceSummaryService().summarize(
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceAnalysis(sessionID, options, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceAnalysis(
                    try SurfaceAnalysisService(options: options).analyze(
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceFrames(sessionID, queries, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceFrames(
                    try SurfaceFrameService().resolve(
                        document: session.document,
                        queries: queries,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .surfaceContinuitySummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .surfaceContinuitySummary(
                    try SurfaceContinuityService().summarize(
                        document: session.document,
                        objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation,
                        currentGeneration: session.generation
                    )
                )
            case let .selectTargets(sessionID, targets, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                guard session.selectTargets(targets) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Agent selection target is not compatible with the current document."
                    )
                }
                return .selection(
                    SelectionStateResult(
                        message: "\(session.selection.selectedTargets.count) target(s), \(session.selection.selectedReferences.count) reference(s) selected.",
                        generation: session.generation,
                        dirty: session.isDirty,
                        selectedTargets: session.selection.selectedTargets,
                        selectedReferences: session.selection.selectedReferences,
                        hoveredTarget: session.selection.hoveredTarget,
                        hoveredReference: session.selection.hoveredReference,
                        diagnostics: session.diagnostics
                    )
                )
            case let .selectReferences(sessionID, references, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                guard session.selectReferences(references) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Agent selection reference is not compatible with the current document."
                    )
                }
                return .selection(
                    SelectionStateResult(
                        message: "\(session.selection.selectedTargets.count) target(s), \(session.selection.selectedReferences.count) reference(s) selected.",
                        generation: session.generation,
                        dirty: session.isDirty,
                        selectedTargets: session.selection.selectedTargets,
                        selectedReferences: session.selection.selectedReferences,
                        hoveredTarget: session.selection.hoveredTarget,
                        hoveredReference: session.selection.hoveredReference,
                        diagnostics: session.diagnostics
                    )
                )
            case let .save(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let url = try registry.documentURL(id: sessionID)
                try fileService.save(session.document, to: url)
                session.store.markClean()
                return .save(
                    SaveResult(
                        message: "Document saved to \(url.path).",
                        path: url.path,
                        generation: session.generation,
                        dirty: session.isDirty,
                        diagnostics: session.diagnostics
                    )
                )
            case let .export(sessionID, outputPath, expectedGeneration, options, dryRun):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let result = try exportService.export(
                    document: session.document,
                    generation: session.generation,
                    to: URL(fileURLWithPath: outputPath),
                    options: options,
                    dryRun: dryRun,
                    objectRegistry: session.objectRegistry
                )
                return .export(result)
            }
        } catch let error as EditorError {
            return .failure(error)
        } catch {
            return .failure(
                EditorError(
                    code: .commandFailed,
                    message: error.localizedDescription
                )
            )
        }
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        handle(request)
    }
}
