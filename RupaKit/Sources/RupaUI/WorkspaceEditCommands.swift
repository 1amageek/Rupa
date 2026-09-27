import SwiftUI

/// The focused workspace's object edit actions, published for the Edit menu.
///
/// The menu is presented by the App while the selection lives in the workspace view, so the two
/// are joined by one focused scene value. Each action is the same closure the workspace key and the
/// Outliner call, and is `nil` when the current selection cannot take it, so the menu disables the
/// item instead of offering an action Core would refuse.
public struct WorkspaceEditCommands {
    /// Copies the selected objects in place and selects the copies for moving.
    public var duplicate: (@MainActor () -> Void)?
    /// Starts Mirror on the selected objects.
    public var mirror: (@MainActor () -> Void)?
    /// Places copies or instances of the selected objects from one picked point onto others.
    public var place: (@MainActor () -> Void)?
    /// Copies the selected objects with a reference point picked next, for Paste with Placement.
    public var copyWithPlacement: (@MainActor () -> Void)?
    /// Places the objects on the pasteboard at destinations picked next.
    public var pasteWithPlacement: (@MainActor () -> Void)?
    /// Arrays the selected objects along the parent's X axis.
    public var rectangularArray: (@MainActor () -> Void)?
    /// Arrays the selected objects around a center the user picks next.
    public var radialArray: (@MainActor () -> Void)?
    /// Arrays the selected objects along a path curve the user picks next.
    public var curveArray: (@MainActor () -> Void)?
    /// Extends the selected curves to the nearest curves their extensions meet.
    public var completeEdge: (@MainActor () -> Void)?
    /// Doubles the selected splines' control points or raises the selected surfaces' degree.
    public var subdivide: (@MainActor () -> Void)?
    /// Starts Split Segment: each clicked sketch curve splits where it is clicked.
    public var splitSegment: (@MainActor () -> Void)?
    /// Joins the two selected sketch curves or curve ends with a Bridge Curve.
    public var bridge: (@MainActor () -> Void)?
    /// Aligns the selected curve end with the other selected end at the chosen continuity.
    public var alignVertex: (@MainActor () -> Void)?
    /// Reverses the direction of every selected sketch line and spline, as one step.
    public var reverseCurves: (@MainActor () -> Void)?
    /// Makes an instance of the selection where it is and starts moving it into place.
    public var createInstance: (@MainActor () -> Void)?
    /// Turns the selected component instances into independent, editable copies.
    public var realizeInstances: (@MainActor () -> Void)?
    /// Starts Insert Knot: each clicked spline gains a control point where it is clicked.
    public var insertKnot: (@MainActor () -> Void)?

    public init(
        duplicate: (@MainActor () -> Void)?,
        mirror: (@MainActor () -> Void)? = nil,
        place: (@MainActor () -> Void)? = nil,
        copyWithPlacement: (@MainActor () -> Void)? = nil,
        pasteWithPlacement: (@MainActor () -> Void)? = nil,
        rectangularArray: (@MainActor () -> Void)? = nil,
        radialArray: (@MainActor () -> Void)? = nil,
        curveArray: (@MainActor () -> Void)? = nil,
        completeEdge: (@MainActor () -> Void)? = nil,
        subdivide: (@MainActor () -> Void)? = nil,
        splitSegment: (@MainActor () -> Void)? = nil,
        bridge: (@MainActor () -> Void)? = nil,
        alignVertex: (@MainActor () -> Void)? = nil,
        reverseCurves: (@MainActor () -> Void)? = nil,
        createInstance: (@MainActor () -> Void)? = nil,
        realizeInstances: (@MainActor () -> Void)? = nil,
        insertKnot: (@MainActor () -> Void)? = nil
    ) {
        self.duplicate = duplicate
        self.mirror = mirror
        self.place = place
        self.copyWithPlacement = copyWithPlacement
        self.pasteWithPlacement = pasteWithPlacement
        self.rectangularArray = rectangularArray
        self.radialArray = radialArray
        self.curveArray = curveArray
        self.completeEdge = completeEdge
        self.subdivide = subdivide
        self.splitSegment = splitSegment
        self.bridge = bridge
        self.alignVertex = alignVertex
        self.reverseCurves = reverseCurves
        self.createInstance = createInstance
        self.realizeInstances = realizeInstances
        self.insertKnot = insertKnot
    }
}

private struct WorkspaceEditCommandsKey: FocusedValueKey {
    typealias Value = WorkspaceEditCommands
}

extension FocusedValues {
    /// The edit commands of the focused workspace, or `nil` when no workspace is focused.
    public var workspaceEditCommands: WorkspaceEditCommands? {
        get { self[WorkspaceEditCommandsKey.self] }
        set { self[WorkspaceEditCommandsKey.self] = newValue }
    }
}
