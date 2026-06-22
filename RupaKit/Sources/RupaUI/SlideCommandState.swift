struct SlideCommandState: Equatable {
    enum Route: Equatable {
        case inactive
        case curveControlVertices
        case surfaceControlVertices
    }

    var route: Route

    init(route: Route = .inactive) {
        self.route = route
    }

    static var inactive: SlideCommandState {
        SlideCommandState()
    }

    var isActive: Bool {
        route != .inactive
    }

    var isCurveControlVerticesActive: Bool {
        route == .curveControlVertices
    }

    var isSurfaceControlVerticesActive: Bool {
        route == .surfaceControlVertices
    }

    var routeTitle: String {
        switch route {
        case .inactive:
            return "Inactive"
        case .curveControlVertices:
            return "Curve CVs"
        case .surfaceControlVertices:
            return "Surface CVs"
        }
    }

    mutating func activateCurveControlVertices() {
        route = .curveControlVertices
    }

    mutating func activateSurfaceControlVertices() {
        route = .surfaceControlVertices
    }

    mutating func deactivate() {
        route = .inactive
    }
}
