import RupaCore
import RupaProjectModel

public protocol ProjectSourceProjecting: Sendable {
    func project(_ document: DesignDocument) throws -> ProjectSourceModel
}
