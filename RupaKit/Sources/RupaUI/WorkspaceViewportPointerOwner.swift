import RupaCore
import RupaRendering

/// A running command that takes the viewport's clicks, in the order a click reaches them.
enum WorkspaceViewportPickingCommand: Equatable, Sendable {
    /// A view-aligned construction plane placed at the clicked point, under any tool.
    case viewAlignedConstructionPlane
    /// A command that acts on each clicked curve (Trim, Split Segment, Insert Knot, Bridge Curve).
    case curvePick
    case cutCurve
    case boolean
    case bodyCut
    case deform
    /// Freestyle Offset: a click sets the offset distance through the snapped point.
    case freestyleOffset
    /// A constrained-surface draft: a click appends a world point, under any tool.
    case constrainedSurfacePoints
}

/// A way the viewport lets a press edit the model directly, named by what it edits.
///
/// Each affordance belongs to the selection scopes it edits in; `WorkspaceViewportPointerOwner`
/// decides whether any is live. The workspace offers the viewport an affordance's handler only
/// when the owner allows it, and checks the owner again when the drag commits, so a press can
/// never reach an edit that the click routing would not.
enum WorkspaceViewportAffordance: CaseIterable, Sendable {
    /// A click on an object's presentation selects it; hovering highlights it.
    case objectSelection
    /// The selected bodies' move, rotate and scale gizmo. A running Move, Rotate or Scale owns
    /// it, so it stays live under a command that takes clicks (Boolean moving its tools).
    case objectPlacement
    /// The selected box body's resize handles.
    case objectHandles
    /// A selected face's arrow: dragging offsets the face.
    case faceOffset
    /// A selected edge's fillet and chamfer handles.
    case edgeTreatment
    /// A selected open boundary edge's surface affordance: a click starts a boundary surface.
    case boundarySurface
    /// A selected body vertex, poly-spline vertex, surface control point, trim point or surface
    /// frame: dragging moves it (or slides it while Slide runs).
    case bodyVertexEditing
    /// Offset Region's distance handle on the selected regions.
    case regionOffset
    /// Offset Edge's distance handle on the selected edges.
    case edgeOffset
    /// Slot's width and Offset Planar Curve's distance handle on the selected curve.
    case slotWidth
    /// A selected sketch entity's handles: curve and point handles, dimensions, spline control
    /// points, bridge-curve ends and Offset Vertex's distance.
    case sketchEntityEditing
    /// A selected feature's parameter handles: an independent copy's extrusion distance and
    /// body dimensions, a pattern array's spacing, count, extent, path and output mode.
    case featureParameters
    /// The selected construction plane's move and rotate handles.
    case constructionPlane

    /// The selection scopes the affordance edits in.
    var scopes: Set<WorkspaceSelectionScope> {
        switch self {
        case .objectSelection, .objectPlacement, .objectHandles:
            return [.object]
        case .faceOffset:
            return [.face]
        case .edgeTreatment, .boundarySurface:
            return [.edge, .object]
        case .bodyVertexEditing:
            return [.vertex]
        case .regionOffset:
            return [.region]
        case .edgeOffset:
            return [.edge]
        case .slotWidth, .sketchEntityEditing:
            return [.sketchEntity]
        case .featureParameters, .constructionPlane:
            return Set(WorkspaceSelectionScope.allCases)
        }
    }

    /// The picking command whose own value the affordance drags, which it therefore stays live
    /// under; every other affordance stands down while a command takes the clicks.
    var owningPickingCommand: WorkspaceViewportPickingCommand? {
        switch self {
        case .slotWidth:
            return .freestyleOffset
        case .objectSelection, .objectPlacement, .objectHandles, .faceOffset, .edgeTreatment,
             .boundarySurface, .bodyVertexEditing, .regionOffset, .edgeOffset,
             .sketchEntityEditing, .featureParameters, .constructionPlane:
            return nil
        }
    }
}

/// Who a press in the viewport belongs to.
///
/// One value answers both what a click resolves to (`hitPolicy`) and which affordances a press can
/// reach (`allows(_:)`), so the hit test, the selection and the handles cannot disagree: while a
/// command takes the clicks, a click on a selected body reaches the command rather than a handle.
enum WorkspaceViewportPointerOwner: Equatable, Sendable {
    /// A command takes every click, resolved by the command's hit policy. `transforming` says a
    /// Move, Rotate or Scale runs inside it (Boolean's G, R and S move its tools), whose gizmo
    /// stays live.
    case pickingCommand(
        WorkspaceViewportPickingCommand,
        hitPolicy: ViewportSelectionHitPolicy,
        scope: WorkspaceSelectionScope,
        transforming: Bool
    )
    /// The select tool with no picking command: a click selects in the scope and the
    /// scope's affordances edit the selection.
    case directEditing(WorkspaceSelectionScope)
    /// A creation, measuring or mesh tool owns the canvas; no affordance edits the selection.
    case tool(ModelingTool, scope: WorkspaceSelectionScope)

    var pickingCommand: WorkspaceViewportPickingCommand? {
        guard case .pickingCommand(let command, _, _, _) = self else {
            return nil
        }
        return command
    }

    /// What a viewport hit resolves to.
    var hitPolicy: ViewportSelectionHitPolicy {
        switch self {
        case .pickingCommand(_, let hitPolicy, _, _):
            return hitPolicy
        case .directEditing(let scope), .tool(_, let scope):
            return scope.viewportSelectionHitPolicy
        }
    }

    /// Whether a press may reach `affordance`.
    func allows(_ affordance: WorkspaceViewportAffordance) -> Bool {
        switch self {
        case .directEditing(let scope):
            return affordance.scopes.contains(scope)
        case .pickingCommand(let command, _, let scope, let transforming):
            guard affordance.scopes.contains(scope) else { return false }
            if affordance == .objectPlacement {
                return transforming
            }
            return affordance.owningPickingCommand == command
        case .tool:
            return false
        }
    }
}
