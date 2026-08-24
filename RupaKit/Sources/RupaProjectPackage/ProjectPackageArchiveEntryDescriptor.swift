struct ProjectPackageArchiveEntryDescriptor: Equatable, Sendable {
    let path: String
    let checksum: UInt32
    let byteCount: UInt32
    let localRecordRange: Range<Int>
    let payloadRange: Range<Int>
}
