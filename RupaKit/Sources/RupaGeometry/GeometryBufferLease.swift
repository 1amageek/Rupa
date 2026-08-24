import Foundation

/// Retains immutable geometry storage for the complete lifetime of a read lease.
public struct GeometryBufferLease<Element: Codable & Sendable>: Sendable,
    RandomAccessCollection
{
    public typealias Index = Int

    private let storage: GeometryBufferStorage<Element>
    private let range: Range<Int>

    init(storage: GeometryBufferStorage<Element>, range: Range<Int>) {
        self.storage = storage
        self.range = range
    }

    public var startIndex: Int {
        range.lowerBound
    }

    public var endIndex: Int {
        range.upperBound
    }

    public subscript(position: Int) -> Element {
        precondition(range.contains(position))
        return storage[position]
    }

    /// Visits each contiguous region without materializing the leased elements.
    ///
    /// The lease owns every visited chunk. Each span is immutable and its borrow is
    /// statically restricted to the lifetime of the owned chunk.
    public borrowing func withContiguousChunks(
        _ body: borrowing (borrowing Span<Element>) throws -> Void
    ) rethrows {
        try storage.withContiguousChunks(in: range, body)
    }
}
