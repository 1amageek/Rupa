import Foundation

public struct GeometryBuffer<Element: Codable & Sendable>: Codable, Sendable,
    RandomAccessCollection {
    public typealias Index = Int

    let storage: ContiguousArray<Element>

    public init(_ elements: [Element]) {
        self.storage = ContiguousArray(elements)
    }

    public init<C: Collection>(_ elements: C) where C.Element == Element {
        self.storage = ContiguousArray(elements)
    }

    init(storage: ContiguousArray<Element>) {
        self.storage = storage
    }

    public var startIndex: Int {
        storage.startIndex
    }

    public var endIndex: Int {
        storage.endIndex
    }

    public subscript(position: Int) -> Element {
        storage[position]
    }

    public func view(_ range: Range<Int>) throws -> GeometryBufferView<Element> {
        guard range.lowerBound >= startIndex, range.upperBound <= endIndex else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry buffer views must remain within buffer bounds."
            )
        }
        return GeometryBufferView(buffer: self, range: range)
    }

    public func replacingSubrange<C: Collection>(
        _ range: Range<Int>,
        with newElements: C,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryBuffer<Element> where C.Element == Element {
        guard range.lowerBound >= startIndex, range.upperBound <= endIndex else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry buffer replacement ranges must remain within buffer bounds."
            )
        }
        var copy = storage
        copy.replaceSubrange(range, with: newElements)
        telemetry.record(
            reason: .sourceEdit,
            copiedBytes: storage.count * MemoryLayout<Element>.stride
        )
        return GeometryBuffer(storage: copy)
    }

    public func makeBuilder() -> GeometryBufferBuilder<Element> {
        GeometryBufferBuilder(buffer: self)
    }
}

extension GeometryBuffer: Equatable where Element: Equatable {}
