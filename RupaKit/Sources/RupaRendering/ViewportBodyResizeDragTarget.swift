import RupaCore
import SwiftCAD

/// Source dimensions and the placement translation that keeps the opposite faces fixed.
public struct ViewportBodyResizeDragTarget: Sendable {
    public let placement: ViewportBodyPlacementDragTarget
    public let size: Vector3D
    let documentID: DocumentID
    let designRevision: DocumentRevision
    let parameterRevision: DocumentRevision

    public func validate(in document: DesignDocument) throws {
        try placement.validate(in: document)
        guard document.cadDocument.id == documentID,
              document.cadDocument.designGraph.revision == designRevision,
              document.cadDocument.parameters.revision == parameterRevision,
              size.isFinite, min(size.x, size.y, size.z) > 0 else {
            throw EditorError(code: .commandInvalid, message: "The box resize source changed during the gesture.")
        }
    }
}
