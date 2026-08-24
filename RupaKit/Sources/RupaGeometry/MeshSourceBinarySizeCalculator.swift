import Foundation

struct MeshSourceBinarySizeCalculator {
    private var byteCount = MeshSourceBinaryFormat.headerByteCount
    private let limits: MeshSourceCodecLimits

    private init(limits: MeshSourceCodecLimits) {
        self.limits = limits
    }

    static func encodedByteCount(
        of source: MeshSource,
        limits: MeshSourceCodecLimits
    ) throws -> UInt64 {
        try limits.validate()
        try source.validate()

        var calculator = MeshSourceBinarySizeCalculator(limits: limits)
        try calculator.addString(source.identity.rawValue)
        try calculator.addOptionalID(source.allocationState.nextVertexID?.rawValue)
        try calculator.addOptionalID(source.allocationState.nextEdgeID?.rawValue)
        try calculator.addOptionalID(source.allocationState.nextFaceID?.rawValue)
        try calculator.addOptionalID(source.allocationState.nextCornerID?.rawValue)

        try calculator.addBuffer(count: source.vertexIDs.count, elementByteCount: 8)
        try calculator.addBuffer(count: source.vertexPositions.count, elementByteCount: 24)
        try calculator.addBuffer(count: source.edgeIDs.count, elementByteCount: 8)
        try calculator.addBuffer(count: source.edgeEndpoints.count, elementByteCount: 16)
        try calculator.addBuffer(count: source.faceIDs.count, elementByteCount: 8)
        try calculator.addBuffer(count: source.faceCornerRanges.count, elementByteCount: 16)
        try calculator.addBuffer(count: source.cornerIDs.count, elementByteCount: 8)
        try calculator.addBuffer(count: source.cornerVertexIDs.count, elementByteCount: 8)
        try calculator.addBuffer(count: source.cornerEdgeIDs.count, elementByteCount: 8)

        let layers = source.attributes.sortedLayers()
        guard layers.count <= limits.maximumAttributeCount,
            UInt32(exactly: layers.count) != nil
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source attribute count exceeds its configured limit."
            )
        }
        try calculator.add(4)
        for layer in layers {
            try calculator.addString(layer.descriptor.id.rawValue)
            try calculator.addString(layer.descriptor.name)
            try calculator.add(4)
            try calculator.addBuffer(
                count: layer.values.count,
                elementByteCount: layer.values.binaryElementByteCount
            )
            if let indices = layer.indices {
                try calculator.addElements(count: indices.count, elementByteCount: 4)
            }
        }

        guard calculator.byteCount <= limits.maximumBlobByteCount else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source blob exceeds its configured byte limit."
            )
        }
        return calculator.byteCount
    }

    private mutating func addOptionalID(_ rawValue: UInt64?) throws {
        try add(rawValue == nil ? 1 : 9)
    }

    private mutating func addString(_ value: String) throws {
        let utf8Count = value.utf8.count
        guard utf8Count <= limits.maximumStringByteCount,
            UInt32(exactly: utf8Count) != nil
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source string exceeds its configured byte limit."
            )
        }
        try add(4)
        try add(UInt64(utf8Count))
    }

    private mutating func addBuffer(
        count: Int,
        elementByteCount: UInt64
    ) throws {
        try add(8)
        try addElements(count: count, elementByteCount: elementByteCount)
    }

    private mutating func addElements(
        count: Int,
        elementByteCount: UInt64
    ) throws {
        guard count >= 0,
            count <= limits.maximumElementCountPerBuffer,
            let unsignedCount = UInt64(exactly: count)
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source buffer exceeds its configured element limit."
            )
        }
        let product = unsignedCount.multipliedReportingOverflow(by: elementByteCount)
        guard !product.overflow else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source buffer byte count overflowed UInt64."
            )
        }
        try add(product.partialValue)
    }

    private mutating func add(_ additionalByteCount: UInt64) throws {
        let addition = byteCount.addingReportingOverflow(additionalByteCount)
        guard !addition.overflow,
            addition.partialValue <= limits.maximumBlobByteCount
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source blob exceeds its configured byte limit."
            )
        }
        byteCount = addition.partialValue
    }
}

extension GeometryAttributeStorage {
    fileprivate var binaryElementByteCount: UInt64 {
        switch self {
        case .boolean:
            1
        case .int32, .float32:
            4
        case .float64:
            8
        case .vector2:
            16
        case .vector3:
            24
        case .vector4:
            32
        }
    }
}
