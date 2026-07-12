import Foundation

public struct CapabilityVersion: Codable, Comparable, Hashable, Sendable {
    public var major: UInt32
    public var minor: UInt32
    public var patch: UInt32

    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: CapabilityVersion, rhs: CapabilityVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}
