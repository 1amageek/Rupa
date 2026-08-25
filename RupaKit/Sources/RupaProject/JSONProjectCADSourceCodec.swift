import Foundation
import RupaProjectPackage
import SwiftCAD

public struct JSONProjectCADSourceCodec: ProjectCADSourceCoding, Sendable {
    public init() {}

    public func encode(_ document: CADDocument) throws -> ProjectPackageCADSource {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try ProjectPackageCADSource(data: encoder.encode(document))
    }

    public func decode(_ source: ProjectPackageCADSource) throws -> CADDocument {
        try JSONDecoder().decode(CADDocument.self, from: source.data)
    }
}
