import Foundation
import RupaCore
import RupaProjectPackage
import SwiftCAD

public struct JSONProjectProductSourceCodec: ProjectProductSourceCoding, Sendable {
    private static let schemaVersion: UInt32 = 1

    public init() {}

    public func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource {
        let source = try ProjectProductSourceModel(document: document)
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            documentID: source.documentID,
            name: source.name,
            units: source.units,
            modelingSettings: source.modelingSettings,
            productMetadata: source.productMetadata
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try ProjectPackageProductSource(data: encoder.encode(payload))
    }

    public func decode(
        _ source: ProjectPackageProductSource
    ) throws -> ProjectProductSourceModel {
        let payload = try JSONDecoder().decode(Payload.self, from: source.data)
        guard payload.schemaVersion == Self.schemaVersion else {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "Product source schema version is unsupported."
            )
        }
        return try ProjectProductSourceModel(
            documentID: payload.documentID,
            name: payload.name,
            units: payload.units,
            modelingSettings: payload.modelingSettings,
            productMetadata: payload.productMetadata
        )
    }

    private struct Payload: Codable {
        let schemaVersion: UInt32
        let documentID: DocumentID
        let name: String?
        let units: UnitSystem
        let modelingSettings: DocumentModelingSettings
        let productMetadata: ProductMetadata
    }
}
