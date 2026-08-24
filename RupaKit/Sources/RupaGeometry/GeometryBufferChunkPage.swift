import Foundation

final class GeometryBufferChunkPage<Element: Codable & Sendable>: Sendable {
    let chunks: ContiguousArray<GeometryBufferChunk<Element>>

    init(chunks: ContiguousArray<GeometryBufferChunk<Element>>) {
        precondition(!chunks.isEmpty)
        precondition(chunks.count <= GeometryBufferLayout.chunkDirectoryPageCapacity)
        self.chunks = chunks
    }
}
