import RupaCore
import RupaViewportScene
import SwiftCAD

/// Source-owned revision required to invalidate a viewport without hashing CAD data.
public enum ViewportSourceIdentity: Equatable, Sendable {
    case document(id: DocumentID, generation: DocumentGeneration)
    case presentation(EvaluationSnapshotID)

    /// Verifies that this identity belongs to the immutable source values that
    /// will feed one native preparation request.
    func validate(
        document: DesignDocument,
        presentationScene: UniversalViewportScene?
    ) throws {
        func mismatch(_ message: String) -> MeshSourcePresentationRenderError {
            MeshSourcePresentationRenderError(code: .sourceAuthorityMismatch, message: message)
        }

        switch self {
        case .document(let id, _):
            guard id == document.id else {
                throw mismatch("Document source identity does not match the supplied document.")
            }
            if let presentationScene {
                guard presentationScene.projectID == document.projectID,
                      presentationScene.snapshotID.projectID == presentationScene.projectID else {
                    throw mismatch("Presentation scene belongs to a different document project.")
                }
            }
        case .presentation(let snapshotID):
            guard let presentationScene else {
                throw mismatch("Presentation source identity requires a presentation scene.")
            }
            guard snapshotID == presentationScene.snapshotID,
                  snapshotID.projectID == presentationScene.projectID,
                  presentationScene.projectID == document.projectID else {
                throw mismatch("Presentation source identity does not match the document or scene.")
            }
        }
    }
}
