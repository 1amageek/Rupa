struct ProjectPackageCRC32: Sendable {
    private var state: UInt32 = 0xffff_ffff

    mutating func update(_ bytes: borrowing Span<UInt8>) {
        bytes.withUnsafeBytes { rawBytes in
            for byte in rawBytes {
                var value = state ^ UInt32(byte)
                for _ in 0..<8 {
                    let mask = UInt32(bitPattern: -Int32(value & 1))
                    value = (value >> 1) ^ (0xedb8_8320 & mask)
                }
                state = value
            }
        }
    }

    var checksum: UInt32 {
        state ^ 0xffff_ffff
    }
}
