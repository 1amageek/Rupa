import RupaCoreTypes

struct CanonicalIdentityHasher {
    private var hasher: StableSHA256Hasher

    init(domain: String) {
        precondition(!domain.isEmpty)
        var hasher = StableSHA256Hasher()
        hasher.update(string: "rupa.canonical-identity.v1")
        hasher.update(string: domain)
        self.hasher = hasher
    }

    mutating func appendField(_ name: String) {
        hasher.update(byte: 0x01)
        hasher.update(string: name)
    }

    mutating func appendString(_ value: String) {
        hasher.update(byte: 0x02)
        hasher.update(string: value)
    }

    mutating func appendCount(_ value: Int) {
        precondition(value >= 0)
        hasher.update(byte: 0x03)
        hasher.update(UInt64(value))
    }

    mutating func appendUInt32(_ value: UInt32) {
        hasher.update(byte: 0x04)
        hasher.update(value)
    }

    mutating func appendUInt64(_ value: UInt64) {
        hasher.update(byte: 0x05)
        hasher.update(value)
    }

    mutating func appendDouble(_ value: Double) {
        hasher.update(byte: 0x06)
        hasher.update(value.bitPattern)
    }

    mutating func appendBool(_ value: Bool) {
        hasher.update(byte: 0x07)
        hasher.update(byte: value ? 1 : 0)
    }

    mutating func appendNull() {
        hasher.update(byte: 0x08)
    }

    func fingerprint(algorithm: String) throws -> ContentFingerprint {
        try ContentFingerprint(
            algorithm: algorithm,
            value: hasher.hexDigest()
        )
    }
}
