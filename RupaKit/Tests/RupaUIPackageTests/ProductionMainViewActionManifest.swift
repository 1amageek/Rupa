import Foundation

enum ProductionMainViewActionManifest {
    enum Route: String, CaseIterable, Hashable, Sendable {
        case snapshotRead
        case sourceTransaction
        case interactionTransaction
        case domainPlanner
        case mainActorTransient
    }

    enum Category: String, CaseIterable, Hashable, Sendable {
        case sourceCommand
        case sourceHelper
        case canvas
        case patternArray
        case snapshot
        case selection
        case navigation
        case workspace
        case transient
        case domain
    }

    /// The shared project boundary whose behavior proves one audited route.
    ///
    /// Command-specific semantics remain owned by their focused command tests.
    /// This classification proves that every production-reachable action has an
    /// explicit route through, or explicitly outside, project publication.
    enum BoundaryProof: String, CaseIterable, Hashable, Sendable {
        case immutableSnapshot
        case sourceAction
        case interactionAction
        case domainPlan
        case mainActorTransient
    }

    struct Marker: Hashable, Sendable {
        let relativePath: String
        let regularExpression: String
    }

    struct Row: Hashable, Sendable {
        let actionID: String
        let productionEntry: String
        let inputOwner: String
        let route: Route
        let category: Category
        let finalOperation: String
        let plannerFixtureID: String
        let expectedSuccessEvidence: String
        let expectedFailureEvidence: String
        let transientSideEffect: String
        let markers: [Marker]
        let coveredSessionIdentifiers: [String]

        var boundaryProof: BoundaryProof {
            switch route {
            case .snapshotRead:
                .immutableSnapshot
            case .sourceTransaction:
                .sourceAction
            case .interactionTransaction:
                .interactionAction
            case .domainPlanner:
                .domainPlan
            case .mainActorTransient:
                .mainActorTransient
            }
        }
    }

    static let reachableSourceFiles = [
        "Sources/RupaUI/MainView.swift",
        "Sources/RupaUI/PatternArrayEditingService.swift",
        "Sources/RupaUI/PatternArrayExpressionWritebackService.swift",
        "Sources/RupaUI/PatternArrayInspectorView.swift",
        "Sources/RupaUI/SurfaceControlPointInspectorView.swift",
        "Sources/RupaUI/PatternArrayCurvePathPickService.swift",
        "Sources/RupaUI/WorkspaceLaunchSessionFactory.swift",
        "Sources/RupaUI/WorkspaceDomainCommandPanel.swift",
        "Sources/RupaUI/WorkspaceDomainCommandRow.swift",
        "Sources/RupaCore/EditorSession.swift",
        "Sources/RupaDomainFoundation/DomainCommandExecutor.swift",
    ]

    static let sourceCommandRows: [Row] = [
        "addSketchConstraint",
        "alignSketchVertex",
        "applySketchCornerTreatment",
        "chamferBodyEdges",
        "convertSketchLineToArc",
        "convertSketchLineToSpline",
        "createConstructionPlaneFromTargets",
        "createSavedView",
        "createViewAlignedConstructionPlane",
        "cutSketchCurve",
        "deleteBodyFaces",
        "deleteParameter",
        "draftBodyFaces",
        "extendSketchCurve",
        "filletBodyEdges",
        "insertSketchSplineControlPoint",
        "insertSurfaceKnot",
        "insertSurfaceTrimKnot",
        "joinSketchCurves",
        "matchSurfaceBoundaryContinuity",
        "moveBody",
        "moveBodyVertex",
        "movePolySplineSurfaceVertex",
        "moveSketchEntityPoint",
        "moveSketchSplineControlPoint",
        "moveSurfaceControlPoint",
        "moveSurfaceControlPointsInFrame",
        "moveSurfaceTrimControlPoint",
        "moveSurfaceTrimEndpoint",
        "offsetBodyFace",
        "offsetCurve",
        "offsetRegions",
        "offsetSketchVertex",
        "projectBodyOutlinesToConstructionPlane",
        "projectCurvesToGeneratedFace",
        "projectSketchCurvesToConstructionPlane",
        "rebaseWorkspaceOrigin",
        "rebuildSketchCurve",
        "removeSavedView",
        "renameConstructionPlane",
        "renameParameter",
        "resetDocument",
        "reverseSketchCurve",
        "setBridgeCurveParameters",
        "setComponentInstanceLock",
        "setComponentInstanceVisibility",
        "setConstructionPlane",
        "setCubeDimensions",
        "setCylinderDimensions",
        "setExtrudeDistance",
        "setObjectDimension",
        "setSceneNodeLock",
        "setSceneNodeMaterial",
        "setSceneNodeObjectProperty",
        "setSceneNodeTransform",
        "setSceneNodeVisibility",
        "setSketchArcParameters",
        "setSketchCircleParameters",
        "setSketchEntityDimension",
        "setSurfaceControlPointWeight",
        "setSurfaceKnotMultiplicity",
        "setSurfaceKnotValue",
        "setSurfaceTrimDomain",
        "setSurfaceTrimKnotMultiplicity",
        "setSurfaceTrimKnotValue",
        "slidePolySplineSurfaceVertices",
        "slideSketchSplineControlPoints",
        "slideSurfaceControlPoints",
        "splitSketchCurve",
        "splitSurfaceSpan",
        "trimSketchCurveSegment",
        "unjoinSketchCurve",
        "updatePatternArray",
        "updateSavedView",
        "upsertParameter",
    ].map(sourceCommandRow)

    static let sourceHelperRows: [Row] = [
        row(
            actionID: "projectWorkspace.source.helper.launchConstructionPlane",
            productionEntry: "WorkspaceLaunchSessionFactory.installActiveCustomConstructionPlane -> session.createConstructionPlane",
            inputOwner: "WorkspaceLaunchSessionFactory",
            route: .sourceTransaction,
            category: .sourceHelper,
            finalOperation: "EditorCommand.createConstructionPlane",
            plannerFixtureID: "fixture.source.helper.launchConstructionPlane",
            success: "launch fixture creates a construction-plane source and returns a selectable ID",
            failure: "fixture command rejection is reported and the session is not treated as installed",
            transient: "warning status is emitted on fixture failure",
            markers: [
                marker("Sources/RupaUI/WorkspaceLaunchSessionFactory.swift", #"\bsession\.createConstructionPlane\s*\("#),
            ],
            identifiers: ["createConstructionPlane"]
        ),
    ]

    static let canvasRows: [Row] = [
        row(
            actionID: "projectWorkspace.canvas.select",
            productionEntry: "MainView.handleViewportPick -> EditorSession.activateSelectedToolFromCanvas select branch",
            inputOwner: "ViewportCanvasTarget.selectionIntent",
            route: .interactionTransaction,
            category: .canvas,
            finalOperation: "selection replacement or clear",
            plannerFixtureID: "fixture.canvas.select",
            success: "selected scene-node IDs match the hit target and no source revision changes",
            failure: "unresolvable hit leaves selection and source revision unchanged",
            transient: "selection drag preview is cleared after the pick",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcase \.select\b"#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bselectSceneNode\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas"]
        ),
        row(
            actionID: "projectWorkspace.canvas.solid.existingProfile",
            productionEntry: "MainView.handleViewportPick -> activateSelectedToolFromCanvas(.solid) -> createDefaultSolid",
            inputOwner: "ViewportCanvasTarget.hit sketch profile",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.extrudeProfile",
            plannerFixtureID: "fixture.canvas.solid.existingProfile",
            success: "profile target produces a committed body and selected newest scene node",
            failure: "non-sketch target reports a typed diagnostic without committing a body",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcase \.solid\b"#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateDefaultSolid\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas"]
        ),
        row(
            actionID: "projectWorkspace.canvas.solid.rectangle",
            productionEntry: "MainView.handleViewportPick/Drag -> activateSelectedToolFromCanvas(Drag) -> rectangle solid",
            inputOwner: "ViewportCanvasTarget or ViewportModelDrag",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createExtrudedRectangleFromCorners",
            plannerFixtureID: "fixture.canvas.solid.rectangle",
            success: "finite canvas corners produce a committed rectangle solid",
            failure: "missing or invalid canvas coordinates leave the document unchanged",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas(?:Drag)?\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateExtrudedRectangleFromCanvas(?:Click|Drag)\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas", "activateSelectedToolFromCanvasDrag"]
        ),
        row(
            actionID: "projectWorkspace.canvas.sweep",
            productionEntry: "MainView.handleViewportPick -> activateSelectedToolFromCanvas(.sweep) -> createSweepFromSelection",
            inputOwner: "ViewportCanvasTarget sweep selection",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createSweep",
            plannerFixtureID: "fixture.canvas.sweep",
            success: "compatible section/path selection produces a committed sweep",
            failure: "incompatible or missing selection reports failure without publication",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcase \.sweep\b"#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateSweepFromSelection\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas"]
        ),
        row(
            actionID: "projectWorkspace.canvas.sketch",
            productionEntry: "MainView.handleViewportPick/Drag -> activateSelectedToolFromCanvas(Drag) -> rectangle sketch",
            inputOwner: "ViewportCanvasTarget or ViewportModelDrag",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createRectangleSketchFromCorners",
            plannerFixtureID: "fixture.canvas.sketch",
            success: "finite canvas input commits one rectangle sketch",
            failure: "unresolved projection or invalid input leaves the document unchanged",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas(?:Drag)?\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateRectangleSketchFromCanvas(?:Click|Drag)\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas", "activateSelectedToolFromCanvasDrag"]
        ),
        row(
            actionID: "projectWorkspace.canvas.polygon",
            productionEntry: "MainView.handleViewportPick/Drag -> activateSelectedToolFromCanvas(Drag) -> polygon sketch",
            inputOwner: "ViewportCanvasTarget or ViewportModelDrag",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createPolygonSketch",
            plannerFixtureID: "fixture.canvas.polygon",
            success: "normalized center/radius and side count commit a polygon sketch",
            failure: "invalid side count or projected point rejects the command",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas(?:Drag)?\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreatePolygonSketchFromCanvas(?:Click|Drag)\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas", "activateSelectedToolFromCanvasDrag"]
        ),
        row(
            actionID: "projectWorkspace.canvas.arc",
            productionEntry: "MainView.handleViewportPick/Drag -> activateSelectedToolFromCanvas(Drag) -> arc sketch",
            inputOwner: "ViewportCanvasTarget or ViewportModelDrag",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createArcSketch",
            plannerFixtureID: "fixture.canvas.arc",
            success: "finite center/radius input commits an arc sketch",
            failure: "invalid projected geometry rejects the arc without publication",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas(?:Drag)?\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateArcSketchFromCanvas(?:Click|Drag)\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas", "activateSelectedToolFromCanvasDrag"]
        ),
        row(
            actionID: "projectWorkspace.canvas.spline",
            productionEntry: "MainView.handleViewportPick/Drag -> activateSelectedToolFromCanvas(Drag) -> spline sketch",
            inputOwner: "ViewportCanvasTarget or ViewportModelDrag",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createSplineSketch",
            plannerFixtureID: "fixture.canvas.spline",
            success: "finite spline canvas input commits a spline sketch",
            failure: "invalid input reports failure and keeps generation/revision stable",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas(?:Drag)?\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateSplineSketchFromCanvas(?:Click|Drag)\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas", "activateSelectedToolFromCanvasDrag"]
        ),
        row(
            actionID: "projectWorkspace.canvas.surface",
            productionEntry: "MainView.handleViewportPick/Drag -> activateSelectedToolFromCanvas(Drag) -> circle sketch",
            inputOwner: "ViewportCanvasTarget or ViewportModelDrag",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createCircleSketch",
            plannerFixtureID: "fixture.canvas.surface",
            success: "finite center/radius input commits a circle sketch",
            failure: "invalid radius or projection rejects the command",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas(?:Drag)?\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateCircleSketchFromCanvas(?:Click|Drag)\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas", "activateSelectedToolFromCanvasDrag"]
        ),
        row(
            actionID: "projectWorkspace.canvas.section",
            productionEntry: "MainView.handleViewportPick -> activateSelectedToolFromCanvas(.section) -> createDefaultSectionPlane",
            inputOwner: "ViewportCanvasTarget.section tool",
            route: .sourceTransaction,
            category: .canvas,
            finalOperation: "EditorCommand.createSectionPlane",
            plannerFixtureID: "fixture.canvas.section",
            success: "section tool commits a section-plane scene node",
            failure: "command rejection leaves the document and selection unchanged",
            transient: "newest scene node is selected after a successful commit",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcase \.section\b"#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcreateDefaultSectionPlane\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas"]
        ),
        row(
            actionID: "projectWorkspace.canvas.measure",
            productionEntry: "MainView.handleViewportPick -> activateSelectedToolFromCanvas(.measure) -> reportMeasurementSummary",
            inputOwner: "ViewportCanvasTarget.measure tool",
            route: .snapshotRead,
            category: .canvas,
            finalOperation: "MeasurementService.read",
            plannerFixtureID: "fixture.canvas.measure",
            success: "measurement summary reflects current selection without a source revision",
            failure: "measurement failure is recorded as a diagnostic, not a source mutation",
            transient: "diagnostic panel is expanded for measurement findings",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcase \.measure\b"#),
                marker("Sources/RupaCore/EditorSession.swift", #"\breportMeasurementSummary\s*\("#),
            ],
            identifiers: ["activateSelectedToolFromCanvas"]
        ),
        row(
            actionID: "projectWorkspace.canvas.mesh",
            productionEntry: "MainView.handleViewportPick -> activateSelectedToolFromCanvas(.mesh) -> perform(.validateDocument)",
            inputOwner: "ViewportCanvasTarget.mesh tool",
            route: .snapshotRead,
            category: .canvas,
            finalOperation: "EditorCommand.validateDocument",
            plannerFixtureID: "fixture.canvas.mesh",
            success: "mesh validation reports evaluated diagnostics without changing source revision",
            failure: "validation failure remains a typed diagnostic and does not publish a mutation",
            transient: "diagnostic panel is expanded for mesh findings",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.activateSelectedToolFromCanvas\s*\("#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bcase \.mesh\b"#),
                marker("Sources/RupaCore/EditorSession.swift", #"\bperform\(\s*\.validateDocument\b"#),
            ],
            identifiers: ["activateSelectedToolFromCanvas"]
        ),
    ]

    static let patternArrayRows: [Row] = [
        row(
            actionID: "projectWorkspace.patternArray.inspector",
            productionEntry: "PatternArrayInspectorView editing control -> PatternArrayEditingService",
            inputOwner: "PatternArrayInspectorView",
            route: .sourceTransaction,
            category: .patternArray,
            finalOperation: "EditorCommand.updatePatternArray",
            plannerFixtureID: "fixture.patternArray.inspector",
            success: "inspector edit commits the selected Pattern Array while preserving source identity",
            failure: "missing source or invalid distribution returns nil and leaves the document unchanged",
            transient: "inspector result is cleared when the source revision changes",
            markers: [
                marker("Sources/RupaUI/PatternArrayInspectorView.swift", #"\beditingService\.(?:setOutputMode|setRectangular|setRadial|setCurvePath)"#),
                marker("Sources/RupaUI/PatternArrayEditingService.swift", #"\bsession\.updatePatternArray\s*\("#),
            ],
            identifiers: ["updatePatternArray"]
        ),
        row(
            actionID: "projectWorkspace.patternArray.expressionWriteback",
            productionEntry: "PatternArrayExpressionWritebackService.updateReferencedExpression -> session.perform(.upsertParameter)",
            inputOwner: "PatternArrayExpressionWritebackService",
            route: .sourceTransaction,
            category: .patternArray,
            finalOperation: "EditorCommand.upsertParameter",
            plannerFixtureID: "fixture.patternArray.expressionWriteback",
            success: "referenced parameter value is updated with the same parameter identity",
            failure: "unresolved or mismatched parameter is blocked and no source transaction is published",
            transient: "warning status is emitted for blocked writeback",
            markers: [
                marker("Sources/RupaUI/PatternArrayExpressionWritebackService.swift", #"\bsession\.perform\(\s*\.upsertParameter\b"#),
            ],
            identifiers: ["perform"]
        ),
        row(
            actionID: "projectWorkspace.patternArray.curvePathPick",
            productionEntry: "MainView.handlePatternArrayCurvePathPick -> PatternArrayCurvePathPickService.apply",
            inputOwner: "PatternArrayCurvePathPickService",
            route: .sourceTransaction,
            category: .patternArray,
            finalOperation: "EditorCommand.updatePatternArray",
            plannerFixtureID: "fixture.patternArray.curvePathPick",
            success: "valid curve target updates the selected Pattern Array path",
            failure: "non-curve or missing source returns a typed failed outcome",
            transient: "status message records applied or rejected path selection",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bPatternArrayCurvePathPickService\s*\("#),
                marker("Sources/RupaUI/PatternArrayCurvePathPickService.swift", #"\bPatternArrayEditingService\s*\("#),
            ],
            identifiers: ["updatePatternArray"]
        ),
    ]

    static let snapshotRows: [Row] = [
        "activeConstructionPlane",
        "activeSketchPlane",
        "currentEvaluation",
        "diagnostics",
        "document",
        "evaluatedBodyCount",
        "evaluatedGeneration",
        "evaluationSnapshot",
        "evaluationStatus",
        "generation",
        "isDirty",
        "objectRegistry",
        "renderInvalidation",
        "selection",
        "sweepSelectionPreview",
        "validateDocument",
        "workspaceState",
    ].map(snapshotRow)

    static let selectionRows: [Row] = [
        "clearSelection",
        "selectReferences",
        "selectSceneNodes",
        "selectTarget",
        "selectTargets",
    ].map { identifier in
        interactionRow(
            identifier: identifier,
            category: .selection,
            entry: "MainView selection interaction session.\(identifier)"
        )
    }

    static let navigationRows: [Row] = [
        interactionRow(
            identifier: "selectReference",
            category: .navigation,
            entry: "MainView surface basis navigation session.selectReference"
        ),
    ]

    static let workspaceRows: [Row] = [
        "setActiveConstructionPlane",
        "setCurveCurvatureDisplay",
        "setDisplayUnit",
        "setPointDisplay",
        "setRulerConfiguration",
        "setSurfaceControlPointDisplay",
        "setSurfaceFrameDisplay",
        "setViewportGridSettings",
    ].map { identifier in
        interactionRow(
            identifier: identifier,
            category: .workspace,
            entry: "MainView workspace control session.\(identifier)"
        )
    }

    static let transientRows: [Row] = [
        "activateSelectedToolFromCanvas",
        "activateSelectedToolFromCanvasDrag",
        "activateTool",
        "addSketchReferenceLineAnchor",
        "adjustPolygonSideCount",
        "focusNextSketchDimensionInput",
        "hoverReference",
        "hoverSceneNode",
        "hoverTarget",
        "polygonToolState",
        "reportToolStatus",
        "selectedTool",
        "setSketchDimensionInputAngle",
        "setSketchDimensionInputHeight",
        "setSketchDimensionInputLength",
        "setSketchDimensionInputWidth",
        "sketchInputState",
        "togglePolygonCutsFaces",
        "togglePolygonInclinationMode",
        "togglePolygonSizingMode",
        "toggleSketchAxisConstraint",
    ].map { identifier in
        row(
            actionID: "projectWorkspace.transient.\(identifier)",
            productionEntry: "MainView MainActor transient session.\(identifier)",
            inputOwner: "MainActorUI",
            route: .mainActorTransient,
            category: .transient,
            finalOperation: "MainActor transient state.\(identifier)",
            plannerFixtureID: "fixture.transient.\(identifier)",
            success: "transient state changes without source generation or transaction revision change",
            failure: "invalid transient input is rejected with status and no source publication",
            transient: "MainActor state is updated or cleared without persistence",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.\#(identifier)\b"#),
            ],
            identifiers: [identifier]
        )
    }

    static let domainRows: [Row] = [
        row(
            actionID: "projectWorkspace.domain.dispatch",
            productionEntry: "MainView.workspaceUtilityRail -> DomainCommandExecutor.execute(request, in: session)",
            inputOwner: "WorkspaceDomainCommandRow",
            route: .domainPlanner,
            category: .domain,
            finalOperation: "DomainCommandPlan dispatch",
            plannerFixtureID: "fixture.domain.dispatch",
            success: "lowered plan is validated against capability effect before execution",
            failure: "invalid capability, namespace, effect, or revision returns a typed domain error",
            transient: "domain panel shows result or error without bypassing MainView state",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bdomainCommandExecutor\.execute\(\s*request,\s*in:\s*session\s*\)"#),
                marker("Sources/RupaUI/WorkspaceDomainCommandRow.swift", #"\bWorkspaceDomainCommandPanel\s*\("#),
                marker("Sources/RupaUI/WorkspaceDomainCommandPanel.swift", #"\bresult\s*=\s*try\s*execute\(request\)"#),
            ],
            identifiers: ["execute"]
        ),
        row(
            actionID: "projectWorkspace.domain.generationGuard",
            productionEntry: "DomainCommandExecutor.executeDocumentTransaction -> session.store.requireGeneration",
            inputOwner: "DomainCommandExecutor",
            route: .domainPlanner,
            category: .domain,
            finalOperation: "DomainDocumentTransaction generation guard",
            plannerFixtureID: "fixture.domain.generationGuard",
            success: "transaction starts only at the requested document generation",
            failure: "stale generation is rejected before staged state is changed",
            transient: "domain panel receives the typed failure",
            markers: [
                marker("Sources/RupaDomainFoundation/DomainCommandExecutor.swift", #"\bsession\.store\.requireGeneration\s*\("#),
            ],
            identifiers: ["store"]
        ),
        row(
            actionID: "projectWorkspace.domain.revisionGuard",
            productionEntry: "DomainCommandExecutor -> session.requireTransactionRevision",
            inputOwner: "DomainCommandExecutor",
            route: .domainPlanner,
            category: .domain,
            finalOperation: "Domain transaction revision guard",
            plannerFixtureID: "fixture.domain.revisionGuard",
            success: "request revision is checked before both query and document transaction paths",
            failure: "stale transaction revision returns a typed error without publication",
            transient: "domain panel displays the revision conflict",
            markers: [
                marker("Sources/RupaDomainFoundation/DomainCommandExecutor.swift", #"\bsession\.requireTransactionRevision\s*\("#),
            ],
            identifiers: ["requireTransactionRevision"]
        ),
        row(
            actionID: "projectWorkspace.domain.isolatedTransaction",
            productionEntry: "DomainCommandExecutor.executeDocumentTransaction -> session.executeIsolatedSourceTransaction",
            inputOwner: "DomainCommandExecutor",
            route: .domainPlanner,
            category: .domain,
            finalOperation: "ProjectSourceTransaction isolated commit",
            plannerFixtureID: "fixture.domain.isolatedTransaction",
            success: "source commands and semantic mutations publish as one staged transaction",
            failure: "any staged command failure discards the staged session and preserves the live session",
            transient: "domain panel receives only the committed result or typed failure",
            markers: [
                marker("Sources/RupaDomainFoundation/DomainCommandExecutor.swift", #"\bsession\.executeIsolatedSourceTransaction\s*\("#),
            ],
            identifiers: ["executeIsolatedSourceTransaction"]
        ),
        row(
            actionID: "projectWorkspace.domain.revisionRead",
            productionEntry: "DomainCommandExecutor.execute -> session.transactionRevision",
            inputOwner: "DomainCommandExecutor",
            route: .domainPlanner,
            category: .domain,
            finalOperation: "Domain execution revision observation",
            plannerFixtureID: "fixture.domain.revisionRead",
            success: "base and current transaction revisions are compared in the execution result",
            failure: "inconsistent revision identity returns a typed command failure",
            transient: "domain panel does not publish an inconsistent result",
            markers: [
                marker("Sources/RupaDomainFoundation/DomainCommandExecutor.swift", #"\bsession\.transactionRevision\b"#),
            ],
            identifiers: ["transactionRevision"]
        ),
    ]

    static let rows: [Row] =
        sourceCommandRows
        + sourceHelperRows
        + canvasRows
        + patternArrayRows
        + snapshotRows
        + selectionRows
        + navigationRows
        + workspaceRows
        + transientRows
        + domainRows

    static let directCommandNames: Set<String> = [
        "createSavedView",
        "deleteParameter",
        "removeSavedView",
        "renameParameter",
        "updateSavedView",
        "upsertParameter",
    ]

    static let expectedSessionIdentifierCount = 128
    static let expectedSourceCommandCount = 75

    static func observedSessionIdentifiers(filePath: String = #filePath) throws -> Set<String> {
        let source = try sourceContents(filePath: filePath)
        let expression = try NSRegularExpression(
            pattern: #"\bsession\.([A-Za-z_][A-Za-z0-9_]*)"#
        )
        var identifiers = Set<String>()
        for (relativePath, contents) in source {
            let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)
            for match in expression.matches(in: contents, range: range) {
                guard let identifierRange = Range(match.range(at: 1), in: contents) else {
                    throw SourceAuditError.invalidMatch(relativePath)
                }
                identifiers.insert(String(contents[identifierRange]))
            }
        }
        return identifiers
    }

    static func observedDirectCommandNames(filePath: String = #filePath) throws -> Set<String> {
        let source = try sourceContents(filePath: filePath)
        let expression = try NSRegularExpression(
            pattern: #"\bsession\.(?:execute|perform)\(\s*\.([A-Za-z_][A-Za-z0-9_]*)"#
        )
        var names = Set<String>()
        for (relativePath, contents) in source {
            let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)
            for match in expression.matches(in: contents, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: contents) else {
                    throw SourceAuditError.invalidMatch(relativePath)
                }
                names.insert(String(contents[nameRange]))
            }
        }
        return names
    }

    static func missingMarkers(filePath: String = #filePath) throws -> [String] {
        let source = try sourceContents(filePath: filePath)
        var missing: [String] = []
        for row in rows {
            for marker in row.markers {
                guard let contents = source[marker.relativePath] else {
                    missing.append("\(row.actionID):\(marker.relativePath)")
                    continue
                }
                let expression = try NSRegularExpression(pattern: marker.regularExpression)
                let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)
                if expression.numberOfMatches(in: contents, range: range) == 0 {
                    missing.append("\(row.actionID):\(marker.relativePath):\(marker.regularExpression)")
                }
            }
        }
        return missing
    }

    private static func sourceCommandRow(_ name: String) -> Row {
        let markers: [Marker]
        let identifiers: [String]
        let entry: String
        switch name {
        case "createSavedView", "updateSavedView", "removeSavedView":
            markers = [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.execute\(\s*\.\#(name)\b"#),
            ]
            identifiers = ["execute"]
            entry = "MainView saved-view action -> session.execute(.\(name))"
        case "renameParameter":
            markers = [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.execute\(\s*\.\#(name)\b"#),
            ]
            identifiers = ["execute"]
            entry = "MainView parameter action -> session.execute(.renameParameter)"
        case "deleteParameter":
            markers = [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.perform\(\s*\.\#(name)\b"#),
            ]
            identifiers = ["perform"]
            entry = "MainView parameter action -> session.perform(.deleteParameter)"
        case "upsertParameter":
            markers = [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.perform\(\s*\.\#(name)\b"#),
                marker("Sources/RupaUI/PatternArrayExpressionWritebackService.swift", #"\bsession\.perform\(\s*\.\#(name)\b"#),
            ]
            identifiers = ["perform"]
            entry = "MainView and PatternArrayExpressionWritebackService -> session.perform(.upsertParameter)"
        case "updatePatternArray":
            markers = [
                marker("Sources/RupaUI/PatternArrayEditingService.swift", #"\bsession\.updatePatternArray\s*\("#),
            ]
            identifiers = ["updatePatternArray"]
            entry = "PatternArrayEditingService -> session.updatePatternArray"
        default:
            markers = [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.\#(name)\s*\("#),
            ]
            identifiers = [name]
            entry = "MainView -> session.\(name)"
        }
        return row(
            actionID: "projectWorkspace.source.editorCommand.\(name)",
            productionEntry: entry,
            inputOwner: "ProjectWorkspace.sourcePlanner",
            route: .sourceTransaction,
            category: .sourceCommand,
            finalOperation: "EditorCommand.\(name)",
            plannerFixtureID: "fixture.source.editorCommand.\(name)",
            success: "\(name) returns a committed command result and advances the source revision when it mutates",
            failure: "\(name) returns its typed command failure and leaves the live source unchanged",
            transient: "none",
            markers: markers,
            identifiers: identifiers
        )
    }

    private static func snapshotRow(_ identifier: String) -> Row {
        let markerValue: Marker
        let productionEntry: String
        if identifier == "evaluationSnapshot" {
            markerValue = marker(
                "Sources/RupaDomainFoundation/DomainCommandExecutor.swift",
                #"\bsession\.evaluationSnapshot\b"#
            )
            productionEntry = "DomainCommandExecutor query context session.evaluationSnapshot"
        } else if identifier == "validateDocument" {
            markerValue = marker("Sources/RupaUI/MainView.swift", #"\bsession\.validateDocument\s*\("#)
            productionEntry = "MainView snapshot read session.validateDocument"
        } else {
            markerValue = marker("Sources/RupaUI/MainView.swift", #"\bsession\.\#(identifier)\b"#)
            productionEntry = "MainView snapshot read session.\(identifier)"
        }
        return row(
            actionID: "projectWorkspace.snapshot.\(identifier)",
            productionEntry: productionEntry,
            inputOwner: "ProjectViewSnapshot",
            route: .snapshotRead,
            category: .snapshot,
            finalOperation: "snapshot.\(identifier)",
            plannerFixtureID: "fixture.snapshot.\(identifier)",
            success: "\(identifier) reflects the current immutable session snapshot",
            failure: "\(identifier) read failure is explicit and does not publish a source mutation",
            transient: "none",
            markers: [markerValue],
            identifiers: [identifier]
        )
    }

    private static func interactionRow(
        identifier: String,
        category: Category,
        entry: String
    ) -> Row {
        row(
            actionID: "projectWorkspace.\(category.rawValue).\(identifier)",
            productionEntry: entry,
            inputOwner: category == .workspace
                ? "ProjectWorkspace.interactionPlanner"
                : "ProjectWorkspace.selectionPlanner",
            route: .interactionTransaction,
            category: category,
            finalOperation: "interaction.\(identifier)",
            plannerFixtureID: "fixture.\(category.rawValue).\(identifier)",
            success: "\(identifier) updates the intended interaction state without changing CAD source identity",
            failure: "\(identifier) rejects invalid or stale input and preserves the prior interaction state",
            transient: "MainActor interaction state is updated and transient preview is cleared when required",
            markers: [
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.\#(identifier)\s*\("#),
                marker("Sources/RupaUI/MainView.swift", #"\bsession\.\#(identifier)\b"#),
            ],
            identifiers: [identifier]
        )
    }

    private static func row(
        actionID: String,
        productionEntry: String,
        inputOwner: String,
        route: Route,
        category: Category,
        finalOperation: String,
        plannerFixtureID: String,
        success: String,
        failure: String,
        transient: String,
        markers: [Marker],
        identifiers: [String]
    ) -> Row {
        Row(
            actionID: actionID,
            productionEntry: productionEntry,
            inputOwner: inputOwner,
            route: route,
            category: category,
            finalOperation: finalOperation,
            plannerFixtureID: plannerFixtureID,
            expectedSuccessEvidence: success,
            expectedFailureEvidence: failure,
            transientSideEffect: transient,
            markers: markers,
            coveredSessionIdentifiers: identifiers
        )
    }

    private static func marker(_ relativePath: String, _ regularExpression: String) -> Marker {
        Marker(relativePath: relativePath, regularExpression: regularExpression)
    }

    private static func sourceContents(filePath: String) throws -> [String: String] {
        let root = try repositoryRoot(filePath: filePath)
        var contents: [String: String] = [:]
        for relativePath in reachableSourceFiles {
            let url = root.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SourceAuditError.sourceFileNotFound(relativePath)
            }
            contents[relativePath] = try String(contentsOf: url, encoding: .utf8)
        }
        return contents
    }

    private static func repositoryRoot(filePath: String) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw SourceAuditError.repositoryRootNotFound(filePath)
    }

    private enum SourceAuditError: Error {
        case repositoryRootNotFound(String)
        case sourceFileNotFound(String)
        case invalidMatch(String)
    }
}
