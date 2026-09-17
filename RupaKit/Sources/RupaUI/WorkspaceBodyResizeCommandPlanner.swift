import RupaCore
import RupaRendering

enum WorkspaceBodyResizeCommandPlanner {
    static func commands(_ target: ViewportBodyResizeDragTarget, in document: DesignDocument) throws -> [EditorCommand] {
        try target.validate(in: document)
        guard let featureID = target.placement.featureID else {
            throw EditorError(code: .commandInvalid, message: "Box resizing requires a source feature.")
        }
        var commands: [EditorCommand] = [.setCubeDimensions(
            featureID: featureID, sizeX: .length(target.size.x, .meter),
            sizeY: .length(target.size.y, .meter), sizeZ: .length(target.size.z, .meter))]
        if let placement = try WorkspaceTransformMatrix.command(
            setting: target.placement.localTransform, for: target.placement.sceneNodeID, in: document) {
            commands.append(placement)
        }
        return commands
    }
}
