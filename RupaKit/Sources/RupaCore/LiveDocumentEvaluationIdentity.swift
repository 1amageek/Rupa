import SwiftCAD

struct LiveDocumentEvaluationIdentity: Sendable, Equatable {
    var documentID: DocumentID
    var schemaVersion: SchemaVersion
    var units: UnitSystem
    var designRevision: DocumentRevision
    var parameterRevision: DocumentRevision

    init(document: CADDocument) {
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
    }
}
