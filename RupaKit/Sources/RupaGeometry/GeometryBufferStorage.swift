import Foundation

package final class GeometryBufferStorageIdentity: Sendable {}

struct GeometryBufferStorage<Element: Codable & Sendable>: Sendable {
    let directory: GeometryBufferChunkDirectory<Element>
    let count: Int
    let chunkCapacity: Int
    let identity: GeometryBufferStorageIdentity

    init<C: Collection>(
        _ elements: C,
        preferredChunkByteCount: Int = GeometryBufferLayout.preferredChunkByteCount
    ) where C.Element == Element {
        let capacity = GeometryBufferLayout.chunkCapacity(
            for: Element.self,
            preferredChunkByteCount: preferredChunkByteCount
        )
        var chunks = ContiguousArray<GeometryBufferChunk<Element>>()
        let estimatedChunkCount =
            elements.count / capacity
            + (elements.count.isMultiple(of: capacity) ? 0 : 1)
        chunks.reserveCapacity(estimatedChunkCount)
        var pending = ContiguousArray<Element>()
        var actualCount = 0
        pending.reserveCapacity(capacity)

        for element in elements {
            let nextCount = actualCount.addingReportingOverflow(1)
            precondition(!nextCount.overflow)
            actualCount = nextCount.partialValue
            pending.append(element)
            if pending.count == capacity {
                chunks.append(GeometryBufferChunk(elements: pending))
                pending = ContiguousArray()
                pending.reserveCapacity(capacity)
            }
        }
        if !pending.isEmpty {
            chunks.append(GeometryBufferChunk(elements: pending))
        }

        self.init(chunks: chunks, count: actualCount, chunkCapacity: capacity)
    }

    init(
        chunks: ContiguousArray<GeometryBufferChunk<Element>>,
        count: Int,
        chunkCapacity: Int
    ) {
        self.init(
            directory: GeometryBufferChunkDirectory(
                chunks: chunks,
                chunkCapacity: chunkCapacity
            ),
            count: count,
            chunkCapacity: chunkCapacity,
            identity: GeometryBufferStorageIdentity()
        )
    }

    init(
        directory: GeometryBufferChunkDirectory<Element>,
        count: Int,
        chunkCapacity: Int,
        identity: GeometryBufferStorageIdentity = GeometryBufferStorageIdentity()
    ) {
        precondition(count >= 0)
        precondition(chunkCapacity > 0)
        precondition(directory.elementCount == count)
        self.directory = directory
        self.count = count
        self.chunkCapacity = chunkCapacity
        self.identity = identity
    }

    subscript(position: Int) -> Element {
        precondition(position >= 0 && position < count)
        let chunkIndex = position / chunkCapacity
        let elementIndex = position % chunkCapacity
        return directory[chunkIndex].elements[elementIndex]
    }

    borrowing func withContiguousChunks(
        in range: Range<Int>,
        _ body: borrowing (borrowing Span<Element>) throws -> Void
    ) rethrows {
        guard !range.isEmpty else {
            return
        }
        let firstChunkIndex = range.lowerBound / chunkCapacity
        let lastChunkIndex = (range.upperBound - 1) / chunkCapacity

        for chunkIndex in firstChunkIndex...lastChunkIndex {
            let chunkStart = chunkIndex * chunkCapacity
            let localLowerBound = max(range.lowerBound - chunkStart, 0)
            let chunk = directory[chunkIndex]
            let localUpperBound = min(
                range.upperBound - chunkStart,
                chunk.elements.count
            )
            try chunk.withSpan(in: localLowerBound..<localUpperBound, body)
        }
    }

    var chunkIdentities: [ObjectIdentifier] {
        directory.chunkIdentities
    }

    var pageIdentities: [ObjectIdentifier] {
        directory.pageIdentities
    }
}
