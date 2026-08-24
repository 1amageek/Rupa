import Foundation

struct ProjectPackageDataSink: ProjectPackageByteSink {
    private(set) var data = Data()
    private(set) var maximumWrittenChunkByteCount = 0

    var writtenByteCount: UInt64 {
        UInt64(data.count)
    }

    mutating func write(_ bytes: borrowing Span<UInt8>) throws {
        maximumWrittenChunkByteCount = max(maximumWrittenChunkByteCount, bytes.count)
        bytes.withUnsafeBytes { rawBytes in
            // This sink is an explicit owning test boundary. Production package saves
            // use ProjectPackageFileSink and never materialize the archive in Data.
            data.append(contentsOf: rawBytes)
        }
    }
}
