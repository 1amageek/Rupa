import RupaCoreTypes

enum ProjectPackageContentIdentityBuilder {
    static func identity(
        for entries: [ProjectPackageSourceEntry]
    ) throws -> DocumentContentIdentity {
        let sortedEntries = entries.sorted { $0.path < $1.path }
        var hasher = StableSHA256Hasher()
        hasher.update(string: "rupa.project-package.source-identity.v3")
        hasher.update(count: sortedEntries.count)
        for entry in sortedEntries {
            hasher.update(string: entry.path)
            hasher.update(string: entry.mediaType)
            hasher.update(entry.schemaVersion)
            hasher.update(entry.byteCount)
            hasher.update(string: entry.fingerprint.algorithm)
            hasher.update(string: entry.fingerprint.value)
        }
        return try DocumentContentIdentity(
            fingerprint: ContentFingerprint(
                algorithm: "sha256-rupa-document-source-v3",
                value: hasher.hexDigest()
            )
        )
    }
}
