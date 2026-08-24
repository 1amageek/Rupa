enum GeometryBufferLayout {
    // The geometry microbenchmark calibrates this internal value. It is not a public format contract.
    static let preferredChunkByteCount =
        GeometryBufferPerformanceContract.preferredChunkByteCount
    static let chunkDirectoryPageCapacity = 64

    static func chunkCapacity<Element>(
        for _: Element.Type,
        preferredChunkByteCount: Int
    ) -> Int {
        let stride = max(MemoryLayout<Element>.stride, 1)
        return max(preferredChunkByteCount / stride, 1)
    }

    static func copiedByteCount<Element>(
        forElementCount count: Int,
        of _: Element.Type
    ) throws -> UInt64 {
        guard let elementCount = UInt64(exactly: count),
            let stride = UInt64(exactly: MemoryLayout<Element>.stride)
        else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry buffer copy telemetry requires nonnegative representable sizes."
            )
        }
        let result = elementCount.multipliedReportingOverflow(by: stride)
        guard !result.overflow else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry buffer copy telemetry exceeds the supported byte-count range."
            )
        }
        return result.partialValue
    }
}
