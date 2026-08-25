import RupaCore
import RupaProject
import RupaProjectModel

extension DesignDocumentProjectBridge: ProjectSourceProjecting {
    public func project(_ document: DesignDocument) throws -> ProjectSourceModel {
        try sourceModel(for: document)
    }
}
