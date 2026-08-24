import Foundation

struct GeometryBufferChunkDirectory<Element: Codable & Sendable>: Sendable {
    let pages: ContiguousArray<GeometryBufferChunkPage<Element>>
    let chunkCount: Int
    let elementCount: Int
    let chunkCapacity: Int

    init(
        chunks: ContiguousArray<GeometryBufferChunk<Element>>,
        chunkCapacity: Int
    ) {
        precondition(chunkCapacity > 0)
        precondition(
            chunks.enumerated().allSatisfy { index, chunk in
                let isLast = index == chunks.count - 1
                return !chunk.elements.isEmpty
                    && chunk.elements.count <= chunkCapacity
                    && (isLast || chunk.elements.count == chunkCapacity)
            }
        )

        var pages = ContiguousArray<GeometryBufferChunkPage<Element>>()
        let pageCapacity = GeometryBufferLayout.chunkDirectoryPageCapacity
        let pageCount =
            chunks.count / pageCapacity
            + (chunks.count.isMultiple(of: pageCapacity) ? 0 : 1)
        pages.reserveCapacity(pageCount)
        var elementCount = 0
        var pageStart = 0
        while pageStart < chunks.count {
            let pageEnd = min(pageStart + pageCapacity, chunks.count)
            let pageChunks = ContiguousArray(chunks[pageStart..<pageEnd])
            pages.append(GeometryBufferChunkPage(chunks: pageChunks))
            for chunk in pageChunks {
                let nextCount = elementCount.addingReportingOverflow(chunk.elements.count)
                precondition(!nextCount.overflow)
                elementCount = nextCount.partialValue
            }
            pageStart = pageEnd
        }

        self.pages = pages
        chunkCount = chunks.count
        self.elementCount = elementCount
        self.chunkCapacity = chunkCapacity
    }

    private init(
        pages: ContiguousArray<GeometryBufferChunkPage<Element>>,
        chunkCount: Int,
        elementCount: Int,
        chunkCapacity: Int
    ) {
        self.pages = pages
        self.chunkCount = chunkCount
        self.elementCount = elementCount
        self.chunkCapacity = chunkCapacity
    }

    subscript(chunkIndex: Int) -> GeometryBufferChunk<Element> {
        precondition(chunkIndex >= 0 && chunkIndex < chunkCount)
        let pageCapacity = GeometryBufferLayout.chunkDirectoryPageCapacity
        return pages[chunkIndex / pageCapacity].chunks[chunkIndex % pageCapacity]
    }

    func replacingChunks(
        _ replacements: [Int: ContiguousArray<Element>]
    ) -> GeometryBufferChunkDirectory<Element> {
        guard !replacements.isEmpty else {
            return self
        }
        let pageCapacity = GeometryBufferLayout.chunkDirectoryPageCapacity
        let sortedReplacements = replacements.sorted { $0.key < $1.key }
        var updatedPages = pages
        var replacementIndex = 0
        var updatedElementCount = elementCount

        while replacementIndex < sortedReplacements.count {
            let firstChunkIndex = sortedReplacements[replacementIndex].key
            precondition(firstChunkIndex >= 0 && firstChunkIndex < chunkCount)
            let pageIndex = firstChunkIndex / pageCapacity
            var pageChunks = pages[pageIndex].chunks

            while replacementIndex < sortedReplacements.count {
                let replacement = sortedReplacements[replacementIndex]
                let chunkIndex = replacement.key
                guard chunkIndex / pageCapacity == pageIndex else {
                    break
                }
                let elements = replacement.value
                let localIndex = chunkIndex % pageCapacity
                let previousCount = pageChunks[localIndex].elements.count
                precondition(!elements.isEmpty && elements.count <= chunkCapacity)
                precondition(
                    elements.count == previousCount
                        || (chunkIndex == chunkCount - 1 && elements.count >= previousCount)
                )
                let countDifference = elements.count - previousCount
                let nextElementCount = updatedElementCount.addingReportingOverflow(countDifference)
                precondition(!nextElementCount.overflow)
                updatedElementCount = nextElementCount.partialValue
                pageChunks[localIndex] = GeometryBufferChunk(elements: elements)
                replacementIndex += 1
            }
            updatedPages[pageIndex] = GeometryBufferChunkPage(chunks: pageChunks)
        }

        return GeometryBufferChunkDirectory(
            pages: updatedPages,
            chunkCount: chunkCount,
            elementCount: updatedElementCount,
            chunkCapacity: chunkCapacity
        )
    }

    func appending(
        _ chunk: GeometryBufferChunk<Element>
    ) -> GeometryBufferChunkDirectory<Element> {
        precondition(!chunk.elements.isEmpty && chunk.elements.count <= chunkCapacity)
        if chunkCount > 0 {
            precondition(self[chunkCount - 1].elements.count == chunkCapacity)
        }
        let nextElementCount = elementCount.addingReportingOverflow(chunk.elements.count)
        precondition(!nextElementCount.overflow)
        var updatedPages = pages

        if let lastPage = pages.last,
            lastPage.chunks.count < GeometryBufferLayout.chunkDirectoryPageCapacity
        {
            var pageChunks = lastPage.chunks
            pageChunks.append(chunk)
            updatedPages[updatedPages.count - 1] = GeometryBufferChunkPage(chunks: pageChunks)
        } else {
            updatedPages.append(
                GeometryBufferChunkPage(chunks: ContiguousArray([chunk]))
            )
        }
        return GeometryBufferChunkDirectory(
            pages: updatedPages,
            chunkCount: chunkCount + 1,
            elementCount: nextElementCount.partialValue,
            chunkCapacity: chunkCapacity
        )
    }

    func prefixChunks(_ requestedCount: Int) -> ContiguousArray<GeometryBufferChunk<Element>> {
        precondition(requestedCount >= 0 && requestedCount <= chunkCount)
        var result = ContiguousArray<GeometryBufferChunk<Element>>()
        result.reserveCapacity(requestedCount)
        for chunkIndex in 0..<requestedCount {
            result.append(self[chunkIndex])
        }
        return result
    }

    func forEachChunk(
        _ body: (GeometryBufferChunk<Element>) throws -> Void
    ) rethrows {
        for page in pages {
            for chunk in page.chunks {
                try body(chunk)
            }
        }
    }

    var chunkIdentities: [ObjectIdentifier] {
        var identities: [ObjectIdentifier] = []
        identities.reserveCapacity(chunkCount)
        for page in pages {
            identities.append(contentsOf: page.chunks.map(ObjectIdentifier.init))
        }
        return identities
    }

    var pageIdentities: [ObjectIdentifier] {
        pages.map(ObjectIdentifier.init)
    }
}
