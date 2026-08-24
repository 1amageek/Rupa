import Foundation

/// An immutable range view whose lease retains its complete backing-storage lifetime.
public struct GeometryBufferView<Element: Codable & Sendable>: Sendable,
    RandomAccessCollection
{
    public typealias Index = Int

    private let lease: GeometryBufferLease<Element>

    init(lease: GeometryBufferLease<Element>) {
        self.lease = lease
    }

    public var startIndex: Int {
        lease.startIndex
    }

    public var endIndex: Int {
        lease.endIndex
    }

    public subscript(position: Int) -> Element {
        lease[position]
    }

    /// Visits each contiguous region without materializing the view.
    ///
    /// The underlying lease owns the storage. `Span` prevents the borrowed storage
    /// from escaping its valid lifetime.
    public borrowing func withContiguousChunks(
        _ body: borrowing (borrowing Span<Element>) throws -> Void
    ) rethrows {
        try lease.withContiguousChunks(body)
    }
}
