import Foundation
import RupaGeometry

struct ProjectPackageArchiveWriter<Sink: ProjectPackageByteSink> {
    private static var localHeaderSignature: UInt32 { 0x0403_4b50 }
    private static var centralHeaderSignature: UInt32 { 0x0201_4b50 }
    private static var endSignature: UInt32 { 0x0605_4b50 }
    private static var version: UInt16 { 20 }
    private static var utf8Flag: UInt16 { 0x0800 }

    private(set) var sink: Sink
    private let limits: ProjectPackageResourceLimits
    private var centralRecords: [ProjectPackageArchiveCentralRecord] = []

    init(sink: Sink, limits: ProjectPackageResourceLimits) throws {
        try limits.validate()
        self.sink = sink
        self.limits = limits
    }

    mutating func writeDataEntry(path: String, data: Data) throws {
        guard let byteCount = UInt32(exactly: data.count) else {
            throw limit("Project package entry exceeds ZIP32.")
        }
        var crc32 = ProjectPackageCRC32()
        data.withUnsafeBytes { rawBytes in
            let pointer = rawBytes.bindMemory(to: UInt8.self)
            crc32.update(Span(_unsafeElements: pointer))
        }
        var payload = try beginEntry(
            path: path,
            checksum: crc32.checksum,
            byteCount: byteCount
        )
        do {
            try data.withUnsafeBytes { rawBytes in
                let pointer = rawBytes.bindMemory(to: UInt8.self)
                let span = Span(_unsafeElements: pointer)
                var offset = 0
                while offset < span.count {
                    let upperBound = min(span.count, offset + limits.maximumChunkByteCount)
                    try payload.write(span.extracting(offset..<upperBound))
                    offset = upperBound
                }
            }
            try payload.validateCompletion()
            sink = payload.base
        } catch {
            sink = payload.base
            throw error
        }
    }

    mutating func writeMeshEntry(
        _ plan: ProjectPackageMeshBlobPlan,
        telemetry: inout GeometryCopyTelemetry
    ) throws {
        guard let byteCount = UInt32(exactly: plan.reference.byteCount) else {
            throw limit("Mesh source entry exceeds ZIP32.")
        }
        var payload = try beginEntry(
            path: plan.reference.path,
            checksum: plan.checksum,
            byteCount: byteCount
        )
        do {
            try MeshSourceCodec.encode(
                plan.source,
                to: &payload,
                limits: limits.meshSource,
                telemetry: &telemetry
            )
            try payload.validateCompletion()
            sink = payload.base
        } catch {
            sink = payload.base
            throw error
        }
    }

    mutating func writeRetainedEntry(
        _ entry: ProjectPackageArchiveEntryDescriptor,
        from backing: ProjectPackageArchiveBacking
    ) throws {
        var payload = try beginEntry(
            path: entry.path,
            checksum: entry.checksum,
            byteCount: entry.byteCount
        )
        do {
            try backing.copy(
                entry,
                to: &payload,
                maximumChunkByteCount: limits.maximumChunkByteCount
            )
            try payload.validateCompletion()
            sink = payload.base
        } catch {
            sink = payload.base
            throw error
        }
    }

    mutating func finish() throws {
        guard centralRecords.count <= limits.maximumEntryCount,
            let entryCount = UInt16(exactly: centralRecords.count),
            let centralOffset = UInt32(exactly: sink.writtenByteCount)
        else {
            throw limit("Project package archive entry index exceeds ZIP32.")
        }
        for record in centralRecords {
            try writeCentralRecord(record)
        }
        let centralByteCount = sink.writtenByteCount - UInt64(centralOffset)
        guard let centralSize = UInt32(exactly: centralByteCount) else {
            throw limit("Project package central directory exceeds ZIP32.")
        }
        var footer: ContiguousArray<UInt8> = []
        Self.append(Self.endSignature, to: &footer)
        Self.append(UInt16(0), to: &footer)
        Self.append(UInt16(0), to: &footer)
        Self.append(entryCount, to: &footer)
        Self.append(entryCount, to: &footer)
        Self.append(centralSize, to: &footer)
        Self.append(centralOffset, to: &footer)
        Self.append(UInt16(0), to: &footer)
        try emit(footer)
        guard sink.writtenByteCount <= limits.maximumArchiveByteCount else {
            throw limit("Project package archive exceeds its configured limit.")
        }
    }

    private mutating func beginEntry(
        path: String,
        checksum: UInt32,
        byteCount: UInt32
    ) throws -> ProjectPackageArchivePayloadSink<Sink> {
        try ProjectPackageEntryPath.validate(path)
        guard centralRecords.count < limits.maximumEntryCount,
            centralRecords.allSatisfy({ $0.path != path }),
            let nameByteCount = UInt16(exactly: path.utf8.count),
            let localHeaderOffset = UInt32(exactly: sink.writtenByteCount)
        else {
            throw ProjectPackageError(
                code: centralRecords.contains(where: { $0.path == path })
                    ? .duplicateEntry : .resourceLimitExceeded,
                message: "Project package archive entry cannot be indexed: \(path)."
            )
        }
        var header: ContiguousArray<UInt8> = []
        Self.append(Self.localHeaderSignature, to: &header)
        Self.append(Self.version, to: &header)
        Self.append(Self.utf8Flag, to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(checksum, to: &header)
        Self.append(byteCount, to: &header)
        Self.append(byteCount, to: &header)
        Self.append(nameByteCount, to: &header)
        Self.append(UInt16(0), to: &header)
        header.append(contentsOf: path.utf8)
        try emit(header)
        centralRecords.append(
            ProjectPackageArchiveCentralRecord(
                path: path,
                checksum: checksum,
                byteCount: byteCount,
                localHeaderOffset: localHeaderOffset
            )
        )
        return ProjectPackageArchivePayloadSink(
            base: sink,
            expectedByteCount: byteCount,
            expectedChecksum: checksum,
            maximumChunkByteCount: limits.maximumChunkByteCount
        )
    }

    private mutating func writeCentralRecord(
        _ record: ProjectPackageArchiveCentralRecord
    ) throws {
        guard let nameByteCount = UInt16(exactly: record.path.utf8.count) else {
            throw limit("Project package path exceeds ZIP32.")
        }
        var header: ContiguousArray<UInt8> = []
        Self.append(Self.centralHeaderSignature, to: &header)
        Self.append(Self.version, to: &header)
        Self.append(Self.version, to: &header)
        Self.append(Self.utf8Flag, to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(record.checksum, to: &header)
        Self.append(record.byteCount, to: &header)
        Self.append(record.byteCount, to: &header)
        Self.append(nameByteCount, to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt16(0), to: &header)
        Self.append(UInt32(0), to: &header)
        Self.append(record.localHeaderOffset, to: &header)
        header.append(contentsOf: record.path.utf8)
        try emit(header)
    }

    private mutating func emit(_ bytes: ContiguousArray<UInt8>) throws {
        try bytes.withUnsafeBufferPointer { pointer in
            // ContiguousArray owns initialized header bytes. Each extracted span is
            // bounded, synchronously borrowed by the sink, and cannot escape.
            let span = Span(_unsafeElements: pointer)
            var offset = 0
            while offset < span.count {
                let remainingByteCount = span.count - offset
                let upperBound = offset + min(
                    remainingByteCount,
                    limits.maximumChunkByteCount
                )
                try sink.write(span.extracting(offset..<upperBound))
                offset = upperBound
            }
        }
        guard sink.writtenByteCount <= limits.maximumArchiveByteCount else {
            throw limit("Project package archive exceeds its configured limit.")
        }
    }

    private static func append(
        _ value: UInt16,
        to bytes: inout ContiguousArray<UInt8>
    ) {
        ProjectPackageLittleEndianBytes.append(value, to: &bytes)
    }

    private static func append(
        _ value: UInt32,
        to bytes: inout ContiguousArray<UInt8>
    ) {
        ProjectPackageLittleEndianBytes.append(value, to: &bytes)
    }

    private func limit(_ message: String) -> ProjectPackageError {
        ProjectPackageError(code: .resourceLimitExceeded, message: message)
    }
}
