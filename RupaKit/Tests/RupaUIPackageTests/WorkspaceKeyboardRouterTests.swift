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

    #expect(
        router.action(
            for: WorkspaceKeyboardInput(isSpace: true),
            context: keyboardContext(hasConstructionPlaneTargets: true)
        ) == .createConstructionPlane(alignsView: true)
    )
    #expect(
        router.action(
            for: WorkspaceKeyboardInput(modifiers: [.shift], isSpace: true),
            context: keyboardContext(hasConstructionPlaneTargets: true)
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
    hasSurfaceControlVertexSlideTargets: Bool = false,
    hasConstructionPlaneTargets: Bool = false
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
        hasSurfaceControlVertexSlideTargets: hasSurfaceControlVertexSlideTargets,
        hasConstructionPlaneTargets: hasConstructionPlaneTargets
    )
}
