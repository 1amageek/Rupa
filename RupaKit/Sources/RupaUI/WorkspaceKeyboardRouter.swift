import RupaCore
import RupaRendering
import SwiftUI

struct WorkspaceKeyboardPhase: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let down = WorkspaceKeyboardPhase(rawValue: 1 << 0)
    static let repeatPhase = WorkspaceKeyboardPhase(rawValue: 1 << 1)
    static let up = WorkspaceKeyboardPhase(rawValue: 1 << 2)
}

struct WorkspaceKeyboardModifiers: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let command = WorkspaceKeyboardModifiers(rawValue: 1 << 0)
    static let control = WorkspaceKeyboardModifiers(rawValue: 1 << 1)
    static let option = WorkspaceKeyboardModifiers(rawValue: 1 << 2)
    static let shift = WorkspaceKeyboardModifiers(rawValue: 1 << 3)
}

struct WorkspaceKeyboardInput: Equatable, Sendable {
    var characters: String
    var phases: WorkspaceKeyboardPhase
    var modifiers: WorkspaceKeyboardModifiers
    var isTab: Bool
    var isReturn: Bool
    var isEscape: Bool
    var isSpace: Bool
    var isUpArrow: Bool
    var isDownArrow: Bool
    var isDelete: Bool

    init(
        characters: String = "",
        phases: WorkspaceKeyboardPhase = [.down],
        modifiers: WorkspaceKeyboardModifiers = [],
        isTab: Bool = false,
        isReturn: Bool = false,
        isEscape: Bool = false,
        isSpace: Bool = false,
        isUpArrow: Bool = false,
        isDownArrow: Bool = false,
        isDelete: Bool = false
    ) {
        self.characters = characters
        self.phases = phases
        self.modifiers = modifiers
        self.isTab = isTab
        self.isReturn = isReturn
        self.isEscape = isEscape
        self.isSpace = isSpace
        self.isUpArrow = isUpArrow
        self.isDownArrow = isDownArrow
        self.isDelete = isDelete
    }

    init(keyPress: KeyPress) {
        var phases: WorkspaceKeyboardPhase = []
        if keyPress.phase.contains(.down) {
            phases.insert(.down)
        }
        if keyPress.phase.contains(.repeat) {
            phases.insert(.repeatPhase)
        }
        if keyPress.phase.contains(.up) {
            phases.insert(.up)
        }

        var modifiers: WorkspaceKeyboardModifiers = []
        if keyPress.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if keyPress.modifiers.contains(.control) {
            modifiers.insert(.control)
        }
        if keyPress.modifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if keyPress.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }

        self.init(
            characters: keyPress.characters,
            phases: phases,
            modifiers: modifiers,
            isTab: keyPress.key == .tab,
            isReturn: keyPress.key == .return,
            isEscape: keyPress.key == .escape,
            isSpace: keyPress.key == .space,
            isUpArrow: keyPress.key == .upArrow,
            isDownArrow: keyPress.key == .downArrow,
            isDelete: keyPress.key == .delete || keyPress.key == .deleteForward
        )
    }
}

/// A Place option value the keyboard can move to.
enum WorkspacePlaceOptionField: Hashable, Sendable {
    case angle
    case scale
}

enum WorkspaceKeyboardAction: Equatable, Sendable {
    case deleteSelection
    /// Copy the selected objects in place and select the copies for moving.
    case duplicateSelection
    /// Place: turn the placed objects to point along the destination normal instead of facing it.
    case togglePlaceFlip
    /// Place: switch between independent copies and component instances.
    case togglePlaceOutput
    /// Place: choose which axis is up when the source point carries no surface normal.
    case setPlaceUpAxis(SceneNodePlacementSpec.UpAxis)
    /// Place: place one more consecutive copy per destination click.
    case addPlaceCopy
    /// Place: combine each copy with the body under the destination, or `nil` for a new body.
    case setPlaceBoolean(BooleanOperation?)
    /// Place: S and A move the keyboard to the scale or angle value.
    case focusPlaceOption(WorkspacePlaceOptionField)
    /// G/R/S: start Move, Rotate or Scale, or, in that mode already, toggle its screen or uniform constraint.
    case transformMode(ViewportTransformGizmoConfiguration.Mode)
    /// X/Y/Z constrain the transform to an axis; with Shift, to the plane perpendicular to it.
    case constrainTransform(SceneTransformAxis, plane: Bool)
    /// W: the next transform orientation.
    case cycleTransformOrientation
    /// V: pick the transform pivot.
    case pickTransformPivot
    /// Option-V: remove the picked pivot.
    case removeTransformPivot
    /// F: start a freestyle transform.
    case beginTransformFreestyle
    /// Return: finish the transform.
    case finishTransform
    /// Option-X: start Mirror on the whole-object selection.
    case beginMirror
    /// X/Y/Z mirror toward that axis's positive side; with Shift, toward its negative side.
    case chooseMirrorAxis(SceneTransformAxis, positive: Bool)
    /// I: toggle mirrored instances.
    case toggleMirrorInstances
    /// Q: toggle joining the halves.
    case toggleMirrorUnion
    /// F: pick the mirror line.
    case beginMirrorFreestyle
    /// Return: apply the mirror.
    case applyMirror
    /// X/Y/Z: point the array's active direction along that world axis.
    case setArrayAxis(SceneTransformAxis)
    /// I: switch the new array between instances and independent copies.
    case toggleArrayInstances
    /// 2: pick the rectangular array's second direction.
    case pickArraySecondDirection
    /// Return: finish shaping the new array.
    case finishArrayCreation
    /// Control-=: Measure Distance.
    case activateMeasure
    /// D: type the Section Analysis distance.
    case focusSectionAnalysisDistance
    /// F: flip the Section Analysis plane.
    case flipSectionAnalysis
    /// Return: place the Section Analysis slice.
    case confirmSectionAnalysis
    /// Return while Offset, Slot, Offset Vertex, Offset Edge, Offset Region or Slide runs: create
    /// its result, as right-click does.
    case confirmWorkspaceCommand
    /// M: Set Material on the selection.
    case setMaterial
    /// Shift-M: Fork Material on the selection.
    case forkMaterial
    /// Option-M: Remove Material from the selection.
    case removeMaterial
    /// Back out of whatever the workspace is in the middle of.
    case cancelActiveInteraction
    /// Choose what a click in the viewport selects.
    case setSelectionScope(WorkspaceSelectionScope)
    case beginSnapCandidateKindBypass
    case endSnapCandidateKindBypass
    case createConstructionPlane(alignsView: Bool)
    case createViewAlignedConstructionPlane(pickOrigin: Bool)
    case activateDimensionCommand
    case advanceDimensionInputRoute
    case commitDimensionCommand
    case cancelDimensionCommand
    case focusNextSketchDimensionInput
    case activateOffsetCommand
    case activateSlotWidthInput
    /// S in Offset Planar Curve: copies on both sides.
    case toggleCurveOffsetSymmetric
    case activateEdgeOffsetDistanceInput
    case activateRegionOffsetDistanceInput
    case cycleEdgeOffsetGapFill
    case cycleRegionOffsetGapFill
    case toggleEdgeOffsetLockedDistance
    case toggleRegionOffsetLockedDistance
    case toggleCombinedRegions
    case activateSlideCommand
    /// T: Trim removes each clicked curve segment until Escape.
    case activateTrimCommand
    /// L: Bridge Vertex joins the two selected curve ends (or curves).
    case bridgeSelection
    /// B: Fillet Curve or Fillet Vertex on the selected sketch curves or vertex.
    case applySketchCornerTreatment
    /// Tab on a selected Bridge Curve: both ends step G0 → G1 → G2 → G3 → G0.
    case cycleBridgeContinuity
    /// Q on a selected Bridge Curve: trims the curves it bridges.
    case trimBridgeSources
    /// J: Join Curves on the two selected sketch curves.
    case joinSketchCurves
    /// Option-J: Unjoin Curve on the selected sketch curve.
    case unjoinSketchCurve
    /// Option-D: Alternative Duplicate of selected curves or edges onto the construction plane, or
    /// Project Outline of selected bodies.
    case projectToConstructionPlane
    /// I: Project Curve Body of the selected curves onto the selected face.
    case projectCurvesOntoFace
    /// Escape ends Trim or Split Segment.
    case endCurvePickCommand
    /// C with the select tool: Cut Curve on the selected sketch curves.
    case beginCutCurve
    /// F with the select tool and nothing running that takes F: the Command Palette.
    case openCommandPalette
    /// Escape while the Command Palette is open: close it.
    case closeCommandPalette
    /// Tab while Cut Curve runs: Extend on or off.
    case toggleCutCurveExtend
    /// Return while Cut Curve runs: cut.
    case confirmCutCurve
    /// Escape while Cut Curve runs: end it without cutting.
    case cancelCutCurve
    case slideCurveControlVertices(SplineControlPointSlideDirection)
    case slideSurfaceControlVertices(PolySplineSurfaceVertexSlideDirection)
    case adjustPolygonSideCount(Int)
    case toggleSketchAxisConstraint(SketchAxisConstraint)
    case togglePolygonSizingMode
    case togglePolygonInclinationMode
    case togglePolygonCutsFaces
}

struct WorkspaceKeyboardContext: Sendable {
    var isSelectToolActive: Bool
    var isPolygonToolActive: Bool
    var usesSketchAxisConstraint: Bool
    var isDimensionCommandActive: Bool
    var isSlotProfileCommandActive: Bool
    /// Whether O started Offset Planar Curve (not yet turned into Slot).
    var isCurveOffsetCommandActive: Bool = false
    var isEdgeOffsetCommandActive: Bool
    var isRegionOffsetCommandActive: Bool
    var isCurveControlVertexSlideActive: Bool
    var isSurfaceControlVertexSlideActive: Bool
    var selectionScope: WorkspaceSelectionScope
    var hasCurveControlVertexSlideInput: Bool
    var hasSurfaceControlVertexSlideTargets: Bool
    var isPlaceSessionActive: Bool = false
    var isTransformSessionActive: Bool = false
    var isMirrorSessionActive: Bool = false
    var isArrayCreationSessionActive: Bool = false
    var isSectionAnalysisSessionActive: Bool = false
    /// Whether Trim or Split Segment is taking curve clicks.
    var isCurvePickCommandActive: Bool = false
    /// Whether Cut Curve's dialog is picking targets and cutters.
    var isCutCurveSessionActive: Bool = false
    /// Whether the Command Palette is open, whose field owns every key but Escape.
    var isCommandPaletteOpen: Bool = false
    /// Whether the selection is two sketch curves or curve ends Bridge can join.
    var hasBridgeableSelection: Bool = false
    /// Whether one Bridge Curve is selected, whose continuity Tab cycles and Q trims.
    var hasSelectedBridgeCurve: Bool = false
    /// Whether anything is selected that Option-D can project onto the construction plane.
    var hasProjectableSelection: Bool = false
    /// Whether the selection holds sketch curves or vertices Fillet, Join or Unjoin act on: the
    /// count of selected sketch targets.
    var selectedSketchTargetCount: Int = 0
    /// Whether the selection holds whole objects a transform can move.
    var hasWholeObjectSelection: Bool = false
    /// Whether the selection holds edges of one body that Move can move.
    var hasMovableTopologySelection: Bool = false

    /// Whether a command is currently taking typed input.
    ///
    /// Those commands own the editing keys while they are up, so the workspace must not read a
    /// delete meant for a half-typed number as a delete of the selection.
    /// Whether an O command (Offset, Slot, Offset Vertex, Offset Edge, Offset Region) or a Slide
    /// runs, which Return confirms.
    var isWorkspaceCommandActive: Bool {
        isSlotProfileCommandActive
            || isEdgeOffsetCommandActive
            || isRegionOffsetCommandActive
            || isCurveControlVertexSlideActive
            || isSurfaceControlVertexSlideActive
    }

    var ownsTextEditingKeys: Bool {
        isDimensionCommandActive
            || isSlotProfileCommandActive
            || isEdgeOffsetCommandActive
            || isRegionOffsetCommandActive
    }
}

struct WorkspaceKeyboardRouter: Sendable {
    func action(
        for keyPress: KeyPress,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        action(for: WorkspaceKeyboardInput(keyPress: keyPress), context: context)
    }

    func action(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        if context.isCommandPaletteOpen {
            return input.isEscape && input.phases.contains(.down) ? .closeCommandPalette : nil
        }
        if context.isTransformSessionActive, let transformAction = transformSessionAction(for: input) {
            return transformAction
        }
        if context.isMirrorSessionActive, let mirrorAction = mirrorSessionAction(for: input) {
            return mirrorAction
        }
        if context.isArrayCreationSessionActive, let arrayAction = arrayCreationAction(for: input) {
            return arrayAction
        }
        if context.isSectionAnalysisSessionActive, let sectionAction = sectionAnalysisAction(for: input) {
            return sectionAction
        }
        if context.isCutCurveSessionActive, let cutAction = cutCurveAction(for: input) {
            return cutAction
        }
        if let trimAction = trimAction(for: input, context: context) {
            return trimAction
        }
        if input.isReturn, input.phases.contains(.down), input.modifiers.isEmpty,
           context.isWorkspaceCommandActive, !context.isDimensionCommandActive {
            return .confirmWorkspaceCommand
        }
        if input.phases.contains(.down), input.modifiers == [.control], input.characters == "=",
           !context.ownsTextEditingKeys {
            return .activateMeasure
        }
        if input.phases.contains(.down),
           context.isSelectToolActive,
           context.hasWholeObjectSelection,
           !context.ownsTextEditingKeys,
           !context.isPlaceSessionActive,
           let materialAction = materialAction(for: input) {
            return materialAction
        }
        if input.phases.contains(.down),
           input.modifiers == [.option],
           ["x", "≈"].contains(input.characters.lowercased()),
           context.isSelectToolActive,
           context.hasWholeObjectSelection,
           !context.isPlaceSessionActive,
           !context.ownsTextEditingKeys {
            return .beginMirror
        }
        if let snapOverrideAction = snapOverrideAction(for: input) {
            return snapOverrideAction
        }
        guard input.phases.contains(.down) || input.phases.contains(.repeatPhase) else {
            return nil
        }
        if let constructionPlaneAction = constructionPlaneAction(
            for: input,
            context: context
        ) {
            return constructionPlaneAction
        }
        guard !input.modifiers.contains(.command),
              !input.modifiers.contains(.control),
              !input.modifiers.contains(.option) else {
            return nil
        }
        if input.isDelete {
            guard context.isSelectToolActive, !context.ownsTextEditingKeys else {
                return nil
            }
            return .deleteSelection
        }
        if input.modifiers == [.shift],
           input.characters.lowercased() == "d",
           context.isSelectToolActive,
           !context.ownsTextEditingKeys {
            return .duplicateSelection
        }
        if let dimensionAction = dimensionAction(for: input, context: context) {
            return dimensionAction
        }
        // Every other command here is entered by a key the user has to know and left
        // by no key at all, so a workspace that had drifted into a mode could only be
        // talked out of it by guessing which mode it was in. Escape leaves whichever
        // one is running.
        if input.isEscape {
            return .cancelActiveInteraction
        }
        if context.isPlaceSessionActive {
            let key = input.characters.lowercased()
            if input.modifiers.isEmpty, let placeAction = placeAction(for: key) {
                return placeAction
            }
            if input.modifiers == [.shift], key == "e" {
                return .setPlaceBoolean(.intersect)
            }
            if input.modifiers == [.shift], key == "q" {
                return .setPlaceBoolean(.slice)
            }
        }
        if input.isTab,
           context.usesSketchAxisConstraint {
            return .focusNextSketchDimensionInput
        }
        if let selectionScopeAction = selectionScopeAction(for: input, context: context) {
            return selectionScopeAction
        }

        let key = input.characters.lowercased()
        if let offsetAction = offsetAction(for: key, context: context) {
            return offsetAction
        }
        if let slideAction = slideAction(for: input, context: context) {
            return slideAction
        }
        if let polygonSideAction = polygonSideAction(for: input, context: context) {
            return polygonSideAction
        }
        if input.modifiers.isEmpty,
           context.isSelectToolActive,
           context.hasWholeObjectSelection,
           !context.isPlaceSessionActive,
           !context.ownsTextEditingKeys,
           let mode = transformMode(for: key) {
            return .transformMode(mode)
        }
        // G, R and S move, rotate and scale selected edges, faces or vertices.
        if input.modifiers.isEmpty,
           context.isSelectToolActive,
           context.hasMovableTopologySelection,
           !context.isPlaceSessionActive,
           !context.ownsTextEditingKeys,
           let mode = transformMode(for: key) {
            return .transformMode(mode)
        }
        if context.usesSketchAxisConstraint,
           let axisConstraint = SketchAxisConstraint(rawValue: key) {
            return .toggleSketchAxisConstraint(axisConstraint)
        }
        guard context.isPolygonToolActive else {
            return nil
        }
        switch key {
        case "c":
            return .togglePolygonSizingMode
        case "v":
            return .togglePolygonInclinationMode
        case "k":
            return .togglePolygonCutsFaces
        default:
            return nil
        }
    }

    /// What a click selects is a mode, and it was reachable only through six 25 point
    /// icons.
    ///
    /// Picking a face and then an edge of the same body is an ordinary sequence, so the
    /// mode is switched often enough that a trip to the rail costs more than the pick
    /// it precedes. The digits follow the order the rail already shows. A command that
    /// is running owns the keyboard, and its numeric fields would otherwise lose the
    /// digits typed into them.
    private func selectionScopeAction(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        guard context.isSelectToolActive,
              !context.ownsTextEditingKeys,
              input.characters.count == 1,
              let key = input.characters.first,
              let scope = WorkspaceSelectionScope.scope(forKeyEquivalent: key) else {
            return nil
        }
        return .setSelectionScope(scope)
    }

    private func snapOverrideAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        guard input.characters.lowercased() == "x" else {
            return nil
        }
        if input.phases.contains(.up) {
            return .endSnapCandidateKindBypass
        }
        guard (input.phases.contains(.down) || input.phases.contains(.repeatPhase)),
              input.modifiers.contains(.shift),
              !input.modifiers.contains(.command),
              !input.modifiers.contains(.control),
              !input.modifiers.contains(.option) else {
            return nil
        }
        return .beginSnapCandidateKindBypass
    }

    private func constructionPlaneAction(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        guard context.isSelectToolActive,
              input.isSpace,
              !input.modifiers.contains(.command),
              !input.modifiers.contains(.option) else {
            return nil
        }
        if input.modifiers.contains(.control) {
            return .createViewAlignedConstructionPlane(
                pickOrigin: input.modifiers.contains(.shift)
            )
        }
        // Whether the current selection can build a plane is a question about the
        // document, and answering it here turned an unsupported selection into a key
        // that did nothing. The request goes through and the workspace names the
        // operands it accepts.
        return .createConstructionPlane(
            alignsView: !input.modifiers.contains(.shift)
        )
    }

    private func dimensionAction(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        if context.isDimensionCommandActive {
            if input.isTab {
                return .advanceDimensionInputRoute
            }
            if input.isReturn {
                return .commitDimensionCommand
            }
            if input.isEscape {
                return .cancelDimensionCommand
            }
        }
        guard context.isSelectToolActive,
              input.characters == "=" else {
            return nil
        }
        return .activateDimensionCommand
    }

    private func transformMode(for key: String) -> ViewportTransformGizmoConfiguration.Mode? {
        switch key {
        case "g": .move
        case "r": .rotate
        case "s": .scale
        default: nil
        }
    }

    /// The keys Move, Rotate and Scale take while one is running, which Plasticity's gizmos use too.
    private func transformSessionAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        guard input.phases.contains(.down),
              !input.modifiers.contains(.command),
              !input.modifiers.contains(.control) else {
            return nil
        }
        let key = input.characters.lowercased()
        if input.modifiers == [.option] {
            // Option-V can arrive as a composed character, so the key is matched on either form.
            return key == "v" || key == "√" ? .removeTransformPivot : nil
        }
        guard !input.modifiers.contains(.option) else { return nil }
        if input.isReturn {
            return .finishTransform
        }
        let shifted = input.modifiers == [.shift]
        guard input.modifiers.isEmpty || shifted else { return nil }
        switch key {
        case "x": return .constrainTransform(.x, plane: shifted)
        case "y": return .constrainTransform(.y, plane: shifted)
        case "z": return .constrainTransform(.z, plane: shifted)
        default: break
        }
        guard !shifted else { return nil }
        if let mode = transformMode(for: key) {
            return .transformMode(mode)
        }
        switch key {
        case "w": return .cycleTransformOrientation
        case "v": return .pickTransformPivot
        case "f": return .beginTransformFreestyle
        default: return nil
        }
    }

    /// The keys Mirror takes while it runs, which Plasticity's Mirror uses too.
    private func mirrorSessionAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        guard input.phases.contains(.down),
              input.modifiers.isEmpty || input.modifiers == [.shift] else {
            return nil
        }
        if input.isReturn {
            return .applyMirror
        }
        let shifted = input.modifiers == [.shift]
        switch input.characters.lowercased() {
        case "x": return .chooseMirrorAxis(.x, positive: !shifted)
        case "y": return .chooseMirrorAxis(.y, positive: !shifted)
        case "z": return .chooseMirrorAxis(.z, positive: !shifted)
        case "i" where !shifted: return .toggleMirrorInstances
        case "q" where !shifted: return .toggleMirrorUnion
        case "f" where !shifted: return .beginMirrorFreestyle
        default: return nil
        }
    }

    /// The keys Section Analysis takes while its dialog is up, which Plasticity's uses too.
    private func sectionAnalysisAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        guard input.phases.contains(.down), input.modifiers.isEmpty else { return nil }
        if input.isReturn {
            return .confirmSectionAnalysis
        }
        switch input.characters.lowercased() {
        case "d": return .focusSectionAnalysisDistance
        case "f": return .flipSectionAnalysis
        default: return nil
        }
    }

    /// M, Shift-M and Option-M: Set, Fork and Remove Material.
    private func materialAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        let key = input.characters.lowercased()
        switch input.modifiers {
        case []: return key == "m" ? .setMaterial : nil
        case [.shift]: return key == "m" ? .forkMaterial : nil
        // Option-M can arrive as a composed character, so the key is matched on either form.
        case [.option]: return key == "m" || key == "µ" ? .removeMaterial : nil
        default: return nil
        }
    }

    /// The keys a new array takes while it is being shaped, which Plasticity's arrays use too.
    private func arrayCreationAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        guard input.phases.contains(.down), input.modifiers.isEmpty else { return nil }
        if input.isReturn { return .finishArrayCreation }
        switch input.characters.lowercased() {
        case "x": return .setArrayAxis(.x)
        case "y": return .setArrayAxis(.y)
        case "z": return .setArrayAxis(.z)
        case "i": return .toggleArrayInstances
        case "2": return .pickArraySecondDirection
        default: return nil
        }
    }

    /// Place's option keys, which Plasticity's Place uses as well.
    private func placeAction(for key: String) -> WorkspaceKeyboardAction? {
        switch key {
        case "f": .togglePlaceFlip
        case "s": .focusPlaceOption(.scale)
        case "a": .focusPlaceOption(.angle)
        case "i": .togglePlaceOutput
        case "x": .setPlaceUpAxis(.x)
        case "y": .setPlaceUpAxis(.y)
        case "z": .setPlaceUpAxis(.z)
        case "d": .addPlaceCopy
        case "q": .setPlaceBoolean(.union)
        case "w": .setPlaceBoolean(.difference)
        case "b": .setPlaceBoolean(nil)
        default: nil
        }
    }

    private func offsetAction(
        for key: String,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        guard context.isSelectToolActive else {
            return nil
        }
        switch key {
        case "o":
            return .activateOffsetCommand
        case "d":
            if context.isSlotProfileCommandActive {
                return .activateSlotWidthInput
            }
            if context.isEdgeOffsetCommandActive {
                return .activateEdgeOffsetDistanceInput
            }
            return context.isRegionOffsetCommandActive ? .activateRegionOffsetDistanceInput : nil
        case "v":
            if context.isEdgeOffsetCommandActive {
                return .cycleEdgeOffsetGapFill
            }
            return context.isRegionOffsetCommandActive ? .cycleRegionOffsetGapFill : nil
        case "s":
            if context.isCurveOffsetCommandActive {
                return .toggleCurveOffsetSymmetric
            }
            if context.isEdgeOffsetCommandActive {
                return .toggleEdgeOffsetLockedDistance
            }
            return context.isRegionOffsetCommandActive ? .toggleRegionOffsetLockedDistance : nil
        case "i":
            return context.isRegionOffsetCommandActive ? .toggleCombinedRegions : nil
        default:
            return nil
        }
    }

    /// T starts Trim with the select tool; Escape ends Trim or Split Segment.
    /// The keys Cut Curve's dialog takes, which Plasticity's Cut Curve uses too.
    private func cutCurveAction(for input: WorkspaceKeyboardInput) -> WorkspaceKeyboardAction? {
        guard input.phases.contains(.down), input.modifiers.isEmpty else { return nil }
        if input.isTab { return .toggleCutCurveExtend }
        if input.isReturn { return .confirmCutCurve }
        if input.isEscape { return .cancelCutCurve }
        return nil
    }

    private func trimAction(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        guard input.phases.contains(.down), !context.ownsTextEditingKeys else { return nil }
        if context.isCurvePickCommandActive {
            return input.isEscape ? .endCurvePickCommand : nil
        }
        guard context.isSelectToolActive, !context.isPlaceSessionActive else { return nil }
        let key = input.characters.lowercased()
        if input.modifiers == [.option], key == "j" || key == "∆" {
            return context.selectedSketchTargetCount == 1 ? .unjoinSketchCurve : nil
        }
        if input.modifiers == [.option], key == "d" || key == "∂" {
            return context.hasProjectableSelection ? .projectToConstructionPlane : nil
        }
        guard input.modifiers.isEmpty else { return nil }
        if context.hasSelectedBridgeCurve {
            if input.isTab { return .cycleBridgeContinuity }
            if key == "q" { return .trimBridgeSources }
        }
        switch key {
        case "c": return .beginCutCurve
        case "f": return .openCommandPalette
        case "t": return .activateTrimCommand
        case "l": return context.hasBridgeableSelection ? .bridgeSelection : nil
        case "b": return context.selectedSketchTargetCount > 0 ? .applySketchCornerTreatment : nil
        case "j": return context.selectedSketchTargetCount == 2 ? .joinSketchCurves : nil
        case "i": return context.hasProjectableSelection ? .projectCurvesOntoFace : nil
        default: return nil
        }
    }

    private func slideAction(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        guard context.isSelectToolActive else {
            return nil
        }
        let key = input.characters.lowercased()
        if key == "g",
           input.modifiers.contains(.shift) {
            return .activateSlideCommand
        }
        if context.selectionScope == .sketchEntity,
           context.isCurveControlVertexSlideActive,
           context.hasCurveControlVertexSlideInput {
            switch key {
            case "u":
                return .slideCurveControlVertices(
                    input.modifiers.contains(.shift) ? .negativeU : .positiveU
                )
            case "n":
                return .slideCurveControlVertices(.normal)
            default:
                return nil
            }
        }
        if context.selectionScope == .vertex,
           context.isSurfaceControlVertexSlideActive,
           context.hasSurfaceControlVertexSlideTargets {
            switch key {
            case "u":
                return .slideSurfaceControlVertices(
                    input.modifiers.contains(.shift) ? .negativeU : .positiveU
                )
            case "n":
                return .slideSurfaceControlVertices(.normal)
            case "v":
                return .slideSurfaceControlVertices(
                    input.modifiers.contains(.shift) ? .negativeV : .positiveV
                )
            default:
                return nil
            }
        }
        return nil
    }

    private func polygonSideAction(
        for input: WorkspaceKeyboardInput,
        context: WorkspaceKeyboardContext
    ) -> WorkspaceKeyboardAction? {
        guard context.isPolygonToolActive else {
            return nil
        }
        if input.isUpArrow {
            return .adjustPolygonSideCount(1)
        }
        if input.isDownArrow {
            return .adjustPolygonSideCount(-1)
        }
        return nil
    }
}
