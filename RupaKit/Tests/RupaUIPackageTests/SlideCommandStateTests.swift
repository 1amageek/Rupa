import Testing
@testable import RupaUI

@Test func slideCommandStateRoutesCurveControlVerticesAndDeactivates() {
    var state = SlideCommandState.inactive

    #expect(!state.isActive)
    #expect(!state.isCurveControlVerticesActive)
    #expect(!state.isSurfaceControlVerticesActive)
    #expect(state.route == .inactive)
    #expect(state.routeTitle == "Inactive")

    state.activateCurveControlVertices()

    #expect(state.isActive)
    #expect(state.isCurveControlVerticesActive)
    #expect(!state.isSurfaceControlVerticesActive)
    #expect(state.route == .curveControlVertices)
    #expect(state.routeTitle == "Curve CVs")

    state.activateSurfaceControlVertices()

    #expect(state.isActive)
    #expect(!state.isCurveControlVerticesActive)
    #expect(state.isSurfaceControlVerticesActive)
    #expect(state.route == .surfaceControlVertices)
    #expect(state.routeTitle == "Surface CVs")

    state.deactivate()

    #expect(state == .inactive)
}
