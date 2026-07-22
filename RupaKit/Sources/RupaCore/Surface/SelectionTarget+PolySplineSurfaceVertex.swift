import Foundation

public extension SelectionTarget {
    var isGeneratedPolySplineSurfaceVertex: Bool {
        guard case .vertex(let componentID) = component else {
            return false
        }
        return PolySplineSurfaceVertexTarget.parse(componentID: componentID) != nil
    }
}
