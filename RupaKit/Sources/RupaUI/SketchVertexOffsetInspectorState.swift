import RupaCore

struct SketchVertexOffsetInspectorState {
    var entityKind: String
    var entityID: SketchEntityID
    var target: SelectionTarget

    var handle: SketchEntityPointHandle? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchPointHandleReference,
              reference.entityID == entityID else {
            return nil
        }
        switch (entityKind, reference.handle) {
        case ("line", .lineStart),
             ("line", .lineEnd),
             ("arc", .arcStart),
             ("arc", .arcEnd):
            return reference.handle
        default:
            return nil
        }
    }
}
