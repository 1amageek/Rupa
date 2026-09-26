import RupaCore
import Testing
@testable import RupaUI

@Test func workspaceKeyboardRouterMapsSnapOverridePhases() {
    let router = WorkspaceKeyboardRouter()
    let context = keyboardContext()

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "x", modifiers: [.shift]),
            context: context
        ) == .beginSnapCandidateKindBypass
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "x", phases: [.up]),
            context: context
        ) == .endSnapCandidateKindBypass
    )
}

@Test func workspaceKeyboardRouterKeepsDimensionRoutePrecedenceOverSketchFocus() {
    let router = WorkspaceKeyboardRouter()

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isTab: true),
            context: keyboardContext(
                usesSketchAxisConstraint: true,
                isDimensionCommandActive: true
            )
        ) == .advanceDimensionInputRoute
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isTab: true),
            context: keyboardContext(usesSketchAxisConstraint: true)
        ) == .focusNextSketchDimensionInput
    )
}

@Test func workspaceKeyboardRouterMapsSlideSurfaceDirections() {
    let router = WorkspaceKeyboardRouter()
    let context = keyboardContext(
        isSurfaceControlVertexSlideActive: true,
        selectionScope: .vertex,
        hasSurfaceControlVertexSlideTargets: true
    )

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "v", modifiers: [.shift]),
            context: context
        ) == .slideSurfaceControlVertices(.negativeV)
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "n"),
            context: context
        ) == .slideSurfaceControlVertices(.normal)
    )
}

@Test func workspaceKeyboardRouterKeepsOffsetInputPriority() {
    let router = WorkspaceKeyboardRouter()

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "d"),
            context: keyboardContext(
                isSlotProfileCommandActive: true,
                isEdgeOffsetCommandActive: true,
                isRegionOffsetCommandActive: true
            )
        ) == .activateSlotWidthInput
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "v"),
            context: keyboardContext(
                isEdgeOffsetCommandActive: true,
                isRegionOffsetCommandActive: true
            )
        ) == .cycleEdgeOffsetGapFill
    )
}

@Test func workspaceKeyboardRouterMapsConstructionPlaneSpaceVariants() {
    let router = WorkspaceKeyboardRouter()

    // Whether the selection can build a plane is the workspace's answer to give.
    // The request is delivered either way so the refusal can name the operands.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isSpace: true),
            context: keyboardContext()
        ) == .createConstructionPlane(alignsView: true)
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(modifiers: [.shift], isSpace: true),
            context: keyboardContext()
        ) == .createConstructionPlane(alignsView: false)
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(modifiers: [.control, .shift], isSpace: true),
            context: keyboardContext()
        ) == .createViewAlignedConstructionPlane(pickOrigin: true)
    )
}

@Test func workspaceKeyboardRouterMapsPolygonAndAxisCommands() {
    let router = WorkspaceKeyboardRouter()

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isUpArrow: true),
            context: keyboardContext(isPolygonToolActive: true)
        ) == .adjustPolygonSideCount(1)
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "x"),
            context: keyboardContext(usesSketchAxisConstraint: true)
        ) == .toggleSketchAxisConstraint(.x)
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "k"),
            context: keyboardContext(isPolygonToolActive: true)
        ) == .togglePolygonCutsFaces
    )
}

/// Shift-D duplicates the selection in the select tool, and gives the key up to typed input.
@Test func workspaceKeyboardRouterDuplicatesOnShiftDOnlyWhileSelecting() {
    let router = WorkspaceKeyboardRouter()
    let shiftD = WorkspaceKeyboardInput(characters: "D", modifiers: [.shift])

    #expect(router.action(for: shiftD, context: keyboardContext()) == .duplicateSelection)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "d"), context: keyboardContext()) != .duplicateSelection)
    #expect(router.action(for: shiftD, context: keyboardContext(isSelectToolActive: false)) == nil)
    #expect(router.action(for: shiftD, context: keyboardContext(isDimensionCommandActive: true)) != .duplicateSelection)
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "d", modifiers: [.shift, .command]),
            context: keyboardContext()
        ) == nil
    )
}

/// Place's option keys act only while Place is running.
@Test func workspaceKeyboardRouterRoutesPlaceOptionKeysOnlyDuringPlace() {
    let router = WorkspaceKeyboardRouter()
    var placing = keyboardContext()
    placing.isPlaceSessionActive = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "f"), context: placing) == .togglePlaceFlip)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "i"), context: placing) == .togglePlaceOutput)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "y"), context: placing) == .setPlaceUpAxis(.y))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "d"), context: placing) == .addPlaceCopy)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "q"), context: placing) == .setPlaceBoolean(.union))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "w"), context: placing) == .setPlaceBoolean(.difference))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "E", modifiers: [.shift]), context: placing) == .setPlaceBoolean(.intersect))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "Q", modifiers: [.shift]), context: placing) == .setPlaceBoolean(.slice))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "s"), context: placing) == .focusPlaceOption(.scale))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "a"), context: placing) == .focusPlaceOption(.angle))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "b"), context: placing) == .setPlaceBoolean(nil))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "f"), context: keyboardContext()) != .togglePlaceFlip)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "d"), context: keyboardContext()) != .addPlaceCopy)
}

/// Delete removes the selection only while the workspace is the one holding the keys.
///
/// The commands that take typed input own the editing keys while they are up, so a delete meant for
/// a half-typed number must not reach the selection instead.
@Test func workspaceKeyboardRouterGivesDeleteUpToWhoeverIsTakingTypedInput() {
    let router = WorkspaceKeyboardRouter()
    let delete = WorkspaceKeyboardInput(isDelete: true)

    #expect(router.action(for: delete, context: keyboardContext()) == .deleteSelection)

    let refusals: [WorkspaceKeyboardContext] = [
        keyboardContext(isSelectToolActive: false),
        keyboardContext(isDimensionCommandActive: true),
        keyboardContext(isSlotProfileCommandActive: true),
        keyboardContext(isEdgeOffsetCommandActive: true),
        keyboardContext(isRegionOffsetCommandActive: true)
    ]
    for context in refusals {
        #expect(router.action(for: delete, context: context) == nil)
    }

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(modifiers: [.command], isDelete: true),
            context: keyboardContext()
        ) == nil
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(phases: [.up], isDelete: true),
            context: keyboardContext()
        ) == nil
    )
}

@Test func workspaceKeyboardRouterMapsEscapeToCancellation() {
    let router = WorkspaceKeyboardRouter()

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isEscape: true),
            context: keyboardContext()
        ) == .cancelActiveInteraction
    )
    // A tool that is not Select is itself a mode Escape has to leave, so the
    // action is produced regardless of which tool is active.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isEscape: true),
            context: keyboardContext(isSelectToolActive: false, isPolygonToolActive: true)
        ) == .cancelActiveInteraction
    )
    // Dimension keeps its own cancellation while it is taking typed input.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isEscape: true),
            context: keyboardContext(isDimensionCommandActive: true)
        ) == .cancelDimensionCommand
    )
    // Key-up is not a press, and a modified Escape belongs to the menu bar.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(phases: [.up], isEscape: true),
            context: keyboardContext()
        ) == nil
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(modifiers: [.command], isEscape: true),
            context: keyboardContext()
        ) == nil
    )
}

@Test func workspaceKeyboardRouterMapsDigitsToSelectionScopes() {
    let router = WorkspaceKeyboardRouter()

    for (index, scope) in WorkspaceSelectionScope.allCases.enumerated() {
        let key = String(index + 1)
        #expect(
            router.action(
                for: WorkspaceKeyboardInput(characters: key),
                context: keyboardContext()
            ) == .setSelectionScope(scope)
        )
    }
    // The rail shows six scopes, so a seventh digit names none of them.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(
                characters: String(WorkspaceSelectionScope.allCases.count + 1)
            ),
            context: keyboardContext()
        ) == nil
    )
}

@Test func workspaceKeyboardRouterWithholdsSelectionScopeDigitsFromTypedInput() {
    let router = WorkspaceKeyboardRouter()

    // A command taking typed input owns the keyboard; its numeric fields would
    // otherwise lose the digits typed into them.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "2"),
            context: keyboardContext(isDimensionCommandActive: true)
        ) == nil
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "2"),
            context: keyboardContext(isSlotProfileCommandActive: true)
        ) == nil
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "2"),
            context: keyboardContext(isEdgeOffsetCommandActive: true)
        ) == nil
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "2"),
            context: keyboardContext(isRegionOffsetCommandActive: true)
        ) == nil
    )
    // Scope is what a Select click means, so another tool does not claim it.
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(characters: "2"),
            context: keyboardContext(isSelectToolActive: false, isPolygonToolActive: true)
        ) == nil
    )
}

@Test func workspaceSelectionScopeDigitsFollowTheRailOrder() {
    for (index, scope) in WorkspaceSelectionScope.allCases.enumerated() {
        let key = Character(String(index + 1))
        #expect(scope.keyEquivalent == key)
        #expect(WorkspaceSelectionScope.scope(forKeyEquivalent: key) == scope)
    }
    #expect(WorkspaceSelectionScope.scope(forKeyEquivalent: "0") == nil)
}

private func keyboardContext(
    isSelectToolActive: Bool = true,
    isPolygonToolActive: Bool = false,
    usesSketchAxisConstraint: Bool = false,
    isDimensionCommandActive: Bool = false,
    isSlotProfileCommandActive: Bool = false,
    isEdgeOffsetCommandActive: Bool = false,
    isRegionOffsetCommandActive: Bool = false,
    isCurveControlVertexSlideActive: Bool = false,
    isSurfaceControlVertexSlideActive: Bool = false,
    selectionScope: WorkspaceSelectionScope = .object,
    hasCurveControlVertexSlideInput: Bool = false,
    hasSurfaceControlVertexSlideTargets: Bool = false
) -> WorkspaceKeyboardContext {
    WorkspaceKeyboardContext(
        isSelectToolActive: isSelectToolActive,
        isPolygonToolActive: isPolygonToolActive,
        usesSketchAxisConstraint: usesSketchAxisConstraint,
        isDimensionCommandActive: isDimensionCommandActive,
        isSlotProfileCommandActive: isSlotProfileCommandActive,
        isEdgeOffsetCommandActive: isEdgeOffsetCommandActive,
        isRegionOffsetCommandActive: isRegionOffsetCommandActive,
        isCurveControlVertexSlideActive: isCurveControlVertexSlideActive,
        isSurfaceControlVertexSlideActive: isSurfaceControlVertexSlideActive,
        selectionScope: selectionScope,
        hasCurveControlVertexSlideInput: hasCurveControlVertexSlideInput,
        hasSurfaceControlVertexSlideTargets: hasSurfaceControlVertexSlideTargets
    )
}

@Test func workspaceKeyboardRouterStartsTransformsOnlyForWholeObjects() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    context.hasWholeObjectSelection = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "g"), context: context) == .transformMode(.move))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "r"), context: context) == .transformMode(.rotate))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "s"), context: context) == .transformMode(.scale))

    context.hasWholeObjectSelection = false
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "g"), context: context) == nil)
    context.hasWholeObjectSelection = true
    context.isPlaceSessionActive = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "g"), context: context) == nil)
    context.isPlaceSessionActive = false
    context.isEdgeOffsetCommandActive = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "s"), context: context) == .toggleEdgeOffsetLockedDistance)
}

@Test func workspaceKeyboardRouterGivesARunningTransformItsKeys() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    context.isTransformSessionActive = true
    context.hasWholeObjectSelection = true
    func action(_ characters: String, _ modifiers: WorkspaceKeyboardModifiers = []) -> WorkspaceKeyboardAction? {
        router.action(for: WorkspaceKeyboardInput(characters: characters, modifiers: modifiers), context: context)
    }
    #expect(action("x") == .constrainTransform(.x, plane: false))
    // Shift-X is the plane constraint while a transform runs, not the snap bypass.
    #expect(action("X", [.shift]) == .constrainTransform(.x, plane: true))
    #expect(action("z") == .constrainTransform(.z, plane: false))
    #expect(action("g") == .transformMode(.move))
    #expect(action("s") == .transformMode(.scale))
    #expect(action("w") == .cycleTransformOrientation)
    #expect(action("v") == .pickTransformPivot)
    #expect(action("v", [.option]) == .removeTransformPivot)
    #expect(action("√", [.option]) == .removeTransformPivot)
    #expect(action("f") == .beginTransformFreestyle)
    #expect(router.action(for: WorkspaceKeyboardInput(isReturn: true), context: context) == .finishTransform)
    #expect(router.action(for: WorkspaceKeyboardInput(isEscape: true), context: context) == .cancelActiveInteraction)
    #expect(action("d", [.command]) == nil)
}

@Test func workspaceKeyboardRouterStartsAndDrivesMirror() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    context.hasWholeObjectSelection = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "≈", modifiers: [.option]), context: context) == .beginMirror)
    context.hasWholeObjectSelection = false
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "≈", modifiers: [.option]), context: context) == nil)

    context.isMirrorSessionActive = true
    func action(_ characters: String, _ modifiers: WorkspaceKeyboardModifiers = []) -> WorkspaceKeyboardAction? {
        router.action(for: WorkspaceKeyboardInput(characters: characters, modifiers: modifiers), context: context)
    }
    #expect(action("y") == .chooseMirrorAxis(.y, positive: true))
    #expect(action("X", [.shift]) == .chooseMirrorAxis(.x, positive: false))
    #expect(action("i") == .toggleMirrorInstances)
    #expect(action("q") == .toggleMirrorUnion)
    #expect(action("f") == .beginMirrorFreestyle)
    #expect(router.action(for: WorkspaceKeyboardInput(isReturn: true), context: context) == .applyMirror)
    #expect(router.action(for: WorkspaceKeyboardInput(isEscape: true), context: context) == .cancelActiveInteraction)
}

@Test func workspaceKeyboardRouterShapesANewArray() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    context.isArrayCreationSessionActive = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "y"), context: context) == .setArrayAxis(.y))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "i"), context: context) == .toggleArrayInstances)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "2"), context: context) == .pickArraySecondDirection)
    #expect(router.action(for: WorkspaceKeyboardInput(isReturn: true), context: context) == .finishArrayCreation)
}

@Test func workspaceKeyboardRouterMapsMaterialKeys() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    context.hasWholeObjectSelection = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "m"), context: context) == .setMaterial)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "M", modifiers: [.shift]), context: context) == .forkMaterial)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "µ", modifiers: [.option]), context: context) == .removeMaterial)
    context.hasWholeObjectSelection = false
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "m"), context: context) == nil)
}

@Test func workspaceKeyboardRouterStartsMeasureWithControlEquals() {
    let router = WorkspaceKeyboardRouter()
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "=", modifiers: [.control]), context: keyboardContext()) == .activateMeasure)
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "="), context: keyboardContext()) == .activateDimensionCommand)
}

@Test func workspaceKeyboardRouterDrivesSectionAnalysis() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    func action(_ characters: String) -> WorkspaceKeyboardAction? {
        router.action(for: WorkspaceKeyboardInput(characters: characters), context: context)
    }
    #expect(action("f") != .flipSectionAnalysis)
    context.isSectionAnalysisSessionActive = true
    #expect(action("d") == .focusSectionAnalysisDistance)
    #expect(action("f") == .flipSectionAnalysis)
    #expect(router.action(for: WorkspaceKeyboardInput(isReturn: true), context: context) == .confirmSectionAnalysis)
    #expect(router.action(for: WorkspaceKeyboardInput(isEscape: true), context: context) == .cancelActiveInteraction)
}

@Test func workspaceKeyboardRouterMovesSelectedEdges() {
    let router = WorkspaceKeyboardRouter()
    var context = keyboardContext()
    context.hasMovableEdgeSelection = true
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "g"), context: context) == .transformMode(.move))
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "r"), context: context) != .transformMode(.rotate))
    context.hasMovableEdgeSelection = false
    #expect(router.action(for: WorkspaceKeyboardInput(characters: "g"), context: context) == nil)
}
