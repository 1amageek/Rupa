import Foundation

public struct GeometryBufferBuilder<Element: Codable & Sendable>: Sendable {
    private var storage: ContiguousArray<Element>
    public private(set) var telemetry: GeometryCopyTelemetry

    init(buffer: GeometryBuffer<Element>) {
        self.storage = buffer.storage
        self.telemetry = GeometryCopyTelemetry()
    }

    public var count: Int {
        storage.count
    }

    public mutating func replaceSubrange<C: Collection>(
        _ range: Range<Int>,
        with newElements: C
    ) throws where C.Element == Element {
        guard range.lowerBound >= storage.startIndex, range.upperBound <= storage.endIndex else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry buffer builder ranges must remain within buffer bounds."
            )
        }
        let originalBytes = storage.count * MemoryLayout<Element>.stride
        storage.replaceSubrange(range, with: newElements)
        telemetry.record(reason: .sourceEdit, copiedBytes: originalBytes)
    }

    public mutating func append(_ element: Element) {
        storage.append(element)
    }

    public func build() -> GeometryBuffer<Element> {
        GeometryBuffer(storage: storage)
    }
}
