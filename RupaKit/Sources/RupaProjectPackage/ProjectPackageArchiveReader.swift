import Foundation

struct ProjectPackageArchiveReader {
    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let endSignature: UInt32 = 0x0605_4b50
    private static let minimumEndByteCount = 22
    private static let utf8Flag: UInt16 = 0x0800

    let limits: ProjectPackageResourceLimits

    func read(_ data: Data) throws -> ProjectPackageArchiveBacking {
        try limits.validate()
        guard UInt64(data.count) <= limits.maximumArchiveByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package archive exceeds its configured limit."
            )
        }
        let endOffset = try findEndRecord(in: data)
        var end = try ProjectPackageByteCursor(data: data, offset: endOffset)
        guard try end.readUInt32() == Self.endSignature else {
            throw malformed("Project package end record is invalid.")
        }
        let diskNumber = try end.readUInt16()
        let centralDiskNumber = try end.readUInt16()
        let diskEntryCount = try end.readUInt16()
        let entryCount = try end.readUInt16()
        let centralByteCount = try end.readUInt32()
        let centralOffset = try end.readUInt32()
        let commentByteCount = try end.readUInt16()
        guard diskNumber == 0,
            centralDiskNumber == 0,
            diskEntryCount == entryCount,
            Int(entryCount) <= limits.maximumEntryCount,
            commentByteCount == 0,
            end.offset == data.count
        else {
            throw unsupported("Multi-disk, ZIP64, or inconsistent package indexes are unsupported.")
        }
        let centralEnd = UInt64(centralOffset) + UInt64(centralByteCount)
        guard centralEnd == UInt64(endOffset) else {
            throw malformed("Project package central directory bounds are inconsistent.")
        }

        guard let exactCentralOffset = Int(exactly: centralOffset) else {
            throw malformed("Project package central offset exceeds this platform.")
        }
        let records = try readCentralRecords(
            from: data,
            offset: exactCentralOffset,
            upperBound: endOffset,
            count: Int(entryCount)
        )
        return try readLocalEntries(
            from: data,
            records: records,
            centralOffset: exactCentralOffset
        )
    }

    private func findEndRecord(in data: Data) throws -> Int {
        guard data.count >= Self.minimumEndByteCount else {
            throw malformed("Project package archive is too short.")
        }
        let offset = data.count - Self.minimumEndByteCount
        if ProjectPackageByteCursor.uint32(in: data, at: offset) == Self.endSignature {
            return offset
        }
        throw malformed("Project package end record is missing.")
    }

    private func readCentralRecords(
        from data: Data,
        offset: Int,
        upperBound: Int,
        count: Int
    ) throws -> [ProjectPackageArchiveCentralRecord] {
        var cursor = try ProjectPackageByteCursor(
            data: data,
            offset: offset,
            upperBound: upperBound
        )
        var records: [ProjectPackageArchiveCentralRecord] = []
        records.reserveCapacity(count)
        var paths: Set<String> = []
        for _ in 0..<count {
            guard try cursor.readUInt32() == Self.centralHeaderSignature else {
                throw malformed("Project package central entry signature is invalid.")
            }
            let madeByVersion = try cursor.readUInt16()
            let requiredVersion = try cursor.readUInt16()
            let flags = try cursor.readUInt16()
            let method = try cursor.readUInt16()
            try cursor.skip(4)
            let checksum = try cursor.readUInt32()
            let compressedByteCount = try cursor.readUInt32()
            let byteCount = try cursor.readUInt32()
            let nameByteCount = try cursor.readUInt16()
            let extraByteCount = try cursor.readUInt16()
            let commentByteCount = try cursor.readUInt16()
            let diskStart = try cursor.readUInt16()
            let internalAttributes = try cursor.readUInt16()
            let externalAttributes = try cursor.readUInt32()
            let localHeaderOffset = try cursor.readUInt32()
            guard madeByVersion == 20,
                requiredVersion == 20,
                flags == Self.utf8Flag,
                method == 0,
                compressedByteCount == byteCount,
                nameByteCount > 0,
                extraByteCount == 0,
                commentByteCount == 0,
                diskStart == 0,
                internalAttributes == 0,
                externalAttributes == 0
            else {
                throw unsupported(
                    "Only canonical stored ZIP32 project package entries are supported."
                )
            }
            let path = try cursor.readUTF8(byteCount: Int(nameByteCount))
            try validatePath(path)
            guard paths.insert(path).inserted else {
                throw ProjectPackageError(
                    code: .duplicateEntry,
                    message: "Project package archive contains a duplicate path: \(path)."
                )
            }
            records.append(
                ProjectPackageArchiveCentralRecord(
                    path: path,
                    checksum: checksum,
                    byteCount: byteCount,
                    localHeaderOffset: localHeaderOffset
                )
            )
        }
        guard cursor.offset == upperBound else {
            throw malformed("Project package central directory contains trailing bytes.")
        }
        return records
    }

    private func readLocalEntries(
        from data: Data,
        records: [ProjectPackageArchiveCentralRecord],
        centralOffset: Int
    ) throws -> ProjectPackageArchiveBacking {
        var descriptors: [ProjectPackageArchiveEntryDescriptor] = []
        descriptors.reserveCapacity(records.count)
        for record in records {
            guard let localOffset = Int(exactly: record.localHeaderOffset) else {
                throw malformed("Project package local entry offset exceeds this platform.")
            }
            var cursor = try ProjectPackageByteCursor(
                data: data,
                offset: localOffset,
                upperBound: centralOffset
            )
            guard try cursor.readUInt32() == Self.localHeaderSignature else {
                throw malformed("Project package local entry signature is invalid.")
            }
            let requiredVersion = try cursor.readUInt16()
            let flags = try cursor.readUInt16()
            let method = try cursor.readUInt16()
            try cursor.skip(4)
            let checksum = try cursor.readUInt32()
            let compressedByteCount = try cursor.readUInt32()
            let byteCount = try cursor.readUInt32()
            let nameByteCount = try cursor.readUInt16()
            let extraByteCount = try cursor.readUInt16()
            guard requiredVersion == 20,
                flags == Self.utf8Flag,
                method == 0,
                checksum == record.checksum,
                compressedByteCount == record.byteCount,
                byteCount == record.byteCount,
                extraByteCount == 0
            else {
                throw malformed("Project package local and central entry records disagree.")
            }
            let path = try cursor.readUTF8(byteCount: Int(nameByteCount))
            guard path == record.path else {
                throw malformed("Project package local entry path differs from its index.")
            }
            let payloadStart = cursor.offset
            let payloadEnd = UInt64(payloadStart) + UInt64(byteCount)
            guard payloadEnd <= UInt64(centralOffset),
                let exactPayloadEnd = Int(exactly: payloadEnd)
            else {
                throw malformed("Project package entry payload exceeds archive bounds.")
            }
            descriptors.append(
                ProjectPackageArchiveEntryDescriptor(
                    path: path,
                    checksum: checksum,
                    byteCount: byteCount,
                    localRecordRange: localOffset..<exactPayloadEnd,
                    payloadRange: payloadStart..<exactPayloadEnd
                )
            )
        }
        let ordered = descriptors.sorted {
            $0.localRecordRange.lowerBound < $1.localRecordRange.lowerBound
        }
        var expectedOffset = 0
        for descriptor in ordered {
            guard descriptor.localRecordRange.lowerBound == expectedOffset else {
                throw malformed("Project package local entries overlap or hide bytes.")
            }
            expectedOffset = descriptor.localRecordRange.upperBound
        }
        guard expectedOffset == centralOffset else {
            throw malformed("Project package contains bytes outside declared entries.")
        }
        let entries = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.path, $0) })
        guard entries["manifest.json"] != nil else {
            throw ProjectPackageError(
                code: .missingEntry,
                message: "Project package archive requires manifest.json."
            )
        }
        return ProjectPackageArchiveBacking(data: data, entries: entries)
    }

    private func validatePath(_ path: String) throws {
        if path == "manifest.json" {
            return
        }
        if path.hasPrefix("source/") {
            try ProjectPackageEntryPath.validateSourcePath(path)
            return
        }
        try ProjectPackageEntryPath.validatePreservedAdjunctPath(path)
    }

    private func malformed(_ message: String) -> ProjectPackageError {
        ProjectPackageError(code: .malformedArchive, message: message)
    }

    private func unsupported(_ message: String) -> ProjectPackageError {
        ProjectPackageError(code: .unsupportedFeature, message: message)
    }
}
