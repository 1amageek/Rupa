import Foundation
import RupaCoreTypes

/// An immutable typed buffer backed by structurally shared storage pages and chunks.
public struct GeometryBuffer<Element: Codable & Sendable>: Codable, Sendable,
    RandomAccessCollection
{
    public typealias Index = Int

    let storage: GeometryBufferStorage<Element>

    public init(_ elements: [Element]) {
        storage = GeometryBufferStorage(elements)
    }

    public init<C: Collection>(_ elements: C) where C.Element == Element {
        storage = GeometryBufferStorage(elements)
    }

    public init<C: Collection>(
        materializing elements: C,
        telemetry: inout GeometryCopyTelemetry
    ) throws where C.Element == Element {
        storage = GeometryBufferStorage(elements)
        try telemetry.record(
            reason: .bufferMaterialization,
            copiedBytes: try GeometryBufferLayout.copiedByteCount(
                forElementCount: storage.count,
                of: Element.self
            )
        )
    }

    package init<C: Collection>(
        _ elements: C,
        preferredChunkByteCount: Int
    ) where C.Element == Element {
        storage = GeometryBufferStorage(
            elements,
            preferredChunkByteCount: preferredChunkByteCount
        )
    }

    init(storage: GeometryBufferStorage<Element>) {
        self.storage = storage
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let chunkCapacity = GeometryBufferLayout.chunkCapacity(
            for: Element.self,
            preferredChunkByteCount: GeometryBufferLayout.preferredChunkByteCount
        )
        var chunks = ContiguousArray<GeometryBufferChunk<Element>>()
        var pending = ContiguousArray<Element>()
        var count = 0
        pending.reserveCapacity(chunkCapacity)

        while !container.isAtEnd {
            let nextCount = count.addingReportingOverflow(1)
            guard !nextCount.overflow else {
                throw GeometryBufferError(
                    code: .sizeOverflow,
                    message: "Decoded geometry buffer exceeds the supported element-count range."
                )
            }
            pending.append(try container.decode(Element.self))
            count = nextCount.partialValue
            if pending.count == chunkCapacity {
                chunks.append(GeometryBufferChunk(elements: pending))
                pending = ContiguousArray()
                pending.reserveCapacity(chunkCapacity)
            }
        }
        if !pending.isEmpty {
            chunks.append(GeometryBufferChunk(elements: pending))
        }
        storage = GeometryBufferStorage(
            chunks: chunks,
            count: count,
            chunkCapacity: chunkCapacity
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try storage.directory.forEachChunk { chunk in
            for element in chunk.elements {
                try container.encode(element)
            }
        }
    }

    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        storage.count
    }

    public subscript(position: Int) -> Element {
        storage[position]
    }

    public func lease() -> GeometryBufferLease<Element> {
        GeometryBufferLease(storage: storage, range: startIndex..<endIndex)
    }

    public func lease(
        telemetry: inout GeometryCopyTelemetry
    ) -> GeometryBufferLease<Element> {
        lease()
    }

    public func lease(_ range: Range<Int>) throws -> GeometryBufferLease<Element> {
        try validate(range: range, operation: "leases")
        return GeometryBufferLease(storage: storage, range: range)
    }

    public func lease(
        _ range: Range<Int>,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryBufferLease<Element> {
        try lease(range)
    }

    public func view(_ range: Range<Int>) throws -> GeometryBufferView<Element> {
        GeometryBufferView(lease: try lease(range))
    }

    public func view(
        _ range: Range<Int>,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryBufferView<Element> {
        GeometryBufferView(lease: try lease(range, telemetry: &telemetry))
    }

    public func replacingSubrange<C: Collection>(
        _ range: Range<Int>,
        with newElements: C,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryBuffer<Element> where C.Element == Element {
        var builder = makeBuilder()
        try builder.replaceSubrange(range, with: newElements)
        try telemetry.record(contentsOf: builder.telemetry)
        return builder.build()
    }

    public func makeBuilder() -> GeometryBufferBuilder<Element> {
        GeometryBufferBuilder(buffer: self)
    }

    private func validate(range: Range<Int>, operation: String) throws {
        guard range.lowerBound >= startIndex,
            range.upperBound <= endIndex
        else {
            throw GeometryBufferError(
                code: .invalidRange,
                message: "Geometry buffer \(operation) must remain within buffer bounds."
            )
        }
    }
}

extension GeometryBuffer: Equatable where Element: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.elementsEqual(rhs)
    }
}

extension GeometryBuffer where Element: GeometryBufferContentHashable {
    public func contentFingerprint(
        maximumElementCount: Int
    ) throws -> ContentFingerprint {
        guard maximumElementCount >= 0 else {
            throw GeometryBufferError(
                code: .invalidHashingLimit,
                message: "Geometry buffer hashing limits cannot be negative."
            )
        }
        guard count <= maximumElementCount else {
            throw GeometryBufferError(
                code: .hashingLimitExceeded,
                message: "Geometry buffer content exceeds the requested hashing element limit."
            )
        }

        var hasher = StableSHA256Hasher()
        hasher.update(string: "rupa.geometry-buffer.content.v1")
        hasher.update(string: Element.geometryBufferContentDomain)
        hasher.update(count: count)
        for element in self {
            try element.updateGeometryBufferContentHash(&hasher)
        }
        return try ContentFingerprint(
            algorithm: "sha256-rupa-geometry-buffer-v1",
            value: hasher.hexDigest()
        )
    }
}
