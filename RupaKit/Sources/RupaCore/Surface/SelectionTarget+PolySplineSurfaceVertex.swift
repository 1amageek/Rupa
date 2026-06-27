import Foundation

public extension SelectionTarget {
    var isGeneratedPolySplineSurfaceVertex: Bool {
        guard case .vertex(let componentID) = component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            return false
        }
        return PolySplineSurfaceVertexTarget.canParsePersistentName(persistentName)
    }
}
