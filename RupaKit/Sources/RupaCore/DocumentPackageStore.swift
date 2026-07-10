import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DocumentPackageStore: Sendable {
    public init() {}

    public func save(_ document: DesignDocument, to url: URL) throws {
        try document.validate()
        let data = try packageData(for: document)
        try data.write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws -> DesignDocument {
        let source = try MappedFileByteSource(url: url)
        return try load(from: source)
    }

    public func packageData(for document: DesignDocument) throws -> Data {
        try document.validate()
        let encoder = Self.encoder()
        let manifest = PackageManifest(
            format: "rupa.document",
            schemaVersion: document.cadDocument.schemaVersion,
            documentPath: "document.json",
            productMetadataPath: "rupa.json",
            createdAt: document.cadDocument.metadata.createdAt,
            updatedAt: document.cadDocument.metadata.updatedAt
        )
        let payload = PackagePayload(
            modelingSettings: document.modelingSettings,
            productMetadata: document.productMetadata
        )

        return try ProductPackageArchive.make(entries: [
            ProductPackageArchive.Entry(path: "manifest.json", data: encoder.encode(manifest)),
            ProductPackageArchive.Entry(path: "document.json", data: encoder.encode(document.cadDocument)),
            ProductPackageArchive.Entry(path: "rupa.json", data: encoder.encode(payload))
        ])
    }

    private func load(from source: any ByteSource) throws -> DesignDocument {
        do {
            let entries = try ProductPackageArchive.entries(from: source)
            if entries["rupa.json"] != nil {
                return try loadProductPackage(from: entries)
            }
            return try loadLegacyCADPackage(from: source)
        } catch let error as DocumentValidationError {
            throw error
        } catch let error as DecodingError {
            throw error
        } catch {
            return try loadLegacyCADPackage(from: source)
        }
    }

    private func loadLegacyCADPackage(from source: any ByteSource) throws -> DesignDocument {
        let cadDocument = try CADPipeline().loadDocument(from: source)
        return DesignDocument(
            cadDocument: cadDocument,
            modelingSettings: .standard,
            productMetadata: .empty()
        )
    }

    private func loadProductPackage(from entries: [String: Data]) throws -> DesignDocument {
        let unsupportedEntries = Set(entries.keys).subtracting(["manifest.json", "document.json", "rupa.json"])
        guard unsupportedEntries.isEmpty else {
            throw DocumentValidationError.invalidProductMetadata(
                "Rupa package contains unsupported entries: \(unsupportedEntries.sorted().joined(separator: ", "))."
            )
        }
        guard let manifestData = entries["manifest.json"],
              let documentData = entries["document.json"],
              let payloadData = entries["rupa.json"] else {
            throw DocumentValidationError.invalidProductMetadata(
                "Rupa package must contain manifest.json, document.json, and rupa.json."
            )
        }

        let decoder = Self.decoder()
        let manifest = try decoder.decode(PackageManifest.self, from: manifestData)
        guard manifest.format == "rupa.document",
              manifest.documentPath == "document.json",
              manifest.productMetadataPath == "rupa.json" else {
            throw DocumentValidationError.invalidProductMetadata("Rupa package manifest is invalid.")
        }

        let cadDocument = try decoder.decode(CADDocument.self, from: documentData)
        let payload = try decoder.decode(PackagePayload.self, from: payloadData)
        guard manifest.schemaVersion == cadDocument.schemaVersion,
              manifest.createdAt == cadDocument.metadata.createdAt,
              manifest.updatedAt == cadDocument.metadata.updatedAt else {
            throw DocumentValidationError.invalidProductMetadata(
                "Rupa package manifest does not match the CAD document metadata."
            )
        }

        let document = DesignDocument(
            cadDocument: cadDocument,
            modelingSettings: payload.modelingSettings,
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

private struct PackageManifest: Codable, Sendable {
    var format: String
    var schemaVersion: SchemaVersion
    var documentPath: String
    var productMetadataPath: String
    var createdAt: Date
    var updatedAt: Date
}

private struct PackagePayload: Codable, Sendable {
    var modelingSettings: DocumentModelingSettings
    var productMetadata: ProductMetadata
}

private struct ProductPackageArchive {
    typealias Entry = StoredZipArchive.Entry

    static func make(entries: [Entry]) throws -> Data {
        try mapZipArchiveError {
            try StoredZipArchive.make(entries: entries)
        }
    }

    static func entries(from data: Data) throws -> [String: Data] {
        try mapZipArchiveError {
            try StoredZipArchive.readEntries(from: data)
        }
    }

    static func entries(from source: any ByteSource) throws -> [String: Data] {
        try StoredZipArchive.withEntries(from: source) { entries in
            entries
        }
    }

    private static func mapZipArchiveError<Result>(_ operation: () throws -> Result) throws -> Result {
        do {
            return try operation()
        } catch let error as ZipArchiveError {
            throw DocumentValidationError.invalidProductMetadata(
                "Rupa package archive is invalid: \(error)."
            )
        }
    }
}
