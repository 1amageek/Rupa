enum ProjectPackageLittleEndianBytes {
    static func append(_ value: UInt16, to bytes: inout ContiguousArray<UInt8>) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    static func append(_ value: UInt32, to bytes: inout ContiguousArray<UInt8>) {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }
}
