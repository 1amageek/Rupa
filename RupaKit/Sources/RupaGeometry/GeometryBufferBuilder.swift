import Foundation

/// A single-owner editor that copies only the immutable chunks touched by an edit session.
public struct GeometryBufferBuilder<Element: Codable & Sendable>: ~Copyable, Sendable {
    private var baseStorage: GeometryBufferStorage<Element>
    private var editedChunks: [Int: ContiguousArray<Element>]
    private let chunkCapacity: Int
    public private(set) var count: Int
    public private(set) var telemetry: GeometryCopyTelemetry

    init(buffer: GeometryBuffer<Element>) {
        baseStorage = buffer.storage
        editedChunks = [:]
        chunkCapacity = buffer.storage.chunkCapacity
        count = buffer.count
        telemetry = GeometryCopyTelemetry()
    }

    public mutating func replaceSubrange<C: Collection>(
        _ range: Range<Int>,
        with newElements: C
    ) throws where C.Element == Element {
        try validate(range: range)
        let removedCount = range.count
        let replacementCount = newElements.count
        let countAfterRemoval = count - removedCount
        let newCount = countAfterRemoval.addingReportingOverflow(replacementCount)
        guard !newCount.overflow else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry buffer replacement exceeds the supported element-count range."
            )
        }

        if removedCount == replacementCount {
            try replaceEqualLengthSubrange(range, with: newElements)
            return
        }
        try rebuildTail(
            replacing: range,
            with: newElements,
            resultingCount: newCount.partialValue
        )
    }

    public mutating func append(_ element: Element) throws {
        guard count < Int.max else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry buffer element count cannot exceed Int.max."
            )
        }
        let lastChunkIndex = count / chunkCapacity
        let localIndex = count % chunkCapacity

        if localIndex == 0 {
            let snapshot = currentStorage()
            let directory = snapshot.directory.appending(
                GeometryBufferChunk(elements: ContiguousArray([element]))
            )
            count += 1
            baseStorage = GeometryBufferStorage(
                directory: directory,
                count: count,
                chunkCapacity: chunkCapacity
            )
            editedChunks.removeAll(keepingCapacity: true)
            return
        }

        let copiedBytes = try mutateChunk(at: lastChunkIndex) { elements in
            elements.append(element)
        }
        try telemetry.record(reason: .sourceEdit, copiedBytes: copiedBytes)
        count += 1
    }

    public mutating func build() -> GeometryBuffer<Element> {
        let storage = currentStorage()
        baseStorage = storage
        editedChunks.removeAll(keepingCapacity: true)
        return GeometryBuffer(storage: storage)
    }

    private mutating func replaceEqualLengthSubrange<C: Collection>(
        _ range: Range<Int>,
        with newElements: C
    ) throws where C.Element == Element {
        guard !range.isEmpty else {
            return
        }
        var copiedBytes: UInt64 = 0
        var iterator = newElements.makeIterator()
        for position in range {
            guard let element = iterator.next() else {
                throw GeometryBufferError(
                    code: .inconsistentCollection,
                    message: "Geometry replacement collection count changed during iteration."
                )
            }
            let chunkIndex = position / chunkCapacity
            let localIndex = position % chunkCapacity
            let chunkCopiedBytes = try mutateChunk(at: chunkIndex) { elements in
                elements[localIndex] = element
            }
            let addition = copiedBytes.addingReportingOverflow(chunkCopiedBytes)
            guard !addition.overflow else {
                throw GeometryBufferError(
                    code: .sizeOverflow,
                    message:
                        "Geometry buffer copy telemetry exceeds the supported byte-count range."
                )
            }
            copiedBytes = addition.partialValue
        }
        guard iterator.next() == nil else {
            throw GeometryBufferError(
                code: .inconsistentCollection,
                message: "Geometry replacement collection count changed during iteration."
            )
        }
        try telemetry.record(reason: .sourceEdit, copiedBytes: copiedBytes)
    }

    private mutating func mutateChunk(
        at chunkIndex: Int,
        _ body: (inout ContiguousArray<Element>) -> Void
    ) throws -> UInt64 {
        if var elements = editedChunks.removeValue(forKey: chunkIndex) {
            body(&elements)
            editedChunks[chunkIndex] = elements
            return 0
        }

        let sharedElements = baseStorage.directory[chunkIndex].elements
        var elements = sharedElements
        body(&elements)
        editedChunks[chunkIndex] = elements
        return try GeometryBufferLayout.copiedByteCount(
            forElementCount: sharedElements.count,
            of: Element.self
        )
    }

    private mutating func rebuildTail<C: Collection>(
        replacing range: Range<Int>,
        with newElements: C,
        resultingCount: Int
    ) throws where C.Element == Element {
        let snapshot = currentStorage()
        let rebuildStart = (range.lowerBound / chunkCapacity) * chunkCapacity
        let retainedPrefixChunkCount = rebuildStart / chunkCapacity
        var rebuiltChunks = snapshot.directory.prefixChunks(retainedPrefixChunkCount)
        var pending = ContiguousArray<Element>()
        let expectedReplacementCount = newElements.count
        var actualReplacementCount = 0
        pending.reserveCapacity(chunkCapacity)

        func appendRebuilt(
            _ element: Element,
            pending: inout ContiguousArray<Element>,
            chunks: inout ContiguousArray<GeometryBufferChunk<Element>>
        ) {
            pending.append(element)
            if pending.count == chunkCapacity {
                chunks.append(GeometryBufferChunk(elements: pending))
                pending = ContiguousArray()
                pending.reserveCapacity(chunkCapacity)
            }
        }

        if rebuildStart < range.lowerBound {
            for position in rebuildStart..<range.lowerBound {
                appendRebuilt(snapshot[position], pending: &pending, chunks: &rebuiltChunks)
            }
        }
        for element in newElements {
            let nextReplacementCount = actualReplacementCount.addingReportingOverflow(1)
            guard !nextReplacementCount.overflow else {
                throw GeometryBufferError(
                    code: .sizeOverflow,
                    message:
                        "Geometry replacement collection exceeds the supported element-count range."
                )
            }
            actualReplacementCount = nextReplacementCount.partialValue
            appendRebuilt(element, pending: &pending, chunks: &rebuiltChunks)
        }
        guard actualReplacementCount == expectedReplacementCount else {
            throw GeometryBufferError(
                code: .inconsistentCollection,
                message: "Geometry replacement collection count changed during iteration."
            )
        }
        if range.upperBound < count {
            for position in range.upperBound..<count {
                appendRebuilt(snapshot[position], pending: &pending, chunks: &rebuiltChunks)
            }
        }
        if !pending.isEmpty {
            rebuiltChunks.append(GeometryBufferChunk(elements: pending))
        }

        let retainedOldElementCount =
            (range.lowerBound - rebuildStart)
            + (count - range.upperBound)
        try telemetry.record(
            reason: .sourceEdit,
            copiedBytes: try GeometryBufferLayout.copiedByteCount(
                forElementCount: retainedOldElementCount,
                of: Element.self
            )
        )
        baseStorage = GeometryBufferStorage(
            chunks: rebuiltChunks,
            count: resultingCount,
            chunkCapacity: chunkCapacity
        )
        editedChunks.removeAll(keepingCapacity: true)
        count = resultingCount
    }

    private func currentStorage() -> GeometryBufferStorage<Element> {
        guard !editedChunks.isEmpty else {
            return baseStorage
        }
        let directory = baseStorage.directory.replacingChunks(editedChunks)
        return GeometryBufferStorage(
            directory: directory,
            count: count,
            chunkCapacity: chunkCapacity
        )
    }

    private func validate(range: Range<Int>) throws {
        guard range.lowerBound >= 0,
            range.upperBound <= count
        else {
            throw GeometryBufferError(
                code: .invalidRange,
                message: "Geometry buffer builder ranges must remain within buffer bounds."
            )
        }
    }
}
