struct ProjectPackageArchiveCentralRecord: Sendable {
    let path: String
    let checksum: UInt32
    let byteCount: UInt32
    let localHeaderOffset: UInt32
}
