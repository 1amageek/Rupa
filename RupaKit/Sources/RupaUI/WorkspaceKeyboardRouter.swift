import RupaCore
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

enum WorkspaceKeyboardAction: Equatable, Sendable {
    case deleteSelection
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
    case activateEdgeOffsetDistanceInput
    case activateRegionOffsetDistanceInput
    case cycleEdgeOffsetGapFill
    case cycleRegionOffsetGapFill
    case toggleEdgeOffsetLockedDistance
    case toggleRegionOffsetLockedDistance
    case toggleCombinedRegions
    case activateSlideCommand
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
    var isEdgeOffsetCommandActive: Bool
    var isRegionOffsetCommandActive: Bool
    var isCurveControlVertexSlideActive: Bool
    var isSurfaceControlVertexSlideActive: Bool
    var selectionScope: WorkspaceSelectionScope
    var hasCurveControlVertexSlideInput: Bool
    var hasSurfaceControlVertexSlideTargets: Bool

    /// Whether a command is currently taking typed input.
    ///
    /// Those commands own the editing keys while they are up, so the workspace must not read a
    /// delete meant for a half-typed number as a delete of the selection.
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
