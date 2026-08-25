import RupaProjectPackage
import SwiftCAD

public protocol ProjectCADSourceCoding: Sendable {
    func encode(_ document: CADDocument) throws -> ProjectPackageCADSource

    func decode(_ source: ProjectPackageCADSource) throws -> CADDocument
}
