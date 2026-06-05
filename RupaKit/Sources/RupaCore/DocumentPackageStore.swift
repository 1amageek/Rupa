import Foundation
import SwiftCAD

public struct DocumentPackageStore: Sendable {
    public init() {}

    public func save(_ document: DesignDocument, to url: URL) throws {
        try document.validate()
        let data = try packageData(for: document)
        try data.write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws -> DesignDocument {
        let data = try Data(contentsOf: url)
        return try load(fromPackageData: data)
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
            displayUnit: document.displayUnit,
            ruler: document.ruler,
            productMetadata: document.productMetadata
        )

        return try ProductPackageArchive.make(entries: [
            ProductPackageArchive.Entry(path: "manifest.json", data: encoder.encode(manifest)),
            ProductPackageArchive.Entry(path: "document.json", data: encoder.encode(document.cadDocument)),
            ProductPackageArchive.Entry(path: "rupa.json", data: encoder.encode(payload))
        ])
    }

    private func load(fromPackageData data: Data) throws -> DesignDocument {
        do {
            let entries = try ProductPackageArchive.entries(from: data)
            if entries["rupa.json"] != nil {
                return try loadProductPackage(from: entries)
            }
            let cadDocument = try CADPipeline().loadDocument(from: BorrowedBytes(data))
            return DesignDocument(
                cadDocument: cadDocument,
                displayUnit: .millimeter,
                ruler: .standard(for: .millimeter),
                productMetadata: .empty()
            )
        } catch let error as DocumentValidationError {
            throw error
        } catch let error as DecodingError {
            throw error
        } catch {
            let cadDocument = try CADPipeline().loadDocument(from: BorrowedBytes(data))
            return DesignDocument(
                cadDocument: cadDocument,
                displayUnit: .millimeter,
                ruler: .standard(for: .millimeter),
                productMetadata: .empty()
            )
        }
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

private struct PackageManifest: Codable, Sendable {
    var format: String
    var schemaVersion: SchemaVersion
    var documentPath: String
    var productMetadataPath: String
    var createdAt: Date
    var updatedAt: Date
}

private struct PackagePayload: Codable, Sendable {
    var displayUnit: LengthDisplayUnit
    var ruler: RulerConfiguration
    var productMetadata: ProductMetadata
}

private struct ProductPackageArchive {
    struct Entry: Sendable {
        var path: String
        var data: Data
    }

    static func make(entries: [Entry]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        for entry in entries {
            let offset = UInt32(archive.count)
            let name = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            try appendLocalHeader(name: name, data: entry.data, crc: crc, to: &archive)
            archive.append(entry.data)
            try appendCentralDirectoryHeader(
                name: name,
                data: entry.data,
                crc: crc,
                localHeaderOffset: offset,
                to: &centralDirectory
            )
        }
        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        try appendEndRecord(
            entryCount: UInt16(entries.count),
            centralDirectorySize: UInt32(centralDirectory.count),
            centralDirectoryOffset: centralDirectoryOffset,
            to: &archive
        )
        return archive
    }

    static func entries(from data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        let endRecordOffset = try endRecordOffset(in: bytes)
        let entryCount = Int(readUInt16(bytes, at: endRecordOffset + 10))
        let centralDirectoryOffset = Int(readUInt32(bytes, at: endRecordOffset + 16))
        var cursor = centralDirectoryOffset
        var entries: [String: Data] = [:]

        for _ in 0..<entryCount {
            guard readUInt32(bytes, at: cursor) == 0x0201_4b50 else {
                throw DocumentValidationError.invalidProductMetadata("Package central directory is invalid.")
            }
            let compression = readUInt16(bytes, at: cursor + 10)
            guard compression == 0 else {
                throw DocumentValidationError.invalidProductMetadata("Package entries must use stored ZIP compression.")
            }
            let compressedSize = Int(readUInt32(bytes, at: cursor + 20))
            let fileNameLength = Int(readUInt16(bytes, at: cursor + 28))
            let extraLength = Int(readUInt16(bytes, at: cursor + 30))
            let commentLength = Int(readUInt16(bytes, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32(bytes, at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= bytes.count,
                  let path = String(data: Data(bytes[nameStart..<nameEnd]), encoding: .utf8) else {
                throw DocumentValidationError.invalidProductMetadata("Package entry name is invalid.")
            }
            let dataStart = try localDataOffset(bytes, localHeaderOffset: localHeaderOffset)
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= bytes.count else {
                throw DocumentValidationError.invalidProductMetadata("Package entry data is truncated.")
            }
            entries[path] = Data(bytes[dataStart..<dataEnd])
            cursor = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func appendLocalHeader(
        name: Data,
        data: Data,
        crc: UInt32,
        to output: inout Data
    ) throws {
        try appendUInt32(0x0403_4b50, to: &output)
        try appendUInt16(20, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt32(crc, to: &output)
        try appendUInt32(UInt32(data.count), to: &output)
        try appendUInt32(UInt32(data.count), to: &output)
        try appendUInt16(UInt16(name.count), to: &output)
        try appendUInt16(0, to: &output)
        output.append(name)
    }

    private static func appendCentralDirectoryHeader(
        name: Data,
        data: Data,
        crc: UInt32,
        localHeaderOffset: UInt32,
        to output: inout Data
    ) throws {
        try appendUInt32(0x0201_4b50, to: &output)
        try appendUInt16(20, to: &output)
        try appendUInt16(20, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt32(crc, to: &output)
        try appendUInt32(UInt32(data.count), to: &output)
        try appendUInt32(UInt32(data.count), to: &output)
        try appendUInt16(UInt16(name.count), to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt32(0, to: &output)
        try appendUInt32(localHeaderOffset, to: &output)
        output.append(name)
    }

    private static func appendEndRecord(
        entryCount: UInt16,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32,
        to output: inout Data
    ) throws {
        try appendUInt32(0x0605_4b50, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(0, to: &output)
        try appendUInt16(entryCount, to: &output)
        try appendUInt16(entryCount, to: &output)
        try appendUInt32(centralDirectorySize, to: &output)
        try appendUInt32(centralDirectoryOffset, to: &output)
        try appendUInt16(0, to: &output)
    }

    private static func endRecordOffset(in bytes: [UInt8]) throws -> Int {
        guard bytes.count >= 22 else {
            throw DocumentValidationError.invalidProductMetadata("Package archive is too small.")
        }
        var index = bytes.count - 22
        while index >= 0 {
            if readUInt32(bytes, at: index) == 0x0605_4b50 {
                return index
            }
            index -= 1
        }
        throw DocumentValidationError.invalidProductMetadata("Package archive end record is missing.")
    }

    private static func localDataOffset(_ bytes: [UInt8], localHeaderOffset: Int) throws -> Int {
        guard readUInt32(bytes, at: localHeaderOffset) == 0x0403_4b50 else {
            throw DocumentValidationError.invalidProductMetadata("Package local header is invalid.")
        }
        let fileNameLength = Int(readUInt16(bytes, at: localHeaderOffset + 26))
        let extraLength = Int(readUInt16(bytes, at: localHeaderOffset + 28))
        return localHeaderOffset + 30 + fileNameLength + extraLength
    }

    private static func appendUInt16(_ value: UInt16, to output: inout Data) throws {
        output.append(UInt8(value & 0x00ff))
        output.append(UInt8((value >> 8) & 0x00ff))
    }

    private static func appendUInt32(_ value: UInt32, to output: inout Data) throws {
        output.append(UInt8(value & 0x0000_00ff))
        output.append(UInt8((value >> 8) & 0x0000_00ff))
        output.append(UInt8((value >> 16) & 0x0000_00ff))
        output.append(UInt8((value >> 24) & 0x0000_00ff))
    }

    private static func readUInt16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}

private struct CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(0) &- (crc & 1)
                crc = (crc >> 1) ^ (0xedb8_8320 & mask)
            }
        }
        return ~crc
    }
}
