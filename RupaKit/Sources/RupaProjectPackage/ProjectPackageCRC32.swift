struct ProjectPackageCRC32: Sendable {
    private static let table: [UInt32] = {
        var values: [UInt32] = []
        values.reserveCapacity(256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(value & 1))
                value = (value >> 1) ^ (0xedb8_8320 & mask)
            }
            values.append(value)
        }
        return values
    }()

    private var state: UInt32 = 0xffff_ffff

    mutating func update(_ bytes: borrowing Span<UInt8>) {
        bytes.withUnsafeBytes { rawBytes in
            for byte in rawBytes {
                let index = Int((state ^ UInt32(byte)) & 0xff)
                state = (state >> 8) ^ Self.table[index]
            }
        }
    }

    var checksum: UInt32 {
        state ^ 0xffff_ffff
    }
}
