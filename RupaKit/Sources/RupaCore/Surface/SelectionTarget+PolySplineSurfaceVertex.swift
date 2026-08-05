import Foundation

public extension SelectionTarget {
    var isGeneratedPolySplineSurfaceVertex: Bool {
        guard case .vertex(let componentID) = component,
              let subshapeID = componentID.generatedTopologySubshapeID else {
            return false
        }
        return PolySplineSurfaceVertexTarget.canParse(subshapeID: subshapeID)
    }
}
