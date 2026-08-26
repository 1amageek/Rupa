import RupaCore
import RupaCoreTypes
import SwiftCAD

/// A validated value projection of the current DesignDocument for read-only UI use.
///
/// The projection contains no package bytes and no reference to the owning session.
/// `document` is returned by value, so mutating a caller-owned copy cannot mutate the
/// project owner.
public struct ProjectReadDocument: Sendable {
    private let validatedDocument: ValidatedDesignDocument

    public init(document: DesignDocument) throws {
        validatedDocument = try ValidatedDesignDocument(document)
    }

    public var document: DesignDocument {
        validatedDocument.document
    }

    public var documentID: DocumentID {
        validatedDocument.document.id
    }

    public var projectID: ProjectID {
        validatedDocument.document.projectID
    }

    public var name: String {
        validatedDocument.document.cadDocument.metadata.name ?? "Untitled"
    }

    public var hasAuthoritativeCADSource: Bool {
        validatedDocument.document.hasAuthoritativeCADSource
    }
}
