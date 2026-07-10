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

@Test func workspaceSnapInputResolverAttemptsConstructionPlaneOnlySnap() {
    let point = Point2D(x: 0.013, y: -0.027)
    let options = WorkspaceSnapOptionsBuilder(
        isGridSnapEnabled: false,
        isObjectTargetingEnabled: false,
        isConstructionPlaneSnapEnabled: true,
        constructionPlane: .xy,
        overrideState: WorkspaceSnapOverrideState(),
        referenceLineAnchors: []
    ).options()

    let resolution = WorkspaceSnapInputResolver().resolve(
        point,
        in: .empty(),
        ruler: .standard(for: .millimeter),
        options: options
    )

    #expect(resolution.didAttemptResolution)
    #expect(resolution.failureMessage == nil)
    #expect(resolution.input.point == point)
}

@Test func workspaceSnapInputResolverReturnsRawPointWhenResolutionFails() {
    let point = Point2D(x: 0.013, y: -0.027)
    let options = SnapResolutionOptions(
        usesGrid: true,
        usesObjects: false,
        gridIntervalMeters: -1.0
    )

    let resolution = WorkspaceSnapInputResolver().resolve(
        point,
        in: .empty(),
        ruler: .standard(for: .millimeter),
        options: options
    )

    #expect(resolution.didAttemptResolution)
    #expect(resolution.failureMessage != nil)
    #expect(resolution.input.point == point)
    #expect(resolution.input.worldPoint == nil)
}

@Test func workspaceSnapInputResolverSkipsWhenAllSnapRoutesAreDisabled() {
    let point = Point2D(x: 0.013, y: -0.027)
    let options = SnapResolutionOptions(
        usesGrid: false,
        usesObjects: false,
        referenceLineAnchors: []
    )

    let resolution = WorkspaceSnapInputResolver().resolve(
        point,
        in: .empty(),
        ruler: .standard(for: .millimeter),
        options: options
    )

    #expect(!resolution.didAttemptResolution)
    #expect(resolution.failureMessage == nil)
    #expect(resolution.input.point == point)
}
