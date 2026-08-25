import RupaCore
import RupaProjectPackage

public protocol ProjectProductSourceCoding: Sendable {
    func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource

    func decode(_ source: ProjectPackageProductSource) throws -> ProjectProductSourceModel
}
