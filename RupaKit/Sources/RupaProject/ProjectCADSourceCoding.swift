import RupaCore
import RupaProjectPackage

public protocol ProjectCADSourceCoding: Sendable {
    func encode(_ document: DesignDocument) throws -> ProjectPackageCADSource

    func decode(_ source: ProjectPackageCADSource) throws -> DesignDocument
}
