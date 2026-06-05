import Foundation
import SwiftCAD

public struct RupaDocumentPackageStore: Sendable {
    public init() {}

    public func save(_ document: RupaDocument, to url: URL) throws {
        try document.validate()
        let data = try packageData(for: document)
        try data.write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws -> RupaDocument {
        let data = try Data(contentsOf: url)
        return try load(fromPackageData: data)
    }

    public func packageData(for document: RupaDocument) throws -> Data {
        try document.validate()
        let encoder = Self.encoder()
        let manifest = RupaPackageManifest(
            format: "rupa.document",
            schemaVersion: document.cadDocument.schemaVersion,
            documentPath: "document.json",
            productMetadataPath: "rupa.json",
            createdAt: document.cadDocument.metadata.createdAt,
            updatedAt: document.cadDocument.metadata.updatedAt
        )
        let payload = RupaPackagePayload(
            displayUnit: document.displayUnit,
            ruler: document.ruler,
            productMetadata: document.productMetadata
        )

        return try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: encoder.encode(manifest)),
            StoredZipArchive.Entry(path: "document.json", data: encoder.encode(document.cadDocument)),
            StoredZipArchive.Entry(path: "rupa.json", data: encoder.encode(payload))
        ])
    }

    private func load(fromPackageData data: Data) throws -> RupaDocument {
        do {
            return try StoredZipArchive.withEntries(from: BorrowedBytes(data)) { entries in
                if entries["rupa.json"] != nil {
                    return try loadRupaPackage(from: entries)
                }
                let cadDocument = try CADPipeline().loadDocument(from: BorrowedBytes(data))
                return RupaDocument(
                    cadDocument: cadDocument,
                    displayUnit: .millimeter,
                    ruler: .standard(for: .millimeter),
                    productMetadata: .empty()
                )
            }
        } catch let error as RupaDocumentValidationError {
            throw error
        } catch let error as DecodingError {
            throw error
        } catch {
            let cadDocument = try CADPipeline().loadDocument(from: BorrowedBytes(data))
            return RupaDocument(
                cadDocument: cadDocument,
                displayUnit: .millimeter,
                ruler: .standard(for: .millimeter),
                productMetadata: .empty()
            )
        }
    }

    private func loadRupaPackage(from entries: [String: Data]) throws -> RupaDocument {
        let unsupportedEntries = Set(entries.keys).subtracting(["manifest.json", "document.json", "rupa.json"])
        guard unsupportedEntries.isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Rupa package contains unsupported entries: \(unsupportedEntries.sorted().joined(separator: ", "))."
            )
        }
        guard let manifestData = entries["manifest.json"],
              let documentData = entries["document.json"],
              let payloadData = entries["rupa.json"] else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Rupa package must contain manifest.json, document.json, and rupa.json."
            )
        }

        let decoder = Self.decoder()
        let manifest = try decoder.decode(RupaPackageManifest.self, from: manifestData)
        guard manifest.format == "rupa.document",
              manifest.documentPath == "document.json",
              manifest.productMetadataPath == "rupa.json" else {
            throw RupaDocumentValidationError.invalidProductMetadata("Rupa package manifest is invalid.")
        }

        let cadDocument = try decoder.decode(CADDocument.self, from: documentData)
        let payload = try decoder.decode(RupaPackagePayload.self, from: payloadData)
        guard manifest.schemaVersion == cadDocument.schemaVersion,
              manifest.createdAt == cadDocument.metadata.createdAt,
              manifest.updatedAt == cadDocument.metadata.updatedAt else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Rupa package manifest does not match the CAD document metadata."
            )
        }

        let document = RupaDocument(
            cadDocument: cadDocument,
            displayUnit: payload.displayUnit,
            ruler: payload.ruler,
            productMetadata: payload.productMetadata
        )
        try document.validate()
        return document
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(Double.self)
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Rupa package date timestamp must be finite."
                )
            }
            return Date(timeIntervalSinceReferenceDate: value)
        }
        return decoder
    }
}

private struct RupaPackageManifest: Codable, Sendable {
    var format: String
    var schemaVersion: SchemaVersion
    var documentPath: String
    var productMetadataPath: String
    var createdAt: Date
    var updatedAt: Date
}

private struct RupaPackagePayload: Codable, Sendable {
    var displayUnit: LengthDisplayUnit
    var ruler: RulerConfiguration
    var productMetadata: RupaProductMetadata
}
