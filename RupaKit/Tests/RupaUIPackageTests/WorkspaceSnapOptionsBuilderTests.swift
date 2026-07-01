import RupaCore
import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceSnapOptionsBuilderLeavesScaleResolutionToCore() {
    var overrideState = WorkspaceSnapOverrideState()
    overrideState.updateHoveredCandidateKind(.lineEnd)
    _ = overrideState.beginCandidateKindBypass()

    let options = WorkspaceSnapOptionsBuilder(
        isGridSnapEnabled: true,
        isObjectTargetingEnabled: true,
        isConstructionPlaneSnapEnabled: true,
        constructionPlane: .xy,
        overrideState: overrideState,
        referenceLineAnchors: [
            SketchReferenceLineAnchor(point: Point2D(x: 10.0, y: 20.0)),
        ]
    ).options(
        referencePoint: Point2D(x: 1.0, y: 2.0),
        modifierFlags: ViewportInputModifierFlags(containsControl: true)
    )

    #expect(options.usesGrid)
    #expect(options.usesObjects)
    #expect(options.objectTargetingOverride == .forceEnabled)
    #expect(options.suppressedCandidateKinds == [.lineEnd])
    #expect(options.usesConstructionPlaneProjection)
    #expect(options.constructionPlane == .xy)
    #expect(options.gridIntervalMeters == nil)
    #expect(options.objectSearchRadiusMeters == nil)
    #expect(options.maximumCandidateCount == 16)
    #expect(options.referencePoint == Point2D(x: 1.0, y: 2.0))
    #expect(options.referenceLineAnchors == [
        SketchReferenceLineAnchor(point: Point2D(x: 10.0, y: 20.0)),
    ])
}

@Test func workspaceSnapOptionsBuilderSuppressesConstructionPlaneWhenDisabled() {
    let options = WorkspaceSnapOptionsBuilder(
        isGridSnapEnabled: false,
        isObjectTargetingEnabled: false,
        isConstructionPlaneSnapEnabled: false,
        constructionPlane: .yz,
        overrideState: WorkspaceSnapOverrideState(),
        referenceLineAnchors: []
    ).options()

    #expect(!options.usesGrid)
    #expect(!options.usesObjects)
    #expect(!options.usesConstructionPlaneProjection)
    #expect(options.constructionPlane == nil)
}
