import Foundation

final class GeometryBufferChunk<Element: Codable & Sendable>: Sendable {
    let elements: ContiguousArray<Element>

    init(elements: ContiguousArray<Element>) {
        self.elements = elements
    }

    borrowing func withSpan(
        in range: Range<Int>,
        _ body: borrowing (borrowing Span<Element>) throws -> Void
    ) rethrows {
        // This immutable chunk is the sole memory owner and deallocates its array exactly once.
        // ContiguousArray supplies aligned, initialized Element storage for the validated range.
        // The pointer and derived Span remain inside this closure, never escape or cross isolation,
        // and no binding, rebinding, aliasing mutation, offset overflow, or manual allocation occurs.
        try elements.withUnsafeBufferPointer { pointer in
            let span = Span(_unsafeElements: pointer).extracting(range)
            try body(span)
        }
    }
}
