import SwiftCAD

struct LiveDocumentEvaluationIdentity: Sendable, Equatable {
    private let sourceDocument: CADDocument
    var documentID: DocumentID
    var schemaVersion: SchemaVersion
    var units: UnitSystem
    var designRevision: DocumentRevision
    var parameterRevision: DocumentRevision

    init(document: CADDocument) {
        sourceDocument = document
        documentID = document.id
        schemaVersion = document.schemaVersion
        units = document.units
        designRevision = document.designGraph.revision
        parameterRevision = document.parameters.revision
    }

    func matches(_ document: CADDocument) -> Bool {
        documentID == document.id
            && schemaVersion == document.schemaVersion
            && units == document.units
            && designRevision == document.designGraph.revision
            && parameterRevision == document.parameters.revision
            && sourceDocument == document
    }
}
