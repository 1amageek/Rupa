import Foundation

public struct GeometryBufferView<Element: Codable & Sendable>: Sendable,
    RandomAccessCollection {
    public typealias Index = Int

    private let buffer: GeometryBuffer<Element>
    private let range: Range<Int>

    init(buffer: GeometryBuffer<Element>, range: Range<Int>) {
        self.buffer = buffer
        self.range = range
    }

    public var startIndex: Int {
        range.startIndex
    }

    public var endIndex: Int {
        range.endIndex
    }

    public subscript(position: Int) -> Element {
        buffer[position]
    }
}
