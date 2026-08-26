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
        case canvas
        case patternArray
        case snapshot
        case selection
        case navigation
        case workspace
        case transient
        case domain
    }

    enum BoundaryProof: String, CaseIterable, Hashable, Sendable {
        case immutableSnapshot
        case sourceAction
        case interactionAction
        case domainPlan
        case mainActorTransient
    }

    struct Marker: Hashable, Sendable {
        let relativePaths: [String]
        let regularExpression: String
    }

    struct Row: Hashable, Sendable {
        let actionID: String
        let productionEntry: String
        let inputOwner: String
        let route: Route
        let category: Category
        let finalOperation: String
        let expectedSuccessEvidence: String
        let expectedFailureEvidence: String
        let transientSideEffect: String
        let markers: [Marker]

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

    static let sourceMutationFiles = [
        "Sources/RupaUI/MainView.swift",
        "Sources/RupaUI/PatternArrayEditingService.swift",
        "Sources/RupaUI/PatternArrayExpressionWritebackService.swift",
        "Sources/RupaUI/PatternArrayCurvePathPickService.swift",
        "Sources/RupaUI/WorkspaceLaunchProjectFixture.swift",
        "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift",
        "Sources/RupaCore/SweepSelectionPlanningService.swift",
    ]

    static let productionSourceDirectories = [
        "Sources/RupaUI",
        "Sources/RupaKit",
        "Sources/RupaRendering",
        "Sources/RupaViewportScene",
        "../Rupa/Rupa/Rupa",
    ]

    static let legacyExcludedSourceFiles: Set<String> = []

    static let forbiddenProductionReferences = [
        "EditorSession",
        "session.",
        "WorkspaceLaunchSessionFactory",
        "WorkspaceAgentSessionPublication",
    ]

    static let sourceCommandNames = [
        "addSketchConstraint",
        "alignSketchVertex",
        "applySketchCornerTreatment",
        "chamferBodyEdges",
        "convertSketchLineToArc",
        "convertSketchLineToSpline",
        "createConstructionPlane",
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
        "validateDocument",
    ]

    static let canvasEditorCommandNames = [
        "createArcSketch",
        "createCircleSketch",
        "createExtrudedRectangleFromCorners",
        "createFaceKnife",
        "createPolygonSketch",
        "createRectangleSketchFromCorners",
        "createSectionPlane",
        "createSplineSketch",
        "createSweep",
        "extrudeProfile",
    ]

    static var declaredProductionEditorCommandNames: Set<String> {
        Set(sourceCommandNames).union(canvasEditorCommandNames)
    }

    static let editorCommandLookalikes: [String: [String: String]] = [
        "Sources/RupaUI/WorkspaceKeyboardRouter.swift": [
            "createConstructionPlane": #"^\s*return\s+\.createConstructionPlane\s*\($"#,
        ],
    ]

    static let sourceCommandRows = sourceCommandNames.map(sourceCommandRow)

    static let canvasRows: [Row] = [
        routeRow("canvas.select", "MainView.handlePresentationOccurrencePick", .interactionTransaction, .canvas, "ProjectWorkspace.applySelection", "Sources/RupaUI/MainView.swift", #"\bhandlePresentationOccurrencePick\b"#),
        routeRow(
            "canvas.selectRectangle",
            "MainView presentation rectangle selection",
            .interactionTransaction,
            .canvas,
            "ProjectWorkspace.applySelection",
            "Sources/RupaUI/MainView.swift",
            #"mergedSelectionTargets[\s\S]*?presentationOccurrenceIDs"#,
            additionalMarkers: [
                Marker(
                    relativePaths: ["Sources/RupaUI/MainView.swift"],
                    regularExpression: #"selectionDragPreviewSceneNodeIDs\s*=\s*Set\(targets\.compactMap[\s\S]*?case\s+\.object"#
                ),
            ]
        ),
        routeRow(
            "canvas.hoverPresentation",
            "MainView presentation occurrence hover",
            .mainActorTransient,
            .canvas,
            "MainActor hovered target",
            "Sources/RupaUI/MainView.swift",
            #"\bhandlePresentationOccurrenceHover\b"#,
            additionalMarkers: [
                Marker(
                    relativePaths: ["Sources/RupaUI/MainView.swift"],
                    regularExpression: #"selection:\s*displaySelection"#
                ),
                Marker(
                    relativePaths: ["Sources/RupaUI/MainView.swift"],
                    regularExpression: #"objectSelectionIndex:\s*viewportObjectSelectionIndex"#
                ),
            ]
        ),
        routeRow("canvas.cadSubshapeGate", "MainView exact presentation CAD context", .snapshotRead, .canvas, "MeshSourcePresentationCADAffordanceResolver", "Sources/RupaUI/MainView.swift", #"\bexactPresentationCADSceneNodeIDs\b"#),
        routeRow("canvas.sketch", "WorkspaceCanvasCommandPlanner rectangle", .sourceTransaction, .canvas, "EditorCommand.createRectangleSketchFromCorners", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\brectangleCommand\b"#),
        routeRow("canvas.solid", "WorkspaceCanvasCommandPlanner solid", .sourceTransaction, .canvas, "EditorCommand.extrudeProfile or createExtrudedRectangleFromCorners", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\bsolidCommand\b"#),
        routeRow("canvas.polygon", "WorkspaceCanvasCommandPlanner polygon", .sourceTransaction, .canvas, "EditorCommand.createPolygonSketch", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\bpolygonCommand\b"#),
        routeRow("canvas.polygonKnife", "WorkspaceCanvasCommandPlanner face knife", .sourceTransaction, .canvas, "EditorCommand.splitBodyFaceWithSketch", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\bfaceKnifeCommand\b"#),
        routeRow("canvas.arc", "WorkspaceCanvasCommandPlanner arc", .sourceTransaction, .canvas, "EditorCommand.createArcSketch", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\barcCommand\b"#),
        routeRow("canvas.spline", "WorkspaceCanvasCommandPlanner spline", .sourceTransaction, .canvas, "EditorCommand.createSplineSketch", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\bsplineCommand\b"#),
        routeRow("canvas.surface", "WorkspaceCanvasCommandPlanner circle", .sourceTransaction, .canvas, "EditorCommand.createCircleSketch", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\bcircleClickCommand\b"#),
        routeRow("canvas.sweep", "SweepSelectionPlanningService", .sourceTransaction, .canvas, "EditorCommand.createSweep", "Sources/RupaCore/SweepSelectionPlanningService.swift", #"\bcommand\s*\("#),
        routeRow("canvas.section", "WorkspaceCanvasCommandPlanner section", .sourceTransaction, .canvas, "EditorCommand.createSectionPlane", "Sources/RupaUI/WorkspaceCanvasCommandPlanner.swift", #"\.createSectionPlane\s*\("#),
        routeRow("canvas.measure.selection", "MainView measurement target selection", .interactionTransaction, .canvas, "ProjectWorkspace.applySelection", "Sources/RupaUI/MainView.swift", #"measureCanvasTarget[\s\S]*?workspace\.applySelection\(\.replace\(selection\)\)"#),
        routeRow("canvas.measure.read", "MainView immutable measurement", .snapshotRead, .canvas, "MeasurementService", "Sources/RupaUI/MainView.swift", #"measureCanvasTarget[\s\S]*?MeasurementService\(\)\.measure"#),
        routeRow("canvas.mesh.selection", "MainView mesh target selection", .interactionTransaction, .canvas, "ProjectWorkspace.applySelection", "Sources/RupaUI/MainView.swift", #"inspectCanvasMesh[\s\S]*?workspace\.applySelection\(\.replace\(selection\)\)"#),
        routeRow("canvas.mesh.read", "MainView immutable mesh summary", .snapshotRead, .canvas, "MeshSummaryService", "Sources/RupaUI/MainView.swift", #"inspectCanvasMesh[\s\S]*?MeshSummaryService\(\)\.summarize"#),
    ]

    static let patternArrayRows: [Row] = [
        routeRow("pattern.edit", "PatternArrayEditingService", .sourceTransaction, .patternArray, "EditorCommand.updatePatternArray", "Sources/RupaUI/PatternArrayEditingService.swift", #"\.updatePatternArray\s*\("#),
        routeRow("pattern.expression", "PatternArrayExpressionWritebackService", .sourceTransaction, .patternArray, "EditorCommand.upsertParameter", "Sources/RupaUI/PatternArrayExpressionWritebackService.swift", #"\.upsertParameter\s*\("#),
        routeRow("pattern.pathPick", "PatternArrayCurvePathPickService", .sourceTransaction, .patternArray, "EditorCommand.updatePatternArray", "Sources/RupaUI/PatternArrayCurvePathPickService.swift", #"\.updatePatternArray\s*\("#),
    ]

    static let snapshotRows = [
        "document", "documentGeneration", "transactionRevision", "publicationSequence",
        "evaluationSnapshot", "viewport", "cadInteraction", "selection", "workspaceState",
    ].map(snapshotRow)

    static let selectionRows: [Row] = [
        routeRow("selection.replace", "MainView.submitSelection", .interactionTransaction, .selection, "ProjectWorkspace.applySelection", "Sources/RupaUI/MainView.swift", #"workspace\.applySelection\s*\(\.replace"#),
        routeRow("selection.clear", "MainView.clearSelection", .interactionTransaction, .selection, "ProjectWorkspace.applySelection", "Sources/RupaUI/MainView.swift", #"workspace\.applySelection\s*\(\.clear"#),
        routeRow("selection.occurrence", "MainView.handlePresentationOccurrencePick", .interactionTransaction, .selection, "SelectionTarget scene-node navigation", "Sources/RupaUI/MainView.swift", #"snapshot\.sceneNodeID\s*\(for:"#),
    ]

    static let navigationRows: [Row] = [
        routeRow("navigation.occurrence", "ProjectViewSnapshot.sceneNodeID", .snapshotRead, .navigation, "sceneNodeIDByOccurrenceID", "Sources/RupaKit/ProjectViewSnapshot.swift", #"sceneNodeIDByOccurrenceID\[occurrenceID\]"#),
    ]

    static let workspaceRows: [Row] = [
        routeRow("workspace.single", "MainView.applyWorkspace", .interactionTransaction, .workspace, "ProjectWorkspace.applyWorkspace", "Sources/RupaUI/MainView.swift", #"private func applyWorkspace\s*\(\s*_ command:"#),
        routeRow("workspace.batch", "MainView.applyWorkspace batch", .interactionTransaction, .workspace, "ProjectWorkspace.applyWorkspace", "Sources/RupaUI/MainView.swift", #"private func applyWorkspace\s*\(\s*_ commands:"#),
    ]

    static let transientRows = [
        "selectedTool", "hoveredTarget", "selectionDragPreviewTargets", "isWorkspaceFocused", "viewportCameraFrame",
    ].map(transientRow)

    static let domainRows: [Row] = [
        routeRow("domain.dispatch", "ProjectDomainCommandDispatcher.dispatch", .domainPlanner, .domain, "typed ProjectDomainCommandPlan", "Sources/RupaUI/MainView.swift", #"domainCommandDispatcher\.dispatch\s*\("#),
        routeRow("domain.execute", "ProjectWorkspace.execute", .domainPlanner, .domain, "ProjectWorkspace.execute", "Sources/RupaUI/MainView.swift", #"workspace\.execute\s*\("#),
    ]

    static let rows = sourceCommandRows
        + canvasRows
        + patternArrayRows
        + snapshotRows
        + selectionRows
        + navigationRows
        + workspaceRows
        + transientRows
        + domainRows

    static func missingMarkers(filePath: String = #filePath) throws -> [String] {
        let contents = try sourceContents(filePath: filePath)
        var missing: [String] = []
        for row in rows {
            for marker in row.markers {
                let expression = try NSRegularExpression(pattern: marker.regularExpression)
                let matched = marker.relativePaths.contains { relativePath in
                    guard let source = contents[relativePath] else {
                        return false
                    }
                    let range = NSRange(source.startIndex..<source.endIndex, in: source)
                    return expression.firstMatch(in: source, range: range) != nil
                }
                if matched == false {
                    missing.append("\(row.actionID):\(marker.regularExpression)")
                }
            }
        }
        return missing
    }

    static func forbiddenReferenceMatches(filePath: String = #filePath) throws -> [String] {
        let contents = try sourceContents(filePath: filePath)
        var matches: [String] = []
        for (relativePath, source) in contents {
            for forbidden in forbiddenProductionReferences where source.contains(forbidden) {
                matches.append("\(relativePath):\(forbidden)")
            }
        }
        return matches.sorted()
    }

    static func detectedProductionEditorCommandNames(
        filePath: String = #filePath
    ) throws -> Set<String> {
        let root = try repositoryRoot(filePath: filePath)
        let editorCommandURL = root.appendingPathComponent("Sources/RupaCore/EditorCommand.swift")
        let editorCommandSource = try String(contentsOf: editorCommandURL, encoding: .utf8)
        let caseExpression = try NSRegularExpression(
            pattern: #"(?m)^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)"#
        )
        let sourceRange = NSRange(editorCommandSource.startIndex..<editorCommandSource.endIndex, in: editorCommandSource)
        let commandNames: [String] = caseExpression.matches(
            in: editorCommandSource,
            range: sourceRange
        ).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: editorCommandSource) else {
                return nil
            }
            return String(editorCommandSource[range])
        }
        let commandExpressions = try commandNames.map { commandName in
            let suffix = commandName == "validateDocument" ? #"\b"# : #"\s*\("#
            return (
                commandName,
                try NSRegularExpression(pattern: #"\.\#(commandName)\#(suffix)"#)
            )
        }

        var detected: Set<String> = []
        for (relativePath, source) in try sourceContents(filePath: filePath) {
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("case .") == false else {
                    continue
                }
                let sourceLine = String(line)
                let range = NSRange(sourceLine.startIndex..<sourceLine.endIndex, in: sourceLine)
                for (commandName, expression) in commandExpressions {
                    if expression.firstMatch(in: sourceLine, range: range) != nil {
                        if let lookalikePattern = editorCommandLookalikes[relativePath]?[commandName],
                           sourceLine.range(of: lookalikePattern, options: .regularExpression) != nil {
                            continue
                        }
                        detected.insert(commandName)
                    }
                }
            }
        }
        return detected
    }

    static func auditedProductionSourceFiles(filePath: String = #filePath) throws -> [String] {
        let root = try repositoryRoot(filePath: filePath)
        var result: [String] = []
        for relativeDirectory in productionSourceDirectories {
            let directory = root.appendingPathComponent(relativeDirectory).standardizedFileURL
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw SourceAuditError.sourceDirectoryNotFound(relativeDirectory)
            }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let fileName = String(url.path.dropFirst(directory.path.count + 1))
                let relativePath = relativeDirectory.hasPrefix("../")
                    ? "\(relativeDirectory)/\(fileName)"
                    : String(url.path.dropFirst(root.path.count + 1))
                if legacyExcludedSourceFiles.contains(relativePath) == false {
                    result.append(relativePath)
                }
            }
        }
        return Array(Set(result).union(sourceMutationFiles)).sorted()
    }

    private static func sourceCommandRow(_ name: String) -> Row {
        let commandExpression = name == "validateDocument"
            ? #"\.validateDocument\b"#
            : #"\.\#(name)\s*\("#
        var markers = [
            Marker(
                relativePaths: sourceMutationFiles,
                regularExpression: commandExpression
            ),
        ]
        if name == "moveBody" {
            markers.append(
                Marker(
                    relativePaths: ["Sources/RupaUI/MainView.swift"],
                    regularExpression: #"\.moveBody\s*\(\s*target:\s*target\.target"#
                )
            )
        }
        return Row(
            actionID: "source.\(name)",
            productionEntry: "MainView or production helper creates EditorCommand.\(name)",
            inputOwner: "ProjectViewSnapshot and transient UI input",
            route: .sourceTransaction,
            category: .sourceCommand,
            finalOperation: "ProjectWorkspace.perform source action",
            expectedSuccessEvidence: "The command is staged, evaluated, packaged, and published atomically.",
            expectedFailureEvidence: "A typed failure preserves the previously published project view.",
            transientSideEffect: "Only diagnostics and command-specific transient UI state may change.",
            markers: markers
        )
    }

    private static func snapshotRow(_ property: String) -> Row {
        Row(
            actionID: "snapshot.\(property)",
            productionEntry: "Project UI boundary reads ProjectViewSnapshot.\(property)",
            inputOwner: "ProjectViewSnapshot",
            route: .snapshotRead,
            category: .snapshot,
            finalOperation: "immutable snapshot read",
            expectedSuccessEvidence: "The published immutable value is read without a shadow authority.",
            expectedFailureEvidence: "Stale coordinates are rejected by the project boundary.",
            transientSideEffect: "No authoritative shadow state is retained by MainView.",
            markers: [
                Marker(
                    relativePaths: [
                        "Sources/RupaUI/MainView.swift",
                        "Sources/RupaKit/DefaultProjectWorkspaceActionPlanner.swift",
                    ],
                    regularExpression: #"snapshot\.\#(property)\b"#
                ),
            ]
        )
    }

    private static func transientRow(_ property: String) -> Row {
        routeRow(
            "transient.\(property)",
            "MainView owns \(property)",
            .mainActorTransient,
            .transient,
            "MainActor transient state",
            "Sources/RupaUI/MainView.swift",
            #"@(State|FocusState) private var \#(property)\b"#
        )
    }

    private static func routeRow(
        _ actionID: String,
        _ productionEntry: String,
        _ route: Route,
        _ category: Category,
        _ finalOperation: String,
        _ relativePath: String,
        _ regularExpression: String,
        additionalMarkers: [Marker] = []
    ) -> Row {
        Row(
            actionID: actionID,
            productionEntry: productionEntry,
            inputOwner: route == .mainActorTransient ? "MainActor UI" : "ProjectViewSnapshot",
            route: route,
            category: category,
            finalOperation: finalOperation,
            expectedSuccessEvidence: "The action reaches its declared authority boundary.",
            expectedFailureEvidence: "Invalid or stale input is rejected without partial publication.",
            transientSideEffect: route == .mainActorTransient ? "The named UI state changes locally." : "No authoritative shadow state is retained by MainView.",
            markers: [
                Marker(relativePaths: [relativePath], regularExpression: regularExpression),
            ] + additionalMarkers
        )
    }

    private static func sourceContents(filePath: String) throws -> [String: String] {
        let root = try repositoryRoot(filePath: filePath)
        var contents: [String: String] = [:]
        for relativePath in try auditedProductionSourceFiles(filePath: filePath) {
            let url = root.appendingPathComponent(relativePath).standardizedFileURL
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
        case sourceDirectoryNotFound(String)
        case sourceFileNotFound(String)
    }
}
