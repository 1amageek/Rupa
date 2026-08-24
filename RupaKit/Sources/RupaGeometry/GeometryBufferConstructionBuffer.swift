import Foundation

/// Accumulates new elements directly into the immutable chunk layout.
struct GeometryBufferConstructionBuffer<Element: Codable & Sendable>: Sendable {
    private var chunks: ContiguousArray<GeometryBufferChunk<Element>>
    private var pending: ContiguousArray<Element>
    private let chunkCapacity: Int
    private(set) var count: Int

    init() {
        chunks = []
        pending = []
        chunkCapacity = GeometryBufferLayout.chunkCapacity(
            for: Element.self,
            preferredChunkByteCount: GeometryBufferLayout.preferredChunkByteCount
        )
        count = 0
        pending.reserveCapacity(chunkCapacity)
    }

    mutating func reserveCapacity(_ requestedCount: Int) {
        guard requestedCount > 0 else {
            return
        }
        let completeChunkCount = requestedCount / chunkCapacity
        chunks.reserveCapacity(
            completeChunkCount + (requestedCount.isMultiple(of: chunkCapacity) ? 0 : 1)
        )
    }

    func validateAppending(_ additionalCount: Int) throws {
        guard additionalCount >= 0 else {
            throw GeometryBufferError(
                code: .invalidRange,
                message: "Geometry construction append counts cannot be negative."
            )
        }
        let nextCount = count.addingReportingOverflow(additionalCount)
        guard !nextCount.overflow else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry construction exceeds the supported element-count range."
            )
        }
    }

    mutating func append(_ element: Element) throws {
        let nextCount = count.addingReportingOverflow(1)
        guard !nextCount.overflow else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry construction exceeds the supported element-count range."
            )
        }
        pending.append(element)
        count = nextCount.partialValue
        if pending.count == chunkCapacity {
            chunks.append(GeometryBufferChunk(elements: pending))
            pending = ContiguousArray()
            pending.reserveCapacity(chunkCapacity)
        }
    }

    mutating func append<C: Collection>(contentsOf elements: C) throws
    where C.Element == Element {
        for element in elements {
            try append(element)
        }
    }

    func build() -> GeometryBuffer<Element> {
        var completeChunks = chunks
        if !pending.isEmpty {
            completeChunks.append(GeometryBufferChunk(elements: pending))
        }
        return GeometryBuffer(
            storage: GeometryBufferStorage(
                chunks: completeChunks,
                count: count,
                chunkCapacity: chunkCapacity
            )
        )
    }

    func recordCopy(
        reason: GeometryCopyReason,
        in telemetry: inout GeometryCopyTelemetry
    ) throws {
        try telemetry.record(
            reason: reason,
            copiedBytes: try GeometryBufferLayout.copiedByteCount(
                forElementCount: count,
                of: Element.self
            )
        )
    }
}
